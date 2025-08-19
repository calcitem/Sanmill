#!/usr/bin/env python3
"""
NNUE Pitting Script for Sanmill - Human vs NNUE AI
Supports GUI interface for interactive games with NNUE model evaluation.

Usage:
  python nnue_pit.py --config my_config.yaml --gui --first human
  python nnue_pit.py --model nnue_model.bin --gui
  python nnue_pit.py --model nnue_model.bin --games 5 --first ai
"""

import os
import sys
import argparse
import logging
import torch
import torch.nn.functional as F
import numpy as np
import json
from pathlib import Path
from typing import Optional, Tuple, List, Dict, Any
import struct
import threading
import time
import random
from copy import deepcopy
import hashlib
from enum import Enum
from dataclasses import dataclass

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# Import NNUE-PyTorch specific modules
try:
    import model as M
    from features_mill import NineMillFeatures
    from features import get_feature_set_from_name
    HAS_PYTORCH_LIGHTNING = True
    try:
        import pytorch_lightning as pl
    except ImportError:
        HAS_PYTORCH_LIGHTNING = False
except ImportError as e:
    print(f"Warning: NNUE-PyTorch modules not available: {e}")
    print("Falling back to legacy NNUE implementation")
    HAS_PYTORCH_LIGHTNING = False

# Fallback imports for legacy compatibility
try:
    from train_nnue import MillNNUE
    from config_loader import load_config, merge_config_with_args
except ImportError:
    MillNNUE = None
    load_config = None
    merge_config_with_args = None

from game.Game import Game

# Import for standard notation
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'alphazero'))
try:
    from game.engine_adapter import move_to_engine_token
except ImportError:
    # Fallback if alphazero engine_adapter not available
    def move_to_engine_token(move):
        letters = "abcdefg"
        if len(move) == 2:
            x, y = move
            return letters[x] + str(7 - y)
        elif len(move) == 4:
            x0, y0, x1, y1 = move
            from_coord = letters[x0] + str(7 - y0)
            to_coord = letters[x1] + str(7 - y1)
            return f"{from_coord}-{to_coord}"
        else:
            return "?"

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class TTEntryType(Enum):
    """Transposition Table entry type"""
    EXACT = 0      # Exact value
    LOWER_BOUND = 1  # Alpha cutoff (fail-high)
    UPPER_BOUND = 2  # Beta cutoff (fail-low)


@dataclass
class TTEntry:
    """Transposition Table entry"""
    hash_key: int
    depth: int
    score: float
    entry_type: TTEntryType
    best_move: Optional[Tuple[int, int, int, int]]
    age: int  # For replacement strategy


