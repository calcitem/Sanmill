#!/usr/bin/env python3
"""
SL Pitting Script for Sanmill - Human vs SL AI
Supports GUI interface for interactive games with SL model evaluation.

Usage:
  python sl_pit.py --config my_config.json --gui --first human
  python sl_pit.py --model model.tar --gui
  python sl_pit.py --model model.tar --games 5 --first ai
"""

import os
import sys
import argparse
import logging
import torch
import numpy as np
import json
from pathlib import Path
from typing import Optional, Tuple, List, Dict, Any
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

# Import SL specific modules
try:
    from neural_network import SLNet
    from mcts import MCTS
    from config import SLConfig
except ImportError as e:
    print(f"Warning: SL modules not available: {e}")
    SLNet = None
    MCTS = None
    SLConfig = None

# Import game modules
from game.Game import Game
from game.engine_adapter import move_to_engine_token

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
        """Probe the transposition table"""
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
        """Store entry in transposition table"""
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
        np.random.seed(42)  # Fixed seed for reproducible hashes

        # Hash values for pieces (24 valid positions * 2 piece types)
        self.piece_hashes = np.random.randint(0, 2**63, size=(24, 2), dtype=np.int64)

        # Hash values for side to move
        self.side_to_move_hash = np.random.randint(0, 2**63, dtype=np.int64)

        # Hash values for game phases
        self.phase_hashes = np.random.randint(0, 2**63, size=4, dtype=np.int64)

        # Hash values for piece counts
        self.piece_count_hashes = np.random.randint(0, 2**63, size=(10, 10), dtype=np.int64)

    def hash_position(self, game_state: 'SLGameAdapter') -> int:
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

        # Hash piece counts
        white_hand = min(game_state.white_pieces_in_hand, 9)
        black_hand = min(game_state.black_pieces_in_hand, 9)
        hash_value ^= self.piece_count_hashes[white_hand][black_hand]

        # Ensure positive hash value
        return abs(hash_value)


class SLModelLoader:
    """SL model loader that can handle .tar and .pth formats"""

    def __init__(self, model_path: str, device: str = None):
        self.model_path = model_path
        self.model = None

        # Device selection
        if device is None:
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        else:
            self.device = torch.device(device)

    def _auto_detect_model_architecture(self, state_dict):
        """Auto-detect model architecture from state_dict keys and shapes"""
        # Extract architecture parameters from state_dict
        input_channels = None
        num_filters = None
        action_size = 1000  # Default
        dropout_rate = 0.3  # Default
        
        # Analyze residual blocks to determine count
        residual_blocks = set()
        for key in state_dict.keys():
            if key.startswith('residual_blocks.'):
                block_num = int(key.split('.')[1])
                residual_blocks.add(block_num)
            elif key == 'input_conv.conv.weight':
                # Shape is [out_channels, in_channels, kernel_h, kernel_w]
                shape = state_dict[key].shape
                num_filters = shape[0]
                input_channels = shape[1]
            elif key == 'policy_head.weight':
                # Shape is [action_size, input_features]
                action_size = state_dict[key].shape[0]
        
        num_residual_blocks = len(residual_blocks)
        
        logger.info(f"Auto-detected model architecture:")
        logger.info(f"  - Input channels: {input_channels}")
        logger.info(f"  - Number of filters: {num_filters}")
        logger.info(f"  - Number of residual blocks: {num_residual_blocks}")
        logger.info(f"  - Action size: {action_size}")
        logger.info(f"  - Dropout rate: {dropout_rate} (default)")
        
        return {
            'input_channels': input_channels,
            'num_filters': num_filters,
            'num_residual_blocks': num_residual_blocks,
            'action_size': action_size,
            'dropout_rate': dropout_rate
        }

    def load_model(self):
        """Load SL model from file with automatic architecture detection"""
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"SL model file not found: {self.model_path}")

        if SLNet is None:
            raise RuntimeError("SL neural network module not available")

        try:
            # Load model checkpoint
            checkpoint = torch.load(self.model_path, map_location=self.device)

            # Extract state_dict and model configuration
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                # Standard checkpoint format
                state_dict = checkpoint['model_state_dict']
                
                # Try to get model configuration from different possible sources
                config_dict = None
                
                # First, try 'model_args' (preferred)
                if 'model_args' in checkpoint:
                    config_dict = checkpoint['model_args']
                    logger.info("Using model configuration from 'model_args'")
                # Second, try 'config'
                elif 'config' in checkpoint:
                    config_dict = checkpoint['config']
                    logger.info("Using model configuration from 'config'")
                # Third, auto-detect from state_dict
                else:
                    logger.info("No saved configuration found, auto-detecting from model state_dict")
                    config_dict = self._auto_detect_model_architecture(state_dict)
                
                # Create model with detected/saved configuration
                self.model = SLNet(
                    input_channels=config_dict.get('input_channels', 19),
                    num_filters=config_dict.get('num_filters', 256),
                    num_residual_blocks=config_dict.get('num_residual_blocks', 10),
                    action_size=config_dict.get('action_size', 1000),
                    dropout_rate=config_dict.get('dropout_rate', 0.3)
                )

                self.model.load_state_dict(state_dict)
            else:
                # Direct model state dict - auto-detect architecture
                logger.info("Direct state_dict format detected, auto-detecting architecture")
                config_dict = self._auto_detect_model_architecture(checkpoint)
                
                self.model = SLNet(
                    input_channels=config_dict.get('input_channels', 19),
                    num_filters=config_dict.get('num_filters', 256),
                    num_residual_blocks=config_dict.get('num_residual_blocks', 10),
                    action_size=config_dict.get('action_size', 1000),
                    dropout_rate=config_dict.get('dropout_rate', 0.3)
                )
                self.model.load_state_dict(checkpoint)

            self.model.to(self.device)
            self.model.eval()

            logger.info(f"✅ Loaded SL model: {self.model_path}")
            logger.info(f"   Device: {self.device}")
            logger.info(f"   Model parameters: {sum(p.numel() for p in self.model.parameters()):,}")
            return self.model

        except Exception as e:
            logger.error(f"Failed to load SL model: {e}")
            raise RuntimeError(f"Failed to load SL model: {e}")


