/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef SEARCH_H_INCLUDED
#define SEARCH_H_INCLUDED

#include <vector>
#include "misc.h"
#include "movepick.h"
#include "types.h"
#include "endgame.h"

#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

using namespace std;

namespace Search
{

/// RootMove struct is used for moves at the root of the tree. For each root move
/// we store a score and a PV (really a refutation in the case of moves which
/// fail low). Score is normally set at -VALUE_INFINITE for all non-pv moves.

struct RootMove
{
    explicit RootMove(Move m) : pv(1, m)
    {
    }

    bool operator==(const Move &m) const
    {
        return pv[0] == m;
    }

    bool operator<(const RootMove &m) const
    {
        // Sort in descending order
        return m.score != score ? m.score < score
            : m.previousScore < previousScore;
    }

    Value score = -VALUE_INFINITE;
    Value previousScore = -VALUE_INFINITE;
    int selDepth = 0;
    int tbRank = 0;
    Value tbScore;
    std::vector<Move> pv;
};

typedef std::vector<RootMove> RootMoves;


void init() noexcept;
void clear();

} // namespace Search


#include "tt.h"

extern vector<Key> posKeyHistory;

#endif // #ifndef SEARCH_H_INCLUDED
