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

#ifndef SEARCH_H
#define SEARCH_H

#include "config.h"

#include <mutex>
#include <string>
#include <array>

#include "stack.h"
#include "tt.h"
#include "hashmap.h"
#include "endgame.h"
#include "types.h"
#include "misc.h"

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
    int ply;
    Move currentMove;
    Move excludedMove;
    Move killers[2];
    Value staticEval;
    int statScore;
    int moveCount;
    bool inCheck;
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
    { // Init explicitly due to broken value-initialization of non POD in MSVC
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
}

class AIAlgorithm
{
public:
#ifdef TIME_STAT
    TimePoint sortTime { 0 };
#endif
#ifdef CYCLE_STAT
    stopwatch::rdtscp_clock::time_point sortCycle;
    stopwatch::timer::duration sortCycle { 0 };
    stopwatch::timer::period sortCycle;
#endif

public:
    AIAlgorithm();
    ~AIAlgorithm();

    void setPosition(Position *p);

    void quit()
    {
        loggerDebug("Timeout\n");
        requiredQuit = true;
#ifdef HOSTORY_HEURISTIC
        movePicker->clearHistoryScore();
#endif
    }

#ifdef ALPHABETA_AI
    int search();
    const char *nextMove();
#endif // ALPHABETA_AI

    void stashPosition();

    void do_move(Move move);

    void undo_move();

#ifdef TRANSPOSITION_TABLE_ENABLE
    void clearTT();
#endif

#ifdef ENDGAME_LEARNING
    bool findEndgameHash(key_t key, Endgame &endgame);
    static int recordEndgameHash(key_t key, const Endgame &endgame);
    void clearEndgameHashMap();
    static void recordEndgameHashMapToFile();
    static void loadEndgameFileToHashMap();
#endif // ENDGAME_LEARNING

public: /* TODO: Move to private or protected */

#ifdef EVALUATE_ENABLE
    Value evaluate();

#ifdef EVALUATE_MATERIAL
    Value evaluateMaterial();
#endif
#ifdef EVALUATE_SPACE
    Value evaluateSpace();
#endif
#ifdef EVALUATE_MOBILITY
    Value evaluateMobility();
#endif
#ifdef EVALUATE_TEMPO
    Value evaluateTempo();
#endif
#ifdef EVALUATE_THREAT
    Value evaluateThreat();
#endif
#ifdef EVALUATE_SHAPE
    Value evaluateShape();
#endif
#ifdef EVALUATE_MOTIF
    Value evaluateMotif();
#endif
#endif /* EVALUATE_ENABLE */

    Value search(Depth depth, Value alpha, Value beta);

    Value MTDF(Value firstguess, Depth depth);

public:
    const char *moveToCommand(Move move);
protected:
    Depth changeDepth();
       
public:
    MovePicker *movePicker { nullptr };

    Value bestvalue { VALUE_ZERO };
    Value lastvalue { VALUE_ZERO };

    Depth originDepth{ 0 };

private:
    Position *pos { nullptr };

    Stack<Position> positionStack;

    bool requiredQuit {false};

    Move bestMove { MOVE_NONE };

private:
    char cmdline[64] {};

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
public:
    size_t tteCount{ 0 };
    size_t ttHitCount{ 0 };
    size_t ttMissCount{ 0 };
    size_t ttInsertNewCount{ 0 };
    size_t ttAddrHitCount{ 0 };
    size_t ttReplaceCozDepthCount{ 0 };
    size_t ttReplaceCozHashCount{ 0 };
#endif
#endif
};

#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<Key> moveHistory;
#endif

#endif /* SEARCH_H */
