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

    for (const auto &m : MoveList(pos)) {
        if (Root && depth <= 1)
            cnt = 1, nodes++;
        else {
            pos.do_move(m, st);
            cnt = leaf ? MoveList(pos).size() : perft<false>(pos, depth - 1);
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

void MainThread::search()
{

    if (Limits.perft) {
        nodes = perft<true>(rootPos, Limits.perft);
        sync_cout << "\nNodes searched: " << nodes << "\n" << sync_endl;
        return;
    }

    Color us = rootPos.side_to_move();
    Time.init(Limits, us, rootPos.game_ply());
    //TT.new_search();

    if (rootMoves.empty()) {
        rootMoves.emplace_back(MOVE_NONE);
        sync_cout << "info depth 0 score "
            << UCI::value(false /* TODO */ ? -VALUE_MATE : VALUE_DRAW)
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
        sync_cout << UCI::pv(&bestThread->rootPos, bestThread->completedDepth, -VALUE_INFINITE, VALUE_INFINITE) << sync_endl;

    sync_cout << "bestmove " << UCI::move(bestThread->rootMoves[0].pv[0]);

    if (bestThread->rootMoves[0].pv.size() > 1 /* || bestThread->rootMoves[0].extract_ponder_from_tt(rootPos) */)
        std::cout << " ponder " << UCI::move(bestThread->rootMoves[0].pv[1]);

    std::cout << sync_endl;
}


/// Thread::search() is the main iterative deepening loop. It calls search()
/// repeatedly with increasing depth until the allocated thinking time has been
/// consumed, the user stops the search, or the maximum search depth is reached.

void Thread::search()
{

    // To allow access to (ss-7) up to (ss+2), the stack must be oversized.
    // The former is needed to allow update_continuation_histories(ss-1, ...),
    // which accesses its argument at ss-6, also near the root.
    // The latter is needed for statScores and killer initialization.
    Stack stack[MAX_PLY + 10], *ss = stack + 7;
    Move  pv[MAX_PLY + 1];
    Value bestValue, alpha, beta, delta;
    Move  lastBestMove = MOVE_NONE;
    Depth lastBestMoveDepth = 0;
    MainThread *mainThread = (this == Threads.main() ? Threads.main() : nullptr);
    double timeReduction = 1, totBestMoveChanges = 0;
    Color us = rootPos.side_to_move();
    int iterIdx = 0;

    std::memset(ss - 7, 0, 10 * sizeof(Stack));
    for (int i = 7; i > 0; i--)
        (ss - i)->continuationHistory = &this->continuationHistory[0][0][NO_PIECE][0]; // Use as a sentinel

    ss->pv = pv;

    bestValue = delta = alpha = -VALUE_INFINITE;
    beta = VALUE_INFINITE;

    if (mainThread) {
        if (mainThread->bestPreviousScore == VALUE_INFINITE)
            for (int i = 0; i < 4; ++i)
                mainThread->iterValue[i] = VALUE_ZERO;
        else
            for (int i = 0; i < 4; ++i)
                mainThread->iterValue[i] = mainThread->bestPreviousScore;
    }

    size_t multiPV = (size_t)Options["MultiPV"];

    // Pick integer skill levels, but non-deterministically round up or down
    // such that the average integer skill corresponds to the input floating point one.
    // UCI_Elo is converted to a suitable fractional skill level, using anchoring
    // to CCRL Elo (goldfish 1.13 = 2000) and a fit through Ordo derived Elo
    // for match (TC 60+0.6) results spanning a wide range of k values.
    PRNG rng(now());
    double floatLevel = Options["UCI_LimitStrength"] ?
        Utility::clamp(std::pow((Options["UCI_Elo"] - 1346.6) / 143.4, 1 / 0.806), 0.0, 20.0) :
        double(Options["Skill Level"]);
    int intLevel = int(floatLevel) +
        ((floatLevel - int(floatLevel)) * 1024 > rng.rand<unsigned>() % 1024 ? 1 : 0);
    Skill skill(intLevel);

    // When playing with strength handicap enable MultiPV search that we will
    // use behind the scenes to retrieve a set of possible moves.
    if (skill.enabled())
        multiPV = std::max(multiPV, (size_t)4);

    multiPV = std::min(multiPV, rootMoves.size());
    //ttHitAverage = TtHitAverageWindow * TtHitAverageResolution / 2;

    int searchAgainCounter = 0;

    // Iterative deepening loop until requested to stop or the target depth is reached
    while (++rootDepth < MAX_PLY
           && !Threads.stop
           && !(Limits.depth && mainThread && rootDepth > Limits.depth)) {
        // Age out PV variability metric
        if (mainThread)
            totBestMoveChanges /= 2;

        // Save the last iteration's scores before first PV line is searched and
        // all the move scores except the (new) PV are set to -VALUE_INFINITE.
        for (RootMove &rm : rootMoves)
            rm.previousScore = rm.score;

        size_t pvFirst = 0;
        pvLast = 0;

        if (!Threads.increaseDepth)
            searchAgainCounter++;

        // MultiPV loop. We perform a full root search for each PV line
        for (pvIdx = 0; pvIdx < multiPV && !Threads.stop; ++pvIdx) {
            if (pvIdx == pvLast) {
                pvFirst = pvLast;
                for (pvLast++; pvLast < rootMoves.size(); pvLast++)
                    if (rootMoves[pvLast].tbRank != rootMoves[pvFirst].tbRank)
                        break;
            }

            // Reset UCI info selDepth for each depth and each PV line
            selDepth = 0;

            // Reset aspiration window starting size
            if (rootDepth >= 4) {
                Value prev = rootMoves[pvIdx].previousScore;
                delta = Value(21);
                alpha = std::max(prev - delta, -VALUE_INFINITE);
                beta = std::min(prev + delta, VALUE_INFINITE);
            }

            // Start with a small aspiration window and, in the case of a fail
            // high/low, re-search with a bigger window until we don't fail
            // high/low anymore.
            int failedHighCnt = 0;
            while (true) {
                Depth adjustedDepth = std::max(1, rootDepth - failedHighCnt - searchAgainCounter);
                bestValue = ::search<PV>(rootPos, ss, alpha, beta, adjustedDepth, false);

                // Bring the best move to the front. It is critical that sorting
                // is done with a stable algorithm because all the values but the
                // first and eventually the new best one are set to -VALUE_INFINITE
                // and we want to keep the same order for all the moves except the
                // new PV that goes to the front. Note that in case of MultiPV
                // search the already searched PV lines are preserved.
                std::stable_sort(rootMoves.begin() + pvIdx, rootMoves.begin() + pvLast);

                // If search has been stopped, we break immediately. Sorting is
                // safe because RootMoves is still valid, although it refers to
                // the previous iteration.
                if (Threads.stop)
                    break;

                // When failing high/low give some update (without cluttering
                // the UI) before a re-search.
                if (mainThread
                    && multiPV == 1
                    && (bestValue <= alpha || bestValue >= beta)
                    && Time.elapsed() > 3000)
                    sync_cout << UCI::pv(&rootPos, rootDepth, alpha, beta) << sync_endl;

                // In case of failing low/high increase aspiration window and
                // re-search, otherwise exit the loop.
                if (bestValue <= alpha) {
                    beta = (alpha + beta) / 2;
                    alpha = std::max(bestValue - delta, -VALUE_INFINITE);

                    failedHighCnt = 0;
                    if (mainThread)
                        mainThread->stopOnPonderhit = false;
                } else if (bestValue >= beta) {
                    beta = std::min(bestValue + delta, VALUE_INFINITE);
                    ++failedHighCnt;
                } else {
                    ++rootMoves[pvIdx].bestMoveCount;
                    break;
                }

                delta += delta / 4 + 5;

                assert(alpha >= -VALUE_INFINITE && beta <= VALUE_INFINITE);
            }

            // Sort the PV lines searched so far and update the GUI
            std::stable_sort(rootMoves.begin() + pvFirst, rootMoves.begin() + pvIdx + 1);

            if (mainThread
                && (Threads.stop || pvIdx + 1 == multiPV || Time.elapsed() > 3000))
                sync_cout << UCI::pv(&rootPos, rootDepth, alpha, beta) << sync_endl;
        }

        if (!Threads.stop)
            completedDepth = rootDepth;

        if (rootMoves[0].pv[0] != lastBestMove) {
            lastBestMove = rootMoves[0].pv[0];
            lastBestMoveDepth = rootDepth;
        }

        // Have we found a "mate in x"?
        if (Limits.mate
            && bestValue >= VALUE_MATE_IN_MAX_PLY
            && VALUE_MATE - bestValue <= 2 * Limits.mate)
            Threads.stop = true;

        if (!mainThread)
            continue;

        // If skill level is enabled and time is up, pick a sub-optimal best move
        if (skill.enabled() && skill.time_to_pick(rootDepth))
            skill.pick_best(multiPV);

        // Do we have time for the next iteration? Can we stop searching now?
        if (Limits.use_time_management()
            && !Threads.stop
            && !mainThread->stopOnPonderhit) {
            double fallingEval = (332 + 6 * (mainThread->bestPreviousScore - bestValue)
                                  + 6 * (mainThread->iterValue[iterIdx] - bestValue)) / 704.0;
            fallingEval = Utility::clamp(fallingEval, 0.5, 1.5);

            // If the bestMove is stable over several iterations, reduce time accordingly
            timeReduction = lastBestMoveDepth + 9 < completedDepth ? 1.94 : 0.91;
            double reduction = (1.41 + mainThread->previousTimeReduction) / (2.27 * timeReduction);

            // Use part of the gained time from a previous stable move for the current move
            for (Thread *th : Threads) {
                totBestMoveChanges += th->bestMoveChanges;
                th->bestMoveChanges = 0;
            }
            double bestMoveInstability = 1 + totBestMoveChanges / Threads.size();

            // Stop the search if we have only one legal move, or if available time elapsed
            if (rootMoves.size() == 1
                || Time.elapsed() > Time.optimum() * fallingEval * reduction * bestMoveInstability) {
                // If we are allowed to ponder do not stop the search now but
                // keep pondering until the GUI sends "ponderhit" or "stop".
                if (mainThread->ponder)
                    mainThread->stopOnPonderhit = true;
                else
                    Threads.stop = true;
            } else if (Threads.increaseDepth
                       && !mainThread->ponder
                       && Time.elapsed() > Time.optimum() * fallingEval * reduction * bestMoveInstability * 0.6)
                Threads.increaseDepth = false;
            else
                Threads.increaseDepth = true;
        }

        mainThread->iterValue[iterIdx] = bestValue;
        iterIdx = (iterIdx + 1) & 3;
    }

    if (!mainThread)
        return;

    mainThread->previousTimeReduction = timeReduction;

    // If skill level is enabled, swap best PV line with the sub-optimal one
    if (skill.enabled())
        std::swap(rootMoves[0], *std::find(rootMoves.begin(), rootMoves.end(),
                                           skill.best ? skill.best : skill.pick_best(multiPV)));
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


Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove);

vector<Key> moveHistory;

AIAlgorithm::AIAlgorithm()
{
    pos = new Position();
    //movePicker = new MovePicker();
}

AIAlgorithm::~AIAlgorithm()
{
    //delete pos;
}

Depth AIAlgorithm::changeDepth()
{
    Depth d = 0;

#ifdef _DEBUG
    Depth reduce = 0;
#else
    Depth reduce = 0;
#endif

    const Depth placingDepthTable_12[] = {
         +1,  2,  +2,  4,     /* 0 ~ 3 */
         +4, 12, +12, 18,     /* 4 ~ 7 */
        +12, 16, +16, 16,     /* 8 ~ 11 */
        +16, 16, +16, 17,     /* 12 ~ 15 */
        +17, 16, +16, 15,     /* 16 ~ 19 */
        +15, 14, +14, 14,     /* 20 ~ 23 */
    };

    const Depth placingDepthTable_9[] = {
         +1, 7,  +7,  10,     /* 0 ~ 3 */
        +10, 12, +12, 12,     /* 4 ~ 7 */
        +12, 13, +13, 13,     /* 8 ~ 11 */
        +13, 13, +13, 13,     /* 12 ~ 15 */
        +13, 13, +13          /* 16 ~ 18 */
    };

    const Depth movingDepthTable[] = {
         1,  1,  1,  1,     /* 0 ~ 3 */
         1,  1, 11, 11,     /* 4 ~ 7 */
        11, 11, 11, 11,     /* 8 ~ 11 */
        11, 11, 11, 11,     /* 12 ~ 15 */
        11, 11, 11, 11,     /* 16 ~ 19 */
        12, 12, 13, 14,     /* 20 ~ 23 */
    };

#ifdef ENDGAME_LEARNING
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        0, 0, 0, 0, 0,       /* 3 ~ 7 */
        0, 0, 0, 0, 0          /* 8 ~ 12 */
    };
#else
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        11, 11, 10, 9, 8,       /* 3 ~ 7 */
        7, 6, 5, 4, 3          /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    const Depth flyingDepth = 9;

    if (pos->phase & PHASE_PLACING) {
        if (rule.nTotalPiecesEachSide == 12) {
            d = placingDepthTable_12[rule.nTotalPiecesEachSide * 2 - pos->count<IN_HAND>(BLACK) - pos->count<IN_HAND>(WHITE)];
        } else {
            d = placingDepthTable_9[rule.nTotalPiecesEachSide * 2 - pos->count<IN_HAND>(BLACK) - pos->count<IN_HAND>(WHITE)];
        }
    }

    if (pos->phase & PHASE_MOVING) {
        int pb = pos->count<ON_BOARD>(BLACK);
        int pw = pos->count<ON_BOARD>(WHITE);

        int pieces = pb + pw;
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }

        // Can fly
        if (rule.allowFlyWhenRemainThreePieces) {
            if (pb == rule.nPiecesAtLeast ||
                pw == rule.nPiecesAtLeast) {
                d = flyingDepth;
            }

            if (pb == rule.nPiecesAtLeast &&
                pw == rule.nPiecesAtLeast) {
                d = flyingDepth / 2;
            }
        }
    }

    if (unlikely(d > reduce)) {
        d -= reduce;
    }

    d += DEPTH_ADJUST;

    d = d >= 1 ? d : 1;

#if defined(FIX_DEPTH)
    d = FIX_DEPTH;
#endif

    assert(d <= 32);

    //loggerDebug("Depth: %d\n", d);

    return d;
}

void AIAlgorithm::setPosition(Position *p)
{
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

#ifdef ENDGAME_LEARNING
        // TODO: 规则改变时清空残局库
        //clearEndgameHashMap();
        //endgameList.clear();
#endif // ENDGAME_LEARNING

        moveHistory.clear();
    }

    //position = p;
    pos = p;
    // position = pos;

     //requiredQuit = false;
}

