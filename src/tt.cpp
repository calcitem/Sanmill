// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tt.cpp

#include "tt.h"
#include <limits>

#ifdef TRANSPOSITION_TABLE_ENABLE

static constexpr int TRANSPOSITION_TABLE_SIZE = 0x1000000;
HashMap<Key, TTEntry> TT(TRANSPOSITION_TABLE_SIZE);

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

Value TranspositionTable::probe(Key key, Depth depth, Bound &type
#ifdef TT_MOVE_ENABLE
                                ,
                                Move &ttMove
#endif // TT_MOVE_ENABLE
)
{
    TTEntry tte {};

    if (!TT.find(key, tte)) {
        return VALUE_UNKNOWN;
    }

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY
    if (tte.bound() != BOUND_EXACT) {
#endif
        if (tte.age8 != transpositionTableAge) {
            return VALUE_UNKNOWN;
        }
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY
    }
#endif
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    if (tte.depth() >= depth) {
        type = tte.bound();
#ifdef TT_MOVE_ENABLE
        ttMove = tte.tt_move();
#endif
        return tte.value();
    }

    return VALUE_UNKNOWN;
}

bool TranspositionTable::search(Key key, TTEntry &tte)
{
    return TT.find(key, tte);
}

void TranspositionTable::prefetch(Key key)
{
    TT.prefetchValue(key);
}

int TranspositionTable::save(Value value, Depth depth, Bound type, Key key
#ifdef TT_MOVE_ENABLE
                             ,
                             const Move &ttMove
#endif // TT_MOVE_ENABLE
)
{
    TTEntry tte {};

    if (search(key, tte)) {
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        if (tte.age8 == transpositionTableAge) {
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
            if (tte.genBound8 != BOUND_NONE && tte.depth() > depth) {
                return -1;
            }
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
    }

    tte.value8 = static_cast<int8_t>(value);
    tte.depth8 = static_cast<int8_t>(depth - DEPTH_OFFSET);
    tte.genBound8 = static_cast<uint8_t>(type);

#ifdef TT_MOVE_ENABLE
    tte.ttMove = ttMove;
#endif // TT_MOVE_ENABLE

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    tte.age8 = transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    TT.insert(key, tte);

    return 0;
}

void TranspositionTable::clear()
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    if (transpositionTableAge == std::numeric_limits<uint8_t>::max()) {
        debugPrintf("Clean TT\n");
        TT.clear();
        transpositionTableAge = 0;
    } else {
        transpositionTableAge++;
    }
#else
    TT.clear();
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
}

#endif /* TRANSPOSITION_TABLE_ENABLE */
