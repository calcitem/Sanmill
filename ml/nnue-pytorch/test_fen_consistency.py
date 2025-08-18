#!/usr/bin/env python3

"""
Test script to verify FEN parsing consistency between Python and C++ implementations.

This script tests the Nine Men's Morris FEN parsing to ensure that:
1. Position indices are correctly mapped
2. FEN format parsing matches C++ Position class
3. Feature extraction works correctly
"""

import torch
from data_loader import parse_mill_fen, MillPosition
from features_mill import NineMillFeatures, cpp_square_to_feature_index, feature_index_to_cpp_square


def test_position_mapping():
    """Test the position index mapping between C++ and Python."""
    print("Testing position index mapping...")
    
    # Test C++ square to feature index conversion
    test_cases = [
        (8, 0),    # SQ_A1 -> feature 0
        (15, 7),   # SQ_C8 -> feature 7  
        (16, 8),   # SQ_B1 -> feature 8
        (23, 15),  # SQ_B8 -> feature 15
        (24, 16),  # SQ_C1 -> feature 16
        (31, 23),  # SQ_C8 -> feature 23
    ]
    
    for cpp_square, expected_feature in test_cases:
        feature_idx = cpp_square_to_feature_index(cpp_square)
        back_to_cpp = feature_index_to_cpp_square(feature_idx)
        
        print(f"C++ square {cpp_square} -> feature {feature_idx} -> back to {back_to_cpp}")
        assert feature_idx == expected_feature, f"Expected {expected_feature}, got {feature_idx}"
        assert back_to_cpp == cpp_square, f"Round trip failed: {cpp_square} -> {feature_idx} -> {back_to_cpp}"
    
    print("✅ Position mapping tests passed!")


def test_fen_parsing():
    """Test FEN parsing with various Nine Men's Morris positions."""
    print("\nTesting FEN parsing...")
    
    # Test cases with expected results
    # Let's create more accurate test cases
    test_fens = [
        # Simple placing phase position with 3 white pieces
        {
            'fen': 'O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1',
            'expected_white_count': 3,
            'expected_black_count': 0,
            'expected_side': 0,  # white
            'expected_phase': 1,  # placing
        },
        # Mixed position with 2 white and 2 black pieces
        {
            'fen': 'O@*****/O@*****/********/ b m s 2 7 2 7 0 0 0 0 0 0 0 0 2',
            'expected_white_count': 2,
            'expected_black_count': 2,
            'expected_side': 1,  # black
            'expected_phase': 2,  # moving
        }
    ]
    
    for i, test in enumerate(test_fens):
        print(f"Test case {i+1}: {test['fen'][:50]}...")
        
        pos = parse_mill_fen(test['fen'])
        
        # Check piece counts
        assert len(pos.white_pieces) == test['expected_white_count'], \
            f"White piece count: expected {test['expected_white_count']}, got {len(pos.white_pieces)}"
        assert len(pos.black_pieces) == test['expected_black_count'], \
            f"Black piece count: expected {test['expected_black_count']}, got {len(pos.black_pieces)}"
        
        # Check side to move
        assert pos.side_to_move == test['expected_side'], \
            f"Side to move: expected {test['expected_side']}, got {pos.side_to_move}"
        
        # Check phase
        assert pos.phase == test['expected_phase'], \
            f"Phase: expected {test['expected_phase']}, got {pos.phase}"
        
        # Verify position indices are in valid range
        for piece_pos in pos.white_pieces + pos.black_pieces:
            assert 0 <= piece_pos < 24, f"Invalid position index: {piece_pos}"
        
        print(f"  ✅ White pieces at positions: {pos.white_pieces}")
        print(f"  ✅ Black pieces at positions: {pos.black_pieces}")
    
    print("✅ FEN parsing tests passed!")


def test_feature_extraction():
    """Test feature extraction from parsed positions."""
    print("\nTesting feature extraction...")
    
    # Create feature set
    features = NineMillFeatures()
    
    # Test position
    board_state = {
        'white_pieces': [0, 8, 16],  # Three white pieces at different rings
        'black_pieces': [1, 9, 17],  # Three black pieces at different rings
        'side_to_move': 'white'
    }
    
    # Extract features
    white_features, black_features = features.get_active_features(board_state)
    
    # Check that features are extracted
    white_active = torch.sum(white_features).item()
    black_active = torch.sum(black_features).item()
    
    print(f"White active features: {white_active}")
    print(f"Black active features: {black_active}")
    
    # Should have 6 active features (3 white + 3 black from white perspective)
    # and 6 active features from black perspective
    assert white_active == 6, f"Expected 6 white active features, got {white_active}"
    assert black_active == 6, f"Expected 6 black active features, got {black_active}"
    
    print("✅ Feature extraction tests passed!")


def test_star_positions():
    """Test star position definitions."""
    print("\nTesting star position definitions...")
    
    # From C++ Position::is_star_square()
    # Without diagonals: s == 16 || s == 18 || s == 20 || s == 22
    # With diagonals: s == 17 || s == 19 || s == 21 || s == 23
    
    # Convert to feature indices
    star_no_diag_cpp = [16, 18, 20, 22]
    star_with_diag_cpp = [17, 19, 21, 23]
    
    star_no_diag_features = [cpp_square_to_feature_index(s) for s in star_no_diag_cpp]
    star_with_diag_features = [cpp_square_to_feature_index(s) for s in star_with_diag_cpp]
    
    print(f"Star positions (no diagonals): C++ {star_no_diag_cpp} -> features {star_no_diag_features}")
    print(f"Star positions (with diagonals): C++ {star_with_diag_cpp} -> features {star_with_diag_features}")
    
    # Verify they're in valid range
    for pos in star_no_diag_features + star_with_diag_features:
        assert 0 <= pos < 24, f"Star position {pos} out of range"
    
    print("✅ Star position tests passed!")


def main():
    """Run all consistency tests."""
    print("Nine Men's Morris FEN Consistency Tests")
    print("=" * 50)
    
    try:
        test_position_mapping()
        test_fen_parsing()
        test_feature_extraction()
        test_star_positions()
        
        print("\n" + "=" * 50)
        print("🎉 All tests passed! FEN parsing is consistent with C++ implementation.")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    return True


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
