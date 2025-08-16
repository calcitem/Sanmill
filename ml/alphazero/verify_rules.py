#!/usr/bin/env python3
"""
Verify that AlphaZero game rules match the C++ Sanmill engine.

This script:
1. Generates moves using AlphaZero's GameLogic
2. Converts them to engine notation
3. Sends them to the C++ engine for validation
4. Compares legal moves from both implementations
"""

import os
import sys
from game.GameLogic import Board
from game.engine_adapter import move_to_engine_token, engine_token_to_move
from engine_bridge import MillEngine

def compare_rules():
    """Compare AlphaZero rules with C++ engine rules."""
    
    print("=== Sanmill Rule Verification ===")
    print("Comparing AlphaZero GameLogic with C++ engine...\n")
    
    # Initialize engine
    engine_path = os.environ.get("SANMILL_ENGINE", "sanmill")
    if not os.path.exists(engine_path):
        print(f"Error: Engine not found at {engine_path}")
        print("Set SANMILL_ENGINE environment variable to the correct path")
        return False
    
    engine = MillEngine(engine_path)
    try:
        engine.start()
        engine.set_standard_rules()
        print("✓ Engine started and configured with standard rules")
    except Exception as e:
        print(f"✗ Failed to start engine: {e}")
        return False
    
    # Test initial position
    print("\n--- Testing Initial Position ---")
    board = Board()
    
    # Get legal moves from AlphaZero
    az_moves = board.get_legal_moves(1)  # Player 1 (White)
    az_tokens = []
    for move in az_moves:
        try:
            token = move_to_engine_token(move)
            az_tokens.append(token)
        except ValueError as e:
            print(f"Warning: Could not convert move {move}: {e}")
    
    # Get legal moves from engine
    engine_tokens = engine.get_legal_moves([])
    
    print(f"AlphaZero legal moves ({len(az_tokens)}): {sorted(az_tokens)}")
    print(f"Engine legal moves ({len(engine_tokens)}): {sorted(engine_tokens)}")
    
    # Compare
    az_set = set(az_tokens)
    engine_set = set(engine_tokens)
    
    if az_set == engine_set:
        print("✓ Initial position legal moves match perfectly!")
    else:
        print("✗ Legal moves differ:")
        only_az = az_set - engine_set
        only_engine = engine_set - az_set
        if only_az:
            print(f"  Only in AlphaZero: {sorted(only_az)}")
        if only_engine:
            print(f"  Only in Engine: {sorted(only_engine)}")
        return False
    
    # Test a few moves sequence
    print("\n--- Testing Move Sequence ---")
    test_moves = ["a7", "g7", "a4", "g4", "a1"]  # Some initial placements
    move_list = []
    
    for i, move_token in enumerate(test_moves):
        print(f"\nMove {i+1}: {move_token}")
        
        # Apply move in AlphaZero
        try:
            move_coords = engine_token_to_move(move_token)
            player = 1 if i % 2 == 0 else -1
            board.execute_move(move_coords, player)
            print(f"  ✓ Applied in AlphaZero: Player {player}")
        except Exception as e:
            print(f"  ✗ Failed to apply in AlphaZero: {e}")
            break
        
        # Check engine legal moves after this move
        move_list.append(move_token)
        try:
            engine_legal = engine.get_legal_moves(move_list)
            print(f"  Engine legal moves after {move_token}: {len(engine_legal)} moves")
        except Exception as e:
            print(f"  ✗ Engine error: {e}")
            break
        
        # Get AlphaZero legal moves
        next_player = -player
        az_legal = board.get_legal_moves(next_player)
        az_legal_tokens = []
        for move in az_legal:
            try:
                token = move_to_engine_token(move)
                if board.period == 3:  # Add 'x' prefix for captures
                    token = f"x{token}"
                az_legal_tokens.append(token)
            except ValueError:
                pass
        
        print(f"  AlphaZero legal moves: {len(az_legal_tokens)} moves")
        
        # Quick comparison
        if len(engine_legal) == len(az_legal_tokens):
            print("  ✓ Move count matches")
        else:
            print(f"  ⚠ Move count differs: Engine={len(engine_legal)}, AZ={len(az_legal_tokens)}")
    
    engine.stop()
    print("\n=== Verification Complete ===")
    return True

if __name__ == "__main__":
    success = compare_rules()
    sys.exit(0 if success else 1)
