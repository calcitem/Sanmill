// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

    [[nodiscard]] Value value() const noexcept
    {
        return static_cast<Value>(value8);
    }

    [[nodiscard]] Depth depth() const noexcept
    {
        return static_cast<Depth>(depth8) + DEPTH_OFFSET;
    }

    [[nodiscard]] Bound bound() const noexcept
    {
        return static_cast<Bound>(genBound8);
    }

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

    static Value probe(Key key, Depth depth, Value alpha, Value beta,
                       Bound &type
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

    static Bound boundType(Value value, Value alpha, Value beta);

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
