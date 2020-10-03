/*
  Sanmill, a mill state playing engine derived from NineChess 1.5
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
#include "timeman.h"
#include "tt.h"
#include "uci.h"

#include "endgame.h"
#include "types.h"
#include "option.h"

namespace Search
{
LimitsType Limits;
}

namespace Tablebases
{
int Cardinality;
bool RootInTB;
bool UseRule50;
Depth ProbeDepth;
}

namespace TB = Tablebases;

using std::string;
using Eval::evaluate;
using namespace Search;

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove);

namespace
{

// Different node types, used as a template parameter
enum NodeType
{
    NonPV, PV
};

// Skill structure is used to implement strength limit
struct Skill
{
    explicit Skill(int l) : level(l)
    {
    }
    bool enabled() const
    {
        return level < 20;
    }
    bool time_to_pick(Depth depth) const
    {
        return depth == 1 + level;
    }
    Move pick_best(size_t multiPV);

    int level;
    Move best = MOVE_NONE;
};

// Breadcrumbs are used to mark nodes as being searched by a given thread
struct Breadcrumb
{
    std::atomic<Thread *> thread;
    std::atomic<Key> key;
};
std::array<Breadcrumb, 1024> breadcrumbs;

// ThreadHolding structure keeps track of which thread left breadcrumbs at the given
// node for potential reductions. A free node will be marked upon entering the moves
// loop by the constructor, and unmarked upon leaving that loop by the destructor.
struct ThreadHolding
{
    explicit ThreadHolding(Thread *thisThread, Key posKey, int ply)
    {
        location = ply < 8 ? &breadcrumbs[posKey & (breadcrumbs.size() - 1)] : nullptr;
        otherThread = false;
        owning = false;
        if (location) {
            // See if another already marked this location, if not, mark it ourselves
            Thread *tmp = (*location).thread.load(std::memory_order_relaxed);
            if (tmp == nullptr) {
                (*location).thread.store(thisThread, std::memory_order_relaxed);
                (*location).key.store(posKey, std::memory_order_relaxed);
                owning = true;
            } else if (tmp != thisThread
                       && (*location).key.load(std::memory_order_relaxed) == posKey)
                otherThread = true;
        }
    }

    ~ThreadHolding()
    {
        if (owning) // Free the marked location
            (*location).thread.store(nullptr, std::memory_order_relaxed);
    }

    bool marked()
    {
        return otherThread;
    }

private:
    Breadcrumb *location;
    bool otherThread, owning;
};

template <NodeType NT>
Value search(Position &pos, Stack *ss, Value alpha, Value beta, Depth depth, bool cutNode);

// perft() is our utility to verify move generation. All the leaf nodes up
// to the given depth are generated and counted, and the sum is returned.
template<bool Root>
uint64_t perft(Position &pos, Depth depth)
{
    StateInfo st;
    uint64_t cnt, nodes = 0;
    const bool leaf = (depth == 2);

    for (const auto &m : MoveList<LEGAL>(pos)) {
        if (Root && depth <= 1)
            cnt = 1, nodes++;
        else {
            pos.do_move(m, st);
            cnt = leaf ? MoveList<LEGAL>(pos).size() : perft<false>(pos, depth - 1);
            nodes += cnt;
            pos.undo_move(m);
        }
        if (Root)
            sync_cout << UCI::move(m) << ": " << cnt << sync_endl;
    }
    return nodes;
}

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

    Time.availableNodes = 0;
    TT.clear();
    Threads.clear();
}


/// MainThread::search() is started when the program receives the UCI 'go'
/// command. It searches from the root position and outputs the "bestmove".

int MainThread::search()
{
    if (Limits.perft) {
        nodes = perft<true>(*rootPos, Limits.perft);
        sync_cout << "\nNodes searched: " << nodes << "\n" << sync_endl;
        return 0;
    }

    Color us = rootPos->side_to_move();
    Time.init(Limits, us, rootPos->game_ply());
    //TT.new_search();

    if (rootMoves.empty()) {
        rootMoves.emplace_back(MOVE_NONE);
        sync_cout << "info depth 0 score "
            << UCI::value(rootPos->get_phase() == PHASE_GAMEOVER ? -VALUE_MATE : VALUE_DRAW) // TODO
            << sync_endl;
    } else {
        for (Thread *th : Threads) {
            th->bestMoveChanges = 0;
            if (th != this)
                th->start_searching();
        }

        Thread::search(); // Let's start searching!
    }

    // When we reach the maximum depth, we can arrive here without a raise of
    // Threads.stop. However, if we are pondering or in an infinite search,
    // the UCI protocol states that we shouldn't print the best move before the
    // GUI sends a "stop" or "ponderhit" command. We therefore simply wait here
    // until the GUI sends one of those commands.

    while (!Threads.stop && (ponder || Limits.infinite)) {
    } // Busy wait for a stop or a ponder reset

   // Stop the threads if not already stopped (also raise the stop if
   // "ponderhit" just reset Threads.ponder).
    Threads.stop = true;

    // Wait until all threads have finished
    for (Thread *th : Threads)
        if (th != this)
            th->wait_for_search_finished();

    // When playing in 'nodes as time' mode, subtract the searched nodes from
    // the available ones before exiting.
    if (Limits.npmsec)
        Time.availableNodes += Limits.inc[us] - Threads.nodes_searched();

    Thread *bestThread = this;

    // Check if there are threads with a better score than main thread
    if (Options["MultiPV"] == 1
        && !Limits.depth
        && !(Skill((int)Options["Skill Level"]).enabled() || Options["UCI_LimitStrength"])
        && rootMoves[0].pv[0] != MOVE_NONE) {
        std::map<Move, int64_t> votes;
        Value minScore = this->rootMoves[0].score;

        // Find minimum score
        for (Thread *th : Threads)
            minScore = std::min(minScore, th->rootMoves[0].score);

        // Vote according to score and depth, and select the best thread
        for (Thread *th : Threads) {
            votes[th->rootMoves[0].pv[0]] +=
                (th->rootMoves[0].score - minScore + 14) * int(th->completedDepth);

            if (abs(bestThread->rootMoves[0].score) >= VALUE_TB_WIN_IN_MAX_PLY) {
                // Make sure we pick the shortest mate / TB conversion or stave off mate the longest
                if (th->rootMoves[0].score > bestThread->rootMoves[0].score)
                    bestThread = th;
            } else if (th->rootMoves[0].score >= VALUE_TB_WIN_IN_MAX_PLY
                       || (th->rootMoves[0].score > VALUE_TB_LOSS_IN_MAX_PLY
                           && votes[th->rootMoves[0].pv[0]] > votes[bestThread->rootMoves[0].pv[0]]))
                bestThread = th;
        }
    }

    bestPreviousScore = bestThread->rootMoves[0].score;

    // Send again PV info if we have a new best thread
    if (bestThread != this)
        sync_cout << UCI::pv(bestThread->rootPos, bestThread->completedDepth, -VALUE_INFINITE, VALUE_INFINITE) << sync_endl;

    sync_cout << "bestmove " << UCI::move(bestThread->rootMoves[0].pv[0]);

    if (bestThread->rootMoves[0].pv.size() > 1 /* || bestThread->rootMoves[0].extract_ponder_from_tt(rootPos) */)
        std::cout << " ponder " << UCI::move(bestThread->rootMoves[0].pv[1]);

    std::cout << sync_endl;

    return 0;
}


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
    static int nRepetition = 0;

    if (rootPos->get_phase() == PHASE_MOVING) {
        Key key = rootPos->key();

        if (std::find(moveHistory.begin(), moveHistory.end(), key) != moveHistory.end()) {
            nRepetition++;
            if (nRepetition == 3) {
                nRepetition = 0;
                return 3;
            }
        } else {
            moveHistory.push_back(key);
        }
    }

    if (rootPos->get_phase() == PHASE_PLACING) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    MoveList<LEGAL>::shuffle();

    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;

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
            value = search(pos, ss, i, originDepth, alpha, beta, bestMove);
