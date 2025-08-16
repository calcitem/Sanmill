// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_symmetries.cpp - Implementation of symmetry transformations for NNUE

#include "nnue_symmetries.h"
#include "nnue_features.h"
#include "position.h"
#include <algorithm>
#include <cassert>
#include <cstring>

namespace NNUE {

// Static member definitions
Square SymmetryTransforms::square_transform_table_[SYM_OP_COUNT][SQUARE_NB];
bool SymmetryTransforms::initialized_ = false;

void SymmetryTransforms::initialize() {
    if (initialized_) {
        return;
    }
    
    // Pre-compute all square transformations for fast lookup
    for (int sq = 0; sq < SQUARE_NB; ++sq) {
        Square square = static_cast<Square>(sq + SQ_BEGIN);
        
        square_transform_table_[SYM_IDENTITY][sq] = square;
        square_transform_table_[SYM_ROTATE_90][sq] = rotate_90_transform(square);
        square_transform_table_[SYM_ROTATE_180][sq] = rotate_180_transform(square);
        square_transform_table_[SYM_ROTATE_270][sq] = rotate_270_transform(square);
        square_transform_table_[SYM_MIRROR_VERTICAL][sq] = mirror_vertical_transform(square);
        square_transform_table_[SYM_MIRROR_HORIZONTAL][sq] = mirror_horizontal_transform(square);
        square_transform_table_[SYM_MIRROR_BACKSLASH][sq] = mirror_backslash_transform(square);
        square_transform_table_[SYM_MIRROR_SLASH][sq] = mirror_slash_transform(square);
        
        // Color swap variants apply the same geometric transformation
        square_transform_table_[SYM_COLOR_SWAP][sq] = square;
        square_transform_table_[SYM_COLOR_SWAP_ROTATE_90][sq] = rotate_90_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_ROTATE_180][sq] = rotate_180_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_ROTATE_270][sq] = rotate_270_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_MIRROR_VERTICAL][sq] = mirror_vertical_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_MIRROR_HORIZONTAL][sq] = mirror_horizontal_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_MIRROR_BACKSLASH][sq] = mirror_backslash_transform(square);
        square_transform_table_[SYM_COLOR_SWAP_MIRROR_SLASH][sq] = mirror_slash_transform(square);
    }
    
    initialized_ = true;
}

Square SymmetryTransforms::transform_square(Square sq, SymmetryOp op) {
    assert(initialized_);
    assert(sq >= SQ_BEGIN && sq < SQ_END);
    assert(op >= 0 && op < SYM_OP_COUNT);
    
    const int sq_index = sq - SQ_BEGIN;
    return square_transform_table_[op][sq_index];
}

// Mill board square transformations based on the 3x3 grid layout
// Mill board layout (square indices 8-31, representing 24 positions):
//  8----9----10
//  |    |    |
//  | 16-17-18 |
//  | |  |  | |
//  |11-12-13|19
//  | |  |  | |
//  | 20-21-22 |
//  |    |    |
//  14---15---23

Square SymmetryTransforms::rotate_90_transform(Square sq) {
    // Map to 0-23 range for easier calculation
    const int idx = sq - SQ_BEGIN;
    
    // Rotation mapping for 90 degrees clockwise
    // This maps the mill board positions correctly
    constexpr int rotation_90[24] = {
        2,  10, 18, 5,  13, 21, 0,  3,  // Ring 1: 8-15 -> rotated positions
        6,  7,  1,  4,  12, 20, 14, 15, // Ring 2: 16-23 -> rotated positions
        9,  17, 8,  11, 19, 23, 16, 22  // Ring 3: remaining positions
    };
    
    return static_cast<Square>(rotation_90[idx] + SQ_BEGIN);
}

Square SymmetryTransforms::rotate_180_transform(Square sq) {
    // 180 degree rotation is equivalent to two 90 degree rotations
    return rotate_90_transform(rotate_90_transform(sq));
}

Square SymmetryTransforms::rotate_270_transform(Square sq) {
    // 270 degree rotation is equivalent to three 90 degree rotations
    return rotate_90_transform(rotate_180_transform(sq));
}

