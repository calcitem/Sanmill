#!/usr/bin/env python3
"""
Comparison between direct neural network evaluation and MCTS-guided search.
Demonstrates why MCTS is beneficial for SL.
"""

import torch
import numpy as np
import time
from sl_pit import SLGameAdapter, SLPlayer, SLModelLoader

def direct_evaluation_method(model, game_state):
    """Direct neural network evaluation - like NNUE approach"""
    print("🤖 Direct NN Evaluation Method:")
    print("- Single forward pass through neural network")
    print("- Fast but limited depth")

    start_time = time.time()

    # Get valid moves
    valid_moves = game_state.get_valid_moves()
    if not valid_moves:
        return None

    best_move = None
    best_score = float('-inf')
    evaluations = 0

    # Evaluate each move directly
    for move in valid_moves:
        # Make move
        success, undo_info = game_state.make_move_and_undo(move)
        if success:
            # Get neural network evaluation
            features = game_state.to_sl_features()
            features_tensor = torch.from_numpy(features).unsqueeze(0)

            with torch.no_grad():
                policy_logits, value = model(features_tensor)
                score = float(value.cpu().item())

            evaluations += 1

            # Undo move
            game_state.undo_move(undo_info)

            # Update best move
            if score > best_score:
                best_score = score
                best_move = move

    elapsed = time.time() - start_time

    print(f"- Evaluated {evaluations} positions")
    print(f"- Time: {elapsed:.3f}s")
    print(f"- Best score: {best_score:.3f}")
    print(f"- Selected move: {best_move}")

    return best_move, best_score, evaluations, elapsed

def mcts_evaluation_method(sl_player, game_state):
    """MCTS-guided search - SL approach"""
    print("\n🌳 MCTS Search Method:")
    print("- Multiple simulations with tree search")
    print("- Slower but deeper understanding")

    start_time = time.time()

    # Reset statistics
    sl_player.model_evaluations = 0
    sl_player.mcts_calls = 0

    # Get best move using MCTS (or fallback)
    best_move = sl_player.get_best_move(game_state)

    elapsed = time.time() - start_time
    evaluations = sl_player.model_evaluations

    print(f"- MCTS simulations: {sl_player.mcts_sims}")
    print(f"- Model evaluations: {evaluations}")
    print(f"- Time: {elapsed:.3f}s")
    print(f"- Selected move: {best_move}")

    # Get position evaluation for comparison
    value, _ = sl_player.evaluate_position(game_state)
    print(f"- Position value: {value:.3f}")

    return best_move, value, evaluations, elapsed

def analyze_position_complexity(game_state):
    """Analyze the complexity of current position"""
    valid_moves = game_state.get_valid_moves()

    print(f"\n📊 Position Analysis:")
    print(f"- Phase: {game_state.phase} ({'Placing' if game_state.phase == 0 else 'Moving/Flying' if game_state.phase < 3 else 'Capture'})")
    print(f"- Valid moves: {len(valid_moves)}")
    print(f"- White pieces: {game_state.white_pieces_on_board}+{game_state.white_pieces_in_hand}")
    print(f"- Black pieces: {game_state.black_pieces_on_board}+{game_state.black_pieces_in_hand}")
    print(f"- Move count: {game_state.move_count}")

    return len(valid_moves)

def main():
    print("🎯 SL: Direct NN vs MCTS Comparison")
    print("=" * 50)

    try:
        # Load model
        model_path = "models_from_npz_debug/final_preprocessed_model.tar"
        print(f"Loading model: {model_path}")

        model_loader = SLModelLoader(model_path, 'cpu')  # Use CPU for fair comparison
        model = model_loader.load_model()

        # Create SL player with reduced MCTS sims for demonstration
        sl_player = SLPlayer(model_loader, mcts_sims=100, temperature=0.0)

        # Create test positions
        test_positions = []

        # Position 1: Opening position
        game_state1 = SLGameAdapter()
        test_positions.append(("Opening Position", game_state1))

        # Position 2: Mid-game position (simulate some moves)
        game_state2 = SLGameAdapter()
        # Make a few moves to get to mid-game
        moves = [(3, 0, 3, 0), (0, 3, 0, 3), (3, 6, 3, 6), (6, 3, 6, 3)]  # Some placements
        for move in moves:
            game_state2.make_move(move)
        test_positions.append(("Mid-game Position", game_state2))

        # Compare methods on different positions
        for position_name, game_state in test_positions:
            print(f"\n{'='*60}")
            print(f"Testing: {position_name}")
            print(f"{'='*60}")

            # Analyze position complexity
            complexity = analyze_position_complexity(game_state)

            # Method 1: Direct evaluation
            try:
                direct_result = direct_evaluation_method(model, game_state)
                direct_move, direct_score, direct_evals, direct_time = direct_result
            except Exception as e:
                print(f"Direct method failed: {e}")
                continue

            # Method 2: MCTS search
            try:
                mcts_result = mcts_evaluation_method(sl_player, game_state)
                mcts_move, mcts_score, mcts_evals, mcts_time = mcts_result
            except Exception as e:
                print(f"MCTS method failed: {e}")
                continue

            # Compare results
            print(f"\n📈 Comparison:")
            print(f"- Direct NN:  {direct_evals:3d} evals, {direct_time:.3f}s, score {direct_score:+.3f}")
            print(f"- MCTS:       {mcts_evals:3d} evals, {mcts_time:.3f}s, score {mcts_score:+.3f}")
            print(f"- Same move:  {'✅' if direct_move == mcts_move else '❌'}")
            print(f"- MCTS ratio: {mcts_evals/direct_evals:.1f}x more evaluations")
            print(f"- Time ratio: {mcts_time/direct_time:.1f}x slower")

            if direct_move != mcts_move:
                print(f"- Direct chose: {direct_move}")
                print(f"- MCTS chose:   {mcts_move}")

        print(f"\n🎯 Key Insights:")
        print(f"1. Direct NN: Fast, simple, good for tactical positions")
        print(f"2. MCTS: Slower, but finds better moves in complex positions")
        print(f"3. MCTS uses ~10-50x more evaluations but gains strategic depth")
        print(f"4. For strong play, the extra computation is worth it!")

    except Exception as e:
        print(f"Error: {e}")
        print("Make sure the model file exists and is accessible.")

if __name__ == '__main__':
    main()