class TranspositionTable:
    """Transposition Table for caching search results"""
    
    def __init__(self, size_mb: int = 64):
        """Initialize transposition table
        
        Args:
            size_mb: Size in megabytes (default 64MB)
        """
        # Calculate number of entries based on size
        # Each entry is roughly 64 bytes (hash_key=8, depth=4, score=8, entry_type=4, best_move=32, age=4, overhead=4)
        entry_size = 64
        self.max_entries = (size_mb * 1024 * 1024) // entry_size
        self.table = {}
        self.current_age = 0
        
        # Statistics
        self.hits = 0
        self.misses = 0
        self.collisions = 0
        self.overwrites = 0
        
        logger.info(f"Initialized Transposition Table: {size_mb}MB, max {self.max_entries} entries")
    
    def clear(self):
        """Clear the transposition table"""
        self.table.clear()
        self.hits = 0
        self.misses = 0
        self.collisions = 0
        self.overwrites = 0
        self.current_age += 1
        
    def probe(self, hash_key: int, depth: int, alpha: float, beta: float) -> Tuple[bool, Optional[float], Optional[Tuple[int, int, int, int]]]:
        """Probe the transposition table
        
        Args:
            hash_key: Position hash key
            depth: Search depth
            alpha: Alpha value
            beta: Beta value
            
        Returns:
            (found, score, best_move): found indicates if usable entry was found
        """
        if hash_key not in self.table:
            self.misses += 1
            return False, None, None
        
        entry = self.table[hash_key]
        
        # Check if entry is from sufficient depth
        if entry.depth < depth:
            self.misses += 1
            return False, None, entry.best_move  # Return move hint even if depth insufficient
        
        self.hits += 1
        
        # Check if we can use the stored score
        if entry.entry_type == TTEntryType.EXACT:
            return True, entry.score, entry.best_move
        elif entry.entry_type == TTEntryType.LOWER_BOUND and entry.score >= beta:
            return True, entry.score, entry.best_move
        elif entry.entry_type == TTEntryType.UPPER_BOUND and entry.score <= alpha:
            return True, entry.score, entry.best_move
        
        # Entry exists but score not usable, return move hint
        return False, None, entry.best_move
    
    def store(self, hash_key: int, depth: int, score: float, entry_type: TTEntryType, 
              best_move: Optional[Tuple[int, int, int, int]] = None):
        """Store entry in transposition table
        
        Args:
            hash_key: Position hash key
            depth: Search depth
            score: Position score
            entry_type: Type of bound
            best_move: Best move found
        """
        # Check if we need to evict entries
        if len(self.table) >= self.max_entries and hash_key not in self.table:
            self._evict_entry()
        
        # Check for replacement
        if hash_key in self.table:
            old_entry = self.table[hash_key]
            # Replace if: deeper search, or same depth but newer age, or different hash (collision)
            if (depth >= old_entry.depth or 
                (depth == old_entry.depth and self.current_age > old_entry.age) or
                old_entry.hash_key != hash_key):
                if old_entry.hash_key != hash_key:
                    self.collisions += 1
                else:
                    self.overwrites += 1
            else:
                # Don't replace with inferior entry
                return
        
        # Store new entry
        self.table[hash_key] = TTEntry(
            hash_key=hash_key,
            depth=depth,
            score=score,
            entry_type=entry_type,
            best_move=best_move,
            age=self.current_age
        )
    
    def _evict_entry(self):
        """Evict an entry using age-based replacement"""
        if not self.table:
            return
            
        # Find oldest entry
        oldest_key = min(self.table.keys(), key=lambda k: self.table[k].age)
        del self.table[oldest_key]
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get transposition table statistics"""
        total_probes = self.hits + self.misses
        hit_rate = (self.hits / max(1, total_probes)) * 100
        
        return {
            "size": len(self.table),
            "max_size": self.max_entries,
            "usage_percent": (len(self.table) / self.max_entries) * 100,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate_percent": hit_rate,
            "collisions": self.collisions,
            "overwrites": self.overwrites
        }


class PositionHasher:
    """Fast position hashing using Zobrist hashing technique"""
    
    def __init__(self):
        # Initialize Zobrist hash tables for each piece type and position
        # We need random numbers for: 24 positions * 2 players + side_to_move + phases
        np.random.seed(42)  # Fixed seed for reproducible hashes
        
        # Hash values for pieces (24 valid positions * 2 piece types)
        self.piece_hashes = np.random.randint(0, 2**63, size=(24, 2), dtype=np.int64)
        
        # Hash values for side to move
        self.side_to_move_hash = np.random.randint(0, 2**63, dtype=np.int64)
        
        # Hash values for game phases
        self.phase_hashes = np.random.randint(0, 2**63, size=4, dtype=np.int64)
        
        # Hash values for piece counts (to distinguish positions with same piece placement but different hand counts)
        self.piece_count_hashes = np.random.randint(0, 2**63, size=(10, 10), dtype=np.int64)  # 10x10 for white/black hand counts
        
    def hash_position(self, game_state: 'NNUEGameAdapter') -> int:
        """Compute hash for game position"""
        hash_value = 0
        
        # Hash piece positions
        for i, (x, y) in enumerate(sorted(game_state.valid_positions)):
            piece = game_state.board.pieces[x][y]
            if piece == 1:  # White piece
                hash_value ^= self.piece_hashes[i][0]
            elif piece == -1:  # Black piece
                hash_value ^= self.piece_hashes[i][1]
        
        # Hash side to move
        if game_state.side_to_move == 1:  # Black to move
            hash_value ^= self.side_to_move_hash
        
        # Hash game phase
        hash_value ^= self.phase_hashes[min(game_state.phase, 3)]
        
        # Hash piece counts to distinguish positions with same board but different hand counts
        white_hand = min(game_state.white_pieces_in_hand, 9)
        black_hand = min(game_state.black_pieces_in_hand, 9)
        hash_value ^= self.piece_count_hashes[white_hand][black_hand]
        
        # Ensure positive hash value
        return abs(hash_value)


class NNUEModelLoader:
    """NNUE model loader that can handle PyTorch Lightning .ckpt, .bin and .pth formats"""
    
    def __init__(self, model_path: str, feature_size: int = 1152, hidden_size: int = 256, 
                 force_cpu: bool = None, feature_set_name: str = "NineMill"):
        self.model_path = model_path
        self.feature_size = feature_size
        self.hidden_size = hidden_size
        self.feature_set_name = feature_set_name
        self.model = None
        
        # Auto-detect device requirements based on model type
        if force_cpu is None:
            # For PyTorch Lightning models, check if they require CUDA
            if model_path.endswith('.ckpt'):
                # PyTorch Lightning models with custom feature transformers may require CUDA
                self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
                if not torch.cuda.is_available():
                    logger.warning("Model may require CUDA but CUDA is not available. Trying CPU fallback.")
            else:
                # Legacy models default to CPU
                self.device = torch.device('cpu')
        elif force_cpu:
            self.device = torch.device('cpu')
        else:
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
    def load_model(self):
        """Load NNUE model from file (supports PyTorch Lightning, legacy formats)"""
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"NNUE model file not found: {self.model_path}")
        
        # Handle PyTorch Lightning checkpoint files
        if self.model_path.endswith('.ckpt') and HAS_PYTORCH_LIGHTNING:
            return self._load_pytorch_lightning_model()
        
        # Handle legacy formats
        if self.model_path.endswith('.bin'):
            detected_feature_size, detected_hidden_size = self._detect_binary_dimensions()
        elif self.model_path.endswith('.pth') or self.model_path.endswith('.tar'):
            detected_feature_size, detected_hidden_size = self._detect_pytorch_dimensions()
        else:
            detected_feature_size, detected_hidden_size = self.feature_size, self.hidden_size
            
        # Update dimensions if needed
        if detected_feature_size != self.feature_size:
            logger.warning(f"Updating feature size from {self.feature_size} to {detected_feature_size}")
            self.feature_size = detected_feature_size
        if detected_hidden_size != self.hidden_size:
            logger.warning(f"Updating hidden size from {self.hidden_size} to {detected_hidden_size}")
            self.hidden_size = detected_hidden_size
            
        # Create model instance with correct dimensions
        if MillNNUE:
            self.model = MillNNUE(feature_size=self.feature_size, hidden_size=self.hidden_size)
        else:
            raise RuntimeError("Legacy MillNNUE not available")
        
        if self.model_path.endswith('.bin'):
            self._load_binary_model()
        elif self.model_path.endswith('.pth') or self.model_path.endswith('.tar'):
            self._load_pytorch_model()
        else:
            raise ValueError(f"Unsupported model format: {self.model_path}")
            
        self.model.to(self.device)
        self.model.eval()
        logger.info(f"✅ Loaded NNUE model: {self.model_path} (feature_size={self.feature_size}, hidden_size={self.hidden_size})")
        return self.model
    
    def _load_pytorch_lightning_model(self):
        """Load PyTorch Lightning checkpoint file"""
        if not HAS_PYTORCH_LIGHTNING:
            raise RuntimeError("PyTorch Lightning not available for loading .ckpt files")
        
        try:
            # Load the PyTorch Lightning model
            logger.info(f"Loading PyTorch Lightning model from: {self.model_path}")
            
            # Create feature set
            feature_set = get_feature_set_from_name(self.feature_set_name)
            
            # Load model from checkpoint
            nnue_model = M.NNUE.load_from_checkpoint(
                self.model_path,
                feature_set=feature_set,
                map_location=self.device
            )
            
            nnue_model.to(self.device)
            nnue_model.eval()
            
            # Initialize idx_offset for inference (batch_size=1 for single position evaluation)
            self._initialize_model_idx_offset(nnue_model, batch_size=1)
            
            logger.info(f"✅ Loaded PyTorch Lightning NNUE model: {self.model_path}")
            logger.info(f"   Feature set: {self.feature_set_name}")
            logger.info(f"   Device: {self.device}")
            
            self.model = nnue_model
            return nnue_model
            
        except Exception as e:
            logger.error(f"Failed to load PyTorch Lightning model: {e}")
            raise RuntimeError(f"Failed to load PyTorch Lightning model: {e}")
    
    def _initialize_model_idx_offset(self, model, batch_size: int = 1):
        """Initialize idx_offset for the model's layer stacks"""
        if hasattr(model, 'layer_stacks') and hasattr(model.layer_stacks, 'idx_offset'):
            if model.layer_stacks.idx_offset is None:
                model.layer_stacks.idx_offset = torch.arange(
                    0,
                    batch_size * model.layer_stacks.count,
                    model.layer_stacks.count,
                    device=self.device
                )
                logger.info(f"✅ Initialized model idx_offset for batch size {batch_size}")
            else:
                logger.info("Model idx_offset already initialized")
        else:
            logger.warning("Model does not have layer_stacks.idx_offset - this may be expected for some model types")
    
    def _detect_binary_dimensions(self) -> tuple:
        """Detect model dimensions from binary file header"""
        try:
            with open(self.model_path, 'rb') as f:
                # Read header
                header = f.read(8)
                if header != b'SANMILL1':
                    raise ValueError(f"Invalid header: {header}")
                
                # Read dimensions
                feature_size, hidden_size = struct.unpack('<II', f.read(8))
                return feature_size, hidden_size
        except Exception as e:
            logger.warning(f"Failed to detect dimensions from binary file: {e}")
            return self.feature_size, self.hidden_size
    
    def _detect_pytorch_dimensions(self) -> tuple:
        """Detect model dimensions from PyTorch checkpoint"""
        try:
            checkpoint = torch.load(self.model_path, map_location='cpu')
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                state_dict = checkpoint['model_state_dict']
            else:
                state_dict = checkpoint
            
            # Extract dimensions from the state dict
            if 'input_to_hidden.weight' in state_dict:
                input_weight_shape = state_dict['input_to_hidden.weight'].shape
                hidden_size, feature_size = input_weight_shape
                return feature_size, hidden_size
            else:
                raise ValueError("Cannot find input_to_hidden.weight in state dict")
                
        except Exception as e:
            logger.warning(f"Failed to detect dimensions from PyTorch file: {e}")
            return self.feature_size, self.hidden_size
        
    def _load_binary_model(self):
        """Load from C++ compatible binary format"""
        try:
            with open(self.model_path, 'rb') as f:
                # Read header
                header = f.read(8)
                if header != b'SANMILL1':
                    raise ValueError(f"Invalid header: {header}")
                
                # Read dimensions (already detected and model created with correct size)
                feature_size, hidden_size = struct.unpack('<II', f.read(8))
                
                # Dimensions should match now since we detected them earlier
                assert feature_size == self.feature_size and hidden_size == self.hidden_size, \
                    f"Dimension mismatch: file has ({feature_size}, {hidden_size}), model has ({self.feature_size}, {self.hidden_size})"
                
                # Read input weights
                input_weights_size = feature_size * hidden_size * 2  # int16
                input_weights_data = f.read(input_weights_size)
                input_weights = np.frombuffer(input_weights_data, dtype=np.int16)
                input_weights = input_weights.reshape(hidden_size, feature_size)
                input_weights = input_weights.astype(np.float32) / 127.0  # Dequantize
                
                # Read input biases
                input_biases_size = hidden_size * 4  # int32
                input_biases_data = f.read(input_biases_size)
                input_biases = np.frombuffer(input_biases_data, dtype=np.int32)
                input_biases = input_biases.astype(np.float32) / 127.0  # Dequantize
                
                # Read output weights
                output_weights_size = hidden_size * 2 * 1  # int8
                output_weights_data = f.read(output_weights_size)
                output_weights = np.frombuffer(output_weights_data, dtype=np.int8)
                output_weights = output_weights.reshape(1, hidden_size * 2)
                output_weights = output_weights.astype(np.float32) / 127.0  # Dequantize
                
                # Read output bias
                output_bias_data = f.read(4)  # int32
                output_bias = np.frombuffer(output_bias_data, dtype=np.int32)[0]
                output_bias = float(output_bias) / 127.0  # Dequantize
                
                # Set model weights
                with torch.no_grad():
                    self.model.input_to_hidden.weight.copy_(torch.from_numpy(input_weights))
                    self.model.input_to_hidden.bias.copy_(torch.from_numpy(input_biases))
                    self.model.hidden_to_output.weight.copy_(torch.from_numpy(output_weights))
                    self.model.hidden_to_output.bias.fill_(output_bias)
                    
        except Exception as e:
            raise RuntimeError(f"Failed to load binary model: {e}")
            
    def _load_pytorch_model(self):
        """Load from PyTorch checkpoint format"""
        try:
            if self.model_path.endswith('.ckpt'):
                # PyTorch Lightning checkpoint
                from model import NNUE
                self.model = NNUE.load_from_checkpoint(self.model_path, map_location=self.device)
                
                # Initialize idx_offset for inference (batch size = 1)
                if hasattr(self.model, 'layer_stacks') and hasattr(self.model.layer_stacks, 'idx_offset'):
                    if self.model.layer_stacks.idx_offset is None:
                        batch_size = 1  # For inference
                        self.model.layer_stacks.idx_offset = torch.arange(
                            0,
                            batch_size * self.model.layer_stacks.count,
                            self.model.layer_stacks.count,
                            device=self.device
                        )
                        logger.info(f"✅ Initialized idx_offset for inference (batch_size={batch_size})")
                
            else:
                # Regular PyTorch checkpoint
                checkpoint = torch.load(self.model_path, map_location=self.device)
                if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                    self.model.load_state_dict(checkpoint['model_state_dict'])
                else:
                    self.model.load_state_dict(checkpoint)
        except Exception as e:
            raise RuntimeError(f"Failed to load PyTorch model: {e}")


