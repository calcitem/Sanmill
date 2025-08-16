// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_features.cpp - Feature extraction implementation

#include "nnue_features.h"
#include "position.h"
#include "bitboard.h"
#include "movegen.h"
#include <cstring>

namespace NNUE {

void FeatureExtractor::extract_features(Position& pos, bool* features) {
    // Clear all features first
    std::memset(features, 0, FeatureIndices::TOTAL_FEATURES * sizeof(bool));
    
    // Extract basic piece placement features
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (!pos.empty(sq)) {
            Color c = pos.color_on(sq);
            int feature_idx = square_to_feature_index(sq, c);
            if (feature_idx >= 0 && feature_idx < 48) {
                features[feature_idx] = true;
            }
        }
    }
    
    // Extract phase features
    extract_phase_features(pos, features);
    
    // Extract piece count features
    extract_piece_count_features(pos, features);
    
    // Extract mobility features if in moving phase
    if (pos.get_phase() == Phase::moving) {
        extract_mobility_features(pos, features);
    }
    
    // Extract mill formation features
    extract_mill_features(pos, features);
}

void FeatureExtractor::extract_phase_features(Position& pos, bool* features) {
    Phase current_phase = pos.get_phase();
    
    switch (current_phase) {
        case Phase::placing:
            features[FeatureIndices::PHASE_PLACING] = true;
            break;
        case Phase::moving:
            features[FeatureIndices::PHASE_MOVING] = true;
            break;
        case Phase::gameOver:
            features[FeatureIndices::PHASE_GAMEOVER] = true;
            break;
        default:
            break;
    }
}

void FeatureExtractor::extract_piece_count_features(Position& pos, bool* features) {
    // Pieces in hand (0-9 pieces encoded as binary)
    int white_in_hand = pos.piece_in_hand_count(WHITE);
    int black_in_hand = pos.piece_in_hand_count(BLACK);
    
    // Encode piece counts in binary (up to 15 pieces each)
    for (int i = 0; i < 4; i++) {  // 4 bits for each color
        if (white_in_hand & (1 << i)) {
            features[FeatureIndices::WHITE_IN_HAND_START + i] = true;
        }
        if (black_in_hand & (1 << i)) {
            features[FeatureIndices::BLACK_IN_HAND_START + i] = true;
        }
    }
    
    // Pieces on board (similar encoding)
    int white_on_board = pos.piece_on_board_count(WHITE);
    int black_on_board = pos.piece_on_board_count(BLACK);
    
    for (int i = 0; i < 4; i++) {  // 4 bits for each color
        if (white_on_board & (1 << i)) {
            features[FeatureIndices::WHITE_ON_BOARD_START + i] = true;
        }
        if (black_on_board & (1 << i)) {
            features[FeatureIndices::BLACK_ON_BOARD_START + i] = true;
        }
    }
}

void FeatureExtractor::extract_mobility_features(Position& pos, bool* features) {
    if (pos.get_phase() != Phase::moving) {
        return;
    }
    
    // Count mobility for each color
    int white_mobility = 0;
    int black_mobility = 0;
    
    // Count possible moves for each piece
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (!pos.empty(sq)) {
            Color c = pos.color_on(sq);
            
            // Count adjacent empty squares using MoveList adjacency
            Bitboard adjacent = MoveList<LEGAL>::adjacentSquaresBB[sq];
            Bitboard all_pieces = pos.byTypeBB[ALL_PIECES];
            int adjacent_count = popcount(adjacent & ~all_pieces);
            
            if (c == WHITE) {
                white_mobility += adjacent_count;
            } else {
                black_mobility += adjacent_count;
            }
        }
    }
    
    // Encode mobility difference
    int mobility_diff = white_mobility - black_mobility;
    
    // Map mobility difference to feature indices
    int mobility_feature_idx = FeatureIndices::MOBILITY_START;
    if (mobility_diff > 0) {
        features[mobility_feature_idx] = true;      // White has more mobility
    } else if (mobility_diff < 0) {
        features[mobility_feature_idx + 1] = true;  // Black has more mobility
    }
    // If mobility_diff == 0, neither feature is set (equal mobility)
}

void FeatureExtractor::extract_mill_features(Position& pos, bool* features) {
    // Check for potential mills and blocking opportunities
    int mill_feature_idx = FeatureIndices::MILL_FORMATION_START;
    
    // Analyze each mill pattern
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (pos.empty(sq)) {
            // Check if placing a piece here would form a mill
            for (Color c : {WHITE, BLACK}) {
                if (pos.potential_mills_count(sq, c) > 0) {
                    int feature_offset = (c == WHITE) ? 0 : 4;
                    features[mill_feature_idx + feature_offset] = true;
                }
            }
        }
    }
    
    // Check for blocking opportunities
    int blocking_feature_idx = FeatureIndices::BLOCKING_START;
    
    // Check if current side can block opponent mills
    Color opponent = (pos.side_to_move() == WHITE) ? BLACK : WHITE;
    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        if (pos.empty(sq) && pos.potential_mills_count(sq, opponent) > 0) {
            // Opponent could form mill here - this is a blocking opportunity
            features[blocking_feature_idx] = true;
            break;
        }
    }
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

bool FeatureExtractor::has_piece(Position& pos, Square sq, Color c) {
    return !pos.empty(sq) && pos.color_on(sq) == c;
}

} // namespace NNUE
