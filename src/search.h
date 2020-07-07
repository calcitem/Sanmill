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
    int search(Depth depth);
    const char *nextMove();
#endif // ALPHABETA_AI

    void stashPosition();

    void do_move(Move move);

    void undoMove();

    void do_null_move();
    void undo_null_move();

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
    Depth changeDepth(Depth origDepth);
       
public:
    MovePicker *movePicker { nullptr };

    Value bestvalue { VALUE_ZERO };
    Value lastvalue { VALUE_ZERO };

    Depth originDepth{ 0 };

private:
    Position *pos { nullptr };
    Position *position { nullptr };

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