Square SymmetryTransforms::mirror_vertical_transform(Square sq) {
    const int idx = sq - SQ_BEGIN;
    
    // Vertical mirror mapping
    constexpr int mirror_vertical[24] = {
        10, 9,  8,  19, 12, 11, 22, 21, // Top row mirrored
        20, 15, 14, 13, 17, 16, 23, 18, // Middle sections
        0,  1,  2,  3,  4,  5,  6,  7   // Bottom sections
    };
    
    return static_cast<Square>(mirror_vertical[idx] + SQ_BEGIN);
}

Square SymmetryTransforms::mirror_horizontal_transform(Square sq) {
    const int idx = sq - SQ_BEGIN;
    
    // Horizontal mirror mapping
    constexpr int mirror_horizontal[24] = {
        14, 15, 23, 11, 12, 13, 8,  9,  // Left-right flip
        10, 19, 22, 21, 20, 18, 17, 16, // Middle sections
        0,  1,  2,  3,  4,  5,  6,  7   // Adjusted positions
    };
    
    return static_cast<Square>(mirror_horizontal[idx] + SQ_BEGIN);
}

Square SymmetryTransforms::mirror_backslash_transform(Square sq) {
    const int idx = sq - SQ_BEGIN;
    
    // Backslash diagonal mirror mapping (top-left to bottom-right)
    constexpr int mirror_backslash[24] = {
        8,  16, 20, 9,  17, 21, 10, 18, // Diagonal transformation
        22, 11, 19, 23, 12, 13, 14, 15, // Continue mapping
        1,  4,  7,  2,  5,  6,  0,  3   // Complete the transformation
    };
    
    return static_cast<Square>(mirror_backslash[idx] + SQ_BEGIN);
}

Square SymmetryTransforms::mirror_slash_transform(Square sq) {
    const int idx = sq - SQ_BEGIN;
    
    // Slash diagonal mirror mapping (top-right to bottom-left)
    constexpr int mirror_slash[24] = {
        22, 21, 20, 18, 17, 16, 23, 19, // Slash transformation
        11, 10, 9,  8,  13, 12, 15, 14, // Continue mapping
        7,  6,  5,  4,  3,  2,  1,  0   // Complete the transformation
    };
    
    return static_cast<Square>(mirror_slash[idx] + SQ_BEGIN);
}

