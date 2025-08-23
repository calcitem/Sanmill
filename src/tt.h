// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tt.h

#ifndef TT_H_INCLUDED
#define TT_H_INCLUDED

#include "hashmap.h"
#include "types.h"

using CTSL::HashMap;

#ifdef TRANSPOSITION_TABLE_ENABLE

/// TTEntry struct is the transposition table entry, inspired by Stockfish design:
///
/// value               16 bit
/// eval                16 bit  
/// depth               8 bit
/// bound type & age    8 bit
/// move               16 bit
///
/// Total: 8 bytes when TT_MOVE_ENABLE, otherwise 6 bytes

struct TTEntry
{
    TTEntry() { }

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

    // Save entry to TT with better replacement strategy
    void save(Key k, Value v, Value e, bool pv, Bound b, Depth d, Move m, uint8_t generation8);
    
    // Check if entry is occupied (non-zero depth)
    bool is_occupied() const noexcept { return depth8 != 0; }

private:
    friend class TranspositionTable;

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
