// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_symmetries.h - Symmetry transformations for NNUE evaluation
// Applies the same symmetry concepts from perfect database to NNUE features

#ifndef NNUE_SYMMETRIES_H_INCLUDED
#define NNUE_SYMMETRIES_H_INCLUDED

#include "types.h"
#include "position.h"

namespace NNUE {

// Symmetry transformation operations for the mill board
// These map 1:1 with perfect database transformations
enum SymmetryOp : int {
    SYM_IDENTITY = 0,
    SYM_ROTATE_90 = 1,
    SYM_ROTATE_180 = 2,
    SYM_ROTATE_270 = 3,
    SYM_MIRROR_VERTICAL = 4,
    SYM_MIRROR_HORIZONTAL = 5,
    SYM_MIRROR_BACKSLASH = 6,
    SYM_MIRROR_SLASH = 7,
    SYM_COLOR_SWAP = 8,
    SYM_COLOR_SWAP_ROTATE_90 = 9,
    SYM_COLOR_SWAP_ROTATE_180 = 10,
    SYM_COLOR_SWAP_ROTATE_270 = 11,
    SYM_COLOR_SWAP_MIRROR_VERTICAL = 12,
    SYM_COLOR_SWAP_MIRROR_HORIZONTAL = 13,
    SYM_COLOR_SWAP_MIRROR_BACKSLASH = 14,
    SYM_COLOR_SWAP_MIRROR_SLASH = 15,
    SYM_OP_COUNT = 16
};

// Symmetry transformation utilities
class SymmetryTransforms {
public:
    // Initialize transformation lookup tables
    static void initialize();
    
    // Transform a square according to the given symmetry operation
    static Square transform_square(Square sq, SymmetryOp op);
    
    // Transform feature vector using symmetry operation
    static void transform_features(const bool* input_features, bool* output_features, SymmetryOp op);
    
    // Apply symmetry to position and extract transformed features
    static void extract_symmetry_features(Position& pos, bool* features, SymmetryOp op);
    
    // Check if a symmetry operation swaps colors
    static bool swaps_colors(SymmetryOp op) {
        return op >= SYM_COLOR_SWAP;
    }
    
    // Get the inverse of a symmetry operation
    static SymmetryOp get_inverse(SymmetryOp op);
    
    // Combine two symmetry operations
    static SymmetryOp combine(SymmetryOp op1, SymmetryOp op2);

private:
    // Lookup tables for fast square transformations
    static Square square_transform_table_[SYM_OP_COUNT][SQUARE_NB];
    static bool initialized_;
    
    // Individual transformation functions
    static Square rotate_90_transform(Square sq);
    static Square rotate_180_transform(Square sq);
    static Square rotate_270_transform(Square sq);
    static Square mirror_vertical_transform(Square sq);
    static Square mirror_horizontal_transform(Square sq);
    static Square mirror_backslash_transform(Square sq);
    static Square mirror_slash_transform(Square sq);
};

// Symmetry-aware NNUE evaluation
class SymmetryAwareNNUE {
public:
    // Evaluate position using all symmetries and return average/best result
    static int32_t evaluate_with_symmetries(const Position& pos);
    
    // Find canonical form of position (minimal representation under symmetries)
    static SymmetryOp find_canonical_symmetry(const Position& pos);
    
    // Generate training data with symmetry augmentation
    static void generate_symmetric_training_data(const Position& pos, 
                                               std::vector<std::pair<bool*, int32_t>>& training_examples);
    
    // Check if position is symmetric under given operation
    static bool is_position_symmetric(const Position& pos, SymmetryOp op);
    
private:
    // Extract features for all symmetries
    static void extract_all_symmetric_features(Position& pos, bool features[][115]);
};

} // namespace NNUE

#endif // NNUE_SYMMETRIES_H_INCLUDED
