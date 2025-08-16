// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_features.h - Feature extraction for NNUE evaluation

#ifndef NNUE_FEATURES_H_INCLUDED
#define NNUE_FEATURES_H_INCLUDED

#include "types.h"
#include "position.h"

namespace NNUE {

// Feature extraction for Mill game positions
class FeatureExtractor {
public:
    // Extract features from position
    static void extract_features(Position& pos, bool* features);
    
    // Extract phase-specific features
    static void extract_phase_features(Position& pos, bool* features);
    
    // Extract piece count features
    static void extract_piece_count_features(Position& pos, bool* features);
    
    // Extract mobility features
    static void extract_mobility_features(Position& pos, bool* features);
    
    // Extract mill formation features
    static void extract_mill_features(Position& pos, bool* features);

private:
    // Convert square index to feature index
    static int square_to_feature_index(Square sq, Color c);
};

// Feature indices for different aspects of the position
// Features are organized to be contiguous and densely packed.
namespace FeatureIndices {
    // 1. Piece Placement Features (48 features)
    // For each of the 24 squares, one feature indicates if a white piece is
    // present, and another for a black piece.
    constexpr int PIECE_PLACEMENT_START = 0;
    constexpr int WHITE_PIECES_START = PIECE_PLACEMENT_START;
    constexpr int BLACK_PIECES_START = WHITE_PIECES_START + 24;
    constexpr int PIECE_PLACEMENT_END = BLACK_PIECES_START + 24;

    // 2. Game Phase Features (3 features)
    // One-hot encoding for the current game phase.
    constexpr int PHASE_START = PIECE_PLACEMENT_END;
    constexpr int PHASE_PLACING = PHASE_START;
    constexpr int PHASE_MOVING = PHASE_START + 1;
    constexpr int PHASE_GAMEOVER = PHASE_START + 2;
    constexpr int PHASE_END = PHASE_START + 3;

    // 3. Piece Count Features (40 features)
    // One-hot encoding for the number of pieces in hand and on the board for
    // each color.
    // - 10 features for white pieces in hand (0-9)
    // - 10 features for black pieces in hand (0-9)
    // - 10 features for white pieces on board (0-9)
    // - 10 features for black pieces on board (0-9)
    constexpr int PIECE_COUNT_START = PHASE_END;
    constexpr int WHITE_IN_HAND_START = PIECE_COUNT_START;
    constexpr int BLACK_IN_HAND_START = WHITE_IN_HAND_START + 10;
    constexpr int WHITE_ON_BOARD_START = BLACK_IN_HAND_START + 10;
    constexpr int BLACK_ON_BOARD_START = WHITE_ON_BOARD_START + 10;
    constexpr int PIECE_COUNT_END = BLACK_ON_BOARD_START + 10;

    // 4. Tactical Features (24 features)
    // Features related to mills, blocking, and mobility.
    // - 8 features for white's potential mills
    // - 8 features for black's potential mills
    // - 8 features for mobility difference
    constexpr int TACTICAL_START = PIECE_COUNT_END;
    constexpr int WHITE_MILL_POTENTIAL = TACTICAL_START;
    constexpr int BLACK_MILL_POTENTIAL = WHITE_MILL_POTENTIAL + 8;
    constexpr int MOBILITY_DIFF_START = BLACK_MILL_POTENTIAL + 8;
    constexpr int TACTICAL_END = MOBILITY_DIFF_START + 8;

    // Total number of features
    constexpr int TOTAL_FEATURES = TACTICAL_END;
};

} // namespace NNUE

#endif // NNUE_FEATURES_H_INCLUDED
