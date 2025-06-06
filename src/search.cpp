// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// search.cpp

#include "search.h"
#include "evaluate.h"
#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "uci.h"
#include "tt.h"
#include "thread.h"
#include "thread_pool.h"
#include "search_engine.h"

#ifdef GABOR_MALOM_PERFECT_AI
#include "perfect_adaptor.h"
#endif

using Eval::evaluate;
using std::string;

/// Search::init() is called at startup
void Search::init() noexcept { }

/// Search::clear() resets search state to its initial value
void Search::clear()
{
    // Threads.stop_all();

#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.clear();
#endif
}

vector<Key> posKeyHistory;

// Quiescence Search
Value Search::qsearch(SearchEngine &searchEngine, Position *pos,
                      Sanmill::Stack<Position> &ss, Depth depth,
                      Depth originDepth, Value alpha, Value beta,
                      Move &bestMove)
{
    // Evaluate the current position
    Value stand_pat = Eval::evaluate(*pos);

    static uint64_t nodeCounter = 0; // TODO: thread_local
    const unsigned checkMask = (depth >= -1) ? 255 : 1023;

    if ((++nodeCounter & checkMask) == 0 &&
        !searchEngine.searchAborted.load(std::memory_order_relaxed)) {
        if (searchEngine.is_timeout(searchEngine.searchStartTime)) {
            searchEngine.searchAborted.store(true, std::memory_order_relaxed);
            return alpha;
        }
    }

    // Adjust evaluation to prefer quicker wins or slower losses
    if (stand_pat > 0) {
        stand_pat += depth;
    } else {
        stand_pat -= depth;
    }

    // If depth limit reached, return stand_pat
    const int MAX_QUIESCENCE_DEPTH = 0; // TODO: Set to 1 or more
    if (depth <= -MAX_QUIESCENCE_DEPTH) {
        return stand_pat;
    }

    // If the evaluation is greater or equal to beta, cut off
    if (stand_pat >= beta) {
        return beta;
    }

    // If the evaluation is better than alpha, update alpha
    if (stand_pat > alpha) {
        alpha = stand_pat;
    }

    // If the position is a terminal node, return the evaluation
    if (unlikely(pos->phase == Phase::gameOver)) {
        return stand_pat;
    }

    // Generate remove moves
    MovePicker mp(*pos, MOVE_NONE);
    mp.next_move<REMOVE>();
    const int moveCount = mp.move_count();

    // Prefetch transposition table entries for all moves
    for (int i = 0; i < moveCount; i++) {
        TranspositionTable::prefetch(pos->key_after(mp.moves[i].move));
    }

    // For each capture move
    for (int i = 0; i < moveCount; i++) {
        ss.push(*pos);
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Make the move on the board
        pos->do_move(move);
        const Color after = pos->sideToMove;

        // Recursively call qsearch
        Value value = (after != before) ?
                          -qsearch(searchEngine, pos, ss, depth - 1,
                                   originDepth, -beta, -alpha, bestMove) :
                          qsearch(searchEngine, pos, ss, depth - 1, originDepth,
                                  alpha, beta, bestMove);

        // Undo the move
        pos->undo_move(ss);

        // If the value is better than alpha, update alpha
        if (value > alpha) {
            alpha = value;
            if (depth == originDepth) {
                bestMove = move;
            }

            // If the value is greater or equal to beta, cut off
            if (alpha >= beta) {
                return beta;
            }
        }

        if (searchEngine.searchAborted.load(std::memory_order_relaxed)) {
            return alpha;
        }
    }

    // Return alpha as the best value
    return alpha;
}

