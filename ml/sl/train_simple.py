#!/usr/bin/env python3
"""
Simplified Alpha Zero training script

Designed for testing and debugging basic functionalities, avoiding complex multiprocessing and Perfect Database issues.
"""

import sys
import os

def setup_environment():
    """Set up environment and paths."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    game_dir = os.path.join(parent_dir, 'game')

    # Add necessary paths
    for path in [current_dir, parent_dir, game_dir]:
        if path not in sys.path:
            sys.path.insert(0, path)

def test_game_basic():
    """Test basic game functionality."""
    print("🧪 Testing basic game functionality...")

    try:
        from game.Game import Game
        game = Game()

        # Test initialization
        board = game.getInitBoard()
        print(f"✅ Initial board created successfully")

        # Test action space
        action_size = game.getActionSize()
        print(f"✅ Action space size: {action_size}")

        # Test valid moves
        valid_moves = game.getValidMoves(board, 1)
        valid_count = sum(valid_moves)
        print(f"✅ Initial valid moves count: {valid_count}")

        # Test the first valid move
        first_valid = None
        for i, valid in enumerate(valid_moves):
            if valid == 1:
                first_valid = i
                break

        if first_valid is not None:
            next_board, next_player = game.getNextState(board, 1, first_valid)
            print(f"✅ Executed move {first_valid} successfully, next player: {next_player}")

        return True

    except Exception as e:
        print(f"❌ Basic game functionality test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_neural_network():
    """Test neural network initialization."""
    print("\n🧠 Testing neural network...")

    try:
        from game.Game import Game
        from neural_network import SLNetworkWrapper

        game = Game()

        # Create the network
        model_args = {
            'input_channels': 17,
            'num_filters': 64,          # Reduce parameters
            'num_residual_blocks': 3,   # Reduce layers
            'action_size': game.getActionSize(),
            'dropout_rate': 0.3
        }

        network = SLNetworkWrapper(model_args, device='cpu') # Force CPU
        print("✅ Neural network initialized successfully")

        # Test prediction
        board = game.getInitBoard()
        # Use the board object directly, no tensor conversion needed

        pi, v = network.predict(board)
        print(f"✅ Neural network prediction successful, policy dimension: {len(pi)}, value: {v:.3f}")

        return True, network

    except Exception as e:
        print(f"❌ Neural network test failed: {e}")
        import traceback
        traceback.print_exc()
        return False, None

def test_single_game():
    """Test a single game."""
    print("\n🎲 Testing a single game...")

    try:
        from game.Game import Game

        game = Game()
        board = game.getInitBoard()
        current_player = 1
        turn_count = 0
        max_turns = 100 # Prevent infinite loops

        print(f"Starting game, initial player: {current_player}")

        while turn_count < max_turns:
            # Check if the game has ended
            game_ended = game.getGameEnded(board, current_player)
            if game_ended != 0:
                print(f"✅ Game ended, winner: {game_ended}, total turns: {turn_count}")
                return True

            # Get valid moves
            valid_moves = game.getValidMoves(board, current_player)
            valid_actions = [i for i, v in enumerate(valid_moves) if v == 1]

            if not valid_actions:
                print(f"❌ Player {current_player} has no valid moves")
                return False

            # Randomly select a valid move
            import random
            action = random.choice(valid_actions)

            # Execute the move
            board, next_player = game.getNextState(board, current_player, action)

            if turn_count % 10 == 0:
                print(f"Turn {turn_count}: Player {current_player} executes move {action}")

            current_player = next_player
            turn_count += 1

        print(f"⚠️  Game exceeded maximum turns {max_turns}")
        return True # Although not finished, functionality is normal

    except Exception as e:
        print(f"❌ Single game test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_mcts():
    """Test MCTS."""
    print("\n🌳 Testing MCTS...")

    try:
        from game.Game import Game
        from neural_network import SLNetworkWrapper
        from mcts import MCTS

        game = Game()

        # Create a simple network
        model_args = {
            'input_channels': 17,
            'num_filters': 32,      # Very small network
            'num_residual_blocks': 2,
            'action_size': game.getActionSize(),
            'dropout_rate': 0.3
        }

        network = SLNetworkWrapper(model_args, device='cpu')

        # Create MCTS
        mcts_args = {
            'c_puct': 1.0,
            'num_sims': 10,
            'temp_threshold': 15
        }
        mcts = MCTS(game, network, mcts_args)
        print("✅ MCTS initialized successfully")

        # Test search
        board = game.getInitBoard()
        pi = mcts.get_action_probabilities(board, current_player=1, temperature=1.0)
        print(f"✅ MCTS search successful, policy vector length: {len(pi)}")

        # Select action
        action = max(range(len(pi)), key=lambda x: pi[x])
        print(f"✅ MCTS recommended action: {action}")

        return True

    except Exception as e:
        print(f"❌ MCTS test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Main test function."""
    print("🧪 Alpha Zero Simplified Test")
    print("=" * 50)

    # Set up environment
    setup_environment()

    # Run tests
    tests = [
        ("Game Basic Functionality", test_game_basic),
        ("Neural Network", test_neural_network),
        ("Single Game", test_single_game),
        ("MCTS", test_mcts)
    ]

    results = {}
    for test_name, test_func in tests:
        print(f"\n{'=' * 20} {test_name} {'=' * 20}")
        try:
            if test_name == "Neural Network":
                success, _ = test_func()
                results[test_name] = success
            else:
                results[test_name] = test_func()
        except Exception as e:
            print(f"❌ Test '{test_name}' raised an exception: {e}")
            results[test_name] = False

    # Summary
    print(f"\n{'=' * 50}")
    print("📊 Test Results Summary:")
    print("=" * 50)

    all_passed = True
    for test_name, result in results.items():
        status = "✅ Passed" if result else "❌ Failed"
        print(f"  {test_name}: {status}")
        if not result:
            all_passed = False

    print()
    if all_passed:
        print("🎉 All tests passed! Basic functionality is working.")
        print("💡 You can now try to use train.py for actual training")
        print("💡 Or modify the configuration to reduce multiprocessing and complex features")
    else:
        print("⚠️  Some tests failed, basic issues need to be fixed")
        print("💡 It is recommended to solve the basic test issues before training")

    return 0 if all_passed else 1

if __name__ == "__main__":
    exit_code = main()

    print("\n" + "=" * 50)
    print("Press any key to exit...")
    input()

    sys.exit(exit_code)
