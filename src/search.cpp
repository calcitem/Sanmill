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

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>   // For std::memset
#include <iostream>
#include <sstream>

#include "evaluate.h"
#include "misc.h"
#include "movegen.h"
#include "movepick.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"

#include "endgame.h"
#include "types.h"
#include "option.h"

using std::string;
using Eval::evaluate;
using namespace Search;

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove);

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth, Value alpha, Value beta, Move &bestMove);

namespace
{

// Different node types, used as a template parameter
enum NodeType
{
    NonPV, PV
};

} // namespace


/// Search::init() is called at startup to initialize various lookup tables

void Search::init()
{
    return;
}


/// Search::clear() resets search state to its initial value

void Search::clear()
{
    Threads.main()->wait_for_search_finished();

#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.clear();
#endif
    Threads.clear();
}

#ifdef THREEFOLD_REPETITION
int nRepetition;
#endif // THREEFOLD_REPETITION

/// Thread::search() is the main iterative deepening loop. It calls search()
/// repeatedly with increasing depth until the allocated thinking time has been
/// consumed, the user stops the search, or the maximum search depth is reached.

int Thread::search()
{
    Sanmill::Stack<Position> ss;

    Value value = VALUE_ZERO;

    Depth d = adjustDepth();
    adjustedDepth = d;

    time_t time0 = time(nullptr);
    srand(static_cast<unsigned int>(time0));

#ifdef TIME_STAT
    auto timeStart = chrono::steady_clock::now();
    chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    chrono::steady_clock::time_point cycleEnd;
#endif

#ifdef THREEFOLD_REPETITION
    if (rootPos->get_phase() == Phase::moving) {
        Key key = rootPos->key();

        for (auto i : moveHistory) {
            if (key == i)
            {
                nRepetition++;
                if (nRepetition == 3) {
                    nRepetition = 0;
                    return 3;
                }
            }
        }

#if defined(UCI_DO_BEST_MOVE) || defined(QT_GUI_LIB)
        moveHistory.push_back(key);
#endif // UCI_DO_BEST_MOVE

        //sync_cout << "moveHistory Size = " << moveHistory.size();
        //std::cout << sync_endl;
        assert(moveHistory.size() < 256);
    }

    if (rootPos->get_phase() == Phase::placing) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    MoveList<LEGAL>::shuffle();

#ifndef MTDF_AI
    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;
#endif

    if (gameOptions.getIDSEnabled()) {
        loggerDebug("IDS: ");

        Depth depthBegin = 2;
        Value lastValue = VALUE_ZERO;

        loggerDebug("\n==============================\n");
        loggerDebug("==============================\n");
        loggerDebug("==============================\n");

        for (Depth i = depthBegin; i < d; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TranspositionTable::clear();
#endif
#endif

#ifdef MTDF_AI
            value = MTDF(rootPos, ss, value, i, originDepth, bestMove);
#else
            value = search(rootPos, ss, i, originDepth, alpha, beta, bestMove);
#endif

            loggerDebug("%d(%d) ", value, value - lastValue);

            lastValue = value;
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        loggerDebug("\nIDS Time: %llds\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

#ifndef MTDF_AI
    if (gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }
#endif

    originDepth = d;

#ifdef MTDF_AI
    value = MTDF(rootPos, ss, value, d, originDepth, bestMove);
#else
    value = search(rootPos, ss, d, originDepth, alpha, beta, bestMove);
#endif

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}


///////////////////////////////////////////////////////////////////////////////

extern ThreadPool Threads;

vector<Key> moveHistory;

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    Depth epsilon;

#ifdef TT_MOVE_ENABLE
    Move ttMove = MOVE_NONE;
#endif // TT_MOVE_ENABLE

#if defined (TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    Key posKey = pos->key();
#endif

#ifdef ENDGAME_LEARNING
    Endgame endgame;

    if (gameOptions.getLearnEndgameEnabled() &&
        Thread::findEndgameHash(posKey, endgame)) {
        switch (endgame.type) {
        case ENDGAME_PLAYER_BLACK_WIN:
            bestValue = VALUE_MATE;
            bestValue += depth;
            break;
        case ENDGAME_PLAYER_WHITE_WIN:
            bestValue = -VALUE_MATE;
            bestValue -= depth;
            break;
        default:
            break;
        }

        return bestValue;
    }
#endif /* ENDGAME_LEARNING */

#ifdef TRANSPOSITION_TABLE_ENABLE
    Bound type = BOUND_NONE;

    Value probeVal = TranspositionTable::probe(posKey, depth, alpha, beta, type
#ifdef TT_MOVE_ENABLE
                                               , ttMove
#endif // TT_MOVE_ENABLE                                     
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        Threads.main()->ttHitCount++;
#endif

        bestValue = probeVal;

#if 0
        // TODO: Need adjust value?
        if (position->turn == BLACK)
            bestValue += tte.depth - depth;
        else
            bestValue -= tte.depth - depth;
#endif

#ifdef TT_MOVE_ENABLE
        //         if (ttMove != MOVE_NONE) {
        //             bestMove = ttMove;
        //         }
#endif // TT_MOVE_ENABLE

        return bestValue;
    }
#ifdef TRANSPOSITION_TABLE_DEBUG
    else {
        Threads.main()->ttMissCount++;
    }
#endif

    //hashMapMutex.unlock();
#endif /* TRANSPOSITION_TABLE_ENABLE */

#if 0
    if (position->phase == Phase::placing && depth == 1 && pos->pieceToRemoveCount > 0) {
        depth--;
    }
#endif

    // Check for aborted search
    // TODO: and immediate draw
    if (unlikely(pos->phase == Phase::gameOver) ||   // TODO: Deal with hash
        depth <= 0 ||
        Threads.stop.load(std::memory_order_relaxed)) {
        bestValue = Eval::evaluate(*pos);

        // For win quickly
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::save(bestValue,
                                 depth,
                                 BOUND_EXACT,
                                 posKey
#ifdef TT_MOVE_ENABLE
                                 , MOVE_NONE
#endif // TT_MOVE_ENABLE
        );
#endif

        return bestValue;
    }

    MovePicker mp(*pos);
    Move nextMove = mp.next_move();
    int moveCount = mp.move_count();

    if (moveCount == 1 && depth == originDepth) {
        bestMove = nextMove;
        bestValue = VALUE_UNIQUE;
        return bestValue;
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifndef DISABLE_PREFETCH
    for (int i = 0; i < moveCount; i++) {
        TranspositionTable::prefetch(pos->key_after(mp.moves[i].move));
    }

#ifdef PREFETCH_DEBUG
    if (posKey << 8 >> 8 == 0x0) {
        int pause = 1;
    }
#endif // PREFETCH_DEBUG
#endif // !DISABLE_PREFETCH
#endif // TRANSPOSITION_TABLE_ENABLE

    for (int i = 0; i < moveCount; i++) {
        ss.push(*(pos));
        Color before = pos->sideToMove;
        Move move = mp.moves[i].move;
        pos->do_move(move);
        Color after = pos->sideToMove;

        if (gameOptions.getDepthExtension() == true && moveCount == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

#ifdef PVS_AI
        if (i == 0) {
            if (after != before) {
                value = -search(depth - 1 + epsilon, -beta, -alpha);
            } else {
                value = search(depth - 1 + epsilon, alpha, beta);
            }
        } else {
            if (after != before) {
                value = -search(depth - 1 + epsilon, -alpha - VALUE_PVS_WINDOW, -alpha);

                if (value > alpha && value < beta) {
                    value = -search(depth - 1 + epsilon, -beta, -alpha);
                    //assert(value >= alpha && value <= beta);
                }
            } else {
                value = search(depth - 1 + epsilon, alpha, alpha + VALUE_PVS_WINDOW);

                if (value > alpha && value < beta) {
                    value = search(depth - 1 + epsilon, alpha, beta);
                    //assert(value >= alpha && value <= beta);
                }
            }
        }
#else
        if (after != before) {
            value = -search(pos, ss, depth - 1 + epsilon, originDepth, -beta, -alpha, bestMove);
        } else {
            value = search(pos, ss, depth - 1 + epsilon, originDepth, alpha, beta, bestMove);
        }
#endif // PVS_AI

        pos->undo_move(ss);

        assert(value > -VALUE_INFINITE && value < VALUE_INFINITE);

        // Check for a new best move
        // Finished searching the move. If a stop occurred, the return value of
        // the search cannot be trusted, and we return immediately without
        // updating best move, PV and TT.
        if (Threads.stop.load(std::memory_order_relaxed))
            return VALUE_ZERO;

        if (value >= bestValue) {
            bestValue = value;

            if (value > alpha) {
                if (depth == originDepth) {
                    bestMove = move;
                }

                break;
            }
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
    TranspositionTable::save(bestValue,
                             depth,
                             bestValue >= beta ? BOUND_LOWER :
                             BOUND_UPPER,
                             posKey
#ifdef TT_MOVE_ENABLE
                             , bestMove
#endif // TT_MOVE_ENABLE
    );
#endif /* TRANSPOSITION_TABLE_ENABLE */

    assert(bestValue > -VALUE_INFINITE && bestValue < VALUE_INFINITE);

    return bestValue;
}

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove)
{
    Value g = firstguess;
    Value lowerbound = -VALUE_INFINITE;
    Value upperbound = VALUE_INFINITE;
    Value beta;

    while (lowerbound < upperbound) {
        if (g == lowerbound) {
            beta = g + VALUE_MTDF_WINDOW;
        } else {
            beta = g;
        }

        g = search(pos, ss, depth, originDepth, beta - VALUE_MTDF_WINDOW, beta, bestMove);

        if (g < beta) {
            upperbound = g;    // fail low
        } else {
            lowerbound = g;    // fail high
        }
    }

    return g;
}
