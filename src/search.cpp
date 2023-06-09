// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#include "endgame.h"
#include "evaluate.h"
#include "mcts.h"
#include "option.h"
#include "thread.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect_adaptor.h"
#endif

using Eval::evaluate;
using std::string;

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

bool is_timeout(TimePoint startTime);

/// Search::init() is called at startup

void Search::init() noexcept { }

/// Search::clear() resets search state to its initial value

void Search::clear()
{
    Threads.main()->wait_for_search_finished();

#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.clear();
#endif
    Threads.clear();
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern Value nnueTrainingDataBestValue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// Thread::search() is the main iterative deepening loop. It calls search()
/// repeatedly with increasing depth until the allocated thinking time has been
/// consumed, the user stops the search, or the maximum search depth is reached.

int Thread::search()
{
    Sanmill::Stack<Position> ss;

    Value value = VALUE_ZERO;
    const Depth d = get_depth();

    if (gameOptions.getAiIsLazy()) {
        const int np = bestvalue / VALUE_EACH_PIECE;
        if (np > 1) {
            if (d < 4) {
                originDepth = 1;
                sync_cout << "Lazy Mode: depth = " << originDepth << sync_endl;
            } else {
                originDepth = 4;
                sync_cout << "Lazy Mode: depth = " << originDepth << sync_endl;
            }
        } else {
            originDepth = d;
        }
    } else {
        originDepth = d;
    }

    const time_t time0 = time(nullptr);
    srand(static_cast<unsigned int>(time0));

#ifdef TIME_STAT
    auto timeStart = chrono::steady_clock::now();
    chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    chrono::steady_clock::time_point cycleEnd;
#endif

    if (rootPos->get_phase() == Phase::moving) {
#ifdef RULE_50
        if (posKeyHistory.size() >= rule.nMoveRule) {
            return 50;
        }

        if (rule.endgameNMoveRule < rule.nMoveRule &&
            rootPos->is_three_endgame() &&
            posKeyHistory.size() >= rule.endgameNMoveRule) {
            return 10;
        }
#endif // RULE_50

        if (rule.threefoldRepetitionRule && rootPos->has_game_cycle()) {
            return 3;
        }

        assert(posKeyHistory.size() < 256);
    }

    if (rootPos->get_phase() == Phase::placing) {
        posKeyHistory.clear();
        rootPos->st.rule50 = 0;
    } else if (rootPos->get_phase() == Phase::moving) {
        rootPos->st.rule50 = static_cast<unsigned>(posKeyHistory.size());
    }

    MoveList<LEGAL>::shuffle();

#if 0
    // TODO(calcitem): Only NMM
    if (rootPos->piece_on_board_count(WHITE)
                + rootPos->piece_on_board_count(BLACK)
            <= 1
        && !rule.hasDiagonalLines && gameOptions.getShufflingEnabled()) {
        const uint32_t seed = static_cast<uint32_t>(now());
        std::shuffle(MoveList<LEGAL>::movePriorityList.begin(),
            MoveList<LEGAL>::movePriorityList.end(),
            std::default_random_engine(seed));
    }
#endif

    Value alpha = VALUE_NONE;
    Value beta = VALUE_NONE;

    if (gameOptions.getAlgorithm() != 2 /* !MTD(f) */) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    if (gameOptions.getMoveTime() > 0 || gameOptions.getIDSEnabled()) {
        debugPrintf("IDS: ");

        constexpr Depth depthBegin = 2;
        Value lastValue = VALUE_ZERO;

        const TimePoint startTime = now();

        for (Depth i = depthBegin; i < originDepth; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TranspositionTable::clear();
#endif
#endif

            if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
                // debugPrintf("Algorithm: MTD(f).\n");
                value = MTDF(rootPos, ss, value, i, i, bestMove);
            } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
                value = monte_carlo_tree_search(rootPos, bestMove);
            } else if (gameOptions.getAlgorithm() == 4 /* RA */) {
#if defined(GABOR_MALOM_PERFECT_AI)
                value = perfect_search(rootPos, bestMove);
                if (value == VALUE_UNKNOWN) {
                    // Fall back
                    value = MTDF(rootPos, ss, VALUE_ZERO, i, i, bestMove);
                }
#endif // GABOR_MALOM_PERFECT_AI
            } else {
                value = qsearch(rootPos, ss, i, i, alpha, beta, bestMove);
            }

            debugPrintf("%d(%d) ", value, value - lastValue);

            lastValue = value;

            if (is_timeout(startTime)) {
                debugPrintf("originDepth = %d, depth = %d\n", originDepth, i);
                goto out;
            }
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        debugPrintf(
            "\nIDS Time: %llds\n",
            chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    if (gameOptions.getAlgorithm() != 2 /* !MTD(f) */
        && gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
        value = MTDF(rootPos, ss, value, originDepth, originDepth, bestMove);
    } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
        value = monte_carlo_tree_search(rootPos, bestMove);
    } else if (gameOptions.getAlgorithm() == 4 /* RA */) {
#if defined(GABOR_MALOM_PERFECT_AI)
        Value v = perfect_search(rootPos, bestMove);
        if (v == VALUE_UNKNOWN) {
            // Fall back
            value = MTDF(rootPos, ss, value, originDepth, originDepth,
                         bestMove);
        } else {
            value = v;
        }
#endif // GABOR_MALOM_PERFECT_AI
    } else {
        value = qsearch(rootPos, ss, d, originDepth, alpha, beta, bestMove);
    }

out:

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    debugPrintf(
        "Total Time: %llus\n",
        chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

///////////////////////////////////////////////////////////////////////////////

vector<Key> posKeyHistory;

Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    Depth epsilon;

#ifdef RULE_50
    if (pos->rule50_count() > rule.nMoveRule ||
        (rule.endgameNMoveRule < rule.nMoveRule && pos->is_three_endgame() &&
         pos->rule50_count() >= rule.endgameNMoveRule)) {
        alpha = VALUE_DRAW;
        if (alpha >= beta) {
            return alpha;
        }
    }
#endif // RULE_50

#ifdef THREEFOLD_REPETITION_TEST
    // Check if we have an upcoming move which draws by repetition, or
    // if the opponent had an alternative move earlier to this position.
    if (/* alpha < VALUE_DRAW && */
        depth != originDepth && pos->has_repeated(ss)) {
        alpha = VALUE_DRAW;
        if (alpha >= beta) {
            return alpha;
        }
    }
#endif // THREEFOLD_REPETITION

#ifdef TT_MOVE_ENABLE
    Move ttMove = MOVE_NONE;
#endif // TT_MOVE_ENABLE

    // Transposition table lookup

#if defined(TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    const Key posKey = pos->key();
#endif

#ifdef ENDGAME_LEARNING
    Endgame endgame;

    if (gameOptions.isEndgameLearningEnabled() && posKey &&
        Thread::probeEndgameHash(posKey, endgame)) {
        switch (endgame.type) {
        case EndGameType::whiteWin:
            bestValue = VALUE_MATE;
            bestValue += depth;
            break;
        case EndGameType::blackWin:
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

    // check transposition-table

    const Value oldAlpha = alpha; // To flag BOUND_EXACT when eval above alpha
                                  // and no available moves

    Bound type = BOUND_NONE;

    const Value probeVal = TranspositionTable::probe(posKey, depth, alpha, beta,
                                                     type
#ifdef TT_MOVE_ENABLE
                                                     ,
                                                     ttMove
#endif // TT_MOVE_ENABLE
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        Threads.main()->ttHitCount++;
#endif

        bestValue = probeVal;

        return bestValue;
    }
#ifdef TRANSPOSITION_TABLE_DEBUG
    if (probeVal == VALUE_UNKNOWN) {
        Threads.main()->ttMissCount++;
    }
#endif

#endif /* TRANSPOSITION_TABLE_ENABLE */

    // process leaves

    // Check for aborted search
    // TODO(calcitem): and immediate draw
    if (unlikely(pos->phase == Phase::gameOver) || // TODO(calcitem): Deal with
                                                   // hash
        depth <= 0 || Threads.stop.load(std::memory_order_relaxed)) {
        bestValue = Eval::evaluate(*pos);

        // For win quickly
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

        return bestValue;
    }

    // if this isn't the root of the search tree (where we have
    // to pick a move and can't simply return VALUE_DRAW) then check to
    // see if the position is a repeat. if so, we can assume that
    // this line is a draw and return VALUE_DRAW.
    if (rule.threefoldRepetitionRule && depth != originDepth &&
        pos->has_repeated(ss)) {
        return VALUE_DRAW;
    }

    // Initialize a MovePicker object for the current position, and prepare
    // to search the moves.
    MovePicker mp(*pos);
    const Move nextMove = mp.next_move();
    const int moveCount = mp.move_count();

#ifndef NNUE_GENERATE_TRAINING_DATA
    if (moveCount == 1 && depth == originDepth) {
        bestMove = nextMove;
        bestValue = VALUE_UNIQUE;
        return bestValue;
    }
#endif /* !NNUE_GENERATE_TRAINING_DATA */

#if 0
    // TODO(calcitem): Weak
    if (bestMove != MOVE_NONE) {
        for (int i = 0; i < moveCount; i++) {
            if (mp.moves[i].move == bestMove) {
                // TODO(calcitem): need to write value?
                std::swap(mp.moves[0], mp.moves[i]);
                break;
            }
        }
    }
#endif // TT_MOVE_ENABLE

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

    // Loop through the moves until no moves remain or a beta cutoff occurs
    for (int i = 0; i < moveCount; i++) {
        ss.push(*pos);
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Make and search the move
        pos->do_move(move);
        const Color after = pos->sideToMove;

        if (gameOptions.getDepthExtension() == true && moveCount == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

        // epsilon += pos->piece_to_remove_count(pos->sideToMove);

        if (gameOptions.getAlgorithm() == 1 /* PVS */) {
            // debugPrintf("Algorithm: PVS.\n");

            if (i == 0) {
                if (after != before) {
                    value = -qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                     -beta, -alpha, bestMove);
                } else {
                    value = qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                    alpha, beta, bestMove);
                }
            } else {
                if (after != before) {
                    value = -qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                     -alpha - VALUE_PVS_WINDOW, -alpha,
                                     bestMove);

                    if (value > alpha && value < beta) {
                        value = -qsearch(pos, ss, depth - 1 + epsilon,
                                         originDepth, -beta, -alpha, bestMove);
                        // assert(value >= alpha && value <= beta);
                    }
                } else {
                    value = qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                    alpha, alpha + VALUE_PVS_WINDOW, bestMove);

                    if (value > alpha && value < beta) {
                        value = qsearch(pos, ss, depth - 1 + epsilon,
                                        originDepth, alpha, beta, bestMove);
                        // assert(value >= alpha && value <= beta);
                    }
                }
            }
        } else {
            // debugPrintf("Algorithm: Alpha-Beta.\n");

            if (after != before) {
                value = -qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                 -beta, -alpha, bestMove);
            } else {
                value = qsearch(pos, ss, depth - 1 + epsilon, originDepth,
                                alpha, beta, bestMove);
            }
        }

        pos->undo_move(ss);

        // assert(value > -VALUE_INFINITE && value < VALUE_INFINITE);

        // Check for a new best move
        // Finished searching the move. If a stop occurred, the return value of
        // the search cannot be trusted, and we return immediately without
        // updating best move and TT.
        if (Threads.stop.load(std::memory_order_relaxed))
            return VALUE_ZERO;

        if (value >= bestValue) {
            bestValue = value;

            if (value > alpha) {
                if (depth == originDepth) {
                    bestMove = move;
                }

                if (value < beta) {
                    // Update alpha! Always alpha < beta
                    alpha = value;
                } else {
                    assert(value >= beta); // Fail high
                    break;                 // Fail high
                }
            }
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
    TranspositionTable::save(
        bestValue, depth,
        TranspositionTable::boundType(bestValue, oldAlpha, beta), posKey
#ifdef TT_MOVE_ENABLE
        ,
        bestMove
#endif // TT_MOVE_ENABLE
    );
#endif /* TRANSPOSITION_TABLE_ENABLE */

    // assert(bestValue > -VALUE_INFINITE && bestValue < VALUE_INFINITE);

    return bestValue;
}

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove)
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

        g = qsearch(pos, ss, depth, originDepth, beta - VALUE_MTDF_WINDOW, beta,
                    bestMove);

        if (g < beta) {
            upperbound = g; // fail low
        } else {
            lowerbound = g; // fail high
        }
    }

    return g;
}

bool is_timeout(TimePoint startTime)
{
    const auto limit = gameOptions.getMoveTime() * 1000;
    const TimePoint elapsed = now() - startTime;

    if (elapsed > limit) {
#ifdef _WIN32
        debugPrintf("\nTimeout. elapsed = %lld\n", elapsed);
#endif
        return true;
    }

    return false;
}
