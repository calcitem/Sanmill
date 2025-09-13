#!/usr/bin/env python3
"""
Katamill Pitting Script - Human/AI vs Katamill model (policy+value with aux heads)

Usage:
  python -m ml.katamill.pit --model checkpoints/katamill.pth --gui --first human
  python -m ml.katamill.pit --model checkpoints/katamill.pth --games 5 --first ai
"""

import argparse
import json
import logging
import os
import sys
from typing import Optional

import numpy as np
import torch

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import modules with fallback
try:
    from .config import default_pit_config, default_mcts_config, default_net_config
    from .neural_network import KatamillNet, KatamillWrapper
    from .mcts import MCTS
except ImportError:
    from config import default_pit_config, default_mcts_config, default_net_config
    from neural_network import KatamillNet, KatamillWrapper
    from mcts import MCTS

try:
    from ml.game.Game import Game
except Exception:
    try:
        from game.Game import Game
    except Exception:
        # Last resort - add game path
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game


logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def load_model(path: Optional[str], device: str) -> KatamillWrapper:
    # Default config as fallback
    net_config = default_net_config()
    
    if path and os.path.exists(path):
        # Load checkpoint and auto-detect configuration
        state = torch.load(path, map_location='cpu')
        
        # Try to extract network config from checkpoint
        if isinstance(state, dict) and 'net_config' in state:
            saved_config = state['net_config']
            # Update config with saved parameters
            for key, value in saved_config.items():
                if hasattr(net_config, key):
                    setattr(net_config, key, value)
            logger.info(f"Auto-detected network config from checkpoint: {net_config.num_filters} filters, {net_config.num_residual_blocks} blocks")
    
    # Create network with detected/default config
    net = KatamillNet(net_config)
    
    if path and os.path.exists(path):
        # Load state dict with adaptive loading
        if isinstance(state, dict):
            if 'model_state_dict' in state:
                state_dict = state['model_state_dict']
            elif 'state_dict' in state:
                state_dict = state['state_dict']
            else:
                state_dict = state
        else:
            state_dict = state
        
        # Load with strict=True for exact matching (after auto-detection)
        try:
            net.load_state_dict(state_dict, strict=True)
            logger.info(f"Successfully loaded model with exact architecture match")
        except RuntimeError as e:
            # If strict loading fails, it means config detection failed
            logger.error(f"Architecture mismatch even after auto-detection: {str(e)[:200]}...")
            logger.error("This indicates the checkpoint may be corrupted or from incompatible version")
            raise ValueError(f"Cannot load model due to architecture mismatch: {model_path}")
            
        logger.info(f"Loaded KatamillNet weights from {path} with exact matching")
    else:
        logger.info("Using random initialization (no checkpoint provided)")
    
    return KatamillWrapper(net, device=device)


def pick_device(name: str) -> str:
    if name == 'auto':
        return 'cuda' if torch.cuda.is_available() else 'cpu'
    return name


def parse_human_move(board, move_str: str, current_player: int) -> Optional[int]:
    """Parse human move notation to action index.
    
    Supports:
    - Placing: 'a1', 'd7', etc.
    - Moving: 'a1-a4', 'd7-d6', etc.
    - Removing: 'xg7', 'xa1', etc.
    """
    try:
        from ml.game.engine_adapter import engine_token_to_move
        from ml.game.Game import Game
        
        game = Game()
        
        # Convert notation to move coordinates
        move = engine_token_to_move(move_str)
        
        # Convert move to action index
        action = board.get_action_from_move(move)
        
        # Validate action
        valids = game.getValidMoves(board, current_player)
        if valids[action] == 1:
            return action
        else:
            return None
    except Exception as e:
        logger.debug(f"Failed to parse move '{move_str}': {e}")
        return None


def show_legal_moves(board, current_player: int):
    """Display legal moves in human-readable format."""
    try:
        from ml.game.engine_adapter import move_to_engine_token
        from ml.game.Game import Game
        
        game = Game()
        valids = game.getValidMoves(board, current_player)
        legal_actions = np.where(valids == 1)[0]
        
        moves_by_type = {'place': [], 'move': [], 'remove': []}
        
        for action in legal_actions:
            move = board.get_move_from_action(action)
            if board.period == 3:  # Removal phase
                notation = 'x' + move_to_engine_token(move[:2])
                moves_by_type['remove'].append(notation)
            elif len(move) == 2 or (len(move) == 4 and move[0] == move[2] and move[1] == move[3]):
                # Placing
                notation = move_to_engine_token(move[:2])
                moves_by_type['place'].append(notation)
            else:
                # Moving
                notation = move_to_engine_token(move)
                moves_by_type['move'].append(notation)
        
        logger.info("Legal moves:")
        if moves_by_type['place']:
            logger.info(f"  Place: {', '.join(sorted(moves_by_type['place']))}")
        if moves_by_type['move']:
            logger.info(f"  Move: {', '.join(sorted(moves_by_type['move']))}")
        if moves_by_type['remove']:
            logger.info(f"  Remove: {', '.join(sorted(moves_by_type['remove']))}")
            
    except Exception as e:
        logger.debug(f"Failed to show legal moves: {e}")
        # Fallback to action indices
        logger.info(f"Legal action indices: {legal_actions.tolist()}")