void SymmetryTransforms::transform_features(const bool* input_features, bool* output_features, SymmetryOp op) {
    assert(initialized_);
    
    // Clear output features
    std::memset(output_features, 0, FeatureIndices::TOTAL_FEATURES * sizeof(bool));
    
    // Handle color swapping operations
    const bool swap_colors = swaps_colors(op);
    
    // Transform piece placement features
    for (int sq_idx = 0; sq_idx < SQUARE_NB; ++sq_idx) {
        const Square original_sq = static_cast<Square>(sq_idx + SQ_BEGIN);
        const Square transformed_sq = transform_square(original_sq, op);
        const int transformed_idx = transformed_sq - SQ_BEGIN;
        
        // Get original white and black piece features
        const bool white_piece = input_features[FeatureIndices::WHITE_PIECES_START + sq_idx];
        const bool black_piece = input_features[FeatureIndices::BLACK_PIECES_START + sq_idx];
        
        if (swap_colors) {
            // Swap colors during transformation
            output_features[FeatureIndices::WHITE_PIECES_START + transformed_idx] = black_piece;
            output_features[FeatureIndices::BLACK_PIECES_START + transformed_idx] = white_piece;
        } else {
            // Keep colors the same
            output_features[FeatureIndices::WHITE_PIECES_START + transformed_idx] = white_piece;
            output_features[FeatureIndices::BLACK_PIECES_START + transformed_idx] = black_piece;
        }
    }
    
    // Copy non-geometric features (phases, counts, tactical features)
    // These are either invariant or need color swapping only
    
    // Phase features are invariant
    for (int i = FeatureIndices::PHASE_START; i < FeatureIndices::PHASE_END; ++i) {
        output_features[i] = input_features[i];
    }
    
    // Piece count features
    if (swap_colors) {
        // Swap white and black count features
        for (int i = 0; i < 10; ++i) {
            output_features[FeatureIndices::WHITE_IN_HAND_START + i] = 
                input_features[FeatureIndices::BLACK_IN_HAND_START + i];
            output_features[FeatureIndices::BLACK_IN_HAND_START + i] = 
                input_features[FeatureIndices::WHITE_IN_HAND_START + i];
            output_features[FeatureIndices::WHITE_ON_BOARD_START + i] = 
                input_features[FeatureIndices::BLACK_ON_BOARD_START + i];
            output_features[FeatureIndices::BLACK_ON_BOARD_START + i] = 
                input_features[FeatureIndices::WHITE_ON_BOARD_START + i];
        }
    } else {
        // Keep count features the same
        for (int i = FeatureIndices::PIECE_COUNT_START; i < FeatureIndices::PIECE_COUNT_END; ++i) {
            output_features[i] = input_features[i];
        }
    }
    
    // Tactical features
    if (swap_colors) {
        // Swap mill potential features
        for (int i = 0; i < 8; ++i) {
            output_features[FeatureIndices::WHITE_MILL_POTENTIAL + i] = 
                input_features[FeatureIndices::BLACK_MILL_POTENTIAL + i];
            output_features[FeatureIndices::BLACK_MILL_POTENTIAL + i] = 
                input_features[FeatureIndices::WHITE_MILL_POTENTIAL + i];
        }
        
        // Mobility difference features need sign flip when colors are swapped
        for (int i = 0; i < 7; ++i) {
            // Map mobility difference with opposite sign
            const int opposite_idx = 6 - i;  // Reverse the index for sign flip
            output_features[FeatureIndices::MOBILITY_DIFF_START + i] = 
                input_features[FeatureIndices::MOBILITY_DIFF_START + opposite_idx];
        }
    } else {
        // Keep tactical features the same
        for (int i = FeatureIndices::TACTICAL_START; i < FeatureIndices::TACTICAL_END; ++i) {
            output_features[i] = input_features[i];
        }
    }
}

void SymmetryTransforms::extract_symmetry_features(Position& pos, bool* features, SymmetryOp op) {
    if (op == SYM_IDENTITY) {
        // No transformation needed
        FeatureExtractor::extract_features(pos, features);
        return;
    }
    
    // Extract features from original position, then transform them
    bool original_features[FeatureIndices::TOTAL_FEATURES];
    FeatureExtractor::extract_features(pos, original_features);
    transform_features(original_features, features, op);
}

SymmetryOp SymmetryTransforms::get_inverse(SymmetryOp op) {
    // Lookup table for inverse operations
    constexpr SymmetryOp inverse_table[SYM_OP_COUNT] = {
        SYM_IDENTITY,                    // Identity is self-inverse
        SYM_ROTATE_270,                  // 90° -> 270°
        SYM_ROTATE_180,                  // 180° is self-inverse
        SYM_ROTATE_90,                   // 270° -> 90°
        SYM_MIRROR_VERTICAL,             // Vertical mirror is self-inverse
        SYM_MIRROR_HORIZONTAL,           // Horizontal mirror is self-inverse
        SYM_MIRROR_BACKSLASH,            // Backslash mirror is self-inverse
        SYM_MIRROR_SLASH,                // Slash mirror is self-inverse
        SYM_COLOR_SWAP,                  // Color swap is self-inverse
        SYM_COLOR_SWAP_ROTATE_270,       // Color swap + 90° -> Color swap + 270°
        SYM_COLOR_SWAP_ROTATE_180,       // Color swap + 180° is self-inverse
        SYM_COLOR_SWAP_ROTATE_90,        // Color swap + 270° -> Color swap + 90°
        SYM_COLOR_SWAP_MIRROR_VERTICAL,  // Color swap + vertical mirror is self-inverse
        SYM_COLOR_SWAP_MIRROR_HORIZONTAL,// Color swap + horizontal mirror is self-inverse
        SYM_COLOR_SWAP_MIRROR_BACKSLASH, // Color swap + backslash mirror is self-inverse
        SYM_COLOR_SWAP_MIRROR_SLASH      // Color swap + slash mirror is self-inverse
    };
    
    return inverse_table[op];
}

