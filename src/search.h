/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#include "stack.h"
#include "tt.h"
#include "endgame.h"
#include "movepick.h"
#include "types.h"

#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

class AIAlgorithm;
class Node;
class Position;
class MovePicker;

using namespace std;
using namespace CTSL;

namespace Search
{
/// Threshold used for countermoves based pruning
constexpr int CounterMovePruneThreshold = 0;


/// Stack struct keeps track of the information we need to remember from nodes
/// shallower and deeper in the tree during the search. Each search thread has
/// its own array of Stack objects, indexed by the current ply.

struct Stack
{
    Move *pv;
    PieceToHistory *continuationHistory;
    int ply;
    Move currentMove;
    Move excludedMove;
    Move killers[2];
    Value staticEval;
    int statScore;
    int moveCount;
};


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
    { // Sort in descending order
        return m.score != score ? m.score < score
            : m.previousScore < previousScore;
    }

    Value score = -VALUE_INFINITE;
    Value previousScore = -VALUE_INFINITE;
    int selDepth = 0;
    int tbRank = 0;
    int bestMoveCount = 0;
    Value tbScore;
    std::vector<Move> pv;
};

typedef std::vector<RootMove> RootMoves;


/// LimitsType struct stores information sent by GUI about available time to
/// search the current move, maximum depth/time, or if we are in analysis mode.

struct LimitsType
{
    LimitsType()
    { 
        // Init explicitly due to broken value-initialization of non POD in MSVC
        time[WHITE] = time[BLACK] = inc[WHITE] = inc[BLACK] = npmsec = movetime = TimePoint(0);
        movestogo = depth = mate = perft = infinite = 0;
        nodes = 0;
    }

    bool use_time_management() const
    {
        return !(mate | movetime | depth | nodes | perft | infinite);
    }

    std::vector<Move> searchmoves;
    TimePoint time[COLOR_NB], inc[COLOR_NB], npmsec, movetime, startTime;
    int movestogo, depth, mate, perft, infinite;
    int64_t nodes;
};

extern LimitsType Limits;

void init();
void clear();

} // namespace Search


#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<Key> moveHistory;
#endif

#endif // #ifndef SEARCH_H_INCLUDED