#endif

            loggerDebug("%d(%d) ", value, value - lastValue);

            lastValue = value;
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        loggerDebug("\nIDS Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    if (gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    originDepth = d;

#ifdef MTDF_AI
    value = MTDF(rootPos, ss, value, d, originDepth, bestMove);
#else
    value = search(pos, ss, d, originDepth, alpha, beta, bestMove);
#endif

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}


namespace
{

// search<>() is the main search function for both PV and non-PV nodes

template <NodeType NT>
Value search(Position &pos, Stack *ss, Value alpha, Value beta, Depth depth, bool cutNode)
{
    //return MTDF(rootPos, ss, value, i, adjustedDepth, bestMove);    // TODO;
    return VALUE_DRAW;
}


// When playing with strength handicap, choose best move among a set of RootMoves
// using a statistical rule dependent on 'level'. Idea by Heinz van Saanen.

Move Skill::pick_best(size_t multiPV)
{

    const RootMoves &rootMoves = Threads.main()->rootMoves;
    static PRNG rng(now()); // PRNG sequence should be non-deterministic

    // RootMoves are already sorted by score in descending order
    Value topScore = rootMoves[0].score;
    //int delta = std::min(topScore - rootMoves[multiPV - 1].score, PawnValueMg);
    int delta = std::min(topScore - rootMoves[multiPV - 1].score, StoneValue);
    int weakness = 120 - 2 * level;
    int maxScore = -VALUE_INFINITE;

    // Choose best move. For each move score we add two terms, both dependent on
    // weakness. One is deterministic and bigger for weaker levels, and one is
    // random. Then we choose the move with the resulting highest score.
    for (size_t i = 0; i < multiPV; ++i) {
        // This is our magic formula
        int push = (weakness * int(topScore - rootMoves[i].score)
                    + delta * (rng.rand<unsigned>() % weakness)) / 128;

        if (rootMoves[i].score + push >= maxScore) {
            maxScore = rootMoves[i].score + push;
            best = rootMoves[i].pv[0];
        }
    }

    return best;
}

} // namespace

