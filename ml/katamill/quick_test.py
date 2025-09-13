#!/usr/bin/env python3
"""
Quick test to verify the game ending and outcome distribution fixes.
"""

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
from selfplay import play_single_game, SelfPlayConfig
from config import NetConfig


def quick_selfplay_test():
    """Test a few self-play games with the fixed configuration."""
    print("=" * 60)
    print("QUICK SELFPLAY TEST WITH FIXED CONFIGURATION")
    print("=" * 60)
    
    # Create small random model for testing
    net_config = NetConfig.tiny()
    net = KatamillNet(net_config)
    wrapper = KatamillWrapper(net, device='cpu')
    
    # Use similar config to quick_config.json but smaller for speed
    cfg = SelfPlayConfig(
        num_games=5,
        max_moves=120,  # Shorter than 150 for speed
        mcts_sims=30,   # Fewer sims for speed
        temperature=1.2,
        temp_decay_moves=15,
        cpuct=1.0,
        num_workers=1
    )
    
    game = Game()
    outcomes = {'white_wins': 0, 'black_wins': 0, 'draws': 0}
    
    print(f"Testing {cfg.num_games} games with max_moves={cfg.max_moves}, mcts_sims={cfg.mcts_sims}")
    
    for i in range(cfg.num_games):
        print(f"\n--- Self-Play Game {i + 1} ---")
        
        try:
            samples = play_single_game(game, wrapper, cfg)
            
            if samples:
                # Get outcome from last sample
                last_sample = samples[-1]
                meta = last_sample.get('metadata', {})
                final_result = meta.get('final_result', 0.0)
                game_length = meta.get('game_length', len(samples))
                
                print(f"Game completed: {game_length} moves, result={final_result:.4f}")
                
                # Determine outcome
                if abs(final_result) < 0.01:
                    outcomes['draws'] += 1
                    print("Outcome: Draw")
                else:
                    # Use the corrected logic from selfplay.py
                    z_last = float(last_sample['z'][0])
                    step_player = int(meta.get('step_player', 1))
                    
                    if z_last > 0:
                        winner_color = step_player
                    else:
                        winner_color = -step_player
                    
                    if winner_color == 1:
                        outcomes['white_wins'] += 1
                        print("Outcome: White wins")
                    else:
                        outcomes['black_wins'] += 1
                        print("Outcome: Black wins")
            else:
                print("Game failed to generate samples")
                
        except Exception as e:
            print(f"Game {i + 1} failed: {e}")
    
    # Print results
    print("\n" + "=" * 60)
    print("QUICK SELFPLAY TEST RESULTS:")
    total_games = sum(outcomes.values())
    for outcome, count in outcomes.items():
        percentage = (count / total_games) * 100 if total_games > 0 else 0
        print(f"  {outcome}: {count}/{total_games} ({percentage:.1f}%)")
    
    # Analysis
    print("\nANALYSIS:")
    if total_games == 0:
        print("  ❌ No games completed - system error")
    elif outcomes['white_wins'] == total_games or outcomes['black_wins'] == total_games:
        print("  ⚠ EXTREME BIAS: 100% favor one side")
        print("  This confirms the bias issue in self-play")
    elif abs(outcomes['white_wins'] - outcomes['black_wins']) <= 1:
        print("  ✅ BIAS FIXED: Balanced outcome distribution")
    else:
        bias_side = "White" if outcomes['white_wins'] > outcomes['black_wins'] else "Black"
        print(f"  ⚠ MODERATE BIAS: Favors {bias_side}")
    
    return outcomes


if __name__ == '__main__':
    quick_selfplay_test()