#ifdef ALPHABETA_AI
int AIAlgorithm::search()
{
    Value value = VALUE_ZERO;

    Depth d = changeDepth();
    newDepth = d;

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

    if (pos->get_phase() == PHASE_MOVING) {
        pos->update_key_misc();
        Key key = pos->key();

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

    if (pos->get_phase() == PHASE_PLACING) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    MoveList::shuffle();

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
            value = MTDF(pos, ss, value, i, originDepth, bestMove);
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
    value = MTDF(pos, ss, value, d, originDepth, bestMove);
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
#endif // ALPHABETA_AI

#ifdef ALPHABETA_AI
string AIAlgorithm::nextMove()
{
    return UCI::move(bestMove);

#if 0
    char charSelect = '*';

    Position::print_board();

    int moveIndex = 0;
    bool foundBest = false;

    int cs = root->childrenSize;
    for (int i = 0; i < cs; i++) {
        if (root->children[i]->move != bestMove) {
            charSelect = ' ';
        } else {
            charSelect = '*';
            foundBest = true;
        }

        loggerDebug("[%.2d] %d\t%s\t%d\t%u %c\n", moveIndex,
                    root->children[i]->move,
                    UCI::move(root->children[i]->move).c_str();
        root->children[i]->value,
#ifdef HOSTORY_HEURISTIC
            root->children[i]->score,
#else
            0,
#endif
            charSelect);

        moveIndex++;
    }

    Color side = position->sideToMove;

#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.getLearnEndgameEnabled()) {
        if (bestValue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = state->position->playerSideToMove == PLAYER_BLACK ?
                ENDGAME_PLAYER_WHITE_WIN : ENDGAME_PLAYER_BLACK_WIN;
            position->update_key_misc();
            key_t endgameHash = position->key(); // TODO: Do not generate hash repeately
            recordEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getResignIfMostLose() == true) {
        if (root->value <= -VALUE_MATE) {
            gameoverReason = LOSE_REASON_RESIGN;
            //sprintf(cmdline, "Player%d give up!", position->sideToMove);
            return cmdline;
        }
    }

    nodeCount = 0;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount) {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    if (foundBest == false) {
        loggerDebug("Warning: Best Move NOT Found\n");
    }

    return UCI::move(bestMove).c_str();
#endif
}
#endif // ALPHABETA_AI

#ifdef ENDGAME_LEARNING
bool AIAlgorithm::findEndgameHash(key_t posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int AIAlgorithm::recordEndgameHash(key_t posKey, const Endgame &endgame)
{
    //hashMapMutex.lock();
    key_t hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, TTEntry: 0x%08I32x, Address: 0x%08I32x\n", posKey, endgame.type, hashValue, addr);

    return 0;
}

void AIAlgorithm::clearEndgameHashMap()
{
    //hashMapMutex.lock();
    endgameHashMap.clear();
    //hashMapMutex.unlock();
}

void AIAlgorithm::recordEndgameHashMapToFile()
{
    const QString filename = "endgame.txt";
    endgameHashMap.dump(filename);

    loggerDebug("[endgame] Dump hash map to file\n");
}

void AIAlgorithm::loadEndgameFileToHashMap()
{
    const QString filename = "endgame.txt";
    endgameHashMap.load(filename);
}

#endif // ENDGAME_LEARNING

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
    pos->update_key_misc();
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
#ifdef PREFETCH_SUPPORT
    for (int i = 0; i < moveCount; i++) {
        TranspositionTable::prefetch(pos->next_primary_key(mp.moves[i].move));
    }

#ifdef PREFETCH_DEBUG
    if (posKey << 8 >> 8 == 0x0) {
        int pause = 1;
    }
#endif // PREFETCH_DEBUG
#endif // PREFETCH_SUPPORT
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
