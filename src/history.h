// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// history.h

#ifndef HISTORY_H_INCLUDED
#define HISTORY_H_INCLUDED

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>

#include "types.h"

// History and killer moves for Sanmill game
// Inspired by Stockfish's history implementation but adapted for Nine Men's Morris

constexpr int HISTORY_MAX = 16384;        // Maximum history value
constexpr int KILLER_COUNT = 2;           // Number of killer moves per ply
constexpr int MAX_KILLERS_PLY = 128;      // Maximum search depth for killers

// History entry with bonus/malus update mechanism (like Stockfish)
template<typename T, int MaxValue>
class HistoryEntry {
    T entry = 0;

public:
    HistoryEntry& operator=(const T& v) {
        entry = v;
        return *this;
    }
    
    operator const T&() const { return entry; }
    
    // Update history with bonus/malus (Stockfish-style)
    void update(int bonus) {
        // Clamp bonus to reasonable range
        bonus = std::clamp(bonus, -MaxValue, MaxValue);
        entry += static_cast<T>(bonus - entry * std::abs(bonus) / MaxValue);
        
        // Ensure entry stays within bounds
        entry = static_cast<T>(std::clamp(static_cast<int>(entry), -MaxValue, MaxValue));
    }
};

using HistoryScore = HistoryEntry<int16_t, HISTORY_MAX>;

// Butterfly history: indexed by [Color][from][to] for quiet moves
// For Sanmill, from/to are square indices (0-23)
class ButterflyHistory {
public:
    ButterflyHistory() { clear(); }
    
    void clear() {
        for (auto& color : table) {
            for (auto& from : color) {
                for (auto& entry : from) {
                    entry = HistoryScore{};
                }
            }
        }
    }
    
    HistoryScore& operator()(Color c, Square from, Square to) {
        return table[c][from][to];
    }
    
    const HistoryScore& operator()(Color c, Square from, Square to) const {
        return table[c][from][to];
    }

private:
    HistoryScore table[COLOR_NB][24][24];
};

// Piece-to history: indexed by [piece][to_square] 
class PieceToHistory {
public:
    PieceToHistory() { clear(); }
    
    void clear() {
        for (auto& piece : table) {
            for (auto& entry : piece) {
                entry = HistoryScore{};
            }
        }
    }
    
    HistoryScore& operator()(Piece piece, Square to) {
        return table[piece][to];
    }
    
    const HistoryScore& operator()(Piece piece, Square to) const {
        return table[piece][to];
    }

private:
    // For Sanmill: WHITE_PIECE=0, BLACK_PIECE=1, so 2 piece types x 24 squares
    HistoryScore table[2][24];
};

// Killer moves: store good moves that caused beta cutoffs
class KillerMoves {
public:
    KillerMoves() { clear(); }
    
    void clear() {
        for (auto& ply : killers) {
            for (auto& move : ply) {
                move = MOVE_NONE;
            }
        }
    }
    
    // Add a killer move for the given ply
    void add(Move move, int ply) {
        if (ply >= MAX_KILLERS_PLY || move == MOVE_NONE) return;
        
        // Don't add if it's already the first killer
        if (killers[ply][0] == move) return;
        
        // Shift killers: second becomes first, new move becomes second
        killers[ply][1] = killers[ply][0];
        killers[ply][0] = move;
    }
    
    // Check if a move is a killer move for the given ply
    bool is_killer(Move move, int ply) const {
        if (ply >= MAX_KILLERS_PLY) return false;
        return killers[ply][0] == move || killers[ply][1] == move;
    }
    
    // Get killer moves for a ply
    Move killer1(int ply) const {
        return (ply < MAX_KILLERS_PLY) ? killers[ply][0] : MOVE_NONE;
    }
    
    Move killer2(int ply) const {
        return (ply < MAX_KILLERS_PLY) ? killers[ply][1] : MOVE_NONE;
    }

private:
    Move killers[MAX_KILLERS_PLY][KILLER_COUNT];
};

// Counter moves: moves that refute other moves
class CounterMoves {
public:
    CounterMoves() { clear(); }
    
    void clear() {
        for (auto& from : table) {
            for (auto& entry : from) {
                entry = MOVE_NONE;
            }
        }
    }
    
    Move& operator()(Square from, Square to) {
        return table[from][to];
    }
    
    const Move& operator()(Square from, Square to) const {
        return table[from][to];
    }

private:
    Move table[24][24];  // 24x24 for Sanmill squares
};

#endif // HISTORY_H_INCLUDED
