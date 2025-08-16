// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_features.cpp - Feature extraction implementation

#include "nnue_features.h"
#include "position.h"
#include "bitboard.h"
#include "movegen.h"
#include <cstring>
#include <algorithm>
#include <cassert>

namespace NNUE {

// Helper function to extract LSB (Least Significant Bit) and clear it
// This replaces the missing pop_lsb function with a portable implementation
inline Square extract_lsb(Bitboard& b) {
    // Error handling: return invalid square if bitboard is empty
    if (b == 0) {
        return SQ_NONE;
    }
    
#if defined(_MSC_VER) && defined(_WIN64)
    unsigned long idx;
    _BitScanForward(&idx, b);
    b &= b - 1;  // Clear the LSB
    return static_cast<Square>(idx);
#elif defined(__GNUC__)
    const int idx = __builtin_ctz(b);
    b &= b - 1;  // Clear the LSB
    return static_cast<Square>(idx);
#else
    // Generic fallback implementation
    const Bitboard lsb = b & -b;  // Isolate LSB
    b &= b - 1;  // Clear the LSB
    
    // Count trailing zeros manually for the isolated LSB
    int idx = 0;
    Bitboard temp = lsb;
    while (temp > 1) {
        temp >>= 1;
        ++idx;
    }
    return static_cast<Square>(idx);
#endif
}

// Optimized helper function to count mobility using bitboard operations
int count_mobility(Position& pos, Color color) {
    // Check if pieces can fly (endgame rule)
    if (pos.piece_on_board_count(color) <= 3) {
        // In the endgame, pieces may fly; mobility approximates the number of empty squares.
        return 24 - (pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK));
    }

    int mobility = 0;
    const Bitboard all_pieces = pos.byTypeBB[ALL_PIECES];
    const Bitboard empty_squares = ~all_pieces;
    
    // Get bitboard of all pieces of the specified color
    Bitboard pieces = pos.byColorBB[color];
    
    // Process each piece using bitboard operations (much faster than loop)
    while (pieces) {
        const Square sq = extract_lsb(pieces);  // Extract and remove one piece position
        
        // Validate square is in valid range before accessing adjacent squares
        if (sq >= SQ_BEGIN && sq < SQ_END) {
            const Bitboard adjacent = MoveList<LEGAL>::adjacentSquaresBB[sq];
            mobility += popcount(adjacent & empty_squares);
        }
    }
    
    return mobility;
}


void FeatureExtractor::extract_features(Position& pos, bool* features) {
    // Validate input
    assert(features != nullptr && "Feature array must not be null");
    
    // 1. Clear all features
    std::memset(features, 0, FeatureIndices::TOTAL_FEATURES * sizeof(bool));

    // 2. Piece Placement Features - optimized using bitboards
    // Process white pieces - use consistent coordinate mapping with symmetries
    Bitboard white_pieces = pos.byColorBB[WHITE];
    while (white_pieces) {
        const Square sq = extract_lsb(white_pieces);
        
        // Validate square extraction was successful
        if (sq == SQ_NONE) {
            break;  // No more pieces to process
        }
        
        const int feature_idx = sq - SQ_BEGIN;  // Engine coordinate (0-23 range)
        if (feature_idx >= 0 && feature_idx < SQUARE_NB) {
            features[FeatureIndices::WHITE_PIECES_START + feature_idx] = true;
        }
    }
    
    // Process black pieces - use consistent coordinate mapping with symmetries
    Bitboard black_pieces = pos.byColorBB[BLACK];
    while (black_pieces) {
        const Square sq = extract_lsb(black_pieces);
        
        // Validate square extraction was successful
        if (sq == SQ_NONE) {
            break;  // No more pieces to process
        }
        
        const int feature_idx = sq - SQ_BEGIN;  // Engine coordinate (0-23 range)
        if (feature_idx >= 0 && feature_idx < SQUARE_NB) {
            features[FeatureIndices::BLACK_PIECES_START + feature_idx] = true;
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

    // Map difference to a feature index in [0..7]. The mapping is symmetric
    // around zero and covers the full range to match 8 mobility buckets:
    // [-inf, -8] -> 0
    // [-7, -5]   -> 1
    // [-4, -2]   -> 2
    // [-1, 0]    -> 3 (slightly black / neutral)
    // [1, 2]     -> 4 (slightly white)
    // [3, 5]     -> 5
    // [6, 8]     -> 6
    // [9,  inf]  -> 7
    // This ensures consistency with symmetry color-swap mapping.
    int mobility_idx = 3; // Default near-neutral bucket
    if (mobility_diff <= -8) mobility_idx = 0;
    else if (mobility_diff <= -5) mobility_idx = 1;
    else if (mobility_diff <= -2) mobility_idx = 2;
    else if (mobility_diff >= 9) mobility_idx = 7;
    else if (mobility_diff >= 6) mobility_idx = 6;
    else if (mobility_diff >= 3) mobility_idx = 5;
    else if (mobility_diff >= 1) mobility_idx = 4;
    features[FeatureIndices::MOBILITY_DIFF_START + mobility_idx] = true;
}

int FeatureExtractor::square_to_feature_index(Square sq, Color c) {
    if (sq < SQ_BEGIN || sq >= SQ_END) {
        return -1;  // Invalid square
    }
    
    // Convert engine square to feature index (0-23 range)
    const int feature_idx = sq - SQ_BEGIN;
    
    if (c == WHITE) {
        return FeatureIndices::WHITE_PIECES_START + feature_idx;
    } else {
        return FeatureIndices::BLACK_PIECES_START + feature_idx;
    }
}

} // namespace NNUE
