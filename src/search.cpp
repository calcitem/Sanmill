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

// Add a small random component to draw evaluations to avoid 3fold-blindness
Value value_draw(Thread *thisThread)
{
    return VALUE_DRAW + Value(2 * (thisThread->nodes & 1) - 1);
}

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

} // namespace


/// Search::init() is called at startup to initialize various lookup tables

void Search::init()
{
    // TODO
    return;
}


/// Search::clear() resets search state to its initial value

void Search::clear()
{
    // TODO
    return;
}

/// MainThread::search() is started when the program receives the UCI 'go'
/// command. It searches from the root position and outputs the "bestmove".

void MainThread::search()
{
    // TODO
#if 0
    if (Limits.perft) {
        nodes = perft<true>(rootPos, Limits.perft);
        sync_cout << "\nNodes searched: " << nodes << "\n" << sync_endl;
        return;
    }

    Color us = rootPos.side_to_move();
    Time.init(Limits, us, rootPos.game_ply());
    TT.new_search();

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
        sync_cout << UCI::pv(bestThread->rootPos, bestThread->completedDepth, -VALUE_INFINITE, VALUE_INFINITE) << sync_endl;

    sync_cout << "bestmove " << UCI::move(bestThread->rootMoves[0].pv[0]);

    if (bestThread->rootMoves[0].pv.size() > 1 || bestThread->rootMoves[0].extract_ponder_from_tt(rootPos))
        std::cout << " ponder " << UCI::move(bestThread->rootMoves[0].pv[1]);

    std::cout << sync_endl;
#endif
}

/// Thread::search() is the main iterative deepening loop. It calls search()
/// repeatedly with increasing depth until the allocated thinking time has been
/// consumed, the user stops the search, or the maximum search depth is reached.

void Thread::search()
{
    // TODO
    return;
}

Value MTDF(Position *pos, Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove);

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
const char* AIAlgorithm::nextMove()
{
    return moveToCommand(bestMove);

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
                    moveToCommand(root->children[i]->move),
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

    if (gameOptions.getGiveUpIfMostLose() == true) {
        if (root->value <= -VALUE_MATE) {
            sprintf(cmdline, "Player%d give up!", position->sideToMove);
            return cmdline;
        }
    }

    nodeCount = 0;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount)
    {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    if (foundBest == false) {
        loggerDebug("Warning: Best Move NOT Found\n");
    }

    return moveToCommand(bestMove);
#endif
}
#endif // ALPHABETA_AI

const char *AIAlgorithm::moveToCommand(Move move)
{
    File file2;
    Rank rank2;
    Position::square_to_polar(to_sq(move), file2, rank2);

    if (move < 0) {
        sprintf(cmdline, "-(%1u,%1u)", file2, rank2);
    } else if (move & 0x7f00) {
        File file1;
        Rank rank1;
        Position::square_to_polar(from_sq(move), file1, rank1);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", file1, rank1, file2, rank2);
    } else {
        sprintf(cmdline, "(%1u,%1u)", file2, rank2);
    }

    return cmdline;
}

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

// search<>() is the main search function for both PV and non-PV nodes

Value search(Position *pos, Stack<Position> &ss, Depth depth, Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

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
        bestValue = Eval::evaluate(pos);

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

    MovePicker mp(pos);
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

Value MTDF(Position *pos, Stack<Position> &ss, Value firstguess, Depth depth, Depth originDepth, Move &bestMove)
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
