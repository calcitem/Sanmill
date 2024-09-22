// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers
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
#include "movepick.h"
#include "option.h"
#include "uci.h"
#include "thread.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect_adaptor.h"
#endif

using Eval::evaluate;
using std::string;

// Forward declarations
Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove);

Value random_search(Position *pos, Move &bestMove);

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

#if defined(GABOR_MALOM_PERFECT_AI)
    Move fallbackMove = MOVE_NONE;
    Value fallbackValue = VALUE_UNKNOWN;
#endif // GABOR_MALOM_PERFECT_AI

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
    auto timeStart = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    std::chrono::steady_clock::time_point cycleEnd;
#endif

    bool isMovingOrMayMoveInPlacing = (rootPos->get_phase() == Phase::moving) ||
                                      (rootPos->get_phase() == Phase::placing &&
                                       rule.mayMoveInPlacingPhase);

    if (isMovingOrMayMoveInPlacing) {
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

    if (rootPos->get_phase() == Phase::placing && !rule.mayMoveInPlacingPhase) {
        posKeyHistory.clear();
        rootPos->st.rule50 = 0;
    } else if (isMovingOrMayMoveInPlacing) {
        rootPos->st.rule50 = static_cast<unsigned>(posKeyHistory.size());
    }

    MoveList<LEGAL>::shuffle();

#if 0
    // TODO: Only NMM
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
                // MTD(f) algorithm
                value = MTDF(rootPos, ss, value, i, i, bestMove);
            } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
                value = monte_carlo_tree_search(rootPos, bestMove);
            } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
                value = random_search(rootPos, bestMove);
            } else {
                value = ::search(rootPos, ss, i, i, alpha, beta, bestMove);
            }

#if defined(GABOR_MALOM_PERFECT_AI)
            fallbackMove = bestMove;
            fallbackValue = value;
#endif // GABOR_MALOM_PERFECT_AI
            aiMoveType = AiMoveType::traditional;

            debugPrintf("Algorithm bestMove = %s\n",
                        UCI::move(bestMove).c_str());

#if defined(GABOR_MALOM_PERFECT_AI)
            if (gameOptions.getUsePerfectDatabase() == true) {
                value = perfect_search(rootPos, bestMove);
                if (value != VALUE_UNKNOWN) {
                    debugPrintf("perfect_search OK.\n");
                    debugPrintf("DB bestMove = %s\n",
                                UCI::move(bestMove).c_str());
                    if (bestMove == fallbackMove) {
                        aiMoveType = AiMoveType::consensus;
                    } else {
                        aiMoveType = AiMoveType::perfect;
                    }
                    goto next;
                } else {
                    debugPrintf("perfect_search failed.\n");
                    bestMove = fallbackMove;
                    value = fallbackValue;
                    aiMoveType = AiMoveType::traditional;
                }
            }
#endif // GABOR_MALOM_PERFECT_AI

#if defined(GABOR_MALOM_PERFECT_AI)
next:
#endif // GABOR_MALOM_PERFECT_AI

            debugPrintf("%d(%d) ", value, value - lastValue);

            lastValue = value;

            if (is_timeout(startTime)) {
                debugPrintf("originDepth = %d, depth = %d\n", originDepth, i);
                goto out;
            }
        }

#ifdef TIME_STAT
        timeEnd = std::chrono::steady_clock::now();
        sync_cout << "\nIDS Time: "
                  << std::chrono::duration_cast<std::chrono::seconds>(timeEnd -
                                                                      timeStart)
                         .count()
                  << "s\n";
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
    } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
        value = random_search(rootPos, bestMove);
    } else {
        value = ::search(rootPos, ss, d, originDepth, alpha, beta, bestMove);
    }

    fallbackMove = bestMove;
    fallbackValue = value;
    aiMoveType = AiMoveType::traditional;

    debugPrintf("Algorithm bestMove = %s\n", UCI::move(bestMove).c_str());