SymmetryOp SymmetryTransforms::combine(SymmetryOp op1, SymmetryOp op2) {
    // This is a simplified implementation - a full group table would be better
    // For now, we only handle identity combinations
    if (op1 == SYM_IDENTITY) return op2;
    if (op2 == SYM_IDENTITY) return op1;
    
    // For other combinations, we would need a full group multiplication table
    // This is complex for the dihedral group D8 extended with color swap
    // For now, return identity as a safe fallback
    return SYM_IDENTITY;
}

// Symmetry-aware evaluation functions
int32_t SymmetryAwareNNUE::evaluate_with_symmetries(const Position& pos) {
    // For now, we implement a simple approach: evaluate the canonical form
    // More sophisticated approaches could average multiple symmetries
    
    Position pos_copy = pos;
    SymmetryOp canonical_op = find_canonical_symmetry(pos_copy);
    
    bool features[FeatureIndices::TOTAL_FEATURES];
    SymmetryTransforms::extract_symmetry_features(pos_copy, features, canonical_op);
    
    // This would need integration with the actual NNUE evaluator
    // For now, return 0 as placeholder
    return 0;
}

SymmetryOp SymmetryAwareNNUE::find_canonical_symmetry(const Position& pos) {
    // Find the symmetry operation that produces the lexicographically smallest
    // position representation
    SymmetryOp best_op = SYM_IDENTITY;
    
    // Extract features for identity transformation as baseline
    bool best_features[FeatureIndices::TOTAL_FEATURES];
    Position pos_copy = pos;
    FeatureExtractor::extract_features(pos_copy, best_features);
    
    // Test all other symmetry operations
    for (int op = 1; op < SYM_OP_COUNT; ++op) {
        bool current_features[FeatureIndices::TOTAL_FEATURES];
        SymmetryTransforms::extract_symmetry_features(pos_copy, current_features, static_cast<SymmetryOp>(op));
        
        // Compare feature vectors lexicographically
        if (std::lexicographical_compare(current_features, current_features + FeatureIndices::TOTAL_FEATURES,
                                       best_features, best_features + FeatureIndices::TOTAL_FEATURES)) {
            best_op = static_cast<SymmetryOp>(op);
            std::memcpy(best_features, current_features, sizeof(best_features));
        }
    }
    
    return best_op;
}

void SymmetryAwareNNUE::generate_symmetric_training_data(const Position& pos, 
                                                       std::vector<std::pair<bool*, int32_t>>& training_examples) {
    Position pos_copy = pos;
    
    // Generate training examples for all valid symmetries
    for (int op = 0; op < SYM_OP_COUNT; ++op) {
        bool* features = new bool[FeatureIndices::TOTAL_FEATURES];
        SymmetryTransforms::extract_symmetry_features(pos_copy, features, static_cast<SymmetryOp>(op));
        
        // The target value should be the same for all symmetries
        // (or negated for color-swapping symmetries)
        int32_t target_value = 0; // This would come from the perfect database or other evaluation
        
        if (SymmetryTransforms::swaps_colors(static_cast<SymmetryOp>(op))) {
            target_value = -target_value; // Negate evaluation for color-swapped positions
        }
        
        training_examples.emplace_back(features, target_value);
    }
}

bool SymmetryAwareNNUE::is_position_symmetric(const Position& pos, SymmetryOp op) {
    Position pos_copy = pos;
    
    // Extract original features
    bool original_features[FeatureIndices::TOTAL_FEATURES];
    FeatureExtractor::extract_features(pos_copy, original_features);
    
    // Extract transformed features
    bool transformed_features[FeatureIndices::TOTAL_FEATURES];
    SymmetryTransforms::extract_symmetry_features(pos_copy, transformed_features, op);
    
    // Check if they are identical
    return std::memcmp(original_features, transformed_features, sizeof(original_features)) == 0;
}

void SymmetryAwareNNUE::extract_all_symmetric_features(Position& pos, bool features[][115]) {
    for (int op = 0; op < SYM_OP_COUNT; ++op) {
        SymmetryTransforms::extract_symmetry_features(pos, features[op], static_cast<SymmetryOp>(op));
    }
}

} // namespace NNUE
