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
    
    NNUE_DEBUG_PRINT("Starting feature extraction...");
    
    // 1. Clear all features
    std::memset(features, 0, FeatureIndices::TOTAL_FEATURES * sizeof(bool));

    // 2. Piece Placement Features - optimized using bitboards
    NNUE_DEBUG_PRINT("Extracting piece placement features...");
    
    int white_piece_count = 0;
    int black_piece_count = 0;
    
    // Process white pieces - use consistent coordinate mapping with symmetries
    Bitboard white_pieces = pos.byColorBB[WHITE];
    NNUE_DEBUG_PRINTF("White pieces bitboard: 0x%llx", static_cast<unsigned long long>(white_pieces));
    
    while (white_pieces) {
        const Square sq = extract_lsb(white_pieces);
        
        // Validate square extraction was successful
        if (sq == SQ_NONE) {
            break;  // No more pieces to process
        }
        
        const int feature_idx = sq - SQ_BEGIN;  // Engine coordinate (0-23 range)
        if (feature_idx >= 0 && feature_idx < SQUARE_NB) {
            features[FeatureIndices::WHITE_PIECES_START + feature_idx] = true;
            white_piece_count++;
            NNUE_DEBUG_PRINTF("White piece at square %d (feature %d)", sq, FeatureIndices::WHITE_PIECES_START + feature_idx);
        }
    }
    
    // Process black pieces - use consistent coordinate mapping with symmetries
    Bitboard black_pieces = pos.byColorBB[BLACK];
    NNUE_DEBUG_PRINTF("Black pieces bitboard: 0x%llx", static_cast<unsigned long long>(black_pieces));
    
    while (black_pieces) {
        const Square sq = extract_lsb(black_pieces);
        
        // Validate square extraction was successful
        if (sq == SQ_NONE) {
            break;  // No more pieces to process
        }
        
        const int feature_idx = sq - SQ_BEGIN;  // Engine coordinate (0-23 range)
        if (feature_idx >= 0 && feature_idx < SQUARE_NB) {
            features[FeatureIndices::BLACK_PIECES_START + feature_idx] = true;
            black_piece_count++;
            NNUE_DEBUG_PRINTF("Black piece at square %d (feature %d)", sq, FeatureIndices::BLACK_PIECES_START + feature_idx);
        }
    }
    
    NNUE_DEBUG_PRINTF("Piece placement: %d white, %d black pieces", white_piece_count, black_piece_count);

    // 3. Game Phase Features
    NNUE_DEBUG_PRINT("Extracting game phase features...");
    const Phase phase = pos.get_phase();
    NNUE_DEBUG_PRINTF("Current phase: %d", static_cast<int>(phase));
    
    if (phase == Phase::placing) {
        features[FeatureIndices::PHASE_PLACING] = true;
        NNUE_DEBUG_PRINTF("Phase feature set: PLACING (index %d)", FeatureIndices::PHASE_PLACING);
    } else if (phase == Phase::moving) {
        features[FeatureIndices::PHASE_MOVING] = true;
        NNUE_DEBUG_PRINTF("Phase feature set: MOVING (index %d)", FeatureIndices::PHASE_MOVING);
    } else if (phase == Phase::gameOver) {
        features[FeatureIndices::PHASE_GAMEOVER] = true;
        NNUE_DEBUG_PRINTF("Phase feature set: GAMEOVER (index %d)", FeatureIndices::PHASE_GAMEOVER);
    }

    // 4. Piece Count Features (one-hot encoded)
    NNUE_DEBUG_PRINT("Extracting piece count features...");
    const int white_in_hand = pos.piece_in_hand_count(WHITE);
    const int black_in_hand = pos.piece_in_hand_count(BLACK);
    const int white_on_board = pos.piece_on_board_count(WHITE);
    const int black_on_board = pos.piece_on_board_count(BLACK);

    NNUE_DEBUG_PRINTF("Piece counts - White: %d in hand, %d on board; Black: %d in hand, %d on board", 
                      white_in_hand, white_on_board, black_in_hand, black_on_board);

    if (white_in_hand >= 0 && white_in_hand < 10) {
        features[FeatureIndices::WHITE_IN_HAND_START + white_in_hand] = true;
        NNUE_DEBUG_PRINTF("White in hand feature: index %d", FeatureIndices::WHITE_IN_HAND_START + white_in_hand);
    }
    if (black_in_hand >= 0 && black_in_hand < 10) {
        features[FeatureIndices::BLACK_IN_HAND_START + black_in_hand] = true;
        NNUE_DEBUG_PRINTF("Black in hand feature: index %d", FeatureIndices::BLACK_IN_HAND_START + black_in_hand);
    }
    if (white_on_board >= 0 && white_on_board < 10) {
        features[FeatureIndices::WHITE_ON_BOARD_START + white_on_board] = true;
        NNUE_DEBUG_PRINTF("White on board feature: index %d", FeatureIndices::WHITE_ON_BOARD_START + white_on_board);
    }
    if (black_on_board >= 0 && black_on_board < 10) {
        features[FeatureIndices::BLACK_ON_BOARD_START + black_on_board] = true;
        NNUE_DEBUG_PRINTF("Black on board feature: index %d", FeatureIndices::BLACK_ON_BOARD_START + black_on_board);
    }

    // 5. Tactical Features
    NNUE_DEBUG_PRINT("Extracting tactical features...");
    
    // Mill potential features
    for (Color c : {WHITE, BLACK}) {
        int mill_potential = 0;
        for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
            if (pos.empty(sq)) {
                mill_potential += pos.potential_mills_count(sq, c);
            }
        }
        mill_potential = std::min(mill_potential, 7); // Clamp to 0-7 range
        
        NNUE_DEBUG_PRINTF("%s mill potential: %d", c == WHITE ? "White" : "Black", mill_potential);
        
        if (c == WHITE) {
            features[FeatureIndices::WHITE_MILL_POTENTIAL + mill_potential] = true;
            NNUE_DEBUG_PRINTF("White mill potential feature: index %d", FeatureIndices::WHITE_MILL_POTENTIAL + mill_potential);
        } else {
            features[FeatureIndices::BLACK_MILL_POTENTIAL + mill_potential] = true;
            NNUE_DEBUG_PRINTF("Black mill potential feature: index %d", FeatureIndices::BLACK_MILL_POTENTIAL + mill_potential);
        }
    }

    // Mobility features
    NNUE_DEBUG_PRINT("Computing mobility features...");
    const int total_on_board = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    const int white_mobility = (phase == Phase::placing) ? (24 - total_on_board) : count_mobility(pos, WHITE);
    const int black_mobility = (phase == Phase::placing) ? (24 - total_on_board) : count_mobility(pos, BLACK);
    int mobility_diff = white_mobility - black_mobility;

    NNUE_DEBUG_PRINTF("Mobility - White: %d, Black: %d, Diff: %d", white_mobility, black_mobility, mobility_diff);

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
    NNUE_DEBUG_PRINTF("Mobility difference feature: index %d (bucket %d)", FeatureIndices::MOBILITY_DIFF_START + mobility_idx, mobility_idx);
    
    // Final feature extraction summary
    int total_active_features = 0;
    for (int i = 0; i < FeatureIndices::TOTAL_FEATURES; i++) {
        if (features[i]) total_active_features++;
    }
    NNUE_DEBUG_PRINTF("Feature extraction completed: %d/%d features active", total_active_features, FeatureIndices::TOTAL_FEATURES);
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