#if defined(GABOR_MALOM_PERFECT_AI)
    if (gameOptions.getUsePerfectDatabase() == true) {
        value = perfect_search(rootPos, bestMove);
        if (value != VALUE_UNKNOWN) {
            debugPrintf("perfect_search OK.\n");
            debugPrintf("DB bestMove = %s\n", UCI::move(bestMove).c_str());
            if (bestMove == fallbackMove) {
                aiMoveType = AiMoveType::consensus;
            } else {
                aiMoveType = AiMoveType::perfect;
            }
            goto out;
        } else {
            debugPrintf("perfect_search failed.\n");
            bestMove = fallbackMove;
            value = fallbackValue;
            aiMoveType = AiMoveType::traditional;
        }
    }
#endif // GABOR_MALOM_PERFECT_AI

out:

#ifdef TIME_STAT
    timeEnd = std::chrono::steady_clock::now();
    auto duration = timeEnd - timeStart;
    if (std::chrono::duration_cast<std::chrono::seconds>(duration).count() >
        100) {
        debugPrintf(
            "Total Time: %llu s\n",
            std::chrono::duration_cast<std::chrono::seconds>(duration).count());
    } else {
        debugPrintf(
            "Total Time: %llu ms\n",
            std::chrono::duration_cast<std::chrono::milliseconds>(duration)
                .count());
    }
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

/////////////////////////////////////////////////////////////////////////////////

// Random search implementation
Value random_search(Position *pos, Move &bestMove)
{
    MoveList<LEGAL> ml(*pos);

    if (ml.size() == 0) {
        return VALUE_DRAW;
    }

    ml.shuffle();

    const int index = rand() % ml.size();
    bestMove = ml.getMove(index);

    return VALUE_ZERO;
}

// Static search
Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    // Perform static evaluation of the position
    Value bestValue = evaluate(*pos);

    // Adjust evaluation based on depth for faster wins or delayed losses
    if (bestValue > 0) {
        bestValue += depth;
    } else {
        bestValue -= depth;
    }

    return bestValue;
}

vector<Key> posKeyHistory;

/// Search function that performs recursive search with alpha-beta pruning
Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    Depth epsilon;

    // Check for terminal position, depth limit, or search abortion
    if (unlikely(pos->phase == Phase::gameOver) || depth <= 0 ||
        Threads.stop.load(std::memory_order_relaxed)) {
        // Call qsearch for static evaluation
        return qsearch(pos, ss, depth, originDepth, alpha, beta, bestMove);
    }

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
    // Check for threefold repetition excluding root depth
    if (depth != originDepth && pos->has_repeated(ss)) {
        alpha = VALUE_DRAW;
        if (alpha >= beta) {
            return alpha;
        }
    }
#endif // THREEFOLD_REPETITION_TEST

    // Transposition table lookup
    Move ttMove = MOVE_NONE;

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
    const Value oldAlpha = alpha; // To flag BOUND_EXACT when eval above alpha
                                  // and no available moves

    Bound type = BOUND_NONE;

    const Value probeVal = TranspositionTable::probe(posKey, depth, type
#ifdef TT_MOVE_ENABLE
                                                     ,
                                                     ttMove
#endif // TT_MOVE_ENABLE
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        Threads.main()->ttHitCount++;
#endif

        if (type == BOUND_EXACT) {
            return probeVal;
        }
        if (type == BOUND_LOWER) {
            alpha = std::max(alpha, probeVal);
        } else if (type == BOUND_UPPER) {
            beta = std::min(beta, probeVal);
        }
        if (alpha >= beta) {
            return probeVal;
        }
    }

#ifdef TRANSPOSITION_TABLE_DEBUG
    if (probeVal == VALUE_UNKNOWN) {
        Threads.main()->ttMissCount++;
    }
#endif

#endif /* TRANSPOSITION_TABLE_ENABLE */

    // Check for threefold repetition excluding root depth
    if (rule.threefoldRepetitionRule && depth != originDepth &&
        pos->has_repeated(ss)) {
        // Add a small component to draw evaluations to avoid 3-fold blindness
        return VALUE_DRAW + 1;
    }

    // Initialize MovePicker to order and select moves
    MovePicker mp(*pos, ttMove);
    const Move nextMove = mp.next_move<LEGAL>();
    const int moveCount = mp.move_count();