class SLGameAdapter:
    """Adapter to use existing ml/game Board with SL - reuses ml/game logic"""

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
            logger.error(f"Failed to initialize SLGameAdapter: {e}")
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

    def to_sl_features(self) -> np.ndarray:
        """Convert game state to SL feature tensor"""
        # SL uses a board representation suitable for CNNs
        # We'll create multiple channels for different features

        # 7x7 board with multiple channels (19 channels to match model)
        features = np.zeros((19, 7, 7), dtype=np.float32)  # 19 channels

        # Channel 0: White pieces
        # Channel 1: Black pieces
        for x in range(7):
            for y in range(7):
                if self.board.allowed_places[x][y]:
                    piece = self.board.pieces[x][y]
                    if piece == 1:  # White piece
                        features[0, x, y] = 1.0
                    elif piece == -1:  # Black piece
                        features[1, x, y] = 1.0

        # Channel 2: Valid positions (board structure)
        for x in range(7):
            for y in range(7):
                if self.board.allowed_places[x][y]:
                    features[2, x, y] = 1.0

        # Channel 3-6: Phase information (one-hot encoding)
        phase = min(self.phase, 3)
        if phase == 0:  # Placing phase
            features[3, :, :] = 1.0
        elif phase == 1:  # Moving phase
            features[4, :, :] = 1.0
        elif phase == 2:  # Flying phase
            features[5, :, :] = 1.0
        else:  # Capture phase (phase == 3)
            features[6, :, :] = 1.0

        # Channel 7: Side to move (broadcast to entire board)
        features[7, :, :] = float(self.side_to_move)

        # Channel 8: White pieces in hand (normalized)
        features[8, :, :] = self.white_pieces_in_hand / 9.0

        # Channel 9: Black pieces in hand (normalized)
        features[9, :, :] = self.black_pieces_in_hand / 9.0

        # Channel 10: White pieces on board (normalized)
        features[10, :, :] = self.white_pieces_on_board / 9.0

        # Channel 11: Black pieces on board (normalized)
        features[11, :, :] = self.black_pieces_on_board / 9.0

        # Channel 12: Move count (normalized)
        features[12, :, :] = min(self.move_count / 100.0, 1.0)

        # Channel 13-15: Piece history (last few moves)
        # For simplicity, we'll use zeros for now

        # Channel 16-18: Mill detection and strategy features
        # For simplicity, we'll use zeros for now

        # The remaining channels (13-18) are set to zero by default
        # In a full implementation, you would add:
        # - Historical position information
        # - Mill formation potential
        # - Strategic position values
        # - Threat detection
        # - Mobility information

        return features

    def is_valid_position(self, x: int, y: int) -> bool:
        """Check if position is valid on the board"""
        return 0 <= x < 7 and 0 <= y < 7 and self.board.allowed_places[x][y] == 1

    def get_valid_moves(self) -> List[Tuple[int, int, int, int]]:
        """Get list of valid moves in current position"""
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
        """Make a move on the board"""
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

            # Use ml/game's state transition
            next_board, next_player = self.game.getNextState(self.board, self.current_player, action)
            self.board = next_board
            self.current_player = next_player
            return True
        except Exception as e:
            return False

    def is_game_over(self) -> Tuple[bool, Optional[str]]:
        """Check if game is over"""
        is_over, result, reason = self.board.check_game_over_conditions(self.current_player)
        if is_over:
            return True, reason
        return False, None

    def get_removable_pieces(self, player_side_to_move: int) -> List[Tuple[int, int]]:
        """Get removable pieces for GUI"""
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
        new_adapter = SLGameAdapter()
        new_adapter.board = deepcopy(self.board)
        new_adapter.current_player = self.current_player
        return new_adapter

    def make_move_and_undo(self, move) -> Tuple[bool, Any]:
        """Make a move and return undo information"""
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