class NNUEGameAdapter:
    """Adapter to use existing ml/game Board with NNUE - reuses ml/game logic"""
    
    def __init__(self):
        try:
            self.game = Game()
            self.board = self.game.getInitBoard()
            self.current_player = 1  # 1 for white, -1 for black (ml/game format)
            
            # Valid board positions (reuse from ml/game)
            self.valid_positions = []
            for x in range(7):
                for y in range(7):
                    if self.board.allowed_places[x][y]:
                        self.valid_positions.append((x, y))
        except Exception as e:
            logger.error(f"Failed to initialize NNUEGameAdapter: {e}")
            raise
    
    @property
    def side_to_move(self):
        """Get current player (0: white, 1: black) - converting from ml/game format"""
        return 0 if self.current_player == 1 else 1
    
    @property
    def phase(self):
        """Get current phase (0: placing, 1: moving, 2: flying, 3: capture)"""
        return self.board.period
    
    @property
    def white_pieces_in_hand(self):
        """Number of white pieces not yet placed"""
        return self.board.pieces_in_hand_count(1)
    
    @property
    def black_pieces_in_hand(self):
        """Number of black pieces not yet placed"""
        return self.board.pieces_in_hand_count(-1)
    
    @property
    def white_pieces_on_board(self):
        """Number of white pieces on board"""
        return self.board.count(1)
    
    @property
    def black_pieces_on_board(self):
        """Number of black pieces on board"""
        return self.board.count(-1)
    
    @property
    def move_count(self):
        """Total number of moves"""
        return self.board.move_counter
        
    def to_nnue_features(self) -> np.ndarray:
        """Convert game state to NNUE feature vector using ml/game data structures"""
        features = np.zeros(115, dtype=np.float32)
        
        # Piece placement features (24 + 24 = 48 features)
        white_idx = 0
        black_idx = 24
        for i, (x, y) in enumerate(sorted(self.valid_positions)):
            piece = self.board.pieces[x][y]  # Access using ml/game format
            if piece == 1:  # White piece (ml/game uses 1 for white)
                features[white_idx + i] = 1.0
            elif piece == -1:  # Black piece (ml/game uses -1 for black)
                features[black_idx + i] = 1.0
                    
        # Phase features (3 features) - handle capture phase differently
        if self.phase == 3:  # Capture phase maps to placing phase feature for NNUE
            features[48] = 1.0
        else:
            features[48 + min(self.phase, 2)] = 1.0
        
        # Piece count features (4 features)
        features[51] = self.white_pieces_in_hand / 9.0
        features[52] = self.black_pieces_in_hand / 9.0
        features[53] = self.white_pieces_on_board / 9.0
        features[54] = self.black_pieces_on_board / 9.0
        
        # Side to move (1 feature)
        features[55] = float(self.side_to_move)
        
        # Move count normalized (1 feature)
        features[56] = min(self.move_count / 100.0, 1.0)
        
        # Mill detection features (remaining features) - reuse ml/game mill logic
        self._add_mill_features(features)
        
        return features
    
    def _add_mill_features(self, features: np.ndarray):
        """Add mill-related features using ml/game mill detection"""
        from game.standard_rules import mills
        
        mill_feature_start = 57
        feature_idx = mill_feature_start
        
        # For each valid position, check if it's part of a mill
        for i, (x, y) in enumerate(sorted(self.valid_positions)):
            if feature_idx >= 115:
                break
                
            piece = self.board.pieces[x][y]
            if piece != 0:  # Has a piece
                # Use Game's mill detection logic
                if self.game.is_mill(self.board, [x, y]):
                    features[feature_idx] = 1.0
            
            feature_idx += 1
        
    def is_valid_position(self, x: int, y: int) -> bool:
        """Check if position is valid on the board - reuse ml/game logic"""
        return 0 <= x < 7 and 0 <= y < 7 and self.board.allowed_places[x][y] == 1
        
    def get_valid_moves(self) -> List[Tuple[int, int, int, int]]:
        """Get list of valid moves in current position - reuse ml/game logic"""
        # Use ml/game's move generation directly
        valid_moves_array = self.game.getValidMoves(self.board, self.current_player)
        moves = []
        
        # Convert from ml/game action format to coordinate format
        for action_idx, is_valid in enumerate(valid_moves_array):
            if is_valid:
                move_coords = self.board.get_move_from_action(action_idx)
                # Convert to 4-tuple format (x1, y1, x2, y2)
                if len(move_coords) == 2:
                    # Placing or removing move
                    moves.append((move_coords[0], move_coords[1], move_coords[0], move_coords[1]))
                else:
                    # Moving
                    moves.append(tuple(move_coords))
                
        return moves
        
    def make_move(self, move) -> bool:
        """Make a move on the board - reuse ml/game logic"""
        try:
            # Convert coordinate move to action index
            if len(move) == 4:
                if move[0] == move[2] and move[1] == move[3]:
                    # Placing or removing move
                    action = self.board.get_action_from_move([move[0], move[1]])
                else:
                    # Moving
                    action = self.board.get_action_from_move(list(move))
            else:
                action = self.board.get_action_from_move(list(move))
            
            # Use ml/game's state transition which calls execute_move internally
            # This ensures proper update of draw counters and threefold repetition detection
            next_board, next_player = self.game.getNextState(self.board, self.current_player, action)
            self.board = next_board
            self.current_player = next_player
            return True
        except Exception as e:
            return False
            
    def is_game_over(self) -> Tuple[bool, Optional[str]]:
        """Check if game is over - reuse ml/game logic"""
        # Use the more comprehensive check_game_over_conditions instead of getGameEnded
        is_over, result, reason = self.board.check_game_over_conditions(self.current_player)
        if is_over:
            return True, reason
        return False, None
        
    def get_removable_pieces(self, player_side_to_move: int) -> List[Tuple[int, int]]:
        """Get removable pieces for GUI - maps to ml/game removal logic"""
        # In capture phase, we can remove any valid pieces according to game rules
        # This is handled by the ml/game logic in get_valid_moves
        if self.phase == 3:
            valid_moves = self.get_valid_moves()
            removable = []
            for move in valid_moves:
                # In removal phase, moves are (x, y, x, y) for piece at (x, y)
                if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                    removable.append((move[0], move[1]))
            return removable
        return []
    
    def copy(self):
        """Create a copy of the current game state"""
        from copy import deepcopy
        new_adapter = NNUEGameAdapter()
        new_adapter.board = deepcopy(self.board)
        new_adapter.current_player = self.current_player
        return new_adapter
    
    def make_move_and_undo(self, move) -> Tuple[bool, Any]:
        """Make a move and return undo information for efficient backtracking"""
        try:
            # Store state for undo
            old_board = self.board
            old_player = self.current_player
            
            # Convert coordinate move to action index
            if len(move) == 4:
                if move[0] == move[2] and move[1] == move[3]:
                    # Placing or removing move
                    action = self.board.get_action_from_move([move[0], move[1]])
                else:
                    # Moving
                    action = self.board.get_action_from_move(list(move))
            else:
                action = self.board.get_action_from_move(list(move))
            
            # Use ml/game's state transition
            next_board, next_player = self.game.getNextState(self.board, self.current_player, action)
            self.board = next_board
            self.current_player = next_player
            
            # Return undo information
            return True, (old_board, old_player)
        except Exception as e:
            return False, None
    
    def undo_move(self, undo_info):
        """Undo a move using the undo information"""
        if undo_info:
            old_board, old_player = undo_info
            self.board = old_board
            self.current_player = old_player


