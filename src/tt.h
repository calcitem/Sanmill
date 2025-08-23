// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tt.h

#ifndef TT_H_INCLUDED
#define TT_H_INCLUDED

#include "hashmap.h"
#include "types.h"

using CTSL::HashMap;

#ifdef TRANSPOSITION_TABLE_ENABLE

// Constants for generation management (similar to Stockfish)
static constexpr unsigned GENERATION_BITS = 2;
static constexpr int GENERATION_DELTA = (1 << GENERATION_BITS);
static constexpr int GENERATION_CYCLE = 255 + GENERATION_DELTA;
static constexpr int GENERATION_MASK = (0xFF << GENERATION_BITS) & 0xFF;

/// TTEntry struct is the transposition table entry, inspired by Stockfish design:
///
/// key16               16 bit  (for verification)
/// value               16 bit
/// eval                16 bit  
/// depth               8 bit
/// bound type & age    8 bit
/// move               16 bit
///
/// Total: 10 bytes when TT_MOVE_ENABLE, otherwise 8 bytes

struct TTEntry
{
    TTEntry() = default;

    Value value() const noexcept { return static_cast<Value>(value16); }
    Value eval() const noexcept { return static_cast<Value>(eval16); }

    Depth depth() const noexcept
    {
        return static_cast<Depth>(depth8) + DEPTH_OFFSET;
    }

    Bound bound() const noexcept { return static_cast<Bound>(genBound8 & 0x3); }

#ifdef TT_MOVE_ENABLE
    Move tt_move() const noexcept { return static_cast<Move>(ttMove); }
#endif // TT_MOVE_ENABLE

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    uint8_t age() const noexcept { return (genBound8 >> 2) & 0x3F; }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    // Save entry to TT with better replacement strategy (Stockfish-inspired)
    void save(Key k, Value v, Value e, bool pv, Bound b, Depth d, Move m, uint8_t generation8);
    
    // Check if entry is occupied (non-zero depth or key)
    bool is_occupied() const noexcept { return depth8 != 0 || key16_ != 0; }
    
    // Get stored key (for verification)
    uint16_t key16() const noexcept { return key16_; }
    
    // Relative age for replacement strategy
    uint8_t relative_age(uint8_t generation8) const noexcept {
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        // Calculate age difference, handling wraparound
        return ((generation8 - age()) / GENERATION_DELTA) & 0x3F;
#else
        return 0;
#endif
    }

private:
    friend class TranspositionTable;

    uint16_t key16_ {0};    // Store 16 bits of key for verification
    int16_t value16 {0};
    int16_t eval16 {0};
    uint8_t depth8 {0};
    uint8_t genBound8 {0};  // 2 bits bound + 6 bits age/generation
#ifdef TT_MOVE_ENABLE
    uint16_t ttMove {MOVE_NONE};
#endif // TT_MOVE_ENABLE
};

class TranspositionTable
{
public:
    static bool search(Key key, TTEntry &tte);

    static Value probe(Key key, Depth depth, Bound &type, Value &eval
#ifdef TT_MOVE_ENABLE
                       ,
                       Move &ttMove
#endif // TT_MOVE_ENABLE
    );

    static int save(Value value, Value staticEval, Depth depth, Bound type, Key key
#ifdef TT_MOVE_ENABLE
                    ,
                    const Move &ttMove
#endif // TT_MOVE_ENABLE
    );

    static void clear();
    static void new_search();  // Advance generation for new search
    static uint8_t generation();  // Get current generation

    static void prefetch(Key key);

private:
    friend struct TTEntry;
};

extern HashMap<Key, TTEntry> TT;

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
extern uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

#endif // TRANSPOSITION_TABLE_ENABLE

#endif // #ifndef TT_H_INCLUDED
