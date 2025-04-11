// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tt.h

#ifndef TT_H_INCLUDED
#define TT_H_INCLUDED

#include "hashmap.h"
#include "types.h"

using CTSL::HashMap;

#ifdef TRANSPOSITION_TABLE_ENABLE

/// TTEntry struct is the 4 bytes transposition table entry, defined as below:
///
/// value               8 bit
/// depth               8 bit
/// bound type          8 bit
/// age                 8 bit

struct TTEntry
{
    TTEntry() { }

    Value value() const noexcept { return static_cast<Value>(value8); }

    Depth depth() const noexcept
    {
        return static_cast<Depth>(depth8) + DEPTH_OFFSET;
    }

    Bound bound() const noexcept { return static_cast<Bound>(genBound8); }

#ifdef TT_MOVE_ENABLE
    Move tt_move() const noexcept { return (Move)(ttMove); }
#endif // TT_MOVE_ENABLE

private:
    friend class TranspositionTable;

    int8_t value8 {0};
    int8_t depth8 {0};
    uint8_t genBound8 {0};
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    uint8_t age8 {0};
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
#ifdef TT_MOVE_ENABLE
    Move ttMove {MOVE_NONE};
#endif // TT_MOVE_ENABLE
};

class TranspositionTable
{
public:
    static bool search(Key key, TTEntry &tte);

    static Value probe(Key key, Depth depth, Bound &type
#ifdef TT_MOVE_ENABLE
                       ,
                       Move &ttMove
#endif // TT_MOVE_ENABLE
    );

    static int save(Value value, Depth depth, Bound type, Key key
#ifdef TT_MOVE_ENABLE
                    ,
                    const Move &ttMove
#endif // TT_MOVE_ENABLE
    );

    static void clear();

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