class NNUEPlayer:
    """AI player using NNUE model for evaluation with optimized Transposition Table - uses ml/game logic"""
    
    def __init__(self, model_loader: NNUEModelLoader, search_depth: int = 8, use_randomness: bool = False, tt_size_mb: int = 64):
        self.model = model_loader.load_model()
        self.device = model_loader.device
        self.search_depth = search_depth
        self.use_randomness = use_randomness
        
        # Initialize Transposition Table and Position Hasher
        self.transposition_table = TranspositionTable(size_mb=tt_size_mb)
        self.position_hasher = PositionHasher()
        
        # Statistics for performance monitoring
        self.nodes_searched = 0
        self.cutoffs = 0
        self.tt_hits = 0
        self.tt_misses = 0
        self.nnue_evaluations = 0
        
        # Performance optimizations
        self.use_iterative_deepening = True
        self.use_lazy_evaluation = True
        self.use_null_move_pruning = True
        
        # Move ordering cache to avoid repeated evaluations
        self._move_order_cache = {}
        self._cache_age = 0
        
    def evaluate_position(self, game_state: NNUEGameAdapter) -> float:
        """Evaluate position using NNUE model with evaluation counting"""
        self.nnue_evaluations += 1
        
        # Check if this is a PyTorch Lightning model
        if hasattr(self.model, 'feature_set'):
            # PyTorch Lightning model - use feature set
            return self._evaluate_with_pytorch_lightning_model(game_state)
        else:
            # Legacy model - use direct features
            return self._evaluate_with_legacy_model(game_state)
    
    def _evaluate_with_pytorch_lightning_model(self, game_state: NNUEGameAdapter) -> float:
        """Evaluate using PyTorch Lightning NNUE model"""
        # Convert game state to feature format expected by nnue-pytorch
        board_state = {
            'white_pieces': self._extract_piece_positions(game_state, 1),  # White pieces
            'black_pieces': self._extract_piece_positions(game_state, -1), # Black pieces
            'side_to_move': 'white' if game_state.side_to_move == 0 else 'black'
        }
        
        # Get features from feature set
        white_features, black_features = self.model.feature_set.get_active_features(board_state)
        
        # Convert to sparse representation expected by the model
        white_indices = torch.nonzero(white_features, as_tuple=False).flatten()
        white_values = white_features[white_indices]
        black_indices = torch.nonzero(black_features, as_tuple=False).flatten()
        black_values = black_features[black_indices]
        
        # Get model device - use batch size = 1 for inference
        model_device = next(self.model.parameters()).device
        batch_size = 1
        
        # Ensure we have at least one feature to avoid empty tensors and move to device
        if len(white_indices) == 0:
            white_indices = torch.tensor([0], dtype=torch.long, device=model_device)
            white_values = torch.tensor([0.0], dtype=torch.float32, device=model_device)
        else:
            white_indices = white_indices.to(model_device)
            white_values = white_values.to(model_device)
            
        if len(black_indices) == 0:
            black_indices = torch.tensor([0], dtype=torch.long, device=model_device)
            black_values = torch.tensor([0.0], dtype=torch.float32, device=model_device)
        else:
            black_indices = black_indices.to(model_device)
            black_values = black_values.to(model_device)
        
        # Create batch format (batch size = 1)
        us = torch.tensor([1.0 if game_state.side_to_move == 0 else 0.0], dtype=torch.float32).unsqueeze(0).to(model_device)  # [1, 1]
        them = torch.tensor([1.0 if game_state.side_to_move == 1 else 0.0], dtype=torch.float32).unsqueeze(0).to(model_device)  # [1, 1]
        
        # Build tightly-sized sparse batches to include all active features
        n_white = int(len(white_indices))
        n_black = int(len(black_indices))
        # Guard against empty tensors by enforcing at least 1 column
        wf = max(1, n_white)
        bf = max(1, n_black)

        white_indices_batch = torch.zeros((batch_size, wf), dtype=torch.int32, device=model_device)
        white_values_batch = torch.zeros((batch_size, wf), dtype=torch.float32, device=model_device)
        black_indices_batch = torch.zeros((batch_size, bf), dtype=torch.int32, device=model_device)
        black_values_batch = torch.zeros((batch_size, bf), dtype=torch.float32, device=model_device)

        if n_white > 0:
            white_indices_batch[0, :n_white] = white_indices.int()
            white_values_batch[0, :n_white] = white_values
        # else keep the single zero padding
        if n_black > 0:
            black_indices_batch[0, :n_black] = black_indices.int()
            black_values_batch[0, :n_black] = black_values
        
        # PSQT and layer stack indices (batch size = 1); match training bucketization
        # Buckets: 1..7 (0 unused)
        # Placing: based on current side in-hand counts; Non-placing: flying or empties
        white_on_board = game_state.white_pieces_on_board
        black_on_board = game_state.black_pieces_on_board
        empties = 24 - (white_on_board + black_on_board)
        us_is_white = (game_state.side_to_move == 0)
        us_in_hand = game_state.white_pieces_in_hand if us_is_white else game_state.black_pieces_in_hand
        us_on_board = white_on_board if us_is_white else black_on_board
        placing = (game_state.white_pieces_in_hand > 0) or (game_state.black_pieces_in_hand > 0)

        if placing:
            if us_in_hand >= 6:
                bucket = 1
            elif us_in_hand >= 3:
                bucket = 2
            else:
                bucket = 3
        else:
            if us_on_board <= 3:
                bucket = 4
            else:
                if empties >= 8:
                    bucket = 5
                elif empties == 7:
                    bucket = 6
                else:
                    bucket = 7

        psqt_indices = torch.full((batch_size,), bucket, dtype=torch.long, device=model_device)
        layer_stack_indices = torch.full((batch_size,), bucket, dtype=torch.long, device=model_device)
        
        with torch.no_grad():
            # Call model with expected input format
            evaluation = self.model(
                us, them,
                white_indices_batch, white_values_batch,
                black_indices_batch, black_values_batch,
                psqt_indices, layer_stack_indices
            )
            return float(evaluation.squeeze().cpu())
    
    def _evaluate_with_legacy_model(self, game_state: NNUEGameAdapter) -> float:
        """Evaluate using legacy NNUE model"""
        features = game_state.to_nnue_features()
        features_tensor = torch.from_numpy(features).unsqueeze(0).to(self.device)
        side_to_move_tensor = torch.tensor([game_state.side_to_move], dtype=torch.long).to(self.device)
        
        with torch.no_grad():
            evaluation = self.model(features_tensor, side_to_move_tensor)
            return float(evaluation.squeeze().cpu())
    
    def _extract_piece_positions(self, game_state: NNUEGameAdapter, piece_color: int) -> List[int]:
        """Extract piece positions for a specific color"""
        positions = []
        for i, (x, y) in enumerate(sorted(game_state.valid_positions)):
            if game_state.board.pieces[x][y] == piece_color:
                positions.append(i)  # Use feature index
        return positions
            
    def order_moves(self, game_state: NNUEGameAdapter, moves: List[Tuple[int, int, int, int]], 
                   tt_best_move: Optional[Tuple[int, int, int, int]] = None, depth: int = 0) -> List[Tuple[int, int, int, int]]:
        """Optimized move ordering with caching and lazy evaluation"""
        if len(moves) <= 1:
            return moves
        
        # Put TT best move first if it exists and is valid
        ordered_moves = []
        remaining_moves = moves.copy()
        
        if tt_best_move and tt_best_move in remaining_moves:
            ordered_moves.append(tt_best_move)
            remaining_moves.remove(tt_best_move)
            
        if not remaining_moves:
            return ordered_moves
        
        # For deep searches, use simpler heuristics to avoid expensive evaluations
        if depth > 3 and len(remaining_moves) > 8:
            # Use simple heuristics for deep searches
            ordered_moves.extend(self._order_moves_heuristic(game_state, remaining_moves))
            return ordered_moves
            
        # Cache key for move ordering
        position_hash = self.position_hasher.hash_position(game_state)
        cache_key = (position_hash, tuple(sorted(remaining_moves)), self._cache_age)
        
        if cache_key in self._move_order_cache:
            cached_order = self._move_order_cache[cache_key]
            # Verify cached moves are still valid
            if all(move in remaining_moves for move in cached_order):
                ordered_moves.extend(cached_order)
                return ordered_moves
        
        # Score remaining moves using NNUE evaluation (only for shallow searches)
        move_scores = []
        evaluation_limit = min(len(remaining_moves), 12)  # Limit evaluations for performance
        
        for i, move in enumerate(remaining_moves):
            if i >= evaluation_limit:
                # Use heuristic score for remaining moves
                score = self._heuristic_move_score(game_state, move)
                move_scores.append((move, score))
            else:
                success, undo_info = game_state.make_move_and_undo(move)
                if success:
                    # Use NNUE evaluation to score the resulting position
                    score = self.evaluate_position(game_state)
                    game_state.undo_move(undo_info)
                    move_scores.append((move, score))
                else:
                    # Invalid move gets lowest priority
                    move_scores.append((move, float('-inf')))
        
        # Sort moves: best moves first for the current player
        if game_state.side_to_move == 0:  # White (maximizing)
            move_scores.sort(key=lambda x: x[1], reverse=True)
        else:  # Black (minimizing) 
            move_scores.sort(key=lambda x: x[1], reverse=False)
            
        # Cache the result
        ordered_remaining = [move for move, score in move_scores]
        if len(self._move_order_cache) > 10000:  # Limit cache size
            self._move_order_cache.clear()
            self._cache_age += 1
        self._move_order_cache[cache_key] = ordered_remaining
            
        # Combine TT best move with ordered remaining moves
        ordered_moves.extend(ordered_remaining)
        return ordered_moves
    
    def _order_moves_heuristic(self, game_state: NNUEGameAdapter, moves: List[Tuple[int, int, int, int]]) -> List[Tuple[int, int, int, int]]:
        """Fast heuristic-based move ordering for deep searches"""
        move_scores = []
        
        for move in moves:
            score = self._heuristic_move_score(game_state, move)
            move_scores.append((move, score))
        
        # Sort moves by heuristic score
        move_scores.sort(key=lambda x: x[1], reverse=True)
        return [move for move, score in move_scores]
    
    def _heuristic_move_score(self, game_state: NNUEGameAdapter, move: Tuple[int, int, int, int]) -> float:
        """Fast heuristic scoring without NNUE evaluation"""
        score = 0.0
        x1, y1, x2, y2 = move
        
        # Prefer center positions
        center_bonus = 0.1
        center_positions = [(3, 3), (2, 3), (4, 3), (3, 2), (3, 4)]
        if (x2, y2) in center_positions:
            score += center_bonus
        
        # Prefer moves that form potential mills
        # This is a simplified check - in a full implementation you'd check actual mill patterns
        if game_state.phase == 0:  # Placing phase
            # Prefer moves that could form mills
            score += 0.05
        elif game_state.phase in [1, 2]:  # Moving/Flying phase
            # Prefer moves that increase mobility
            distance = abs(x2 - x1) + abs(y2 - y1)
            if distance > 0:
                score += 0.02 * distance
        
        return score

    def get_best_move(self, game_state: NNUEGameAdapter) -> Optional[Tuple[int, int, int, int]]:
        """Get best move using iterative deepening with Alpha-Beta pruning and optimizations"""
        
        # Reset statistics
        self.nodes_searched = 0
        self.cutoffs = 0
        self.tt_hits = 0
        self.tt_misses = 0
        self.nnue_evaluations = 0
        
        # Increment TT age and cache age for new search
        self.transposition_table.current_age += 1
        self._cache_age += 1
        
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return None
        
        if len(valid_moves) == 1:
            return valid_moves[0]  # Only one move available
        
        best_move = None
        best_score = float('-inf') if game_state.side_to_move == 0 else float('inf')
        
        # Use iterative deepening for better move ordering and time management
        if self.use_iterative_deepening and self.search_depth > 2:
            return self._iterative_deepening_search(game_state, valid_moves)
        else:
            return self._fixed_depth_search(game_state, valid_moves, self.search_depth)
    
    def _iterative_deepening_search(self, game_state: NNUEGameAdapter, valid_moves: List[Tuple[int, int, int, int]]) -> Optional[Tuple[int, int, int, int]]:
        """Iterative deepening search for better move ordering"""
        best_move = None
        position_hash = self.position_hasher.hash_position(game_state)
        
        # Start with shallow search and gradually increase depth
        for current_depth in range(1, self.search_depth + 1):
            # Check transposition table for move ordering hint from previous iterations
            tt_found, tt_score, tt_best_move = self.transposition_table.probe(
                position_hash, current_depth, float('-inf'), float('inf'))
            
            # Order moves using TT best move from previous iterations
            ordered_moves = self.order_moves(game_state, valid_moves, tt_best_move or best_move, current_depth)
            
            alpha = float('-inf')
            beta = float('inf')
            current_best_move = None
            
            for move in ordered_moves:
                success, undo_info = game_state.make_move_and_undo(move)
                if success:
                    if game_state.side_to_move == 0:  # White (maximizing) - note: side_to_move changed after move
                        score = self._alpha_beta(game_state, current_depth - 1, alpha, beta, True)  # Now it's black's turn
                        if score > alpha:
                            alpha = score
                            current_best_move = move
                            if current_depth == self.search_depth:  # Final iteration
                                best_move = move
                    else:  # Black (minimizing)
                        score = self._alpha_beta(game_state, current_depth - 1, alpha, beta, False)  # Now it's white's turn
                        if score < beta:
                            beta = score
                            current_best_move = move
                            if current_depth == self.search_depth:  # Final iteration
                                best_move = move
                    
                    # Undo the move
                    game_state.undo_move(undo_info)
            
            # Store result in transposition table for next iteration
            if current_best_move:
                final_score = alpha if game_state.side_to_move == 0 else beta
                self.transposition_table.store(
                    position_hash, current_depth, final_score, TTEntryType.EXACT, current_best_move)
                
                # Update best move from this iteration
                if current_depth < self.search_depth:
                    best_move = current_best_move
        
        return best_move or valid_moves[0]  # Fallback to first move if no best move found
    
    def _fixed_depth_search(self, game_state: NNUEGameAdapter, valid_moves: List[Tuple[int, int, int, int]], depth: int) -> Optional[Tuple[int, int, int, int]]:
        """Fixed depth search (fallback for shallow searches)"""
        position_hash = self.position_hasher.hash_position(game_state)
        
        # Check transposition table for move ordering hint
        tt_found, tt_score, tt_best_move = self.transposition_table.probe(
            position_hash, depth, float('-inf'), float('inf'))
            
        # Order moves using TT best move and optimizations
        ordered_moves = self.order_moves(game_state, valid_moves, tt_best_move, depth)
        
        alpha = float('-inf')
        beta = float('inf')
        best_move = None
        
        for move in ordered_moves:
            success, undo_info = game_state.make_move_and_undo(move)
            if success:
                if game_state.side_to_move == 0:  # White (maximizing) - note: side_to_move changed after move
                    score = self._alpha_beta(game_state, depth - 1, alpha, beta, True)  # Now it's black's turn
                    if score > alpha:
                        alpha = score
                        best_move = move
                else:  # Black (minimizing)
                    score = self._alpha_beta(game_state, depth - 1, alpha, beta, False)  # Now it's white's turn
                    if score < beta:
                        beta = score
                        best_move = move
                
                # Undo the move
                game_state.undo_move(undo_info)
        
        # Store result in transposition table
        if best_move:
            final_score = alpha if game_state.side_to_move == 0 else beta
            self.transposition_table.store(
                position_hash, depth, final_score, TTEntryType.EXACT, best_move)
        
        return best_move or valid_moves[0]
        
    def _alpha_beta(self, game_state: NNUEGameAdapter, depth: int, 
                    alpha: float, beta: float, maximizing: bool) -> float:
        """Alpha-Beta pruning search with Transposition Table and NNUE evaluation"""
        self.nodes_searched += 1
        original_alpha = alpha
        
        # Probe transposition table
        position_hash = self.position_hasher.hash_position(game_state)
        tt_found, tt_score, tt_best_move = self.transposition_table.probe(
            position_hash, depth, alpha, beta)
        
        if tt_found:
            self.tt_hits += 1
            return tt_score
        else:
            self.tt_misses += 1
        
        # Check if game is over or reached depth limit
        is_over, reason = game_state.is_game_over()
        if is_over or depth == 0:
            leaf_score = self.evaluate_position(game_state)
            # Store leaf evaluation in TT
            self.transposition_table.store(
                position_hash, depth, leaf_score, TTEntryType.EXACT, None)
            return leaf_score
            
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            leaf_score = self.evaluate_position(game_state)
            self.transposition_table.store(
                position_hash, depth, leaf_score, TTEntryType.EXACT, None)
            return leaf_score
            
        # Null move pruning - try skipping a move to see if position is still good
        if (self.use_null_move_pruning and depth >= 3 and not maximizing and 
            len(valid_moves) > 3):  # Only for non-critical positions
            # Switch sides without making a move
            original_player = game_state.current_player
            game_state.current_player = -game_state.current_player
            
            # Search with reduced depth
            null_score = self._alpha_beta(game_state, depth - 3, alpha, beta, True)
            
            # Restore original player
            game_state.current_player = original_player
            
            # If null move causes beta cutoff, we can prune this branch
            if null_score >= beta:
                self.cutoffs += 1
                return beta
        
        # Order moves using TT best move hint and optimized evaluation for better pruning
        ordered_moves = self.order_moves(game_state, valid_moves, tt_best_move, depth)
        
        best_move = None
        best_score = float('-inf') if maximizing else float('inf')
            
        if maximizing:
            for move in ordered_moves:
                success, undo_info = game_state.make_move_and_undo(move)
                if success:
                    eval_score = self._alpha_beta(game_state, depth - 1, alpha, beta, False)
                    game_state.undo_move(undo_info)  # Undo immediately after recursive call
                    
                    if eval_score > best_score:
                        best_score = eval_score
                        best_move = move
                    alpha = max(alpha, eval_score)
                    if beta <= alpha:
                        self.cutoffs += 1
                        break  # Beta cutoff - pruning
        else:
            for move in ordered_moves:
                success, undo_info = game_state.make_move_and_undo(move)
                if success:
                    eval_score = self._alpha_beta(game_state, depth - 1, alpha, beta, True)
                    game_state.undo_move(undo_info)  # Undo immediately after recursive call
                    
                    if eval_score < best_score:
                        best_score = eval_score
                        best_move = move
                    beta = min(beta, eval_score)
                    if beta <= alpha:
                        self.cutoffs += 1
                        break  # Alpha cutoff - pruning
        
        # Determine entry type for transposition table
        if best_score <= original_alpha:
            entry_type = TTEntryType.UPPER_BOUND  # Fail-low
        elif best_score >= beta:
            entry_type = TTEntryType.LOWER_BOUND  # Fail-high
        else:
            entry_type = TTEntryType.EXACT  # Exact score
        
        # Store result in transposition table
        self.transposition_table.store(
            position_hash, depth, best_score, entry_type, best_move)
        
        return best_score

    def set_search_depth(self, depth: int):
        """Set search depth dynamically"""
        self.search_depth = max(1, depth)
        
    def set_randomness(self, use_randomness: bool):
        """Set randomness behavior dynamically"""
        self.use_randomness = use_randomness
    
    def set_iterative_deepening(self, use_iterative_deepening: bool):
        """Enable/disable iterative deepening"""
        self.use_iterative_deepening = use_iterative_deepening
        logger.info(f"Iterative deepening {'enabled' if use_iterative_deepening else 'disabled'}")
    
    def set_lazy_evaluation(self, use_lazy_evaluation: bool):
        """Enable/disable lazy evaluation optimizations"""
        self.use_lazy_evaluation = use_lazy_evaluation
        logger.info(f"Lazy evaluation {'enabled' if use_lazy_evaluation else 'disabled'}")
    
    def set_null_move_pruning(self, use_null_move_pruning: bool):
        """Enable/disable null move pruning"""
        self.use_null_move_pruning = use_null_move_pruning
        logger.info(f"Null move pruning {'enabled' if use_null_move_pruning else 'disabled'}")
    
    def clear_transposition_table(self):
        """Clear the transposition table (useful for new games)"""
        self.transposition_table.clear()
        self._move_order_cache.clear()
        self._cache_age += 1
        logger.info("Transposition table and caches cleared")
    
    def get_tt_statistics(self) -> Dict[str, Any]:
        """Get detailed transposition table statistics"""
        return self.transposition_table.get_statistics()

    def get_search_stats(self) -> str:
        """Get search statistics for performance monitoring including TT and NNUE stats"""
        if self.nodes_searched == 0:
            return "No search performed yet"
        
        cutoff_rate = (self.cutoffs / max(1, self.nodes_searched)) * 100
        tt_total = self.tt_hits + self.tt_misses
        tt_hit_rate = (self.tt_hits / max(1, tt_total)) * 100
        nnue_per_node = self.nnue_evaluations / max(1, self.nodes_searched)
        randomness_str = "Random" if self.use_randomness else "Deterministic"
        iterative_str = "ID" if self.use_iterative_deepening else "Fixed"
        
        tt_stats = self.transposition_table.get_statistics()
        
        return (f"Depth: {self.search_depth} ({iterative_str}), Nodes: {self.nodes_searched}, "
                f"Cutoffs: {self.cutoffs} ({cutoff_rate:.1f}%), "
                f"NNUE Evals: {self.nnue_evaluations} ({nnue_per_node:.1f}/node), "
                f"TT Hits: {self.tt_hits}/{tt_total} ({tt_hit_rate:.1f}%), "
                f"Mode: {randomness_str}")


