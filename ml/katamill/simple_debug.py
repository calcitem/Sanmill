#!/usr/bin/env python3
"""
Simple debug script for Windows - bypasses MCTS to test pure game logic.
"""

import os
import sys
import numpy as np

# Add parent directories to path
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import game module
try:
    from ml.game.Game import Game
except Exception:
    try:
        from game.Game import Game
    except Exception:
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game


def test_pure_random_games():
    """Test pure random games without MCTS to isolate game logic issues."""
    print("=" * 60)
    print("TESTING PURE RANDOM NINE MEN'S MORRIS GAMES")
    print("=" * 60)
    
    game = Game()
    outcomes = {'white_wins': 0, 'black_wins': 0, 'draws': 0, 'timeouts': 0}
    
    for test_game in range(20):
        print(f"\n--- Test Game {test_game + 1} ---")
        
        board = game.getInitBoard()
        # Randomize starting player
        cur_player = np.random.choice([1, -1])
        initial_player = cur_player
        print(f"Starting player: {'White' if cur_player == 1 else 'Black'}")
        
        moves = 0
        max_moves = 80  # Reasonable limit
        
        while moves < max_moves:
            # Pure random move selection
            valid_actions = game.getValidMoves(board, cur_player)
            valid_indices = np.where(valid_actions == 1)[0]
            
            if len(valid_indices) == 0:
                print(f"No valid moves at move {moves + 1}!")
                # This should trigger game end detection
                result = game.getGameEnded(board, cur_player)
                print(f"Game ended with no moves: result={result:.4f}")
                if result != 0:
                    break
                else:
                    print("ERROR: No valid moves but game not ended!")
                    outcomes['timeouts'] += 1
                    break
            
            # Select random valid action
            action = int(np.random.choice(valid_indices))
            
            try:
                prev_player = cur_player
                board, cur_player = game.getNextState(board, cur_player, action)
                moves += 1
                
                # Log player changes for debugging
                if moves <= 5 or moves % 10 == 0:
                    if prev_player != cur_player:
                        print(f"  Move {moves}: {prev_player} → {cur_player} (normal)")
                    else:
                        print(f"  Move {moves}: {prev_player} → {cur_player} (consecutive)")
                
                # Check game end
                result = game.getGameEnded(board, cur_player)
                if result != 0:
                    print(f"Game ended after {moves} moves")
                    print(f"Final result: {result:.4f}")
                    print(f"Current player at end: {'White' if cur_player == 1 else 'Black'}")
                    print(f"Initial player was: {'White' if initial_player == 1 else 'Black'}")
                    
                    # Determine winner based on game result
                    if abs(result) < 0.01:
                        outcomes['draws'] += 1
                        print("Final outcome: Draw")
                    elif result > 0:
                        # Current player wins
                        winner_color = cur_player
                        if winner_color == 1:
                            outcomes['white_wins'] += 1
                            print("Final outcome: White wins")
                        else:
                            outcomes['black_wins'] += 1
                            print("Final outcome: Black wins")
                    else:
                        # Current player loses
                        winner_color = -cur_player
                        if winner_color == 1:
                            outcomes['white_wins'] += 1
                            print("Final outcome: White wins")
                        else:
                            outcomes['black_wins'] += 1
                            print("Final outcome: Black wins")
                    break
                    
            except Exception as e:
                print(f"Error executing move {moves + 1}: {e}")
                outcomes['timeouts'] += 1
                break
        
        if moves >= max_moves:
            outcomes['timeouts'] += 1
            print(f"Game timed out after {max_moves} moves")
    
    # Print summary
    print("\n" + "=" * 60)
    print("PURE RANDOM GAME OUTCOME SUMMARY:")
    total_games = sum(outcomes.values())
    for outcome, count in outcomes.items():
        percentage = (count / total_games) * 100 if total_games > 0 else 0
        print(f"  {outcome}: {count}/{total_games} ({percentage:.1f}%)")
    
    # Analysis
    print("\nANALYSIS:")
    decisive_games = outcomes['white_wins'] + outcomes['black_wins']
    if decisive_games > 0:
        white_ratio = outcomes['white_wins'] / decisive_games
        black_ratio = outcomes['black_wins'] / decisive_games
        
        if white_ratio == 0:
            print("  ⚠ CRITICAL: All decisive games favor Black - likely game logic bug")
        elif black_ratio == 0:
            print("  ⚠ CRITICAL: All decisive games favor White - likely game logic bug")
        elif abs(white_ratio - 0.5) > 0.3:
            bias_direction = "White" if white_ratio > 0.5 else "Black"
            print(f"  ⚠ MODERATE BIAS: {bias_direction} wins {white_ratio*100:.1f}% of decisive games")
        else:
            print("  ✓ Outcome distribution appears balanced for random play")
    else:
        print("  ⚠ No decisive games - all draws or timeouts")
    
    return outcomes


if __name__ == '__main__':
    test_pure_random_games()