class SLPlayer:
    """AI player using SL model with MCTS search"""

    def __init__(self, model_loader: SLModelLoader, mcts_sims: int = 800,
                 use_randomness: bool = False, temperature: float = 0.0, tt_size_mb: int = 64):
        self.model = model_loader.load_model()
        self.device = model_loader.device
        self.mcts_sims = mcts_sims
        self.use_randomness = use_randomness
        self.temperature = temperature

        # Initialize MCTS if available
        if MCTS is not None:
            from game.Game import Game
            self.game_engine = Game()  # Create game engine for MCTS

            mcts_config = {
                'cpuct': 1.0,
                'num_simulations': mcts_sims,
                'dirichlet_alpha': 0.3,
                'dirichlet_epsilon': 0.25,
                'temperature': temperature
            }
            self.mcts = MCTS(self.game_engine, self.model, mcts_config)
        else:
            self.mcts = None
            self.game_engine = None
            logger.warning("MCTS not available, using direct model evaluation")

        # Initialize Transposition Table and Position Hasher for fallback search
        self.transposition_table = TranspositionTable(size_mb=tt_size_mb)
        self.position_hasher = PositionHasher()

        # Statistics for performance monitoring
        self.nodes_searched = 0
        self.mcts_calls = 0
        self.model_evaluations = 0

    def evaluate_position(self, game_state: SLGameAdapter) -> Tuple[float, np.ndarray]:
        """Evaluate position using SL model"""
        self.model_evaluations += 1

        # Convert game state to feature tensor
        features = game_state.to_sl_features()
        features_tensor = torch.from_numpy(features).unsqueeze(0).to(self.device)

        with torch.no_grad():
            policy_logits, value = self.model(features_tensor)

            # Convert to numpy
            policy = torch.softmax(policy_logits, dim=1).cpu().numpy()[0]
            value_scalar = float(value.cpu().item())

            return value_scalar, policy

    def get_best_move(self, game_state: SLGameAdapter) -> Optional[Tuple[int, int, int, int]]:
        """Get best move using MCTS or fallback search"""

        # Reset statistics
        self.nodes_searched = 0
        self.mcts_calls = 0
        self.model_evaluations = 0

        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return None

        if len(valid_moves) == 1:
            return valid_moves[0]  # Only one move available

        if self.mcts is not None:
            # Use MCTS search
            return self._mcts_search(game_state, valid_moves)
        else:
            # Fallback to simple evaluation-based search
            return self._evaluation_search(game_state, valid_moves)

    def _mcts_search(self, game_state: SLGameAdapter, valid_moves: List[Tuple[int, int, int, int]]) -> Optional[Tuple[int, int, int, int]]:
        """Use MCTS to find best move"""
        self.mcts_calls += 1

        try:
            # Convert game state to format expected by MCTS
            # This is a simplified implementation - in practice, you'd need to adapt
            # the game state to the exact format expected by your MCTS implementation

            # Get action probabilities from MCTS
            # Use the available MCTS interface (adapt to actual interface)
            try:
                action_probs = self.mcts.get_action_prob(game_state, temp=self.temperature)
            except AttributeError:
                # Fallback: use a different MCTS interface or simulate
                valid_moves = game_state.get_valid_moves()
                action_probs = np.ones(len(valid_moves)) / len(valid_moves)  # Uniform distribution

            # Convert action probabilities to move selection
            if self.use_randomness and self.temperature > 0:
                # Sample from probability distribution
                action_idx = np.random.choice(len(action_probs), p=action_probs)
            else:
                # Select best action
                action_idx = np.argmax(action_probs)

            # Convert action index back to move coordinates
            # This mapping depends on your action space definition
            if action_idx < len(valid_moves):
                return valid_moves[action_idx]
            else:
                return valid_moves[0]  # Fallback

        except Exception as e:
            logger.warning(f"MCTS search failed: {e}, falling back to evaluation search")
            return self._evaluation_search(game_state, valid_moves)

    def _evaluation_search(self, game_state: SLGameAdapter, valid_moves: List[Tuple[int, int, int, int]]) -> Optional[Tuple[int, int, int, int]]:
        """Fallback search using direct model evaluation"""
        best_move = None
        best_value = float('-inf') if game_state.side_to_move == 0 else float('inf')

        for move in valid_moves:
            # Make move
            success, undo_info = game_state.make_move_and_undo(move)
            if success:
                # Evaluate resulting position
                value, _ = self.evaluate_position(game_state)

                # Undo move
                game_state.undo_move(undo_info)

                # Update best move
                if game_state.side_to_move == 0:  # White (maximizing)
                    if value > best_value:
                        best_value = value
                        best_move = move
                else:  # Black (minimizing)
                    if value < best_value:
                        best_value = value
                        best_move = move

        return best_move or valid_moves[0]

    def set_mcts_sims(self, sims: int):
        """Set MCTS simulation count"""
        self.mcts_sims = max(1, sims)
        if self.mcts is not None:
            self.mcts.num_simulations = self.mcts_sims

    def set_randomness(self, use_randomness: bool):
        """Set randomness behavior"""
        self.use_randomness = use_randomness

    def set_temperature(self, temperature: float):
        """Set temperature for move selection"""
        self.temperature = max(0.0, temperature)
        if self.mcts is not None:
            self.mcts.temperature = self.temperature

    def clear_search_tree(self):
        """Clear the search tree (useful for new games)"""
        if self.mcts is not None:
            # Reset MCTS tree - use available interface
            try:
                self.mcts.reset()
            except AttributeError:
                # Try alternative reset methods or recreate MCTS
                try:
                    self.mcts.clear()
                except AttributeError:
                    # Recreate MCTS if no reset method available
                    mcts_config = {
                        'cpuct': 1.0,
                        'num_simulations': self.mcts_sims,
                        'dirichlet_alpha': 0.3,
                        'dirichlet_epsilon': 0.25,
                        'temperature': self.temperature
                    }
                    self.mcts = MCTS(self.game_engine, self.model, mcts_config)
        self.transposition_table.clear()
        logger.info("Search tree and caches cleared")

    def get_search_stats(self) -> str:
        """Get search statistics for performance monitoring"""
        if self.mcts_calls == 0 and self.model_evaluations == 0:
            return "No search performed yet"

        if self.mcts is not None:
            return (f"MCTS Sims: {self.mcts_sims}, Calls: {self.mcts_calls}, "
                    f"Model Evals: {self.model_evaluations}, "
                    f"Temp: {self.temperature:.2f}, "
                    f"Mode: {'Random' if self.use_randomness else 'Deterministic'}")
        else:
            return (f"Direct Eval Mode, Model Evals: {self.model_evaluations}, "
                    f"Mode: {'Random' if self.use_randomness else 'Deterministic'}")