class NNUEGameGUI:
    """Simple GUI for NNUE human vs AI games - uses ml/game logic"""
    
    def __init__(self, nnue_player: NNUEPlayer, human_first: bool = True):
        self.nnue_player = nnue_player
        self.human_first = human_first
        self.game_state = NNUEGameAdapter()
        
        # Following AlphaZero's player mapping logic
        # players[curPlayer + 1] gives the correct player object
        if human_first:
            # Human is player1 (curPlayer=1), AI is player2 (curPlayer=-1)  
            self.players = [self.nnue_player, None, self]  # [player2, None, player1]
            self.human_player_value = 1   # curPlayer value when human plays
            self.ai_player_value = -1     # curPlayer value when AI plays
        else:
            # AI is player1 (curPlayer=1), Human is player2 (curPlayer=-1)
            self.players = [self, None, self.nnue_player]  # [player2, None, player1]  
            self.human_player_value = -1  # curPlayer value when human plays
            self.ai_player_value = 1      # curPlayer value when AI plays
        
        # Try to import tkinter
        try:
            import tkinter as tk
            from tkinter import messagebox
            self.tk = tk
            self.messagebox = messagebox
        except ImportError:
            raise RuntimeError("Tkinter not available. GUI mode requires tkinter.")
            
        self.root = None
        self.canvas = None
        self.status_label = None
        self.selected_pos = None
        self.game_over = False
        
        # Last move display (like alphazero)
        self._last_move_canvas_id = None
        self.last_move_text = ""
        
        # Evaluation display
        self.current_evaluation = 0.0
        
    def start_gui(self):
        """Start the GUI game"""
        self.root = self.tk.Tk()
        self.root.title("Sanmill NNUE - Human vs AI")
        self.root.geometry("700x850")  # 增加高度以容纳评估显示
        
        # Status label
        self.status_label = self.tk.Label(self.root, text="Game started", font=("Arial", 12))
        self.status_label.pack(pady=10)
        
        # NNUE Evaluation display frame
        eval_frame = self.tk.Frame(self.root)
        eval_frame.pack(pady=5)
        
        # Evaluation label
        self.eval_label = self.tk.Label(eval_frame, text="NNUE 评估: 计算中...", 
                                       font=("Arial", 14, "bold"), fg="#333")
        self.eval_label.pack()
        
        # Evaluation progress bar (visual representation)
        eval_bar_frame = self.tk.Frame(eval_frame)
        eval_bar_frame.pack(pady=5)
        
        self.eval_canvas = self.tk.Canvas(eval_bar_frame, width=300, height=20, bg="#ddd")
        self.eval_canvas.pack()
        
        # Human perspective indicator
        self.perspective_label = self.tk.Label(eval_frame, text="(Human 视角)", 
                                             font=("Arial", 10), fg="#666")
        self.perspective_label.pack()
        
        # Canvas for board
        # Updated canvas for professional board layout
        canvas_width = 600
        canvas_height = 600  
        self.canvas = self.tk.Canvas(self.root, width=canvas_width, height=canvas_height, bg="#cfcfcf")
        self.canvas.pack(pady=10)
        self.canvas.bind("<Button-1>", self.on_click)
        
        # Settings frame (above control buttons)
        settings_frame = self.tk.Frame(self.root)
        settings_frame.pack(pady=10)
        
        # Search depth setting
        depth_label = self.tk.Label(settings_frame, text="Search Depth:")
        depth_label.pack(side=self.tk.LEFT, padx=5)
        
        # Import ttk for better combobox
        try:
            from tkinter import ttk
            self.depth_var = self.tk.StringVar(value=str(self.nnue_player.search_depth))
            depth_combobox = ttk.Combobox(settings_frame, textvariable=self.depth_var, 
                                        values=["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"], 
                                        width=5, state="readonly")
            depth_combobox.pack(side=self.tk.LEFT, padx=5)
            depth_combobox.bind("<<ComboboxSelected>>", self.on_depth_changed)
        except ImportError:
            # Fallback to regular entry if ttk not available
            self.depth_var = self.tk.StringVar(value=str(self.nnue_player.search_depth))
            depth_entry = self.tk.Entry(settings_frame, textvariable=self.depth_var, width=5)
            depth_entry.pack(side=self.tk.LEFT, padx=5)
            depth_entry.bind("<Return>", self.on_depth_changed)
        
        # Randomness setting
        randomness_label = self.tk.Label(settings_frame, text="Mode:")
        randomness_label.pack(side=self.tk.LEFT, padx=(20, 5))
        
        try:
            from tkinter import ttk
            self.randomness_var = self.tk.StringVar(value="Deterministic" if not self.nnue_player.use_randomness else "Random")
            randomness_combobox = ttk.Combobox(settings_frame, textvariable=self.randomness_var,
                                             values=["Deterministic", "Random"],
                                             width=12, state="readonly")
            randomness_combobox.pack(side=self.tk.LEFT, padx=5)
            randomness_combobox.bind("<<ComboboxSelected>>", self.on_randomness_changed)
        except ImportError:
            # Fallback to checkbutton if ttk not available
            self.randomness_var = self.tk.BooleanVar(value=self.nnue_player.use_randomness)
            randomness_check = self.tk.Checkbutton(settings_frame, text="Random", 
                                                  variable=self.randomness_var,
                                                  command=self.on_randomness_changed)
            randomness_check.pack(side=self.tk.LEFT, padx=5)

        # Control buttons
        button_frame = self.tk.Frame(self.root)
        button_frame.pack(pady=10)
        
        restart_btn = self.tk.Button(button_frame, text="Restart", command=self.restart_game)
        restart_btn.pack(side=self.tk.LEFT, padx=5)
        
        quit_btn = self.tk.Button(button_frame, text="Quit", command=self.safe_quit)
        quit_btn.pack(side=self.tk.LEFT, padx=5)
        
        # Draw initial board
        self.draw_board()
        self.update_status()
        self.update_evaluation_display()
        
        # Set up window close protocol to use safe quit
        self.root.protocol("WM_DELETE_WINDOW", self.safe_quit)
        
        # If AI goes first, make AI move - use AlphaZero logic
        initial_player_obj = self.players[self.game_state.current_player + 1]  # current_player starts as 1
        if initial_player_obj == self.nnue_player:
            self.root.after(1000, self.make_ai_move)
            
        self.root.mainloop()
        
    def draw_board(self):
        """Draw the game board using alphazero-style professional rendering"""
        self.canvas.delete("all")
        
        # Board configuration (matching alphazero layout)
        board_size_px = 480
        cell_px = board_size_px // 7  # alphazero uses 7, not 6
        margin_left = margin_right = int(cell_px * 1.0)
        margin_top = margin_bottom = int(cell_px * 0.9)
        piece_radius = max(10, int(cell_px * 0.33))
        coord_font_size = max(10, int(cell_px * 0.23))
        
        def xy_to_canvas_center(x, y):
            """Convert board coordinates to canvas center position"""
            cx = margin_left + x * cell_px + cell_px // 2
            cy = margin_top + y * cell_px + cell_px // 2
            return cx, cy
        
        # Standard Nine Men's Morris adjacency connections
        connections = [
            # Outer ring
            [(0,0), (3,0)], [(3,0), (6,0)], [(6,0), (6,3)], [(6,3), (6,6)],
            [(6,6), (3,6)], [(3,6), (0,6)], [(0,6), (0,3)], [(0,3), (0,0)],
            # Middle ring  
            [(1,1), (3,1)], [(3,1), (5,1)], [(5,1), (5,3)], [(5,3), (5,5)],
            [(5,5), (3,5)], [(3,5), (1,5)], [(1,5), (1,3)], [(1,3), (1,1)],
            # Inner ring
            [(2,2), (3,2)], [(3,2), (4,2)], [(4,2), (4,3)], [(4,3), (4,4)],
            [(4,4), (3,4)], [(3,4), (2,4)], [(2,4), (2,3)], [(2,3), (2,2)],
            # Cross connections
            [(3,0), (3,1)], [(3,1), (3,2)], [(3,4), (3,5)], [(3,5), (3,6)],
            [(0,3), (1,3)], [(1,3), (2,3)], [(4,3), (5,3)], [(5,3), (6,3)]
        ]
        
        # Draw board lines first (underneath pieces)
        for (x1, y1), (x2, y2) in connections:
            cx1, cy1 = xy_to_canvas_center(x1, y1)
            cx2, cy2 = xy_to_canvas_center(x2, y2)
            self.canvas.create_line(cx1, cy1, cx2, cy2, fill="#666", width=3)
        
        # Draw coordinate labels (matching alphazero positioning)
        # Row numbers (7..1) on the left - positioned outside board area
        for y in range(7):
            text_y = margin_top + y * cell_px + cell_px // 2
            self.canvas.create_text(margin_left * 0.5, text_y, text=str(7 - y), 
                                  fill="#444", font=("Arial", coord_font_size))
        
        # Column letters (a..g) at the bottom - positioned outside board area
        letters = ["a", "b", "c", "d", "e", "f", "g"]
        base_y = margin_top + board_size_px + margin_bottom * 0.15
        for x in range(7):
            text_x = margin_left + x * cell_px + cell_px // 2
            self.canvas.create_text(text_x, base_y, text=letters[x], 
                                  fill="#444", font=("Arial", coord_font_size))
        
        # Draw pieces only where they exist (clean professional look)
        for x, y in self.game_state.valid_positions:
            piece = self.game_state.board.pieces[x][y]
            if piece != 0:  # Has a piece (ml/game uses 0 for empty)
                cx, cy = xy_to_canvas_center(x, y)
                
                if piece == 1:  # White piece (ml/game uses 1 for white)
                    fill_color = "#ffffff"
                    outline_color = "#888"
                else:  # Black piece (ml/game uses -1 for black)
                    fill_color = "#000000"
                    outline_color = "#888"
                
                # Draw piece with professional styling
                self.canvas.create_oval(cx - piece_radius, cy - piece_radius, 
                                      cx + piece_radius, cy + piece_radius,
                                      fill=fill_color, outline=outline_color, width=2)
        
        # Highlight selected position (orange border like alphazero)
        if self.selected_pos:
            x, y = self.selected_pos
            cx, cy = xy_to_canvas_center(x, y)
            self.canvas.create_oval(cx - piece_radius - 4, cy - piece_radius - 4,
                                  cx + piece_radius + 4, cy + piece_radius + 4,
                                  outline="#e67e22", width=4, fill="")
        
        # Highlight removable pieces in removal phase (red border)
        if self.game_state.phase == 3:
            removable = self.game_state.get_removable_pieces(self.game_state.side_to_move)
            for x, y in removable:
                cx, cy = xy_to_canvas_center(x, y)
                self.canvas.create_oval(cx - piece_radius - 2, cy - piece_radius - 2,
                                      cx + piece_radius + 2, cy + piece_radius + 2,
                                      outline="#ff0000", width=3, fill="")
        
        # Store configuration for click handling
        self._margin_left = margin_left
        self._margin_top = margin_top  
        self._cell_px = cell_px
        self._xy_to_canvas_center = xy_to_canvas_center
        
        # Display last move notation (simplified version)
        self.display_last_move()
    
    def display_last_move(self):
        """Display last move notation on canvas"""
        if hasattr(self, '_last_move_canvas_id') and self._last_move_canvas_id:
            try:
                self.canvas.delete(self._last_move_canvas_id)
            except:
                pass
        
        if hasattr(self, 'last_move_text') and self.last_move_text:
            margin_left = getattr(self, '_margin_left', 68)
            margin_top = getattr(self, '_margin_top', 61)
            # Position text at the top center of the canvas, well above the board
            text_x = self.canvas.winfo_reqwidth() // 2  # Canvas center
            text_y = margin_top // 3  # Above the board with good spacing
            
            self._last_move_canvas_id = self.canvas.create_text(
                text_x, text_y, text=self.last_move_text, 
                fill="black", font=("Arial", 12, "bold"), anchor="center"
            )
    
    def move_to_notation(self, move, player_name, is_removal=False):
        """Convert move to standard notation using alphazero's engine notation"""
        if not move or len(move) < 2:
            return ""
        
        try:
            # Convert to standard engine notation
            if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                # Convert 4-tuple place/remove to 2-tuple for engine_adapter
                notation = move_to_engine_token([move[0], move[1]])
            else:
                notation = move_to_engine_token(move)
            
            # Add capture prefix only for actual removal moves
            if is_removal:
                notation = f"x{notation}"
            
            return f"Last: {player_name} {notation}"
        except Exception:
            # Fallback to simple coordinate display
            letters = "abcdefg"
            def pos_to_coord(x, y):
                return letters[x] + str(7 - y)
            
            if len(move) == 2 or (len(move) == 4 and move[0] == move[2] and move[1] == move[3]):
                coord = pos_to_coord(move[0], move[1])
                if is_removal:
                    return f"Last: {player_name} removes {coord}"
                else:
                    return f"Last: {player_name} places {coord}"
            else:
                from_coord = pos_to_coord(move[0], move[1])
                to_coord = pos_to_coord(move[2], move[3])
                return f"Last: {player_name} {from_coord}-{to_coord}"
    
    def get_human_perspective_evaluation(self) -> float:
        """计算从 Human 视角下的局面评估值"""
        if self.game_over:
            return 0.0
            
        # 获取原始 NNUE 评估
        raw_evaluation = self.nnue_player.evaluate_position(self.game_state)
        
        # 转换为 Human 视角的评估值
        # Human 玩家的 player_value 是 self.human_player_value (1 或 -1)
        # 如果 Human 是白棋 (player_value = 1)，直接使用评估值
        # 如果 Human 是黑棋 (player_value = -1)，取相反数
        if self.human_player_value == 1:
            # Human 是白棋，正数对 Human 有利
            return raw_evaluation
        else:
            # Human 是黑棋，负数对 Human 有利，所以取相反数
            return -raw_evaluation
    
    def update_evaluation_display(self):
        """更新评估值显示"""
        if self.game_over:
            self.eval_label.config(text="NNUE 评估: 游戏结束")
            self.eval_canvas.delete("all")
            return
            
        # 计算 Human 视角的评估值
        self.current_evaluation = self.get_human_perspective_evaluation()
        
        # 格式化显示文本
        if abs(self.current_evaluation) > 10:
            # 极端优势
            eval_text = f"NNUE 评估: {self.current_evaluation:+.1f} (决定性优势)"
        elif abs(self.current_evaluation) > 3:
            # 明显优势
            eval_text = f"NNUE 评估: {self.current_evaluation:+.1f} (明显优势)"
        elif abs(self.current_evaluation) > 1:
            # 轻微优势
            eval_text = f"NNUE 评估: {self.current_evaluation:+.1f} (轻微优势)"
        else:
            # 均势
            eval_text = f"NNUE 评估: {self.current_evaluation:+.1f} (均势)"
            
        self.eval_label.config(text=eval_text)
        
        # 更新评估进度条
        self.draw_evaluation_bar()
    
    def draw_evaluation_bar(self):
        """绘制评估值进度条"""
        self.eval_canvas.delete("all")
        
        # 进度条配置
        bar_width = 300
        bar_height = 20
        
        # 将评估值映射到 [-1, 1] 范围，使用 tanh 函数平滑映射
        import math
        normalized_eval = math.tanh(self.current_evaluation / 3.0)  # 3.0 是缩放因子
        
        # 计算进度条位置
        center_x = bar_width // 2
        bar_position = center_x + (normalized_eval * center_x * 0.9)  # 0.9 留边距
        
        # 绘制背景
        self.eval_canvas.create_rectangle(0, 0, bar_width, bar_height, 
                                        fill="#e0e0e0", outline="#ccc")
        
        # 绘制中线
        self.eval_canvas.create_line(center_x, 0, center_x, bar_height, 
                                   fill="#888", width=2)
        
        # 绘制评估值指示器
        if normalized_eval > 0:
            # Human 优势，绿色
            color = "#4CAF50"
            self.eval_canvas.create_rectangle(center_x, 2, bar_position, bar_height - 2,
                                            fill=color, outline=color)
        else:
            # Human 劣势，红色  
            color = "#f44336"
            self.eval_canvas.create_rectangle(bar_position, 2, center_x, bar_height - 2,
                                            fill=color, outline=color)
        
        # 添加刻度标记
        for i in [-1, -0.5, 0, 0.5, 1]:
            x = center_x + (i * center_x * 0.9)
            self.eval_canvas.create_line(x, bar_height - 5, x, bar_height, 
                                       fill="#666", width=1)
                                  
    def on_click(self, event):
        """Handle mouse click on board"""
        # Check if it's human's turn using AlphaZero logic
        current_player_obj = self.players[self.game_state.current_player + 1]
        if self.game_over or current_player_obj != self:
            return  # Not human's turn
            
        # Convert click to board position using alphazero-style coordinate system
        margin_left = getattr(self, '_margin_left', 68)
        margin_top = getattr(self, '_margin_top', 61)
        cell_px = getattr(self, '_cell_px', 68)
        
        # Calculate board position from canvas click (like alphazero)
        lx = event.x - margin_left
        ly = event.y - margin_top
        if lx < 0 or ly < 0 or lx >= 480 or ly >= 480:
            return  # Click outside board area
            
        clicked_x = max(0, min(6, int(lx // cell_px)))
        clicked_y = max(0, min(6, int(ly // cell_px)))
        
        if not self.game_state.is_valid_position(clicked_x, clicked_y):
            return
            
        if self.game_state.phase == 3:  # Removing phase
            # Click to remove opponent piece - opponent is the opposite of current player
            opponent = -self.game_state.current_player  # ml/game uses 1/-1 format
            if self.game_state.board.pieces[clicked_x][clicked_y] == opponent:
                # Check if this piece can be removed
                removable = self.game_state.get_removable_pieces(self.game_state.side_to_move)
                if (clicked_x, clicked_y) in removable:
                    move = (clicked_x, clicked_y, clicked_x, clicked_y)
                    if self.game_state.make_move(move):
                        # Record last move
                        player_name = "Human"
                        self.last_move_text = self.move_to_notation(move, player_name, is_removal=True)
                        
                        # Log Human move with standard notation
                        try:
                            notation = move_to_engine_token([move[0], move[1]])
                            notation = f"x{notation}"  # Add capture prefix for removal
                            logger.info(f"Human move: {notation}")
                        except Exception:
                            x1, y1, x2, y2 = move
                            logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2}) [remove]")
                        
                        self.draw_board()
                        self.update_status()
                        self.update_evaluation_display()
                        if not self.game_over:
                            # Check if it's AI's turn using AlphaZero logic
                            current_player_obj = self.players[self.game_state.current_player + 1]
                            if current_player_obj == self.nnue_player:
                                self.root.after(500, self.make_ai_move)
        elif self.game_state.phase == 0:  # Placing phase
            if self.game_state.board.pieces[clicked_x][clicked_y] == 0:  # Empty position (ml/game uses 0 for empty)
                move = (clicked_x, clicked_y, clicked_x, clicked_y)
                if self.game_state.make_move(move):
                    # Record last move
                    player_name = "Human"
                    self.last_move_text = self.move_to_notation(move, player_name, is_removal=False)
                    
                    # Log Human move with standard notation
                    try:
                        if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                            notation = move_to_engine_token([move[0], move[1]])
                        else:
                            notation = move_to_engine_token(move)
                        # Don't add 'x' prefix for placement moves, even if they lead to capture phase
                        logger.info(f"Human move: {notation}")
                    except Exception:
                        x1, y1, x2, y2 = move
                        logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2})")
                    
                    self.draw_board()
                    self.update_status()
                    self.update_evaluation_display()
                    if not self.game_over:
                        # Check if it's AI's turn using AlphaZero logic
                        current_player_obj = self.players[self.game_state.current_player + 1]
                        if current_player_obj == self.nnue_player:
                            self.root.after(500, self.make_ai_move)
        else:  # Moving/Flying phase
            if self.selected_pos is None:
                # Select piece to move - use the human player value from our mapping
                if self.game_state.board.pieces[clicked_x][clicked_y] == self.human_player_value:
                    self.selected_pos = (clicked_x, clicked_y)
                    self.draw_board()
            else:
                # Move piece
                if self.game_state.board.pieces[clicked_x][clicked_y] == 0:  # Empty position (ml/game uses 0 for empty)
                    move = (self.selected_pos[0], self.selected_pos[1], clicked_x, clicked_y)
                    if self.game_state.make_move(move):
                        # Record last move
                        player_name = "Human"
                        self.last_move_text = self.move_to_notation(move, player_name, is_removal=False)
                        
                        # Log Human move with standard notation
                        try:
                            notation = move_to_engine_token(move)
                            # Don't add 'x' prefix for movement moves, even if they lead to capture phase
                            logger.info(f"Human move: {notation}")
                        except Exception:
                            x1, y1, x2, y2 = move
                            logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2})")
                        
                        self.selected_pos = None
                        self.draw_board()
                        self.update_status()
                        self.update_evaluation_display()
                        if not self.game_over:
                            # Check if it's AI's turn using AlphaZero logic
                            current_player_obj = self.players[self.game_state.current_player + 1]
                            if current_player_obj == self.nnue_player:
                                self.root.after(500, self.make_ai_move)
                else:
                    self.selected_pos = None
                    self.draw_board()
                    
    def make_ai_move(self):
        """Make AI move"""
        if self.game_over:
            return
            
        # Check if it's actually AI's turn using AlphaZero logic
        current_player_obj = self.players[self.game_state.current_player + 1]
        if current_player_obj != self.nnue_player:
            return  # Not AI's turn
            
        self.update_status("AI is thinking...")
        
        # Use threading to prevent GUI freezing
        def ai_move_thread():
            move = self.nnue_player.get_best_move(self.game_state)
            if move:
                # Remember the phase before making the move to determine if it's a removal
                phase_before_move = self.game_state.phase
                self.game_state.make_move(move)
                # Determine if this was a removal move based on pre-move phase and move pattern
                is_removal = (phase_before_move == 3 and len(move) == 4 and move[0] == move[2] and move[1] == move[3])
            else:
                is_removal = False
            
            # Update GUI in main thread
            self.root.after(0, lambda: self.after_ai_move(move, is_removal))
            
        thread = threading.Thread(target=ai_move_thread, daemon=True)
        thread.start()
        
    def after_ai_move(self, move, is_removal=False):
        """Update GUI after AI move"""
        # Record last move for AI
        if move:
            player_name = "AI"
            self.last_move_text = self.move_to_notation(move, player_name, is_removal=is_removal)
            
            # Log AI move with standard notation and search statistics
            search_stats = self.nnue_player.get_search_stats()
            try:
                if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                    notation = move_to_engine_token([move[0], move[1]])
                else:
                    notation = move_to_engine_token(move)
                # Only add 'x' prefix for actual removal moves
                if is_removal:
                    notation = f"x{notation}"
                logger.info(f"AI move: {notation} | {search_stats}")
            except Exception:
                x1, y1, x2, y2 = move
                move_type = " [remove]" if is_removal else ""
                logger.info(f"AI move: ({x1},{y1}) -> ({x2},{y2}){move_type} | {search_stats}")
        else:
            logger.info("AI has no valid moves")
            
        self.draw_board()
        self.update_status()
        self.update_evaluation_display()
        
        # Check if it's now human's turn and trigger AI if needed
        if not self.game_over:
            current_player_obj = self.players[self.game_state.current_player + 1]
            if current_player_obj == self.nnue_player:
                # Still AI's turn (e.g., in capture phase)
                self.root.after(500, self.make_ai_move)
            
    def update_status(self, message: Optional[str] = None):
        """Update status label"""
        if message:
            self.status_label.config(text=message)
            return
            
        if self.game_state.phase == 0:
            phase_text = "Placing phase"
        elif self.game_state.phase == 1:
            phase_text = "Moving phase"
        elif self.game_state.phase == 2:
            phase_text = "Flying phase"
        else:  # phase == 3
            phase_text = "Remove opponent piece"
            
        # Use AlphaZero logic to determine current player
        current_player_obj = self.players[self.game_state.current_player + 1]
        current_player = "Human" if current_player_obj == self else "AI"
        
        pieces_info = f"White: {self.game_state.white_pieces_on_board}+{self.game_state.white_pieces_in_hand}, " \
                     f"Black: {self.game_state.black_pieces_on_board}+{self.game_state.black_pieces_in_hand}"
        
        status_text = f"{phase_text} | {current_player}'s turn | {pieces_info}"
        self.status_label.config(text=status_text)
        
        # Check for game over using comprehensive ml/game logic
        is_over, reason = self.game_state.is_game_over()
        if is_over:
            self.game_over = True
            
            # Use check_game_over_conditions to get the actual result for determining winner
            _, result, _ = self.game_state.board.check_game_over_conditions(self.game_state.current_player)
            if abs(result) < 1e-4:
                # Draw
                self.messagebox.showinfo("Game Over", f"Game ended in a draw! Reason: {reason}")
            elif result > 0:
                # Current player wins
                winner = current_player
                self.messagebox.showinfo("Game Over", f"{winner} wins! Reason: {reason}")
            else:
                # Current player loses
                winner = "AI" if current_player == "Human" else "Human"
                self.messagebox.showinfo("Game Over", f"{winner} wins! Reason: {reason}")
        elif not self.game_state.get_valid_moves():
            # Fallback: no valid moves (should be caught by ml/game logic above)
            self.game_over = True
            winner = "AI" if current_player == "Human" else "Human"
            self.messagebox.showinfo("Game Over", f"{winner} wins! (No valid moves)")
            
    def on_depth_changed(self, event=None):
        """Handle search depth change"""
        try:
            new_depth = int(self.depth_var.get())
            if 1 <= new_depth <= 10:
                self.nnue_player.set_search_depth(new_depth)
                logger.info(f"Search depth changed to: {new_depth}")
                self.update_status()
            else:
                # Reset to current value if invalid
                self.depth_var.set(str(self.nnue_player.search_depth))
        except ValueError:
            # Reset to current value if not a number
            self.depth_var.set(str(self.nnue_player.search_depth))
    
    def on_randomness_changed(self, event=None):
        """Handle randomness setting change"""
        try:
            if hasattr(self.randomness_var, 'get'):
                if isinstance(self.randomness_var.get(), bool):
                    # BooleanVar (checkbutton)
                    use_random = self.randomness_var.get()
                else:
                    # StringVar (combobox)
                    use_random = (self.randomness_var.get() == "Random")
                
                self.nnue_player.set_randomness(use_random)
                mode_str = "Random" if use_random else "Deterministic"
                logger.info(f"AI mode changed to: {mode_str}")
                self.update_status()
        except Exception as e:
            logger.error(f"Error changing randomness setting: {e}")

    def safe_quit(self):
        """Safely quit the application to avoid Tkinter theme change errors"""
        try:
            if self.root and self.root.winfo_exists():
                # Cancel any pending after() calls to prevent ThemeChanged errors
                try:
                    # Try to cancel all pending after calls
                    self.root.after_cancel("all")
                except:
                    pass
                
                # Unbind all events to prevent further callbacks
                try:
                    self.root.unbind_all("<Key>")
                    self.root.unbind_all("<Button>")
                except:
                    pass
                
                # Withdraw the window first to hide it immediately
                try:
                    self.root.withdraw()
                except:
                    pass
                
                # Then destroy the window properly
                self.root.destroy()
        except Exception as e:
            # If destroy fails, try quit as last resort
            try:
                if self.root:
                    self.root.quit()
            except:
                # If everything fails, exit the process
                import sys
                sys.exit(0)

    def restart_game(self):
        """Restart the game"""
        self.game_state = NNUEGameAdapter()
        self.selected_pos = None
        self.game_over = False
        self.last_move_text = ""  # Clear last move
        
        # Clear transposition table for fresh start
        self.nnue_player.clear_transposition_table()
        
        self.draw_board()
        self.update_status()
        self.update_evaluation_display()
        
        # Check if AI should go first using AlphaZero logic
        initial_player_obj = self.players[self.game_state.current_player + 1]  # current_player starts as 1
        if initial_player_obj == self.nnue_player:
            self.root.after(1000, self.make_ai_move)