/// MainThread::check_time() is used to print debug info and, more importantly,
/// to detect when we are out of available time and thus stop the search.

void MainThread::check_time()
{
    if (--callsCnt > 0)
        return;

    // When using nodes, ensure checking rate is not lower than 0.1% of nodes
    callsCnt = Limits.nodes ? std::min(1024, int(Limits.nodes / 1024)) : 1024;

    static TimePoint lastInfoTime = now();

    TimePoint elapsed = Time.elapsed();
    TimePoint tick = Limits.startTime + elapsed;

    if (tick - lastInfoTime >= 1000) {
        lastInfoTime = tick;
        dbg_print();
    }

    // We should not stop pondering until told so by the GUI
    if (ponder)
        return;

    if ((Limits.use_time_management() && (elapsed > Time.maximum() - 10 || stopOnPonderhit))
        || (Limits.movetime && elapsed >= Limits.movetime)
        || (Limits.nodes && Threads.nodes_searched() >= (uint64_t)Limits.nodes))
        Threads.stop = true;
}


/// UCI::pv() formats PV information according to the UCI protocol. UCI requires
/// that all (if any) unsearched PV lines are sent using a previous search score.

string UCI::pv(Position *pos, Depth depth, Value alpha, Value beta)
{

    std::stringstream ss;
    TimePoint elapsed = Time.elapsed() + 1;
    const RootMoves &rootMoves = pos->this_thread()->rootMoves;
    size_t pvIdx = pos->this_thread()->pvIdx;
    size_t multiPV = std::min((size_t)Options["MultiPV"], rootMoves.size());
    uint64_t nodesSearched = Threads.nodes_searched();
    uint64_t tbHits = Threads.tb_hits() + (TB::RootInTB ? rootMoves.size() : 0);

    for (size_t i = 0; i < multiPV; ++i) {
        bool updated = rootMoves[i].score != -VALUE_INFINITE;

        if (depth == 1 && !updated)
            continue;

        Depth d = updated ? depth : depth - 1;
        Value v = updated ? rootMoves[i].score : rootMoves[i].previousScore;

        bool tb = TB::RootInTB && abs(v) < VALUE_MATE_IN_MAX_PLY;
        v = tb ? rootMoves[i].tbScore : v;

        if (ss.rdbuf()->in_avail()) // Not at first line
            ss << "\n";

        ss << "info"
            << " depth " << d
            << " seldepth " << rootMoves[i].selDepth
            << " multipv " << i + 1
            << " score " << UCI::value(v);

        if (!tb && i == pvIdx)
            ss << (v >= beta ? " lowerbound" : v <= alpha ? " upperbound" : "");

        ss << " nodes " << nodesSearched
            << " nps " << nodesSearched * 1000 / elapsed;

#if 0
        if (elapsed > 1000) // Earlier makes little sense
            ss << " hashfull " << TT.hashfull();
#endif

        ss << " tbhits " << tbHits
            << " time " << elapsed
            << " pv";

        for (Move m : rootMoves[i].pv)
            ss << " " << UCI::move(m);
    }

    return ss.str();
}


///////////////////////////////////////////////////////////////////////////////


vector<Key> moveHistory;


Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    StateInfo st;   // TODO

    Depth epsilon;

#ifdef TT_MOVE_ENABLE
    Move ttMove = MOVE_NONE;
#endif // TT_MOVE_ENABLE

#if defined (TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    Key posKey = pos->key();
#endif

#ifdef ENDGAME_LEARNING
    // 检索残局库
    Endgame endgame;

    if (gameOptions.getLearnEndgameEnabled() &&
        findEndgameHash(posKey, endgame)) {
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
        ttHitCount++;
#endif

        bestValue = probeVal;

#if 0
        // TODO: 有必要针对深度微调 value?
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
        ttMissCount++;
    }
#endif

    //hashMapMutex.unlock();
#endif /* TRANSPOSITION_TABLE_ENABLE */

#if 0
    if (position->phase == PHASE_PLACING && depth == 1 && pos->pieceCountNeedRemove > 0) {
        depth--;
    }
#endif

    if (unlikely(pos->phase == PHASE_GAMEOVER) ||   // TODO: Deal with hash and requiredQuit
        depth <= 0) {
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
        pos->do_move(move, st);
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

#ifdef HOSTORY_HEURISTIC
    movePicker->setHistoryScore(bestMove, depth);
#endif

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
