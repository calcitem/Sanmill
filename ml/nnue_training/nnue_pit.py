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

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from train_nnue import MillNNUE
from config_loader import load_config, merge_config_with_args

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class NNUEModelLoader:
    """NNUE model loader that can handle both .bin and .pth formats"""
    
    def __init__(self, model_path: str, feature_size: int = 115, hidden_size: int = 256):
        self.model_path = model_path
        self.feature_size = feature_size
        self.hidden_size = hidden_size
        self.model = None
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
    def load_model(self) -> MillNNUE:
        """Load NNUE model from file"""
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"NNUE model file not found: {self.model_path}")
            
        # Create model instance
        self.model = MillNNUE(feature_size=self.feature_size, hidden_size=self.hidden_size)
        
        if self.model_path.endswith('.bin'):
            self._load_binary_model()
        elif self.model_path.endswith('.pth') or self.model_path.endswith('.tar'):
            self._load_pytorch_model()
        else:
            raise ValueError(f"Unsupported model format: {self.model_path}")
            
        self.model.to(self.device)
        self.model.eval()
        logger.info(f"✅ Loaded NNUE model: {self.model_path}")
        return self.model
        
    def _load_binary_model(self):
        """Load from C++ compatible binary format"""
        try:
            with open(self.model_path, 'rb') as f:
                # Read header
                header = f.read(8)
                if header != b'SANMILL1':
                    raise ValueError(f"Invalid header: {header}")
                
                # Read dimensions
                feature_size, hidden_size = struct.unpack('<II', f.read(8))
                
                # Verify dimensions match
                if feature_size != self.feature_size or hidden_size != self.hidden_size:
                    logger.warning(f"Model dimensions ({feature_size}, {hidden_size}) "
                                 f"differ from expected ({self.feature_size}, {self.hidden_size})")
                
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


