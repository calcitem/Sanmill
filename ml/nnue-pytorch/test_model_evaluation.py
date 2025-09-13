#!/usr/bin/env python3
"""
Test evaluation functionality of trained NNUE model
"""

import os
import sys
import torch
import json

# Add paths
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from game.Game import Game

def test_model_evaluation():
    """Test model evaluation on different positions"""
    print("🎯 Testing NNUE model evaluation functionality...")
    
    # Load configuration and model
    config_path = "nnue_pit_config.json"
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    try:
        from nnue_pit import NNUEModelLoader, NNUEGameAdapter, NNUEPlayer
        
        # Load model
        model_loader = NNUEModelLoader(
            model_path=config["model_path"],
            feature_size=config["feature_size"],
            feature_set_name=config["feature_set"]
        )
        
        model = model_loader.load_model()
        print("✅ NNUE model loaded successfully")
        
        # Create NNUE player (for evaluation)
        nnue_player = NNUEPlayer(model_loader, search_depth=1)  # Depth 1 for fast evaluation
        
        # Create game adapter
        adapter = NNUEGameAdapter()
        
        # Test different positions
        test_positions = [
            {
                "name": "Opening position",
                "description": "Game start, empty board"
            },
            {
                "name": "Placement phase",
                "description": "After placing some pieces",
                "moves": [(3, 3), (1, 1), (3, 1), (5, 5)]
            },
            {
                "name": "Complex position",
                "description": "Complex position with multiple pieces",
                "moves": [(3, 3), (1, 1), (3, 1), (5, 5), (3, 5), (1, 3), (5, 3), (3, 0)]
            }
        ]
        
        for i, pos in enumerate(test_positions):
            print(f"\n🔍 Testing position {i+1}: {pos['name']}")
            print(f"   Description: {pos['description']}")
            
            # Reset game
            adapter = NNUEGameAdapter()
            
            # Execute moves
            if 'moves' in pos:
                valid_moves = adapter.get_valid_moves()
                for move in pos['moves']:
                    if move in valid_moves:
                        adapter.make_move(move)
                        print(f"   Executed move: {move}")
                    else:
                        print(f"   Invalid move: {move} (available moves: {len(valid_moves)})")
                        break
            
            # Evaluate current position
            try:
                evaluation = nnue_player.evaluate_position(adapter)
                print(f"   🧠 NNUE Evaluation: {evaluation:.6f}")
                
                # Display current position information
                print(f"   🎮 Current player: {'White' if adapter.side_to_move == 0 else 'Black'}")
                print(f"   📊 White pieces: {adapter.white_pieces_on_board}")
                print(f"   📊 Black pieces: {adapter.black_pieces_on_board}")
                print(f"   🎯 Game phase: {adapter.phase}")
                
            except Exception as e:
                print(f"   ❌ Evaluation failed: {e}")
        
        print(f"\n🎉 Model evaluation test completed!")
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_model_evaluation()
    if success:
        print("\n✅ NNUE model evaluation functionality is working!")
        print("You can now play games using the following methods:")
        print("  1. GUI interface: python nnue_pit.py --config nnue_pit_config.json --gui")
        print("  2. Command line: python nnue_pit.py --config nnue_pit_config.json --games 1")
    else:
        print("\n❌ Model evaluation test failed, please check configuration.")
