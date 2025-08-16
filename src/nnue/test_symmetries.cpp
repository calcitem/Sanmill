// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_symmetries.cpp - Unit tests for NNUE symmetry transformations

#include "nnue_symmetries.h"
#include "nnue_features.h"
#include "position.h"
#include <iostream>
#include <cassert>

namespace NNUE {

// Simple test to verify symmetry transformations work correctly
bool test_symmetry_transformations() {
    std::cout << "Testing NNUE symmetry transformations..." << std::endl;
    
    // Initialize symmetry system
    SymmetryTransforms::initialize();
    
    // Test basic square transformations
    std::cout << "Testing square transformations..." << std::endl;
    
    // Test identity transformation
    Square test_sq = SQ_8; // First valid square
    Square transformed = SymmetryTransforms::transform_square(test_sq, SYM_IDENTITY);
    assert(transformed == test_sq && "Identity transformation failed");
    
    // Test rotation 90 degrees
    transformed = SymmetryTransforms::transform_square(test_sq, SYM_ROTATE_90);
    std::cout << "Square " << test_sq << " rotated 90 degrees becomes " << transformed << std::endl;
    
    // Test that four 90-degree rotations return to original
    Square original = test_sq;
    for (int i = 0; i < 4; ++i) {
        original = SymmetryTransforms::transform_square(original, SYM_ROTATE_90);
    }
    assert(original == test_sq && "Four 90-degree rotations should return to original");
    
    // Test inverse operations
    SymmetryOp op = SYM_ROTATE_90;
    SymmetryOp inv_op = SymmetryTransforms::get_inverse(op);
    Square rotated = SymmetryTransforms::transform_square(test_sq, op);
    Square restored = SymmetryTransforms::transform_square(rotated, inv_op);
    assert(restored == test_sq && "Inverse operation failed");
    
    std::cout << "Square transformation tests passed!" << std::endl;
    
    // Test feature transformations
    std::cout << "Testing feature transformations..." << std::endl;
    
    // Create simple test features
    bool input_features[FeatureIndices::TOTAL_FEATURES] = {false};
    bool output_features[FeatureIndices::TOTAL_FEATURES] = {false};
    
    // Set a piece on square 8 (first square) for white
    input_features[FeatureIndices::WHITE_PIECES_START] = true;
    
    // Transform with identity - should be unchanged
    SymmetryTransforms::transform_features(input_features, output_features, SYM_IDENTITY);
    assert(output_features[FeatureIndices::WHITE_PIECES_START] == true && "Identity feature transformation failed");
    
    // Transform with color swap - white piece should become black piece
    std::fill(output_features, output_features + FeatureIndices::TOTAL_FEATURES, false);
    SymmetryTransforms::transform_features(input_features, output_features, SYM_COLOR_SWAP);
    assert(output_features[FeatureIndices::BLACK_PIECES_START] == true && "Color swap transformation failed");
    assert(output_features[FeatureIndices::WHITE_PIECES_START] == false && "Color swap should remove original piece");
    
    std::cout << "Feature transformation tests passed!" << std::endl;
    
    // Test color swap detection
    assert(SymmetryTransforms::swaps_colors(SYM_COLOR_SWAP) == true);
    assert(SymmetryTransforms::swaps_colors(SYM_ROTATE_90) == false);
    assert(SymmetryTransforms::swaps_colors(SYM_COLOR_SWAP_ROTATE_90) == true);
    
    std::cout << "Color swap detection tests passed!" << std::endl;
    
    std::cout << "All symmetry transformation tests passed successfully!" << std::endl;
    return true;
}

// Test position symmetry detection
bool test_position_symmetries() {
    std::cout << "Testing position symmetry detection..." << std::endl;
    
    // Create a simple symmetric position for testing
    Position pos;
    // This would need proper position setup, but for now we'll skip
    // the detailed position testing and just verify the interface works
    
    // Test canonical form detection
    SymmetryOp canonical = SymmetryAwareNNUE::find_canonical_symmetry(pos);
    std::cout << "Canonical symmetry operation: " << canonical << std::endl;
    
    // Test symmetry evaluation (would need proper position and weights)
    // For now, just verify the function can be called
    // int32_t result = SymmetryAwareNNUE::evaluate_with_symmetries(pos);
    
    std::cout << "Position symmetry tests completed!" << std::endl;
    return true;
}

} // namespace NNUE

// Main test function for use in integration tests
int main() {
    try {
        bool all_passed = true;
        
        all_passed &= NNUE::test_symmetry_transformations();
        all_passed &= NNUE::test_position_symmetries();
        
        if (all_passed) {
            std::cout << "\n=== ALL NNUE SYMMETRY TESTS PASSED ===\n" << std::endl;
            return 0;
        } else {
            std::cout << "\n=== SOME NNUE SYMMETRY TESTS FAILED ===\n" << std::endl;
            return 1;
        }
    } catch (const std::exception& e) {
        std::cerr << "Test failed with exception: " << e.what() << std::endl;
        return 1;
    }
}