def play_game(mcts_sims: int, model_path: str, first: str, gui: bool):
    device = pick_device('auto')
    game = Game()
    board = game.getInitBoard()
    cur_player = 1

    # Load model and create MCTS optimized for Nine Men's Morris consecutive moves
    wrapper = load_model(model_path, device)
    mcts = MCTS(game, wrapper, {
        'cpuct': 1.8,  # Balanced exploration for Nine Men's Morris 7x7 board
        'num_simulations': max(mcts_sims, 600),  # Ensure minimum strength
        'dirichlet_alpha': 0.15,  # Moderate noise for human games
        'dirichlet_epsilon': 0.08,  # Low noise for deterministic play
        'use_virtual_loss': True,
        'progressive_widening': True,
        'use_transpositions': True,  # Enable transposition table
        'max_transposition_size': 100000,
        'fpu_reduction': 0.25,  # LC0-style First Play Urgency
        'fpu_at_root': True,
        'consecutive_move_bonus': 0.02,  # Small bonus (removal moves often forced)
        'max_search_depth': 150,
        # Phase-specific parameters for Nine Men's Morris
        'removal_phase_exploration': 0.8,  # Less exploration in forced removal moves
        'placing_phase_exploration': 1.3,  # More exploration in strategic placing
        'flying_phase_simulations_multiplier': 2.0  # More search in complex flying
    })

    human_is_white = (first == 'human')
    
    # Game phase names
    phase_names = {0: "Placing", 1: "Moving", 2: "Flying", 3: "Removing"}

    def render():
        print("\n" + "="*50)
        Game.display(board)
        phase = phase_names.get(board.period, "Unknown")
        color = "White" if cur_player == 1 else "Black"
        print(f"\nPhase: {phase} | Turn: {color}")
        print(f"Pieces - White: {board.count(1)} on board, Black: {board.count(-1)} on board")
        print("="*50)

    moves = 0
    move_history = []
    
    while True:
        render()
        ended = game.getGameEnded(board, cur_player)
        if ended != 0:
            if abs(ended) < 0.01:
                logger.info("Game Over: Draw!")
            else:
                winner = "White" if (ended > 0 and cur_player == 1) or (ended < 0 and cur_player == -1) else "Black"
                logger.info(f"Game Over: {winner} wins!")
            break

        is_human_turn = (cur_player == 1 and human_is_white) or (cur_player == -1 and not human_is_white)
        
        if is_human_turn:
            # Human turn
            show_legal_moves(board, cur_player)
            
            action = None
            while action is None:
                try:
                    move_input = input("\nEnter your move (e.g., 'a1', 'a1-a4', 'xg7'): ").strip()
                    
                    # Allow 'help' command
                    if move_input.lower() == 'help':
                        print("\nMove notation:")
                        print("  - Place a piece: 'a1', 'd7', etc.")
                        print("  - Move a piece: 'a1-a4', 'd7-d6', etc.")
                        print("  - Remove opponent's piece: 'xg7', 'xa1', etc.")
                        print("  - Type 'quit' to exit")
                        continue
                    
                    if move_input.lower() == 'quit':
                        logger.info("Game aborted by user")
                        return
                    
                    action = parse_human_move(board, move_input, cur_player)
                    if action is None:
                        print("Invalid move! Please try again.")
                        
                except KeyboardInterrupt:
                    logger.info("\nGame interrupted")
                    return
                except Exception as e:
                    print(f"Error: {e}. Please try again.")
                    
            move_history.append(('Human', move_input))
            
        else:
            # AI turn
            print("\nAI is thinking...")
            probs = mcts.get_action_probabilities(board, cur_player, temperature=0.0)
            action = int(np.argmax(probs))
            
            # Convert AI move to notation for display
            try:
                from ml.game.engine_adapter import move_to_engine_token
                move = board.get_move_from_action(action)
                if board.period == 3:
                    move_notation = 'x' + move_to_engine_token(move[:2])
                else:
                    move_notation = move_to_engine_token(move)
                logger.info(f"AI plays: {move_notation}")
                move_history.append(('AI', move_notation))
            except:
                logger.info(f"AI plays action {action}")
                move_history.append(('AI', f'action_{action}'))

        board, cur_player = game.getNextState(board, cur_player, action)
        moves += 1
        
        # Show recent move history
        if len(move_history) > 0:
            recent = move_history[-min(5, len(move_history)):]
            print("\nRecent moves:", " -> ".join([f"{p}:{m}" for p, m in recent]))


def main():
    parser = argparse.ArgumentParser(description='Katamill Pitting Script')
    parser.add_argument('--model', type=str, required=False, help='Path to model .pth')
    parser.add_argument('--games', type=int, default=1, help='Number of games')
    parser.add_argument('--mcts-sims', type=int, default=400, help='MCTS sims per move')
    parser.add_argument('--first', choices=['human', 'ai'], default='human', help='Who goes first')
    parser.add_argument('--gui', action='store_true', help='Use GUI (not implemented, fallback to console)')
    args = parser.parse_args()

    for i in range(args.games):
        logger.info(f"Starting game {i+1}/{args.games}")
        play_game(args.mcts_sims, args.model, args.first, args.gui)


if __name__ == '__main__':
    main()


