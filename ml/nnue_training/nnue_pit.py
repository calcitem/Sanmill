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

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from train_nnue import MillNNUE
from config_loader import load_config, merge_config_with_args
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


class NNUEModelLoader:
    """NNUE model loader that can handle both .bin and .pth formats"""
    
    def __init__(self, model_path: str, feature_size: int = 115, hidden_size: int = 256, force_cpu: bool = True):
        self.model_path = model_path
        self.feature_size = feature_size
        self.hidden_size = hidden_size
        self.model = None
        # NNUE is designed for CPU inference - force CPU by default for optimal performance
        if force_cpu:
            self.device = torch.device('cpu')
        else:
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
    def load_model(self) -> MillNNUE:
        """Load NNUE model from file"""
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"NNUE model file not found: {self.model_path}")
        
        # Detect dimensions from model file
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
        self.model = MillNNUE(feature_size=self.feature_size, hidden_size=self.hidden_size)
        
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
        self.game = Game()
        self.board = self.game.getInitBoard()
        self.current_player = 1  # 1 for white, -1 for black (ml/game format)
        
        # Valid board positions (reuse from ml/game)
        self.valid_positions = []
        for x in range(7):
            for y in range(7):
                if self.board.allowed_places[x][y]:
                    self.valid_positions.append((x, y))
    
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


