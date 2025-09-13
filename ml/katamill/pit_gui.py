#!/usr/bin/env python3
"""
Katamill GUI Pitting Script - Human vs AI with Visual Interface
Adapted from ml/sl implementation for Nine Men's Morris with Katamill models.

Usage:
  python -m ml.katamill.pit_gui --model checkpoints/model.pth --gui
  python -m ml.katamill.pit_gui --model checkpoints/model.pth --mcts-sims 200
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
from copy import deepcopy

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import katamill modules
try:
    from .config import default_net_config
    from .neural_network import KatamillNet, KatamillWrapper
    from .mcts import MCTS
    from .pit import load_model
except ImportError:
    from config import default_net_config
    from neural_network import KatamillNet, KatamillWrapper
    from mcts import MCTS
    from pit import load_model

# Import game modules
try:
    from ml.game.Game import Game
    from ml.game.engine_adapter import move_to_engine_token
except ImportError:
    from game.Game import Game
    from game.engine_adapter import move_to_engine_token

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class KatamillPlayer:
    """AI player using Katamill model with MCTS search"""

    def __init__(self, model_path: str, device: str, mcts_sims: int = 200,
                 temperature: float = 0.0):
        self.model_path = model_path
        self.device = torch.device(device)
        self.mcts_sims = mcts_sims
        self.temperature = temperature
        
        # Load model
        self.wrapper = load_model(model_path, device)
        self.game = Game()
        
        # Statistics
        self.move_count = 0
        self.total_think_time = 0.0
        
        logger.info(f"Loaded Katamill model from {model_path}")
        logger.info(f"Device: {device}, MCTS sims: {mcts_sims}")

    def get_best_move(self, board, current_player: int) -> Optional[int]:
        """Get best move using MCTS search with LC0-inspired configuration"""
        start_time = time.time()
        
        # Create fresh MCTS for each move optimized for Nine Men's Morris
        mcts = MCTS(self.game, self.wrapper, {
            'cpuct': 1.8,  # Balanced exploration for 7x7 board (2.5 too high)
            'num_simulations': max(self.mcts_sims, 600),  # Ensure minimum strength
            'dirichlet_alpha': 0.15,  # Moderate noise for human games
            'dirichlet_epsilon': 0.08,  # Low noise for deterministic play
            'use_virtual_loss': True,
            'progressive_widening': True,
            'use_transpositions': True,  # Enable transposition table for efficiency
            'max_transposition_size': 100000,  # Large transposition table
            'consecutive_move_bonus': 0.02,  # Small bonus (consecutive moves often forced)
            'max_search_depth': 150,  # Reasonable depth limit
            'fpu_reduction': 0.25,  # LC0-style First Play Urgency reduction
            'fpu_at_root': True,  # Apply FPU at root for better move ordering
            'min_visits_for_expansion': 1,  # Expand nodes early
            # Nine Men's Morris phase-specific parameters
            'removal_phase_exploration': 0.8,  # Less exploration in removal (forced moves)
            'placing_phase_exploration': 1.3,  # More exploration in placing
            'flying_phase_simulations_multiplier': 2.0  # More search in flying phase
        })
        
        # Get action probabilities
        probs = mcts.get_action_probabilities(board, current_player, temperature=self.temperature)
        
        # Select action
        if self.temperature > 0:
            action = int(np.random.choice(len(probs), p=probs))
        else:
            action = int(np.argmax(probs))
        
        # Update statistics
        think_time = time.time() - start_time
        self.move_count += 1
        self.total_think_time += think_time
        
        logger.info(f"AI move: action {action} (thought for {think_time:.1f}s)")
        return action

    def get_evaluation(self, board, current_player: int) -> float:
        """Get position evaluation from AI perspective"""
        try:
            policy_probs, value = self.wrapper.predict(board, current_player)
            return float(value)
        except Exception as e:
            logger.warning(f"Evaluation failed: {e}")
            return 0.0

    def get_stats(self) -> str:
        """Get AI performance statistics"""
        if self.move_count == 0:
            return "No moves made yet"
        
        avg_time = self.total_think_time / self.move_count
        return f"Moves: {self.move_count}, Avg think time: {avg_time:.1f}s, MCTS sims: {self.mcts_sims}"


class KatamillGUI:
    """GUI for Katamill human vs AI games"""

    def __init__(self, ai_player: KatamillPlayer, human_first: bool = True):
        self.ai_player = ai_player
        self.human_first = human_first
        self.game = Game()
        self.board = self.game.getInitBoard()
        self.current_player = 1  # 1 for white, -1 for black
        
        # Game state
        self.selected_pos = None
        self.game_over = False
        self.move_history = []
        self.position_history = []  # Track position history following Nine Men's Morris rules
        
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
        self.eval_label = None
        self.eval_canvas = None

    def start_gui(self):
        """Start the GUI game"""
        self.root = self.tk.Tk()
        self.root.title("Katamill - Human vs AI")
        self.root.geometry("700x850")

        # Status label
        self.status_label = self.tk.Label(self.root, text="Game started", font=("Arial", 12))
        self.status_label.pack(pady=10)

        # Evaluation display frame
        eval_frame = self.tk.Frame(self.root)
        eval_frame.pack(pady=5)

        # Evaluation label
        self.eval_label = self.tk.Label(eval_frame, text="Position Evaluation: 0.00",
                                       font=("Arial", 14, "bold"), fg="#333")
        self.eval_label.pack()

        # Evaluation bar
        eval_bar_frame = self.tk.Frame(eval_frame)
        eval_bar_frame.pack(pady=5)

        self.eval_canvas = self.tk.Canvas(eval_bar_frame, width=300, height=20, bg="#ddd")
        self.eval_canvas.pack()

        # Canvas for board
        canvas_width = 600
        canvas_height = 600
        self.canvas = self.tk.Canvas(self.root, width=canvas_width, height=canvas_height, bg="#f5f5dc")
        self.canvas.pack(pady=10)
        self.canvas.bind("<Button-1>", self.on_click)

        # Control buttons
        button_frame = self.tk.Frame(self.root)
        button_frame.pack(pady=10)

        restart_btn = self.tk.Button(button_frame, text="New Game", command=self.restart_game)
        restart_btn.pack(side=self.tk.LEFT, padx=5)

        stats_btn = self.tk.Button(button_frame, text="AI Stats", command=self.show_ai_stats)
        stats_btn.pack(side=self.tk.LEFT, padx=5)

        quit_btn = self.tk.Button(button_frame, text="Quit", command=self.safe_quit)
        quit_btn.pack(side=self.tk.LEFT, padx=5)

        # Draw initial board
        self.draw_board()
        self.update_status()
        self.update_evaluation()

        # Set up window close protocol
        self.root.protocol("WM_DELETE_WINDOW", self.safe_quit)

        # If AI goes first, make AI move
        if not self.human_first:
            self.root.after(1000, self.make_ai_move)

        self.root.mainloop()

    def draw_board(self):
        """Draw the Nine Men's Morris board"""
        self.canvas.delete("all")

        # Board configuration
        board_size = 480
        margin = 60
        
        # Calculate positions for the three squares
        outer_size = board_size
        middle_size = board_size * 2 // 3
        inner_size = board_size // 3
        
        outer_offset = 0
        middle_offset = (outer_size - middle_size) // 2
        inner_offset = (outer_size - inner_size) // 2

        # Draw the three squares
        # Outer square
        self.canvas.create_rectangle(margin + outer_offset, margin + outer_offset,
                                   margin + outer_offset + outer_size, margin + outer_offset + outer_size,
                                   outline="#8B4513", width=3, fill="")
        
        # Middle square
        self.canvas.create_rectangle(margin + middle_offset, margin + middle_offset,
                                   margin + middle_offset + middle_size, margin + middle_offset + middle_size,
                                   outline="#8B4513", width=3, fill="")
        
        # Inner square
        self.canvas.create_rectangle(margin + inner_offset, margin + inner_offset,
                                   margin + inner_offset + inner_size, margin + inner_offset + inner_size,
                                   outline="#8B4513", width=3, fill="")

        # Draw connecting lines
        center = margin + board_size // 2
        
        # Horizontal lines
        self.canvas.create_line(margin, center, margin + inner_offset, center, fill="#8B4513", width=3)
        self.canvas.create_line(margin + inner_offset + inner_size, center, margin + board_size, center, fill="#8B4513", width=3)
        
        # Vertical lines
        self.canvas.create_line(center, margin, center, margin + inner_offset, fill="#8B4513", width=3)
        self.canvas.create_line(center, margin + inner_offset + inner_size, center, margin + board_size, fill="#8B4513", width=3)

        # Draw intersection points and pieces
        piece_radius = 15
        
        # Get valid positions from the board
        for x in range(7):
            for y in range(7):
                if self.board.allowed_places[x][y]:
                    # Convert board coordinates to canvas coordinates
                    canvas_x = margin + x * (board_size // 6)
                    canvas_y = margin + y * (board_size // 6)
                    
                    # Draw intersection point
                    self.canvas.create_oval(canvas_x - 3, canvas_y - 3, canvas_x + 3, canvas_y + 3,
                                          fill="#8B4513", outline="#8B4513")
                    
                    # Draw piece if present
                    piece = self.board.pieces[x][y]
                    if piece == 1:  # White piece
                        self.canvas.create_oval(canvas_x - piece_radius, canvas_y - piece_radius,
                                              canvas_x + piece_radius, canvas_y + piece_radius,
                                              fill="#ffffff", outline="#000000", width=2)
                    elif piece == -1:  # Black piece
                        self.canvas.create_oval(canvas_x - piece_radius, canvas_y - piece_radius,
                                              canvas_x + piece_radius, canvas_y + piece_radius,
                                              fill="#000000", outline="#000000", width=2)

        # Highlight selected position
        if self.selected_pos:
            x, y = self.selected_pos
            canvas_x = margin + x * (board_size // 6)
            canvas_y = margin + y * (board_size // 6)
            self.canvas.create_oval(canvas_x - piece_radius - 5, canvas_y - piece_radius - 5,
                                  canvas_x + piece_radius + 5, canvas_y + piece_radius + 5,
                                  outline="#FFD700", width=4, fill="")

        # Store canvas configuration for click handling
        self._margin = margin
        self._board_size = board_size
        self._piece_radius = piece_radius

    def on_click(self, event):
        """Handle mouse click on board"""
        if self.game_over:
            return

        # Check if it's human's turn
        is_human_turn = (self.human_first and self.current_player == 1) or \
                       (not self.human_first and self.current_player == -1)
        
        if not is_human_turn:
            return

        # Convert click to board coordinates
        margin = self._margin
        board_size = self._board_size
        
        click_x = event.x - margin
        click_y = event.y - margin
        
        if click_x < 0 or click_y < 0 or click_x >= board_size or click_y >= board_size:
            return

        # Find nearest valid position
        board_x = round(click_x / (board_size // 6))
        board_y = round(click_y / (board_size // 6))
        
        board_x = max(0, min(6, board_x))
        board_y = max(0, min(6, board_y))
        
        if not self.board.allowed_places[board_x][board_y]:
            return

        self.handle_human_move(board_x, board_y)

    def handle_human_move(self, x: int, y: int):
        """Handle human move at position (x, y)"""
        if self.board.period == 0:  # Placing phase
            if self.board.pieces[x][y] == 0:  # Empty position
                action = self.board.get_action_from_move([x, y])
                self.make_move(action, "Human")
        
        elif self.board.period == 3:  # Removal phase
            # Click to remove opponent piece
            opponent = -self.current_player
            if self.board.pieces[x][y] == opponent:
                action = self.board.get_action_from_move([x, y])
                self.make_move(action, "Human")
        
        else:  # Moving/Flying phase
            if self.selected_pos is None:
                # Select piece to move - validate it can actually move
                if self.board.pieces[x][y] == self.current_player:
                    # Check if this piece has any valid moves
                    has_valid_moves = False
                    try:
                        valid_moves = self.game.getValidMoves(self.board, self.current_player)
                        
                        # Check all possible moves from this position
                        for dest_x in range(7):
                            for dest_y in range(7):
                                if (self.board.allowed_places[dest_x][dest_y] and 
                                    self.board.pieces[dest_x][dest_y] == 0):
                                    try:
                                        test_action = self.board.get_action_from_move([x, y, dest_x, dest_y])
                                        if test_action < len(valid_moves) and valid_moves[test_action] == 1:
                                            has_valid_moves = True
                                            break
                                    except:
                                        continue
                            if has_valid_moves:
                                break
                    except Exception as e:
                        print(f"Error checking valid moves: {e}")
                        has_valid_moves = True  # Allow selection if check fails
                    
                    if has_valid_moves:
                        self.selected_pos = (x, y)
                        self.draw_board()
                        print(f"Selected piece at ({x}, {y})")
                    else:
                        print(f"Piece at ({x}, {y}) cannot move")
            else:
                # Move piece - validate the move is legal
                if self.board.pieces[x][y] == 0:  # Empty position
                    from_x, from_y = self.selected_pos
                    try:
                        action = self.board.get_action_from_move([from_x, from_y, x, y])
                        
                        # Validate this is a legal move
                        valid_moves = self.game.getValidMoves(self.board, self.current_player)
                        if action < len(valid_moves) and valid_moves[action] == 1:
                            self.make_move(action, "Human")
                            self.selected_pos = None
                        else:
                            print(f"Invalid move from ({from_x}, {from_y}) to ({x}, {y})")
                            self.selected_pos = None
                            self.draw_board()
                    except Exception as e:
                        print(f"Error making move: {e}")
                        self.selected_pos = None
                        self.draw_board()
                else:
                    # Clicking on another piece - reselect if it's our piece
                    if self.board.pieces[x][y] == self.current_player:
                        self.selected_pos = (x, y)
                        self.draw_board()
                        print(f"Reselected piece at ({x}, {y})")
                    else:
                        # Deselect if clicking on opponent piece
                        self.selected_pos = None
                        self.draw_board()

    def make_move(self, action: int, player_name: str):
        """Make a move and update the game state"""
        try:
            # Additional validation before making move
            valid_moves = self.game.getValidMoves(self.board, self.current_player)
            if action >= len(valid_moves) or valid_moves[action] != 1:
                print(f"Invalid action {action} for player {self.current_player}")
                print(f"Valid actions: {np.where(valid_moves == 1)[0][:10].tolist()}")  # Show first 10 valid actions
                return
            
            # Validate and execute move with proper position tracking
            next_board, next_player = self.game.getNextState(self.board, self.current_player, action)
            
            # Update game state
            self.board = next_board
            self.current_player = next_player
            
            # Position tracking following Nine Men's Morris rules

            
            try:
                # Determine move type based on game phase and action
                current_phase = getattr(self.board, 'period', 0)
                
                if current_phase == 0:  # Placing phase
                    # Clear history - placing phase doesn't track repetitions
                    self.position_history.clear()
                elif current_phase == 3:  # Removal phase  
                    # Clear history - removal changes board structure
                    self.position_history.clear()
                elif current_phase in [1, 2]:  # Moving/Flying phase
                    # Only track repetitions in moving/flying phases
                    position_key = str(self.board.pieces) + f"_p{self.current_player}"
                    self.position_history.append(position_key)
                    
                    # Check for threefold repetition
                    position_count = self.position_history.count(position_key)
                    if position_count >= 3:
                        print(f"⚠ Threefold repetition detected in moving phase: {position_count} times")
                        # Properly handle draw
                        self.game_over = True
                        self.show_game_result(1e-4)  # Draw value
                        return
                    
                    # Keep history manageable (only for moving phase)
                    if len(self.position_history) > 100:
                        self.position_history.pop(0)
                        
            except Exception as e:
                print(f"Position tracking error: {e}")
                pass  # Continue if position tracking fails
            
            # Record move
            move_notation = f"action_{action}"
            try:
                move = self.board.get_move_from_action(action)
                if len(move) == 2:
                    move_notation = move_to_engine_token(move)
                    if self.board.period == 3:  # Was removal
                        move_notation = f"x{move_notation}"
                else:
                    move_notation = move_to_engine_token(move)
            except:
                pass
            
            self.move_history.append((player_name, move_notation))
            logger.info(f"{player_name} move: {move_notation}")
            
            # Update display
            self.draw_board()
            self.update_status()
            self.update_evaluation()
            
            # Check if game ended (including proper draw detection)
            result = self.game.getGameEnded(self.board, self.current_player)
            if result != 0:
                self.game_over = True
                # Properly handle draws vs wins/losses
                if abs(result) < 0.01:  # Draw (including threefold repetition)
                    print(f"Game ended in draw (result={result:.6f})")
                self.show_game_result(result)
                return
            
            # Schedule AI move if it's AI's turn
            is_ai_turn = (not self.human_first and self.current_player == 1) or \
                        (self.human_first and self.current_player == -1)
            
            if is_ai_turn:
                self.root.after(500, self.make_ai_move)
                
        except Exception as e:
            logger.warning(f"Invalid move by {player_name}: {e}")

    def make_ai_move(self):
        """Make AI move in a separate thread"""
        if self.game_over:
            return

        self.update_status("AI is thinking...")
        
        def ai_thread():
            try:
                action = self.ai_player.get_best_move(self.board, self.current_player)
                if action is not None:
                    self.root.after(0, lambda: self.make_move(action, "AI"))
                else:
                    self.root.after(0, lambda: logger.warning("AI found no valid moves"))
            except Exception as e:
                self.root.after(0, lambda: logger.error(f"AI move failed: {e}"))

        thread = threading.Thread(target=ai_thread, daemon=True)
        thread.start()

    def update_status(self, message: Optional[str] = None):
        """Update status display"""
        if message:
            self.status_label.config(text=message)
            return

        # Determine current player
        if self.human_first:
            current_player_name = "Human" if self.current_player == 1 else "AI"
        else:
            current_player_name = "AI" if self.current_player == 1 else "Human"

        # Phase information
        phase_names = {0: "Placing", 1: "Moving", 2: "Flying", 3: "Removal"}
        phase_name = phase_names.get(self.board.period, "Unknown")
        
        # Piece counts
        white_on_board = self.board.count(1)
        black_on_board = self.board.count(-1)
        white_in_hand = self.board.pieces_in_hand_count(1)
        black_in_hand = self.board.pieces_in_hand_count(-1)
        
        status_text = (f"{phase_name} Phase | {current_player_name}'s turn | "
                      f"White: {white_on_board}+{white_in_hand} | Black: {black_on_board}+{black_in_hand}")
        
        self.status_label.config(text=status_text)

    def update_evaluation(self):
        """Update position evaluation display"""
        if self.game_over:
            self.eval_label.config(text="Position Evaluation: Game Over")
            return

        try:
            # Get evaluation from AI
            raw_eval = self.ai_player.get_evaluation(self.board, self.current_player)
            
            # Convert to human perspective
            if self.human_first:
                # Human is white (player 1)
                human_eval = raw_eval if self.current_player == 1 else -raw_eval
            else:
                # Human is black (player -1)
                human_eval = -raw_eval if self.current_player == 1 else raw_eval
            
            # Format display
            if abs(human_eval) > 2.0:
                eval_text = f"Position Evaluation: {human_eval:+.2f} (Decisive)"
            elif abs(human_eval) > 1.0:
                eval_text = f"Position Evaluation: {human_eval:+.2f} (Clear advantage)"
            elif abs(human_eval) > 0.3:
                eval_text = f"Position Evaluation: {human_eval:+.2f} (Slight advantage)"
            else:
                eval_text = f"Position Evaluation: {human_eval:+.2f} (Equal)"
            
            self.eval_label.config(text=eval_text)
            self.draw_evaluation_bar(human_eval)
            
        except Exception as e:
            self.eval_label.config(text="Position Evaluation: Error")
            logger.warning(f"Evaluation update failed: {e}")

    def draw_evaluation_bar(self, evaluation: float):
        """Draw evaluation bar"""
        self.eval_canvas.delete("all")
        
        bar_width = 300
        bar_height = 20
        center_x = bar_width // 2
        
        # Normalize evaluation using tanh
        import math
        normalized = math.tanh(evaluation / 2.0)
        bar_pos = center_x + (normalized * center_x * 0.9)
        
        # Draw background
        self.eval_canvas.create_rectangle(0, 0, bar_width, bar_height,
                                        fill="#e0e0e0", outline="#ccc")
        
        # Draw center line
        self.eval_canvas.create_line(center_x, 0, center_x, bar_height,
                                   fill="#888", width=2)
        
        # Draw evaluation bar
        if normalized > 0:
            # Human advantage (green)
            self.eval_canvas.create_rectangle(center_x, 2, bar_pos, bar_height - 2,
                                            fill="#4CAF50", outline="#4CAF50")
        else:
            # Human disadvantage (red)
            self.eval_canvas.create_rectangle(bar_pos, 2, center_x, bar_height - 2,
                                            fill="#f44336", outline="#f44336")

    def show_game_result(self, result: float):
        """Show game over dialog"""
        if abs(result) < 0.01:
            winner = "Draw"
            message = "The game ended in a draw!"
        elif result > 0:
            # Current player wins
            if self.current_player == 1:
                winner = "White wins"
            else:
                winner = "Black wins"
            
            if self.human_first:
                winner_name = "Human" if self.current_player == 1 else "AI"
            else:
                winner_name = "AI" if self.current_player == 1 else "Human"
            
            message = f"{winner}! {winner_name} is victorious!"
        else:
            # Current player loses  
            if self.current_player == 1:
                winner = "Black wins"
            else:
                winner = "White wins"
            
            if self.human_first:
                winner_name = "AI" if self.current_player == 1 else "Human"
            else:
                winner_name = "Human" if self.current_player == 1 else "AI"
            
            message = f"{winner}! {winner_name} is victorious!"

        self.messagebox.showinfo("Game Over", message)

    def show_ai_stats(self):
        """Show AI performance statistics"""
        stats = self.ai_player.get_stats()
        self.messagebox.showinfo("AI Statistics", stats)

    def restart_game(self):
        """Restart the game"""
        self.board = self.game.getInitBoard()
        self.current_player = 1
        self.selected_pos = None
        self.game_over = False
        self.move_history = []
        
        # Reset AI stats
        self.ai_player.move_count = 0
        self.ai_player.total_think_time = 0.0
        
        self.draw_board()
        self.update_status()
        self.update_evaluation()
        
        # If AI goes first, make AI move
        if not self.human_first:
            self.root.after(1000, self.make_ai_move)

    def safe_quit(self):
        """Safely quit the application"""
        try:
            if self.root:
                self.root.destroy()
        except:
            import sys
            sys.exit(0)


def main():
    parser = argparse.ArgumentParser(
        description='Katamill GUI Pitting - Human vs AI',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m ml.katamill.pit_gui --model checkpoints/model.pth --gui
  python -m ml.katamill.pit_gui --model checkpoints/iter_3/katamill_final.pth --mcts-sims 200
        """
    )

    parser.add_argument('--model', type=str, required=True, help='Path to Katamill model (.pth)')
    parser.add_argument('--gui', action='store_true', default=True, help='Enable GUI mode (default)')
    parser.add_argument('--first', choices=['human', 'ai'], default='human', help='Who goes first')
    parser.add_argument('--mcts-sims', type=int, default=200, help='MCTS simulations per move')
    parser.add_argument('--temperature', type=float, default=0.0, help='Temperature for AI moves')
    parser.add_argument('--device', choices=['cpu', 'cuda', 'auto'], default='auto', help='Device for inference')

    args = parser.parse_args()

    # Device selection
    if args.device == 'auto':
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
    else:
        device = args.device

    try:
        # Create AI player
        ai_player = KatamillPlayer(args.model, device, args.mcts_sims, args.temperature)
        
        if args.gui:
            # Start GUI game
            logger.info("Starting Katamill GUI game...")
            gui = KatamillGUI(ai_player, human_first=(args.first == 'human'))
            gui.start_gui()
        else:
            logger.info("Console mode not implemented. Use --gui for interactive play.")

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