class SimpleGameState:
    """Simplified game state representation for NNUE evaluation"""
    
    def __init__(self):
        self.board = np.zeros((7, 7), dtype=np.int8)  # -1: empty, 0: white, 1: black
        self.side_to_move = 0  # 0: white, 1: black
        self.phase = 0  # 0: placing, 1: moving, 2: flying
        self.white_pieces_in_hand = 9
        self.black_pieces_in_hand = 9
        self.white_pieces_on_board = 0
        self.black_pieces_on_board = 0
        self.move_count = 0
        
        # Valid board positions (standard Nine Men's Morris board)
        self.valid_positions = set([
            (0,0), (0,3), (0,6),
            (1,1), (1,3), (1,5),
            (2,2), (2,3), (2,4),
            (3,0), (3,1), (3,2), (3,4), (3,5), (3,6),
            (4,2), (4,3), (4,4),
            (5,1), (5,3), (5,5),
            (6,0), (6,3), (6,6)
        ])
        
        # Initialize valid positions as empty (-1)
        self.board.fill(0)  # Invalid positions remain 0
        for x, y in self.valid_positions:
            self.board[x, y] = -1  # Valid positions are empty (-1)
        
    def to_nnue_features(self) -> np.ndarray:
        """Convert game state to NNUE feature vector"""
        features = np.zeros(115, dtype=np.float32)
        
        # Piece placement features (24 + 24 = 48 features)
        white_idx = 0
        black_idx = 24
        for i, (x, y) in enumerate(sorted(self.valid_positions)):
            if (x, y) in self.valid_positions:
                if self.board[x, y] == 0:  # White piece
                    features[white_idx + i] = 1.0
                elif self.board[x, y] == 1:  # Black piece
                    features[black_idx + i] = 1.0
                    
        # Phase features (3 features)
        features[48 + self.phase] = 1.0
        
        # Piece count features (4 features)
        features[51] = self.white_pieces_in_hand / 9.0
        features[52] = self.black_pieces_in_hand / 9.0
        features[53] = self.white_pieces_on_board / 9.0
        features[54] = self.black_pieces_on_board / 9.0
        
        # Side to move (1 feature)
        features[55] = float(self.side_to_move)
        
        # Move count normalized (1 feature)
        features[56] = min(self.move_count / 100.0, 1.0)
        
        # Mill detection features (remaining features)
        # TODO: Add mill detection logic
        
        return features
        
    def is_valid_position(self, x: int, y: int) -> bool:
        """Check if position is valid on the board"""
        return (x, y) in self.valid_positions
        
    def get_valid_moves(self) -> List[Tuple[int, int, int, int]]:
        """Get list of valid moves in current position"""
        moves = []
        
        if self.phase == 0:  # Placing phase
            pieces_in_hand = self.white_pieces_in_hand if self.side_to_move == 0 else self.black_pieces_in_hand
            if pieces_in_hand > 0:
                for x, y in self.valid_positions:
                    if self.board[x, y] == -1:  # Empty position
                        moves.append((x, y, x, y))  # Place move
        else:  # Moving/Flying phase
            for x, y in self.valid_positions:
                if self.board[x, y] == self.side_to_move:  # Own piece
                    # Find adjacent empty positions
                    for nx, ny in self._get_adjacent_positions(x, y):
                        if self.board[nx, ny] == -1:  # Empty
                            moves.append((x, y, nx, ny))  # Move
                            
        return moves
        
    def _get_adjacent_positions(self, x: int, y: int) -> List[Tuple[int, int]]:
        """Get adjacent positions for moving"""
        # TODO: Implement proper adjacency rules for Nine Men's Morris
        adjacent = []
        for dx, dy in [(-1,0), (1,0), (0,-1), (0,1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < 7 and 0 <= ny < 7 and (nx, ny) in self.valid_positions:
                adjacent.append((nx, ny))
        return adjacent
        
    def make_move(self, move: Tuple[int, int, int, int]) -> bool:
        """Make a move on the board"""
        x1, y1, x2, y2 = move
        
        if not self.is_valid_position(x2, y2) or self.board[x2, y2] != -1:
            return False
            
        if self.phase == 0:  # Placing
            if self.side_to_move == 0 and self.white_pieces_in_hand > 0:
                self.board[x2, y2] = 0
                self.white_pieces_in_hand -= 1
                self.white_pieces_on_board += 1
            elif self.side_to_move == 1 and self.black_pieces_in_hand > 0:
                self.board[x2, y2] = 1
                self.black_pieces_in_hand -= 1
                self.black_pieces_on_board += 1
            else:
                return False
        else:  # Moving
            if self.board[x1, y1] != self.side_to_move:
                return False
            self.board[x1, y1] = -1
            self.board[x2, y2] = self.side_to_move
            
        self.move_count += 1
        self.side_to_move = 1 - self.side_to_move
        
        # Update phase
        if self.white_pieces_in_hand == 0 and self.black_pieces_in_hand == 0:
            self.phase = 1  # Moving phase
            
        return True


class NNUEPlayer:
    """AI player using NNUE model for evaluation"""
    
    def __init__(self, model_loader: NNUEModelLoader, search_depth: int = 3):
        self.model = model_loader.load_model()
        self.device = model_loader.device
        self.search_depth = search_depth
        
    def evaluate_position(self, game_state: SimpleGameState) -> float:
        """Evaluate position using NNUE model"""
        features = game_state.to_nnue_features()
        features_tensor = torch.from_numpy(features).unsqueeze(0).to(self.device)
        side_to_move_tensor = torch.tensor([game_state.side_to_move], dtype=torch.long).to(self.device)
        
        with torch.no_grad():
            evaluation = self.model(features_tensor, side_to_move_tensor)
            return float(evaluation.squeeze().cpu())
            
    def get_best_move(self, game_state: SimpleGameState) -> Optional[Tuple[int, int, int, int]]:
        """Get best move using minimax with NNUE evaluation"""
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return None
            
        best_move = None
        best_score = float('-inf') if game_state.side_to_move == 0 else float('inf')
        
        for move in valid_moves:
            # Make move
            temp_state = self._copy_state(game_state)
            if temp_state.make_move(move):
                score = self._minimax(temp_state, self.search_depth - 1, False if game_state.side_to_move == 0 else True)
                
                if game_state.side_to_move == 0:  # White (maximizing)
                    if score > best_score:
                        best_score = score
                        best_move = move
                else:  # Black (minimizing)
                    if score < best_score:
                        best_score = score
                        best_move = move
                        
        return best_move
        
    def _minimax(self, game_state: SimpleGameState, depth: int, maximizing: bool) -> float:
        """Minimax search with NNUE evaluation"""
        if depth == 0:
            return self.evaluate_position(game_state)
            
        valid_moves = game_state.get_valid_moves()
        if not valid_moves:
            return self.evaluate_position(game_state)
            
        if maximizing:
            max_score = float('-inf')
            for move in valid_moves:
                temp_state = self._copy_state(game_state)
                if temp_state.make_move(move):
                    score = self._minimax(temp_state, depth - 1, False)
                    max_score = max(max_score, score)
            return max_score
        else:
            min_score = float('inf')
            for move in valid_moves:
                temp_state = self._copy_state(game_state)
                if temp_state.make_move(move):
                    score = self._minimax(temp_state, depth - 1, True)
                    min_score = min(min_score, score)
            return min_score
            
    def _copy_state(self, game_state: SimpleGameState) -> SimpleGameState:
        """Create a copy of the game state"""
        new_state = SimpleGameState()
        new_state.board = game_state.board.copy()
        new_state.side_to_move = game_state.side_to_move
        new_state.phase = game_state.phase
        new_state.white_pieces_in_hand = game_state.white_pieces_in_hand
        new_state.black_pieces_in_hand = game_state.black_pieces_in_hand
        new_state.white_pieces_on_board = game_state.white_pieces_on_board
        new_state.black_pieces_on_board = game_state.black_pieces_on_board
        new_state.move_count = game_state.move_count
        return new_state


class NNUEGameGUI:
    """Simple GUI for NNUE human vs AI games"""
    
    def __init__(self, nnue_player: NNUEPlayer, human_first: bool = True):
        self.nnue_player = nnue_player
        self.human_first = human_first
        self.game_state = SimpleGameState()
        
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
        
    def start_gui(self):
        """Start the GUI game"""
        self.root = self.tk.Tk()
        self.root.title("Sanmill NNUE - Human vs AI")
        self.root.geometry("600x700")
        
        # Status label
        self.status_label = self.tk.Label(self.root, text="Game started", font=("Arial", 12))
        self.status_label.pack(pady=10)
        
        # Canvas for board
        self.canvas = self.tk.Canvas(self.root, width=500, height=500, bg="white")
        self.canvas.pack(pady=10)
        self.canvas.bind("<Button-1>", self.on_click)
        
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
        
        # If AI goes first, make AI move
        if not self.human_first:
            self.root.after(1000, self.make_ai_move)
            
        self.root.mainloop()
        
    def draw_board(self):
        """Draw the game board"""
        self.canvas.delete("all")
        
        # Board dimensions
        size = 400
        margin = 50
        step = size // 6
        
        # Draw board lines
        positions = [
            # Outer square
            [(margin, margin), (margin + size, margin), (margin + size, margin + size), (margin, margin + size), (margin, margin)],
            # Middle square
            [(margin + step, margin + step), (margin + size - step, margin + step), 
             (margin + size - step, margin + size - step), (margin + step, margin + size - step), (margin + step, margin + step)],
            # Inner square
            [(margin + 2*step, margin + 2*step), (margin + size - 2*step, margin + 2*step),
             (margin + size - 2*step, margin + size - 2*step), (margin + 2*step, margin + size - 2*step), (margin + 2*step, margin + 2*step)],
            # Connecting lines
            [(margin + 3*step, margin), (margin + 3*step, margin + 2*step)],
            [(margin + 3*step, margin + 4*step), (margin + 3*step, margin + size)],
            [(margin, margin + 3*step), (margin + 2*step, margin + 3*step)],
            [(margin + 4*step, margin + 3*step), (margin + size, margin + 3*step)]
        ]
        
        for line in positions:
            for i in range(len(line) - 1):
                self.canvas.create_line(line[i][0], line[i][1], line[i+1][0], line[i+1][1], width=2)
        
        # Draw pieces
        for x, y in self.game_state.valid_positions:
            canvas_x = margin + y * step
            canvas_y = margin + x * step
            
            # Draw position marker
            self.canvas.create_oval(canvas_x - 5, canvas_y - 5, canvas_x + 5, canvas_y + 5, outline="gray")
            
            # Draw piece if present
            if self.game_state.board[x, y] == 0:  # White piece
                self.canvas.create_oval(canvas_x - 15, canvas_y - 15, canvas_x + 15, canvas_y + 15, 
                                      fill="white", outline="black", width=2)
            elif self.game_state.board[x, y] == 1:  # Black piece
                self.canvas.create_oval(canvas_x - 15, canvas_y - 15, canvas_x + 15, canvas_y + 15,
                                      fill="black", outline="black", width=2)
                                      
        # Highlight selected position
        if self.selected_pos:
            x, y = self.selected_pos
            canvas_x = margin + y * step
            canvas_y = margin + x * step
            self.canvas.create_oval(canvas_x - 20, canvas_y - 20, canvas_x + 20, canvas_y + 20,
                                  outline="red", width=3, fill="")
                                  
    def on_click(self, event):
        """Handle mouse click on board"""
        if self.game_over or (not self.human_first and self.game_state.side_to_move == 0) or \
           (self.human_first and self.game_state.side_to_move == 1):
            return  # Not human's turn
            
        # Convert click to board position
        margin = 50
        step = 400 // 6
        
        clicked_x = round((event.y - margin) / step)
        clicked_y = round((event.x - margin) / step)
        
        if not self.game_state.is_valid_position(clicked_x, clicked_y):
            return
            
        if self.game_state.phase == 0:  # Placing phase
            if self.game_state.board[clicked_x, clicked_y] == -1:  # Empty position
                move = (clicked_x, clicked_y, clicked_x, clicked_y)
                if self.game_state.make_move(move):
                    self.draw_board()
                    self.update_status()
                    if not self.game_over:
                        self.root.after(500, self.make_ai_move)
        else:  # Moving phase
            if self.selected_pos is None:
                # Select piece to move
                if self.game_state.board[clicked_x, clicked_y] == (0 if self.human_first else 1):
                    self.selected_pos = (clicked_x, clicked_y)
                    self.draw_board()
            else:
                # Move piece
                if self.game_state.board[clicked_x, clicked_y] == -1:  # Empty position
                    move = (self.selected_pos[0], self.selected_pos[1], clicked_x, clicked_y)
                    if self.game_state.make_move(move):
                        self.selected_pos = None
                        self.draw_board()
                        self.update_status()
                        if not self.game_over:
                            self.root.after(500, self.make_ai_move)
                else:
                    self.selected_pos = None
                    self.draw_board()
                    
    def make_ai_move(self):
        """Make AI move"""
        if self.game_over:
            return
            
        self.update_status("AI is thinking...")
        
        # Use threading to prevent GUI freezing
        def ai_move_thread():
            move = self.nnue_player.get_best_move(self.game_state)
            if move:
                self.game_state.make_move(move)
            
            # Update GUI in main thread
            self.root.after(0, lambda: self.after_ai_move(move))
            
        thread = threading.Thread(target=ai_move_thread, daemon=True)
        thread.start()
        
    def after_ai_move(self, move):
        """Update GUI after AI move"""
        self.draw_board()
        self.update_status()
        
        if move:
            x1, y1, x2, y2 = move
            logger.info(f"AI move: ({x1},{y1}) -> ({x2},{y2})")
        else:
            logger.info("AI has no valid moves")
            
    def update_status(self, message: Optional[str] = None):
        """Update status label"""
        if message:
            self.status_label.config(text=message)
            return
            
        if self.game_state.phase == 0:
            phase_text = "Placing phase"
        else:
            phase_text = "Moving phase"
            
        current_player = "Human" if ((self.human_first and self.game_state.side_to_move == 0) or
                                   (not self.human_first and self.game_state.side_to_move == 1)) else "AI"
        
        pieces_info = f"White: {self.game_state.white_pieces_on_board}+{self.game_state.white_pieces_in_hand}, " \
                     f"Black: {self.game_state.black_pieces_on_board}+{self.game_state.black_pieces_in_hand}"
        
        status_text = f"{phase_text} | {current_player}'s turn | {pieces_info}"
        self.status_label.config(text=status_text)
        
        # Check for game over
        if not self.game_state.get_valid_moves():
            self.game_over = True
            winner = "AI" if current_player == "Human" else "Human"
            self.messagebox.showinfo("Game Over", f"{winner} wins!")
            
    def restart_game(self):
        """Restart the game"""
        self.game_state = SimpleGameState()
        self.selected_pos = None
        self.game_over = False
        self.draw_board()
        self.update_status()
        
        if not self.human_first:
            self.root.after(1000, self.make_ai_move)


def create_config_file(filename: str):
    """Create a sample configuration file"""
    config = {
        "model_path": "nnue_model.bin",
        "feature_size": 115,
        "hidden_size": 256,
        "search_depth": 3,
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
    parser.add_argument('--depth', type=int, default=3, help='AI search depth')
    parser.add_argument('--feature-size', type=int, default=115, help='NNUE feature size')
    parser.add_argument('--hidden-size', type=int, default=512, help='NNUE hidden size')
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
    search_depth = args.depth or config.get('search_depth', 3)
    human_first = (args.first == 'human') if args.first else config.get('human_first', True)
    use_gui = args.gui or config.get('gui', False)
    
    try:
        # Load NNUE model
        logger.info(f"Loading NNUE model from {model_path}")
        model_loader = NNUEModelLoader(model_path, feature_size, hidden_size)
        nnue_player = NNUEPlayer(model_loader, search_depth)
        
        if use_gui:
            # Start GUI game
            logger.info("Starting GUI game...")
            gui = NNUEGameGUI(nnue_player, human_first)
            gui.start_gui()
        else:
            # Console mode (simplified)
            logger.info("Console mode not fully implemented. Use --gui for interactive play.")
            game_state = SimpleGameState()
            
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
