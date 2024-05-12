// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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
    TTEntry()
        : data(0)
    { }

    inline Value value() const noexcept
    {
        return static_cast<Value>((data >> 0) & 0xFF);
    }
    inline Depth depth() const noexcept
    {
        return static_cast<Depth>((data >> 8) & 0xFF) + DEPTH_OFFSET;
    }
    inline Bound bound() const noexcept
    {
        return static_cast<Bound>((data >> 16) & 0xFF);
    }
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    inline uint8_t age() const noexcept
    {
        return static_cast<uint8_t>((data >> 24) & 0xFF);
    }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
#ifdef TT_MOVE_ENABLE
    Move tt_move() const noexcept { return (Move)(ttMove); }
#endif // TT_MOVE_ENABLE

private:
    friend class TranspositionTable;

    uint32_t data;
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