/// Search function that performs recursive search with alpha-beta pruning
Value Search::search(SearchEngine &searchEngine, Position *pos,
                     Sanmill::Stack<Position> &ss, Depth depth,
                     Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value bestValue = -VALUE_INFINITE;

    // Check for terminal position or search abortion
    if (unlikely(pos->phase == Phase::gameOver) ||
        searchEngine.searchAborted.load(std::memory_order_relaxed)) {
        bestValue = Eval::evaluate(*pos);

        // Adjust evaluation to prefer quicker wins or slower losses
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

        return bestValue;
    }

    if (depth <= 0) {
        // Call quiescence search when depth limit is reached
        return qsearch(searchEngine, pos, ss, depth, originDepth, alpha, beta,
                       bestMove);
    }

#ifdef RULE_50
    // Rule 50 move draw condition
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

    Value value;
    Depth epsilon;

    // Initialize MovePicker to order and select moves
    MovePicker mp(*pos, ttMove);
    const Move nextMove = mp.next_move<LEGAL>();
    const int moveCount = mp.move_count();

    // Handle case when no moves are available
    if (moveCount == 0) {
#ifdef _WIN32
#ifdef _DEBUG
        assert(false);
#endif
#endif
        if (depth == originDepth) {
            bestMove = MOVE_NONE;
            debugPrintf("Warning: Search found no legal moves at root depth\n");
        }
        return bestValue;
    }

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
        static uint64_t nodeCounter = 0; // TODO: thread_local

        const unsigned checkMask = (depth <= 3) ? 31 :
                                                  ((depth <= 6) ? 127 : 511);

        if ((++nodeCounter & checkMask) == 0 &&
            searchEngine.searchAborted.load(std::memory_order_relaxed) ==
                false) {
            if (searchEngine.is_timeout(searchEngine.searchStartTime)) {
                searchEngine.searchAborted.store(true,
                                                 std::memory_order_relaxed);
                return bestValue;
            }
        }

        ss.push(*pos);
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Make the move on the board
        pos->do_move(move);
        const Color after = pos->sideToMove;

        // Determine the depth extension
        epsilon = (gameOptions.getDepthExtension() && moveCount == 1) ? 1 : 0;

        // Perform recursive search
        value = (after != before) ?
                    -search(searchEngine, pos, ss, depth - 1 + epsilon,
                            originDepth, -beta, -alpha, bestMove) :
                    search(searchEngine, pos, ss, depth - 1 + epsilon,
                           originDepth, alpha, beta, bestMove);

        // Undo the move
        pos->undo_move(ss);

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

        // Check for search abortion
        if (searchEngine.searchAborted.load(std::memory_order_relaxed)) {
            return bestValue;
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
Value Search::MTDF(SearchEngine &searchEngine, Position *pos,
                   Sanmill::Stack<Position> &ss, Value firstguess, Depth depth,
                   Depth originDepth, Move &bestMove)
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

        g = search(searchEngine, pos, ss, depth, originDepth,
                   beta - VALUE_MTDF_WINDOW, beta, bestMove);

        if (g < beta) {
            upperbound = g; // Fail low
        } else {
            lowerbound = g; // Fail high
        }
    }

    return g;
}

/// Function that performs Principal Variation Search (PVS)
Value Search::pvs(SearchEngine &searchEngine, Position *pos,
                  Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
                  Value alpha, Value beta, Move &bestMove, int i,
                  const Color before, const Color after)
{
    Value value;

    if (i == 0) {
        // First move: full window search
        value = (after != before) ?
                    -search(searchEngine, pos, ss, depth, originDepth, -beta,
                            -alpha, bestMove) :
                    search(searchEngine, pos, ss, depth, originDepth, alpha,
                           beta, bestMove);
    } else {
        // Subsequent moves: null window search (PVS)
        value = (after != before) ?
                    -search(searchEngine, pos, ss, depth, originDepth,
                            -alpha - VALUE_PVS_WINDOW, -alpha, bestMove) :
                    search(searchEngine, pos, ss, depth, originDepth, alpha,
                           alpha + VALUE_PVS_WINDOW, bestMove);

        // Re-search if the value is within the search window
        if (value > alpha && value < beta) {
            value = (after != before) ?
                        -search(searchEngine, pos, ss, depth, originDepth,
                                -beta, -alpha, bestMove) :
                        search(searchEngine, pos, ss, depth, originDepth, alpha,
                               beta, bestMove);
        }
    }

    return value;
}

// Random search implementation
Value Search::random_search(Position *pos, Move &bestMove)
{
    MoveList<LEGAL> ml(*pos);

    if (ml.size() == 0) {
#ifdef _WIN32
#ifdef _DEBUG
        assert(false);
#endif
#endif
        bestMove = MOVE_NONE;
        debugPrintf("Warning: random_search found no legal moves\n");
        return VALUE_DRAW;
    }

    ml.shuffle();

    const int index = rand() % ml.size();
    bestMove = ml.getMove(index);

    // Ensure we got a valid move
    if (bestMove == MOVE_NONE) {
#ifdef _WIN32
#ifdef _DEBUG
        assert(false);
#endif
#endif
        debugPrintf("Warning: random_search selected MOVE_NONE, trying first "
                    "move\n");
        bestMove = ml.getMove(0);
    }

    debugPrintf("random_search selected move: %s\n",
                UCI::move(bestMove).c_str());
    return VALUE_ZERO;
}