class NNUEPlayer:
    """AI player using NNUE model for evaluation - uses ml/game logic"""
    
    def __init__(self, model_loader: NNUEModelLoader, search_depth: int = 8, use_randomness: bool = False):
        self.model = model_loader.load_model()
        self.device = model_loader.device
        self.search_depth = search_depth
        self.use_randomness = use_randomness
        # Statistics for performance monitoring
        self.nodes_searched = 0
        self.cutoffs = 0
        
    def evaluate_position(self, game_state: NNUEGameAdapter) -> float:
        """Evaluate position using NNUE model"""
        features = game_state.to_nnue_features()
        features_tensor = torch.from_numpy(features).unsqueeze(0).to(self.device)
        side_to_move_tensor = torch.tensor([game_state.side_to_move], dtype=torch.long).to(self.device)
        
        with torch.no_grad():
            evaluation = self.model(features_tensor, side_to_move_tensor)
            return float(evaluation.squeeze().cpu())
            
    def order_moves(self, game_state: NNUEGameAdapter, moves: List[Tuple[int, int, int, int]]) -> List[Tuple[int, int, int, int]]:
        """Order moves based on NNUE evaluation for better Alpha-Beta pruning"""
        if len(moves) <= 1:
            return moves
            
        move_scores = []
        for move in moves:
            temp_state = game_state.copy()
            if temp_state.make_move(move):
                # Use NNUE evaluation to score the resulting position
                score = self.evaluate_position(temp_state)
                move_scores.append((move, score))
            else:
                # Invalid move gets lowest priority
                move_scores.append((move, float('-inf')))
        
        # Sort moves: best moves first for the current player
        if game_state.side_to_move == 0:  # White (maximizing)
            move_scores.sort(key=lambda x: x[1], reverse=True)
        else:  # Black (minimizing) 
            move_scores.sort(key=lambda x: x[1], reverse=False)
            
        return [move for move, score in move_scores]

    def get_best_move(self, game_state: NNUEGameAdapter) -> Optional[Tuple[int, int, int, int]]:
        """Get best move using Alpha-Beta pruning with NNUE evaluation"""
        
        # Reset statistics
        self.nodes_searched = 0
        self.cutoffs = 0
        
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return None
            
        # Order moves using NNUE evaluation for better pruning
        ordered_moves = self.order_moves(game_state, valid_moves)
        
        # Collect all moves with their scores
        move_scores = []
        alpha = float('-inf')
        beta = float('inf')
        
        for move in ordered_moves:
            temp_state = game_state.copy()
            if temp_state.make_move(move):
                if game_state.side_to_move == 0:  # White (maximizing)
                    score = self._alpha_beta(temp_state, self.search_depth - 1, alpha, beta, False)
                else:  # Black (minimizing)
                    score = self._alpha_beta(temp_state, self.search_depth - 1, alpha, beta, True)
                move_scores.append((move, score))
        
        if not move_scores:
            return None
            
        # Find the best score
        if game_state.side_to_move == 0:  # White (maximizing)
            best_score = max(score for _, score in move_scores)
        else:  # Black (minimizing)
            best_score = min(score for _, score in move_scores)
        
        # Find all moves with the best score (exactly equal)
        epsilon = 1e-9  # Very small tolerance for floating point comparison
        best_moves = [move for move, score in move_scores if abs(score - best_score) < epsilon]
        
        # Return based on randomness setting
        if self.use_randomness and len(best_moves) > 1:
            # Random selection among equally good moves
            return random.choice(best_moves)
        else:
            # Deterministic: return first best move
            return best_moves[0]
        
    def _alpha_beta(self, game_state: NNUEGameAdapter, depth: int, 
                    alpha: float, beta: float, maximizing: bool) -> float:
        """Alpha-Beta pruning search with NNUE evaluation"""
        self.nodes_searched += 1
        
        # Check if game is over or reached depth limit
        is_over, reason = game_state.is_game_over()
        if is_over or depth == 0:
            return self.evaluate_position(game_state)
            
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return self.evaluate_position(game_state)
            
        # Order moves using NNUE evaluation for better pruning
        ordered_moves = self.order_moves(game_state, valid_moves)
            
        if maximizing:
            max_eval = float('-inf')
            for move in ordered_moves:
                temp_state = game_state.copy()
                if temp_state.make_move(move):
                    eval_score = self._alpha_beta(temp_state, depth - 1, alpha, beta, False)
                    max_eval = max(max_eval, eval_score)
                    alpha = max(alpha, eval_score)
                    if beta <= alpha:
                        self.cutoffs += 1
                        break  # Beta cutoff - pruning
            return max_eval
        else:
            min_eval = float('inf')
            for move in ordered_moves:
                temp_state = game_state.copy()
                if temp_state.make_move(move):
                    eval_score = self._alpha_beta(temp_state, depth - 1, alpha, beta, True)
                    min_eval = min(min_eval, eval_score)
                    beta = min(beta, eval_score)
                    if beta <= alpha:
                        self.cutoffs += 1
                        break  # Alpha cutoff - pruning
            return min_eval

    def set_search_depth(self, depth: int):
        """Set search depth dynamically"""
        self.search_depth = max(1, depth)
        
    def set_randomness(self, use_randomness: bool):
        """Set randomness behavior dynamically"""
        self.use_randomness = use_randomness

    def get_search_stats(self) -> str:
        """Get search statistics for performance monitoring"""
        if self.nodes_searched == 0:
            return "No search performed yet"
        
        cutoff_rate = (self.cutoffs / max(1, self.nodes_searched)) * 100
        randomness_str = "Random" if self.use_randomness else "Deterministic"
        return f"Depth: {self.search_depth}, Nodes: {self.nodes_searched}, Cutoffs: {self.cutoffs} ({cutoff_rate:.1f}%), Mode: {randomness_str}"


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
        
        quit_btn = self.tk.Button(button_frame, text="Quit", command=self.root.quit)
        quit_btn.pack(side=self.tk.LEFT, padx=5)
        
        # Draw initial board
        self.draw_board()
        self.update_status()
        self.update_evaluation_display()
        
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

    def restart_game(self):
        """Restart the game"""
        self.game_state = NNUEGameAdapter()
        self.selected_pos = None
        self.game_over = False
        self.last_move_text = ""  # Clear last move
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
        "log_level": "INFO"
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
        
    feature_size = args.feature_size or config.get('feature_size', 115)
    hidden_size = args.hidden_size or config.get('hidden_size', 256)
    search_depth = args.depth or config.get('search_depth', 8)
    use_randomness = args.random or config.get('use_randomness', False)
    force_cpu = not (args.use_gpu or config.get('use_gpu', False))
    human_first = (args.first == 'human') if args.first else config.get('human_first', True)
    use_gui = args.gui or config.get('gui', False)
    
    try:
        # Load NNUE model
        device_str = "CPU (forced)" if force_cpu else ("GPU" if torch.cuda.is_available() else "CPU")
        logger.info(f"Loading NNUE model from {model_path} on {device_str}")
        model_loader = NNUEModelLoader(model_path, feature_size, hidden_size, force_cpu)
        nnue_player = NNUEPlayer(model_loader, search_depth, use_randomness)
        
        if use_gui:
            # Start GUI game
            logger.info("Starting GUI game...")
            gui = NNUEGameGUI(nnue_player, human_first)
            gui.start_gui()
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