class SLGameGUI:
    """Simple GUI for SL human vs AI games"""

    def __init__(self, sl_player: SLPlayer, human_first: bool = True):
        self.sl_player = sl_player
        self.human_first = human_first
        self.game_state = SLGameAdapter()

        # Player mapping logic (similar to NNUE pit)
        if human_first:
            self.players = [self.sl_player, None, self]  # [player2, None, player1]
            self.human_player_value = 1   # curPlayer value when human plays
            self.ai_player_value = -1     # curPlayer value when AI plays
        else:
            self.players = [self, None, self.sl_player]  # [player2, None, player1]
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

        # Last move display
        self._last_move_canvas_id = None
        self.last_move_text = ""

        # Evaluation display
        self.current_evaluation = 0.0

    def start_gui(self):
        """Start the GUI game"""
        self.root = self.tk.Tk()
        self.root.title("Sanmill SL - Human vs AI")
        self.root.geometry("700x850")

        # Status label
        self.status_label = self.tk.Label(self.root, text="Game started", font=("Arial", 12))
        self.status_label.pack(pady=10)

        # SL Evaluation display frame
        eval_frame = self.tk.Frame(self.root)
        eval_frame.pack(pady=5)

        # Evaluation label
        self.eval_label = self.tk.Label(eval_frame, text="SL Evaluation: Calculating...",
                                       font=("Arial", 14, "bold"), fg="#333")
        self.eval_label.pack()

        # Evaluation progress bar
        eval_bar_frame = self.tk.Frame(eval_frame)
        eval_bar_frame.pack(pady=5)

        self.eval_canvas = self.tk.Canvas(eval_bar_frame, width=300, height=20, bg="#ddd")
        self.eval_canvas.pack()

        # Human perspective indicator
        self.perspective_label = self.tk.Label(eval_frame, text="(Human Perspective)",
                                             font=("Arial", 10), fg="#666")
        self.perspective_label.pack()

        # Canvas for board
        canvas_width = 600
        canvas_height = 600
        self.canvas = self.tk.Canvas(self.root, width=canvas_width, height=canvas_height, bg="#cfcfcf")
        self.canvas.pack(pady=10)
        self.canvas.bind("<Button-1>", self.on_click)

        # Settings frame
        settings_frame = self.tk.Frame(self.root)
        settings_frame.pack(pady=10)

        # MCTS simulations setting
        sims_label = self.tk.Label(settings_frame, text="MCTS Sims:")
        sims_label.pack(side=self.tk.LEFT, padx=5)

        # Import ttk for better combobox
        try:
            from tkinter import ttk
            self.sims_var = self.tk.StringVar(value=str(self.sl_player.mcts_sims))
            sims_combobox = ttk.Combobox(settings_frame, textvariable=self.sims_var,
                                        values=["50", "100", "200", "400", "800", "1600"],
                                        width=8, state="readonly")
            sims_combobox.pack(side=self.tk.LEFT, padx=5)
            sims_combobox.bind("<<ComboboxSelected>>", self.on_sims_changed)
        except ImportError:
            # Fallback to regular entry if ttk not available
            self.sims_var = self.tk.StringVar(value=str(self.sl_player.mcts_sims))
            sims_entry = self.tk.Entry(settings_frame, textvariable=self.sims_var, width=8)
            sims_entry.pack(side=self.tk.LEFT, padx=5)
            sims_entry.bind("<Return>", self.on_sims_changed)

        # Temperature setting
        temp_label = self.tk.Label(settings_frame, text="Temperature:")
        temp_label.pack(side=self.tk.LEFT, padx=(20, 5))

        try:
            from tkinter import ttk
            self.temp_var = self.tk.StringVar(value=f"{self.sl_player.temperature:.1f}")
            temp_combobox = ttk.Combobox(settings_frame, textvariable=self.temp_var,
                                        values=["0.0", "0.1", "0.3", "0.5", "1.0"],
                                        width=5, state="readonly")
            temp_combobox.pack(side=self.tk.LEFT, padx=5)
            temp_combobox.bind("<<ComboboxSelected>>", self.on_temp_changed)
        except ImportError:
            # Fallback to entry if ttk not available
            self.temp_var = self.tk.StringVar(value=f"{self.sl_player.temperature:.1f}")
            temp_entry = self.tk.Entry(settings_frame, textvariable=self.temp_var, width=5)
            temp_entry.pack(side=self.tk.LEFT, padx=5)
            temp_entry.bind("<Return>", self.on_temp_changed)

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

        # Set up window close protocol
        self.root.protocol("WM_DELETE_WINDOW", self.safe_quit)

        # If AI goes first, make AI move
        initial_player_obj = self.players[self.game_state.current_player + 1]
        if initial_player_obj == self.sl_player:
            self.root.after(1000, self.make_ai_move)

        self.root.mainloop()

    def draw_board(self):
        """Draw the game board using professional rendering"""
        self.canvas.delete("all")

        # Board configuration
        board_size_px = 480
        cell_px = board_size_px // 7
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

        # Draw board lines first
        for (x1, y1), (x2, y2) in connections:
            cx1, cy1 = xy_to_canvas_center(x1, y1)
            cx2, cy2 = xy_to_canvas_center(x2, y2)
            self.canvas.create_line(cx1, cy1, cx2, cy2, fill="#666", width=3)

        # Draw coordinate labels
        # Row numbers (7..1) on the left
        for y in range(7):
            text_y = margin_top + y * cell_px + cell_px // 2
            self.canvas.create_text(margin_left * 0.5, text_y, text=str(7 - y),
                                  fill="#444", font=("Arial", coord_font_size))

        # Column letters (a..g) at the bottom
        letters = ["a", "b", "c", "d", "e", "f", "g"]
        base_y = margin_top + board_size_px + margin_bottom * 0.15
        for x in range(7):
            text_x = margin_left + x * cell_px + cell_px // 2
            self.canvas.create_text(text_x, base_y, text=letters[x],
                                  fill="#444", font=("Arial", coord_font_size))

        # Draw pieces
        for x, y in self.game_state.valid_positions:
            piece = self.game_state.board.pieces[x][y]
            if piece != 0:  # Has a piece
                cx, cy = xy_to_canvas_center(x, y)

                if piece == 1:  # White piece
                    fill_color = "#ffffff"
                    outline_color = "#888"
                else:  # Black piece
                    fill_color = "#000000"
                    outline_color = "#888"

                # Draw piece
                self.canvas.create_oval(cx - piece_radius, cy - piece_radius,
                                      cx + piece_radius, cy + piece_radius,
                                      fill=fill_color, outline=outline_color, width=2)

        # Highlight selected position
        if self.selected_pos:
            x, y = self.selected_pos
            cx, cy = xy_to_canvas_center(x, y)
            self.canvas.create_oval(cx - piece_radius - 4, cy - piece_radius - 4,
                                  cx + piece_radius + 4, cy + piece_radius + 4,
                                  outline="#e67e22", width=4, fill="")

        # Highlight removable pieces in removal phase
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

        # Display last move notation
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
            text_x = self.canvas.winfo_reqwidth() // 2
            text_y = margin_top // 3

            self._last_move_canvas_id = self.canvas.create_text(
                text_x, text_y, text=self.last_move_text,
                fill="black", font=("Arial", 12, "bold"), anchor="center"
            )

    def move_to_notation(self, move, player_name, is_removal=False):
        """Convert move to standard notation"""
        if not move or len(move) < 2:
            return ""

        try:
            # Convert to standard engine notation
            if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                notation = move_to_engine_token([move[0], move[1]])
            else:
                notation = move_to_engine_token(move)

            # Add capture prefix for removal moves
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
        """Calculate position evaluation from Human perspective"""
        if self.game_over:
            return 0.0

        # Get SL evaluation
        raw_evaluation, _ = self.sl_player.evaluate_position(self.game_state)

        # Convert to Human perspective
        if self.human_player_value == 1:
            # Human is white, positive is good for Human
            return raw_evaluation
        else:
            # Human is black, negative is good for Human
            return -raw_evaluation

    def update_evaluation_display(self):
        """Update evaluation display"""
        if self.game_over:
            self.eval_label.config(text="SL Evaluation: Game Over")
            self.eval_canvas.delete("all")
            return

        # Calculate Human perspective evaluation
        self.current_evaluation = self.get_human_perspective_evaluation()

        # Format display text
        if abs(self.current_evaluation) > 10:
            eval_text = f"SL Evaluation: {self.current_evaluation:+.1f} (Decisive advantage)"
        elif abs(self.current_evaluation) > 3:
            eval_text = f"SL Evaluation: {self.current_evaluation:+.1f} (Clear advantage)"
        elif abs(self.current_evaluation) > 1:
            eval_text = f"SL Evaluation: {self.current_evaluation:+.1f} (Slight advantage)"
        else:
            eval_text = f"SL Evaluation: {self.current_evaluation:+.1f} (Equal)"

        self.eval_label.config(text=eval_text)

        # Update evaluation bar
        self.draw_evaluation_bar()

    def draw_evaluation_bar(self):
        """Draw evaluation progress bar"""
        self.eval_canvas.delete("all")

        # Bar configuration
        bar_width = 300
        bar_height = 20

        # Map evaluation to [-1, 1] range using tanh
        import math
        normalized_eval = math.tanh(self.current_evaluation / 3.0)

        # Calculate bar position
        center_x = bar_width // 2
        bar_position = center_x + (normalized_eval * center_x * 0.9)

        # Draw background
        self.eval_canvas.create_rectangle(0, 0, bar_width, bar_height,
                                        fill="#e0e0e0", outline="#ccc")

        # Draw center line
        self.eval_canvas.create_line(center_x, 0, center_x, bar_height,
                                   fill="#888", width=2)

        # Draw evaluation indicator
        if normalized_eval > 0:
            # Human advantage, green
            color = "#4CAF50"
            self.eval_canvas.create_rectangle(center_x, 2, bar_position, bar_height - 2,
                                            fill=color, outline=color)
        else:
            # Human disadvantage, red
            color = "#f44336"
            self.eval_canvas.create_rectangle(bar_position, 2, center_x, bar_height - 2,
                                            fill=color, outline=color)

        # Add scale marks
        for i in [-1, -0.5, 0, 0.5, 1]:
            x = center_x + (i * center_x * 0.9)
            self.eval_canvas.create_line(x, bar_height - 5, x, bar_height,
                                       fill="#666", width=1)

    def on_click(self, event):
        """Handle mouse click on board"""
        # Check if it's human's turn
        current_player_obj = self.players[self.game_state.current_player + 1]
        if self.game_over or current_player_obj != self:
            return  # Not human's turn

        # Convert click to board position
        margin_left = getattr(self, '_margin_left', 68)
        margin_top = getattr(self, '_margin_top', 61)
        cell_px = getattr(self, '_cell_px', 68)

        lx = event.x - margin_left
        ly = event.y - margin_top
        if lx < 0 or ly < 0 or lx >= 480 or ly >= 480:
            return  # Click outside board area

        clicked_x = max(0, min(6, int(lx // cell_px)))
        clicked_y = max(0, min(6, int(ly // cell_px)))

        if not self.game_state.is_valid_position(clicked_x, clicked_y):
            return

        if self.game_state.phase == 3:  # Removing phase
            # Click to remove opponent piece
            opponent = -self.game_state.current_player
            if self.game_state.board.pieces[clicked_x][clicked_y] == opponent:
                # Check if this piece can be removed
                removable = self.game_state.get_removable_pieces(self.game_state.side_to_move)
                if (clicked_x, clicked_y) in removable:
                    move = (clicked_x, clicked_y, clicked_x, clicked_y)
                    if self.game_state.make_move(move):
                        # Record last move
                        player_name = "Human"
                        self.last_move_text = self.move_to_notation(move, player_name, is_removal=True)

                        # Log Human move
                        try:
                            notation = move_to_engine_token([move[0], move[1]])
                            notation = f"x{notation}"
                            logger.info(f"Human move: {notation}")
                        except Exception:
                            x1, y1, x2, y2 = move
                            logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2}) [remove]")

                        self.draw_board()
                        self.update_status()
                        self.update_evaluation_display()
                        if not self.game_over:
                            current_player_obj = self.players[self.game_state.current_player + 1]
                            if current_player_obj == self.sl_player:
                                self.root.after(500, self.make_ai_move)
        elif self.game_state.phase == 0:  # Placing phase
            if self.game_state.board.pieces[clicked_x][clicked_y] == 0:  # Empty position
                move = (clicked_x, clicked_y, clicked_x, clicked_y)
                if self.game_state.make_move(move):
                    # Record last move
                    player_name = "Human"
                    self.last_move_text = self.move_to_notation(move, player_name, is_removal=False)

                    # Log Human move
                    try:
                        if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                            notation = move_to_engine_token([move[0], move[1]])
                        else:
                            notation = move_to_engine_token(move)
                        logger.info(f"Human move: {notation}")
                    except Exception:
                        x1, y1, x2, y2 = move
                        logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2})")

                    self.draw_board()
                    self.update_status()
                    self.update_evaluation_display()
                    if not self.game_over:
                        current_player_obj = self.players[self.game_state.current_player + 1]
                        if current_player_obj == self.sl_player:
                            self.root.after(500, self.make_ai_move)
        else:  # Moving/Flying phase
            if self.selected_pos is None:
                # Select piece to move
                if self.game_state.board.pieces[clicked_x][clicked_y] == self.human_player_value:
                    self.selected_pos = (clicked_x, clicked_y)
                    self.draw_board()
            else:
                # Move piece
                if self.game_state.board.pieces[clicked_x][clicked_y] == 0:  # Empty position
                    move = (self.selected_pos[0], self.selected_pos[1], clicked_x, clicked_y)
                    if self.game_state.make_move(move):
                        # Record last move
                        player_name = "Human"
                        self.last_move_text = self.move_to_notation(move, player_name, is_removal=False)

                        # Log Human move
                        try:
                            notation = move_to_engine_token(move)
                            logger.info(f"Human move: {notation}")
                        except Exception:
                            x1, y1, x2, y2 = move
                            logger.info(f"Human move: ({x1},{y1}) -> ({x2},{y2})")

                        self.selected_pos = None
                        self.draw_board()
                        self.update_status()
                        self.update_evaluation_display()
                        if not self.game_over:
                            current_player_obj = self.players[self.game_state.current_player + 1]
                            if current_player_obj == self.sl_player:
                                self.root.after(500, self.make_ai_move)
                else:
                    self.selected_pos = None
                    self.draw_board()

    def make_ai_move(self):
        """Make AI move"""
        if self.game_over:
            return

        # Check if it's actually AI's turn
        current_player_obj = self.players[self.game_state.current_player + 1]
        if current_player_obj != self.sl_player:
            return  # Not AI's turn

        self.update_status("AI is thinking...")

        # Use threading to prevent GUI freezing
        def ai_move_thread():
            move = self.sl_player.get_best_move(self.game_state)
            if move:
                # Remember the phase before making the move
                phase_before_move = self.game_state.phase
                self.game_state.make_move(move)
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

            # Log AI move with search statistics
            search_stats = self.sl_player.get_search_stats()
            try:
                if len(move) == 4 and move[0] == move[2] and move[1] == move[3]:
                    notation = move_to_engine_token([move[0], move[1]])
                else:
                    notation = move_to_engine_token(move)
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
            if current_player_obj == self.sl_player:
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

        # Determine current player
        current_player_obj = self.players[self.game_state.current_player + 1]
        current_player = "Human" if current_player_obj == self else "AI"

        pieces_info = f"White: {self.game_state.white_pieces_on_board}+{self.game_state.white_pieces_in_hand}, " \
                     f"Black: {self.game_state.black_pieces_on_board}+{self.game_state.black_pieces_in_hand}"

        status_text = f"{phase_text} | {current_player}'s turn | {pieces_info}"
        self.status_label.config(text=status_text)

        # Check for game over
        is_over, reason = self.game_state.is_game_over()
        if is_over:
            self.game_over = True

            # Get the actual result for determining winner
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
            # Fallback: no valid moves
            self.game_over = True
            winner = "AI" if current_player == "Human" else "Human"
            self.messagebox.showinfo("Game Over", f"{winner} wins! (No valid moves)")

    def on_sims_changed(self, event=None):
        """Handle MCTS simulations change"""
        try:
            new_sims = int(self.sims_var.get())
            if 1 <= new_sims <= 10000:
                self.sl_player.set_mcts_sims(new_sims)
                logger.info(f"MCTS simulations changed to: {new_sims}")
                self.update_status()
            else:
                # Reset to current value if invalid
                self.sims_var.set(str(self.sl_player.mcts_sims))
        except ValueError:
            # Reset to current value if not a number
            self.sims_var.set(str(self.sl_player.mcts_sims))

    def on_temp_changed(self, event=None):
        """Handle temperature change"""
        try:
            new_temp = float(self.temp_var.get())
            if 0.0 <= new_temp <= 2.0:
                self.sl_player.set_temperature(new_temp)
                logger.info(f"Temperature changed to: {new_temp}")
                self.update_status()
            else:
                # Reset to current value if invalid
                self.temp_var.set(f"{self.sl_player.temperature:.1f}")
        except ValueError:
            # Reset to current value if not a number
            self.temp_var.set(f"{self.sl_player.temperature:.1f}")

    def safe_quit(self):
        """Safely quit the application"""
        try:
            if self.root and self.root.winfo_exists():
                try:
                    self.root.after_cancel("all")
                except:
                    pass

                try:
                    self.root.unbind_all("<Key>")
                    self.root.unbind_all("<Button>")
                except:
                    pass

                try:
                    self.root.withdraw()
                except:
                    pass

                self.root.destroy()
        except Exception as e:
            try:
                if self.root:
                    self.root.quit()
            except:
                import sys
                sys.exit(0)

    def restart_game(self):
        """Restart the game"""
        self.game_state = SLGameAdapter()
        self.selected_pos = None
        self.game_over = False
        self.last_move_text = ""

        # Clear search tree for fresh start
        self.sl_player.clear_search_tree()

        self.draw_board()
        self.update_status()
        self.update_evaluation_display()

        # Check if AI should go first
        initial_player_obj = self.players[self.game_state.current_player + 1]
        if initial_player_obj == self.sl_player:
            self.root.after(1000, self.make_ai_move)


def create_config_file(filename: str):
    """Create a sample configuration file"""
    config = {
        "model_path": "checkpoints/model.tar",
        "mcts_sims": 800,
        "temperature": 0.0,
        "use_randomness": False,
        "human_first": True,
        "gui": True,
        "log_level": "INFO",
        "tt_size_mb": 64,
        "device": "auto"
    }

    with open(filename, 'w') as f:
        json.dump(config, f, indent=2)

    logger.info(f"Created sample config file: {filename}")


def main():
    parser = argparse.ArgumentParser(
        description='SL Pitting Script for Sanmill',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python sl_pit.py --config my_config.json --gui --first human
  python sl_pit.py --model model.tar --gui
  python sl_pit.py --model model.tar --games 5 --first ai
  python sl_pit.py --create-config sample_config.json
        """
    )

    parser.add_argument('--config', type=str, help='Configuration file (JSON format)')
    parser.add_argument('--model', type=str, help='SL model file (.tar or .pth)')
    parser.add_argument('--gui', action='store_true', help='Enable GUI mode')
    parser.add_argument('--first', choices=['human', 'ai'], default='human',
                       help='Who plays first (default: human)')
    parser.add_argument('--games', type=int, default=1, help='Number of games to play')
    parser.add_argument('--mcts-sims', type=int, default=800, help='MCTS simulations per move')
    parser.add_argument('--temperature', type=float, default=0.0, help='Temperature for move selection')
    parser.add_argument('--random', action='store_true', help='Enable random move selection')
    parser.add_argument('--device', type=str, choices=['cpu', 'cuda', 'auto'], default='auto',
                       help='Device to use for model inference')
    parser.add_argument('--tt-size', type=int, default=64, help='Transposition table size in MB')
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

    mcts_sims = args.mcts_sims or config.get('mcts_sims', 800)
    temperature = args.temperature if args.temperature is not None else config.get('temperature', 0.0)
    use_randomness = args.random or config.get('use_randomness', False)
    human_first = (args.first == 'human') if args.first else config.get('human_first', True)
    use_gui = args.gui or config.get('gui', False)
    device = args.device or config.get('device', 'auto')
    tt_size_mb = args.tt_size or config.get('tt_size_mb', 64)

    # Handle device selection
    if device == 'auto':
        device = 'cuda' if torch.cuda.is_available() else 'cpu'

    try:
        # Load SL model
        device_str = device.upper()
        logger.info(f"Loading SL model from {model_path} on {device_str}")
        logger.info(f"MCTS simulations: {mcts_sims}")
        logger.info(f"Temperature: {temperature}")
        logger.info(f"Transposition Table size: {tt_size_mb}MB")

        model_loader = SLModelLoader(model_path, device)
        sl_player = SLPlayer(model_loader, mcts_sims, use_randomness, temperature, tt_size_mb)

        if use_gui:
            # Start GUI game
            logger.info("Starting GUI game...")
            try:
                gui = SLGameGUI(sl_player, human_first)
                gui.start_gui()
            except Exception as e:
                logger.error(f"GUI initialization failed: {e}")
                import traceback
                traceback.print_exc()
                return
        else:
            # Console mode (simplified)
            logger.info("Console mode not fully implemented. Use --gui for interactive play.")
            game_state = SLGameAdapter()

            for game_num in range(args.games):
                logger.info(f"Game {game_num + 1}/{args.games}")
                moves = 0

                while moves < 50 and game_state.get_valid_moves():
                    if game_state.side_to_move == (0 if human_first else 1):
                        # Human move (simplified - just pass for now)
                        logger.info("Human's turn (skipping in console mode)")
                        break
                    else:
                        # AI move
                        move = sl_player.get_best_move(game_state)
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
        import traceback
        traceback.print_exc()
        return


if __name__ == '__main__':
    main()
