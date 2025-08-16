// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_features.cpp - Feature extraction implementation

#include "nnue_features.h"
#include "position.h"
#include "bitboard.h"
#include "movegen.h"
#include <cstring>
#include <algorithm>

namespace NNUE {

// Helper function to count mobility
int count_mobility(Position& pos, Color color) {
    if (pos.piece_on_board_count(color) <= 3) {
        // In the endgame, pieces may fly; mobility approximates the number of empty squares.
        return 24 - (pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK));
    }

    int mobility = 0;
    const Bitboard all_pieces = pos.byTypeBB[ALL_PIECES];

    // Iterate all board squares and accumulate adjacent empty targets for the given color
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (!pos.empty(sq) && pos.color_on(sq) == color) {
            const Bitboard adjacent = MoveList<LEGAL>::adjacentSquaresBB[sq];
            mobility += popcount(adjacent & ~all_pieces);
        }
    }
    return mobility;
}


void FeatureExtractor::extract_features(Position& pos, bool* features) {
    // 1. Clear all features
    std::memset(features, 0, FeatureIndices::TOTAL_FEATURES * sizeof(bool));

    // 2. Piece Placement Features
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (!pos.empty(sq)) {
            const int feature_idx = square_to_feature_index(sq, pos.color_on(sq));
            features[feature_idx] = true;
        }
    }

    // 3. Game Phase Features
    const Phase phase = pos.get_phase();
    if (phase == Phase::placing)
        features[FeatureIndices::PHASE_PLACING] = true;
    else if (phase == Phase::moving)
        features[FeatureIndices::PHASE_MOVING] = true;
    else if (phase == Phase::gameOver)
        features[FeatureIndices::PHASE_GAMEOVER] = true;

    // 4. Piece Count Features (one-hot encoded)
    const int white_in_hand = pos.piece_in_hand_count(WHITE);
    const int black_in_hand = pos.piece_in_hand_count(BLACK);
    const int white_on_board = pos.piece_on_board_count(WHITE);
    const int black_on_board = pos.piece_on_board_count(BLACK);

    if (white_in_hand >= 0 && white_in_hand < 10)
        features[FeatureIndices::WHITE_IN_HAND_START + white_in_hand] = true;
    if (black_in_hand >= 0 && black_in_hand < 10)
        features[FeatureIndices::BLACK_IN_HAND_START + black_in_hand] = true;
    if (white_on_board >= 0 && white_on_board < 10)
        features[FeatureIndices::WHITE_ON_BOARD_START + white_on_board] = true;
    if (black_on_board >= 0 && black_on_board < 10)
        features[FeatureIndices::BLACK_ON_BOARD_START + black_on_board] = true;

    // 5. Tactical Features
    // Mill potential features
    for (Color c : {WHITE, BLACK}) {
        int mill_potential = 0;
        for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
            if (pos.empty(sq)) {
                mill_potential += pos.potential_mills_count(sq, c);
            }
        }
        mill_potential = std::min(mill_potential, 7); // Clamp to 0-7 range
        if (c == WHITE) {
            features[FeatureIndices::WHITE_MILL_POTENTIAL + mill_potential] = true;
        } else {
            features[FeatureIndices::BLACK_MILL_POTENTIAL + mill_potential] = true;
        }
    }

    // Mobility features
    const int total_on_board = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    const int white_mobility = (phase == Phase::placing) ? (24 - total_on_board) : count_mobility(pos, WHITE);
    const int black_mobility = (phase == Phase::placing) ? (24 - total_on_board) : count_mobility(pos, BLACK);
    int mobility_diff = white_mobility - black_mobility;

    // Map difference to a feature index from -4 to +3
    // [-inf, -8] -> 0
    // [-7, -5] -> 1
    // [-4, -2] -> 2
    // [-1, 1] -> 3 (neutral)
    // [2, 4] -> 4
    // [5, 7] -> 5
    // [8, inf] -> 6
    // (This mapping is an example and can be tuned)
    int mobility_idx = 3; // Default to neutral
    if (mobility_diff <= -8) mobility_idx = 0;
    else if (mobility_diff <= -5) mobility_idx = 1;
    else if (mobility_diff <= -2) mobility_idx = 2;
    else if (mobility_diff >= 8) mobility_idx = 6;
    else if (mobility_diff >= 5) mobility_idx = 5;
    else if (mobility_diff >= 2) mobility_idx = 4;
    features[FeatureIndices::MOBILITY_DIFF_START + mobility_idx] = true;
}

int FeatureExtractor::square_to_feature_index(Square sq, Color c) {
    if (sq < SQ_BEGIN || sq >= SQ_END) {
        return -1;  // Invalid square
    }
    
    if (c == WHITE) {
        return FeatureIndices::WHITE_PIECES_START + sq;
    } else {
        return FeatureIndices::BLACK_PIECES_START + sq;
    }
}

} // namespace NNUE
