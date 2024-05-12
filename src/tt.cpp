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

#include "tt.h"
#include <limits>

#ifdef TRANSPOSITION_TABLE_ENABLE

static constexpr int TRANSPOSITION_TABLE_SIZE = 0x1000000;
HashMap<Key, TTEntry> TT(TRANSPOSITION_TABLE_SIZE);

Value TranspositionTable::probe(Key key, Depth depth, Value alpha, Value beta,
                                Bound &type
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

    if (depth > tte.depth()) {
        goto out;
    }

    type = tte.bound();

    switch (tte.bound()) {
    case BOUND_EXACT:
        return tte.value();
    case BOUND_UPPER:
        if (tte.value8 <= alpha) {
            return alpha;
        }
        break;
    case BOUND_LOWER:
        if (tte.value() >= beta) {
            return beta;
        }
        break;
    case BOUND_NONE:
        break;
    }

out:

#ifdef TT_MOVE_ENABLE
    ttMove = tte.ttMove;
#endif // TT_MOVE_ENABLE

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
        if (tte.genBound8 != BOUND_NONE && tte.depth() > depth) {
            return -1;
        }
    }

    tte.value8 = value;
    tte.depth8 = depth;
    tte.genBound8 = type;

#ifdef TT_MOVE_ENABLE
    tte.ttMove = ttMove;
#endif // TT_MOVE_ENABLE

    TT.insert(key, tte);

    return 0;
}

Bound TranspositionTable::boundType(Value value, Value alpha, Value beta)
{
    if (value <= alpha)
        return BOUND_UPPER;
    if (value >= beta)
        return BOUND_LOWER;

    return BOUND_EXACT;
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