def create_config_file(filename: str):
    """Create a sample configuration file"""
    config = {
        "model_path": "nnue_model.bin",
        "feature_size": 115,
        "hidden_size": 256,
        "search_depth": 8,
        "use_randomness": False,
        "human_first": True,
        "gui": True,
        "log_level": "INFO",
        "tt_size_mb": 64,  # Transposition Table size in megabytes
        "use_iterative_deepening": True,  # Enable iterative deepening
        "use_lazy_evaluation": True,  # Enable lazy evaluation optimizations
        "use_null_move_pruning": True  # Enable null move pruning
    }
    
    with open(filename, 'w') as f:
        json.dump(config, f, indent=2)
    
    logger.info(f"Created sample config file: {filename}")


def main():
    parser = argparse.ArgumentParser(
        description='NNUE Pitting Script for Sanmill',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python nnue_pit.py --config my_config.json --gui --first human
  python nnue_pit.py --model nnue_model.bin --gui
  python nnue_pit.py --model nnue_model.bin --games 5 --first ai
  python nnue_pit.py --create-config sample_config.json
        """
    )
    
    parser.add_argument('--config', type=str, help='Configuration file (JSON format)')
    parser.add_argument('--model', type=str, help='NNUE model file (.bin or .pth)')
    parser.add_argument('--gui', action='store_true', help='Enable GUI mode')
    parser.add_argument('--first', choices=['human', 'ai'], default='human',
                       help='Who plays first (default: human)')
    parser.add_argument('--games', type=int, default=1, help='Number of games to play')
    parser.add_argument('--depth', type=int, default=8, help='AI search depth')
    parser.add_argument('--random', action='store_true', help='Enable random move selection among equal best moves')
    parser.add_argument('--feature-size', type=int, default=115, help='NNUE feature size')
    parser.add_argument('--hidden-size', type=int, default=256, help='NNUE hidden size')
    parser.add_argument('--use-gpu', action='store_true', help='Force GPU usage (not recommended for NNUE)')
    parser.add_argument('--tt-size', type=int, default=64, help='Transposition table size in MB')
    parser.add_argument('--no-iterative-deepening', action='store_true', help='Disable iterative deepening')
    parser.add_argument('--no-lazy-evaluation', action='store_true', help='Disable lazy evaluation optimizations')
    parser.add_argument('--no-null-move-pruning', action='store_true', help='Disable null move pruning')
    parser.add_argument('--create-config', type=str, help='Create sample config file')
    
    args = parser.parse_args()
    
    # Create config file if requested
    if args.create_config:
        create_config_file(args.create_config)
        return
    
    # Load configuration
    config = {}
    if args.config:
        try:
            with open(args.config, 'r') as f:
                config = json.load(f)
            logger.info(f"Loaded configuration from {args.config}")
        except Exception as e:
            logger.error(f"Failed to load config file: {e}")
            return
    
    # Override config with command line arguments
    model_path = args.model or config.get('model_path')
    if not model_path:
        logger.error("Model path required. Use --model or specify in config file.")
        return
        
    # Support both legacy and new feature sizes
    feature_size = args.feature_size or config.get('feature_size', 1152)  # Default to nnue-pytorch size
    hidden_size = args.hidden_size or config.get('hidden_size', 256)
    feature_set_name = config.get('feature_set', 'NineMill')
    search_depth = args.depth or config.get('search_depth', 8)
    use_randomness = args.random or config.get('use_randomness', False)
    force_cpu = not (args.use_gpu or config.get('use_gpu', False))
    human_first = (args.first == 'human') if args.first else config.get('human_first', True)
    use_gui = args.gui or config.get('gui', False)
    tt_size_mb = args.tt_size or config.get('tt_size_mb', 64)
    use_iterative_deepening = not args.no_iterative_deepening and config.get('use_iterative_deepening', True)
    use_lazy_evaluation = not args.no_lazy_evaluation and config.get('use_lazy_evaluation', True)
    use_null_move_pruning = not args.no_null_move_pruning and config.get('use_null_move_pruning', True)
    
    try:
        # Load NNUE model
        device_str = "CPU (forced)" if force_cpu else ("GPU" if torch.cuda.is_available() else "CPU")
        logger.info(f"Loading NNUE model from {model_path} on {device_str}")
        logger.info(f"Feature set: {feature_set_name}")
        logger.info(f"Transposition Table size: {tt_size_mb}MB")
        logger.info(f"Optimizations: ID={'ON' if use_iterative_deepening else 'OFF'}, Lazy={'ON' if use_lazy_evaluation else 'OFF'}, NMP={'ON' if use_null_move_pruning else 'OFF'}")
        model_loader = NNUEModelLoader(model_path, feature_size, hidden_size, force_cpu, feature_set_name)
        nnue_player = NNUEPlayer(model_loader, search_depth, use_randomness, tt_size_mb)
        
        # Configure optimizations
        nnue_player.set_iterative_deepening(use_iterative_deepening)
        nnue_player.set_lazy_evaluation(use_lazy_evaluation)
        nnue_player.set_null_move_pruning(use_null_move_pruning)
        
        if use_gui:
            # Start GUI game
            logger.info("Starting GUI game...")
            try:
                gui = NNUEGameGUI(nnue_player, human_first)
                gui.start_gui()
            except Exception as e:
                logger.error(f"GUI initialization failed: {e}")
                import traceback
                traceback.print_exc()
                return
        else:
            # Console mode (simplified)
            logger.info("Console mode not fully implemented. Use --gui for interactive play.")
            game_state = NNUEGameAdapter()
            
            for game_num in range(args.games):
                logger.info(f"Game {game_num + 1}/{args.games}")
                moves = 0
                
                while moves < 50 and game_state.get_valid_moves():  # Simple game loop
                    if game_state.side_to_move == (0 if human_first else 1):
                        # Human move (simplified - just pass for now)
                        logger.info("Human's turn (skipping in console mode)")
                        break
                    else:
                        # AI move
                        move = nnue_player.get_best_move(game_state)
                        if move:
                            game_state.make_move(move)
                            logger.info(f"AI move: {move}")
                        else:
                            logger.info("AI has no valid moves")
                            break
                    moves += 1
                    
                logger.info(f"Game {game_num + 1} completed after {moves} moves")
                
    except Exception as e:
        logger.error(f"Error: {e}")
        return


if __name__ == '__main__':
    main()
