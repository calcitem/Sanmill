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
    static void extract_features(const Position& pos, bool* features);
    
    // Extract phase-specific features
    static void extract_phase_features(const Position& pos, bool* features);
    
    // Extract piece count features
    static void extract_piece_count_features(const Position& pos, bool* features);
    
    // Extract mobility features
    static void extract_mobility_features(const Position& pos, bool* features);
    
    // Extract mill formation features
    static void extract_mill_features(const Position& pos, bool* features);

private:
    // Convert square index to feature index
    static int square_to_feature_index(Square sq, Color c);
    
    // Check if square has piece of given color
    static bool has_piece(const Position& pos, Square sq, Color c);
};

// Feature indices for different aspects of the position
namespace FeatureIndices {
    // Basic piece placement features (0-47)
    constexpr int PIECE_FEATURES_START = 0;
    constexpr int WHITE_PIECES_START = 0;
    constexpr int BLACK_PIECES_START = 24;
    
    // Phase information features (48-50)
    constexpr int PHASE_FEATURES_START = 48;
    constexpr int PHASE_PLACING = 48;
    constexpr int PHASE_MOVING = 49;
    constexpr int PHASE_GAMEOVER = 50;
    
    // Piece count features (51-62)
    constexpr int COUNT_FEATURES_START = 51;
    constexpr int WHITE_IN_HAND_START = 51;    // 0-9 pieces in hand
    constexpr int BLACK_IN_HAND_START = 56;    // 0-9 pieces in hand  
    constexpr int WHITE_ON_BOARD_START = 61;   // encoded piece count
    constexpr int BLACK_ON_BOARD_START = 66;   // encoded piece count
    
    // Mill and tactical features (71-94)
    constexpr int TACTICAL_FEATURES_START = 71;
    constexpr int MILL_FORMATION_START = 71;   // Potential mills
    constexpr int BLOCKING_START = 79;         // Blocking opportunities
    constexpr int MOBILITY_START = 87;         // Mobility features
    
    // Total feature count
    constexpr int TOTAL_FEATURES = 95;
};

} // namespace NNUE

#endif // NNUE_FEATURES_H_INCLUDED