#ifndef NNUE_GENERATE_TRAINING_DATA
    // If only one legal move and at root depth, select it as best move
    if (moveCount == 1 && depth == originDepth) {
        bestMove = nextMove;
        bestValue = VALUE_UNIQUE;
        return bestValue;
    }
#endif /* !NNUE_GENERATE_TRAINING_DATA */

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifndef DISABLE_PREFETCH
    // Prefetch transposition table entries for all moves
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

    // Iterate through all possible moves
    for (int i = 0; i < moveCount; i++) {
        ss.push(*pos);
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Make the move on the board
        pos->do_move(move);
        const Color after = pos->sideToMove;

        if (gameOptions.getDepthExtension() == true && moveCount == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

        // Recursive search based on the selected algorithm
        if (gameOptions.getAlgorithm() == 1 /* PVS */) {
            // Principal Variation Search (PVS)
            if (i == 0) {
                if (after != before) {
                    value = -search(pos, ss, depth - 1 + epsilon, originDepth,
                                    -beta, -alpha, bestMove);
                } else {
                    value = search(pos, ss, depth - 1 + epsilon, originDepth,
                                   alpha, beta, bestMove);
                }
            } else {
                if (after != before) {
                    value = -search(pos, ss, depth - 1 + epsilon, originDepth,
                                    -alpha - VALUE_PVS_WINDOW, -alpha,
                                    bestMove);

                    if (value > alpha && value < beta) {
                        value = -search(pos, ss, depth - 1 + epsilon,
                                        originDepth, -beta, -alpha, bestMove);
                        // Ensure value is within bounds
                    }
                } else {
                    value = search(pos, ss, depth - 1 + epsilon, originDepth,
                                   alpha, alpha + VALUE_PVS_WINDOW, bestMove);

                    if (value > alpha && value < beta) {
                        value = search(pos, ss, depth - 1 + epsilon,
                                       originDepth, alpha, beta, bestMove);
                        // Ensure value is within bounds
                    }
                }
            }
        } else {
            // Alpha-Beta Search
            if (after != before) {
                value = -search(pos, ss, depth - 1 + epsilon, originDepth,
                                -beta, -alpha, bestMove);
            } else {
                value = search(pos, ss, depth - 1 + epsilon, originDepth, alpha,
                               beta, bestMove);
            }
        }

        // Undo the move
        pos->undo_move(ss);

        // Check for search abortion
        if (Threads.stop.load(std::memory_order_relaxed))
            return VALUE_ZERO;

        // Update best value and best move if necessary
        if (value > bestValue) {
            bestValue = value;

            if (value > alpha) {
                if (depth == originDepth) {
                    bestMove = move;
                }

                if (value < beta) {
                    // Update alpha to the new best value
                    alpha = value;
                } else {
                    assert(value >= beta); // Fail high
                    break;                 // Fail high
                }
            }
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
    // Determine the bound type for the transposition table
    Bound ttBound;
    if (bestValue <= oldAlpha)
        ttBound = BOUND_UPPER;
    else if (bestValue >= beta)
        ttBound = BOUND_LOWER;
    else
        ttBound = BOUND_EXACT;

    // Save the result in the transposition table
    TranspositionTable::save(bestValue, depth, ttBound, posKey
#ifdef TT_MOVE_ENABLE
                             ,
                             bestMove
#endif // TT_MOVE_ENABLE
    );
#endif /* TRANSPOSITION_TABLE_ENABLE */

    // Return the best value found
    return bestValue;
}

/// MTDF function implementing the MTD(f) search algorithm
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

        g = search(pos, ss, depth, originDepth, beta - VALUE_MTDF_WINDOW, beta,
                   bestMove);

        if (g < beta) {
            upperbound = g; // Fail low
        } else {
            lowerbound = g; // Fail high
        }
    }

    return g;
}

/// Function to check if the search has timed out
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
