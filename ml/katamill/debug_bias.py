#!/usr/bin/env python3
"""
Debug script to analyze the extreme outcome bias in Katamill self-play.

This script runs a few test games with detailed logging to understand
why all games are ending with 100% bias to one side.
"""

import logging
import os
import sys
import numpy as np
import torch

# Add parent directories to path
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Setup detailed logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Import modules
try:
    from ml.game.Game import Game
except Exception:
    try:
        from game.Game import Game
    except Exception:
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game

from neural_network import KatamillNet, KatamillWrapper
from mcts import MCTS
from config import NetConfig


def test_random_games():
    """Test a few random games to see outcome distribution."""
    print("=" * 60)
    print("DEBUGGING NINE MEN'S MORRIS OUTCOME BIAS")
    print("=" * 60)
    
    # Create random model
    net_config = NetConfig.tiny()  # Use tiny model for fast testing
    net = KatamillNet(net_config)
    wrapper = KatamillWrapper(net, device='cpu')  # Use CPU for debugging
    
    game = Game()
    outcomes = {'white_wins': 0, 'black_wins': 0, 'draws': 0, 'timeouts': 0}
    
    # Test with different starting players
    for test_game in range(10):
        print(f"\n--- Test Game {test_game + 1} ---")
        
        board = game.getInitBoard()
        # Alternate starting player to test bias
        cur_player = 1 if test_game % 2 == 0 else -1
        print(f"Starting player: {'White' if cur_player == 1 else 'Black'}")
        
        # Simple MCTS config for debugging with strict limits
        mcts_config = {
            'cpuct': 1.0,
            'num_simulations': 20,  # Very few sims for speed
            'dirichlet_alpha': 0.3,
            'dirichlet_epsilon': 0.25,
            'use_virtual_loss': False,  # Disable for simpler debugging
            'progressive_widening': False,
            'use_transpositions': False,
            'max_search_depth': 50,  # Limit search depth to prevent infinite loops
        }
        
        mcts = MCTS(game, wrapper, mcts_config)
        moves = 0
        max_moves = 50  # Much shorter for debugging
        
        while moves < max_moves:
            print(f"Move {moves + 1}: Player {'White' if cur_player == 1 else 'Black'}")
            
            # Skip MCTS for now and use pure random moves to test game logic
            print(f"Using random move (bypassing MCTS for speed)")
            valid_actions = game.getValidMoves(board, cur_player)
            valid_indices = np.where(valid_actions == 1)[0]
            
            if len(valid_indices) == 0:
                print("No valid moves available!")
                result = game.getGameEnded(board, cur_player)
                print(f"Game should end: result={result:.4f}")
                break
            
            # Use random action (already selected above)
            # action is already set from np.random.choice(valid_indices)
            
            # Execute move
            try:
                board, cur_player = game.getNextState(board, cur_player, action)
                moves += 1
                
                # Check game end
                result = game.getGameEnded(board, cur_player)
                if result != 0:
                    print(f"Game ended after {moves} moves")
                    print(f"Result: {result:.4f}, Current player: {'White' if cur_player == 1 else 'Black'}")
                    
                    # Determine winner
                    if abs(result) < 0.01:
                        outcomes['draws'] += 1
                        print("Outcome: Draw")
                    elif result > 0:
                        winner = 'White' if cur_player == 1 else 'Black'
                        if cur_player == 1:
                            outcomes['white_wins'] += 1
                        else:
                            outcomes['black_wins'] += 1
                        print(f"Outcome: {winner} wins")
                    else:
                        winner = 'Black' if cur_player == 1 else 'White'
                        if cur_player == 1:
                            outcomes['black_wins'] += 1
                        else:
                            outcomes['white_wins'] += 1
                        print(f"Outcome: {winner} wins")
                    break
                    
            except Exception as e:
                print(f"Error at move {moves}: {e}")
                break
        
        if moves >= max_moves:
            outcomes['timeouts'] += 1
            print(f"Game timed out after {max_moves} moves")
    
    # Print summary
    print("\n" + "=" * 60)
    print("OUTCOME SUMMARY:")
    total_games = sum(outcomes.values())
    for outcome, count in outcomes.items():
        percentage = (count / total_games) * 100 if total_games > 0 else 0
        print(f"  {outcome}: {count}/{total_games} ({percentage:.1f}%)")
    
    # Analysis
    print("\nANALYSIS:")
    if outcomes['white_wins'] == 0 and outcomes['black_wins'] > 0:
        print("  ⚠ SEVERE BIAS: All decisive games favor Black")
        print("  Possible causes:")
        print("    - Game logic error favoring second player")
        print("    - MCTS implementation bias")
        print("    - Model initialization bias")
    elif outcomes['black_wins'] == 0 and outcomes['white_wins'] > 0:
        print("  ⚠ SEVERE BIAS: All decisive games favor White")
        print("  Possible causes:")
        print("    - Game logic error favoring first player")
        print("    - MCTS implementation bias")
        print("    - Model initialization bias")
    elif abs(outcomes['white_wins'] - outcomes['black_wins']) <= 2:
        print("  ✓ Outcome distribution appears balanced")
    else:
        print("  ⚠ Moderate bias detected")
    
    return outcomes


if __name__ == '__main__':
    test_random_games()
