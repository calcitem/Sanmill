// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// search.cpp

#include "search.h"
#include "evaluate.h"
#include "nnue/evaluate_nnue.h"
#include <algorithm>
#include <chrono>
#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "uci.h"
#include "tt.h"
#include "thread.h"
#include "thread_pool.h"
#include "search_engine.h"
#include "mills.h"

#ifdef GABOR_MALOM_PERFECT_AI
#include "perfect_adaptor.h"
#endif

using Eval::evaluate;
using std::string;

/// Search::init() is called at startup
void Search::init() noexcept {
    // Initialize history tables
    clear();
    
    debugPrintf("Search engine initialized with enhanced features:\n");
    debugPrintf("  - Improved transposition table with better replacement strategy\n");
    debugPrintf("  - Null move search for pruning\n");
    debugPrintf("  - History heuristic for move ordering\n");
    debugPrintf("  - Killer move heuristic\n");
}

// History tables definitions
ButterflyHistory Search::mainHistory;
PieceToHistory Search::pieceToHistory;
KillerMoves Search::killerMoves;
CounterMoves Search::counterMoves;

/// Search::clear() resets search state to its initial value
void Search::clear()
{
    // Threads.stop_all();

#ifdef TRANSPOSITION_TABLE_ENABLE
    TT.clear();
#endif

    // Clear history tables
    mainHistory.clear();
    pieceToHistory.clear();
    killerMoves.clear();
    counterMoves.clear();
}

// Position repetition is now tracked via StateInfo chain; the UI still
// manages its own history separately when needed. No engine-level vector here.

// Quiescence Search
Value Search::qsearch(SearchEngine &searchEngine, Position *pos, Depth depth,
                      Depth originDepth, Value alpha, Value beta,
                      Move &bestMove)
{
    Value stand_pat = VALUE_NONE;

#ifdef TRANSPOSITION_TABLE_ENABLE
    // Try to get evaluation from transposition table first
    TTEntry tte;
    const Key posKey = pos->key();
    bool ttHit = TranspositionTable::search(posKey, tte);

    if (ttHit && tte.depth() >= depth) {
        // Use TT value as initial estimate if depth is sufficient
        stand_pat = tte.value();
    }
#endif

    // If no suitable TT entry, evaluate the position
    if (stand_pat == VALUE_NONE) {
        // For Sanmill, NNUE evaluation is computed fresh when needed
        stand_pat = Eval::evaluate(*pos, depth);
    }

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

    // Limit quiescence search depth based on the position-specific search depth
    // This ensures qsearch depth is proportional to the main search depth
    const Depth maxSearchDepth = Mills::get_search_depth(pos);
    const int MAX_QUIESCENCE_DEPTH = std::max(1, static_cast<int>(maxSearchDepth / 2));
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
    const int currentPly = originDepth - depth;
    MovePicker mp(*pos, MOVE_NONE, currentPly);
    mp.next_move_legacy<REMOVE>();
    const int moveCount = mp.move_count();

    // Prefetch transposition table entries for all moves
    for (int i = 0; i < moveCount; i++) {
        TranspositionTable::prefetch(pos->key_after(mp.moves[i].move));
    }

    // Ensure NNUE accumulator is computed at parent node so that children
    // can reuse it via the StateInfo previous-chain
    if (pos->state() && (!pos->state()->accumulator.computed[0] ||
                         !pos->state()->accumulator.computed[1])) {
        (void)Eval::evaluate(*pos, depth);
    }

    // For each capture move
    for (int i = 0; i < moveCount; i++) {
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Use Stockfish-style StateInfo for proper NNUE and undo
        StateInfo st;
        pos->do_move(move, st);

        // For Sanmill's architecture, we don't use incremental NNUE updates
        // The accumulator will be computed fresh when needed
        const Color after = pos->sideToMove;

        // Recursively call qsearch
        Value value = (after != before) ?
                          -qsearch(searchEngine, pos, depth - 1, originDepth,
                                   -beta, -alpha, bestMove) :
                          qsearch(searchEngine, pos, depth - 1, originDepth,
                                  alpha, beta, bestMove);

        // Undo the move
        // Ensure pos->st points to our local st before undo
        pos->st = &st;
        pos->undo_move(move);

        // Debug: verify position state after undo
        if (pos->get_action() == Action::none) {
            debugPrintf("WARNING: Position action became Action::none after "
                        "undo_move!\n");
        }

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
Value Search::search(SearchEngine &searchEngine, Position *pos, Depth depth,
                     Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value bestValue = -VALUE_INFINITE;

    // Check for terminal position or search abortion
    if (unlikely(pos->phase == Phase::gameOver) ||
        searchEngine.searchAborted.load(std::memory_order_relaxed)) {
        bestValue = Eval::evaluate(*pos, depth);

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
        return qsearch(searchEngine, pos, depth, originDepth, alpha, beta,
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
    if (depth != originDepth && pos->has_repeated()) {
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

    Value ttEval = VALUE_NONE;
    const Value probeVal = TranspositionTable::probe(posKey, depth, type, ttEval
#ifdef TT_MOVE_ENABLE
                                                     ,
                                                     ttMove
#endif // TT_MOVE_ENABLE
    );

    // TT cutoff logic (inspired by Stockfish but adapted for Mill Game)
    bool ttHit = (probeVal != VALUE_UNKNOWN);
    
    if (ttHit) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        Threads.main()->ttHitCount++;
#endif

        // More conservative TT cutoffs to preserve search quality
        bool canCutoff = false;
        
        if (type == BOUND_EXACT) {
            canCutoff = true;
        } else if (type == BOUND_LOWER && probeVal >= beta) {
            canCutoff = true;
        } else if (type == BOUND_UPPER && probeVal <= alpha) {
            canCutoff = true;
        }
        
        // Apply cutoff only if conditions are met
        if (canCutoff) {
            // For Mill Game, be more conservative about early cutoffs
            // Avoid cutoffs in critical phases or shallow depths
            if (depth >= 3 || type == BOUND_EXACT) {
                return probeVal;
            }
        }
        
        // Update bounds even if not cutting off
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
        pos->has_repeated()) {
        // Add a small component to draw evaluations to avoid 3-fold blindness
        return VALUE_DRAW + 1;
    }

    Value value;
    Depth epsilon;

    // Note: ttMove validation is not needed here because:
    // 1. MovePicker only scores moves from the legal move list
    // 2. Illegal ttMoves will never be selected by MovePicker
    // 3. This saves significant performance overhead
    // 4. Matches Stockfish's approach of relying on MovePicker's built-in protection

    // Calculate current ply for move ordering
    const int currentPly = originDepth - depth;
    
    // Initialize MovePicker to order and select moves
    MovePicker mp(*pos, ttMove, currentPly);
    mp.next_move_legacy<LEGAL>();
    const int moveCount = mp.move_count();

    // For Sanmill, we use fresh NNUE evaluation for each position
    // No need to pre-compute accumulators since we always refresh

    // Handle case when no moves are available
    if (moveCount == 0) {
        // Debug: print position state when no moves are found
        debugPrintf("No legal moves found: phase=%d, action=%d, sideToMove=%d, "
                    "pieceOnBoard[W]=%d, pieceOnBoard[B]=%d, "
                    "pieceInHand[W]=%d, pieceInHand[B]=%d\n",
                    static_cast<int>(pos->get_phase()),
                    static_cast<int>(pos->get_action()),
                    static_cast<int>(pos->side_to_move()),
                    pos->piece_on_board_count(WHITE),
                    pos->piece_on_board_count(BLACK),
                    pos->piece_in_hand_count(WHITE),
                    pos->piece_in_hand_count(BLACK));

        if (depth == originDepth) {
            bestMove = MOVE_NONE;
            debugPrintf("Warning: Search found no legal moves at root depth\n");
        }
        // Return static evaluation for terminal position
        return Eval::evaluate(*pos, depth);
    }

#ifndef NNUE_GENERATE_TRAINING_DATA
    // If only one legal move and at root depth, select it as best move
    if (moveCount == 1 && depth == originDepth) {
        bestMove = mp.moves[0].move;
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

    // Lazily precompute NNUE accumulator at parent node so that children can
    // build incremental updates from it. This avoids repeated full refreshes.
    if (pos->state() && (!pos->state()->accumulator.computed[0] ||
                         !pos->state()->accumulator.computed[1])) {
        (void)Eval::evaluate(*pos, depth);
    }

    // Try null move search for pruning (before move loop)
    // Be more conservative in Mill Game due to potential consecutive moves from mills
    if (depth >= 4 && moveCount > 2 && !ttHit && 
        pos->get_action() == Action::none) {  // Only in neutral state
        Value nullValue = null_move_search(searchEngine, pos, depth, originDepth, alpha, beta, bestMove);
        if (nullValue != VALUE_UNKNOWN && nullValue >= beta) {
            // Null move cutoff - current position is too good for opponent
            return nullValue;
        }
    }

    // Current ply already calculated above for MovePicker

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

        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        // Use Stockfish-style StateInfo for proper NNUE and undo
        StateInfo st;
        pos->do_move(move, st);

        // For Sanmill's architecture, we don't use incremental NNUE updates
        // The accumulator will be computed fresh when needed
        const Color after = pos->sideToMove;

        // Determine the depth extension
        epsilon = (gameOptions.getDepthExtension() && moveCount == 1) ? 1 : 0;

        // Perform recursive search
        value = (after != before) ?
                    -search(searchEngine, pos, depth - 1 + epsilon, originDepth,
                            -beta, -alpha, bestMove) :
                    search(searchEngine, pos, depth - 1 + epsilon, originDepth,
                           alpha, beta, bestMove);

        // Undo the move
        // Ensure pos->st points to our local st before undo
        pos->st = &st;
        pos->undo_move(move);

        // Debug: verify position state after undo
        if (pos->get_action() == Action::none) {
            debugPrintf("WARNING: Position action became Action::none after "
                        "undo_move!\n");
        }

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
                    // Update history for good moves
                    update_history(pos, move, depth, true);
                } else {
                    assert(value >= beta); // Fail high
                    // Update killer moves for beta cutoff
                    update_killers(move, currentPly);
                    // Update history for good moves that cause cutoff
                    update_history(pos, move, depth, true);
                    // Update history for previous moves that failed to cause cutoff
                    for (int j = 0; j < i; j++) {
                        update_history(pos, mp.moves[j].move, depth, false);
                    }
                    break;                 // Fail high
                }
            } else {
                // Update history for moves that didn't improve alpha
                update_history(pos, move, depth, false);
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
    // Use ttEval if available, otherwise compute static evaluation
    Value staticEval = (ttEval != VALUE_NONE) ? ttEval : Eval::evaluate(*pos, depth);
    TranspositionTable::save(bestValue, staticEval, depth, ttBound, posKey
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
Value Search::MTDF(SearchEngine &searchEngine, Position *pos, Value firstguess,
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

        g = search(searchEngine, pos, depth, originDepth,
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
Value Search::pvs(SearchEngine &searchEngine, Position *pos, Depth depth,
                  Depth originDepth, Value alpha, Value beta, Move &bestMove,
                  int i, const Color before, const Color after)
{
    Value value;

    if (i == 0) {
        // First move: full window search
        value = (after != before) ?
                    -search(searchEngine, pos, depth, originDepth, -beta,
                            -alpha, bestMove) :
                    search(searchEngine, pos, depth, originDepth, alpha, beta,
                           bestMove);
    } else {
        // Subsequent moves: null window search (PVS)
        value = (after != before) ?
                    -search(searchEngine, pos, depth, originDepth,
                            -alpha - VALUE_PVS_WINDOW, -alpha, bestMove) :
                    search(searchEngine, pos, depth, originDepth, alpha,
                           alpha + VALUE_PVS_WINDOW, bestMove);

        // Re-search if the value is within the search window
        if (value > alpha && value < beta) {
            value = (after != before) ?
                        -search(searchEngine, pos, depth, originDepth, -beta,
                                -alpha, bestMove) :
                        search(searchEngine, pos, depth, originDepth, alpha,
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
        // Debug: print position state when no moves are found
        debugPrintf("random_search: No legal moves found: phase=%d, action=%d, "
                    "sideToMove=%d, pieceOnBoard[W]=%d, pieceOnBoard[B]=%d, "
                    "pieceInHand[W]=%d, pieceInHand[B]=%d\n",
                    static_cast<int>(pos->get_phase()),
                    static_cast<int>(pos->get_action()),
                    static_cast<int>(pos->side_to_move()),
                    pos->piece_on_board_count(WHITE),
                    pos->piece_on_board_count(BLACK),
                    pos->piece_in_hand_count(WHITE),
                    pos->piece_in_hand_count(BLACK));

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

// Null move search implementation (adapted for Mill Game)
Value Search::null_move_search(SearchEngine &searchEngine, Position *pos, Depth depth,
                              Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    // Mill Game specific null move pruning conditions:
    // 1. Depth is sufficient (at least 3)
    // 2. Static eval is above beta (indicating a strong position)
    // 3. Not in a removing phase (where player must remove opponent's piece)
    // 4. Not in endgame with very few pieces
    // 5. Not in a position where forming mills might give consecutive moves

    if (pos->phase == Phase::gameOver || 
        searchEngine.searchAborted.load(std::memory_order_relaxed)) {
        return evaluate(*pos, depth);
    }

    // Don't do null move in very shallow depths
    if (depth < 3) {
        return VALUE_UNKNOWN;
    }

    // CRITICAL: Only do null move in neutral state (Action::none)
    // All other actions are mandatory:
    // - Action::remove: must remove opponent's piece
    // - Action::select: player already selected a piece, must move it
    // - Action::place: player must complete placing/moving
    if (pos->get_action() != Action::none) {
        return VALUE_UNKNOWN;
    }

    // Don't do null move in placing phase if very few pieces placed
    // (opening positions are too tactical)
    if (pos->get_phase() == Phase::placing && 
        pos->piece_on_board_count(WHITE) + pos->piece_on_board_count(BLACK) < 6) {
        return VALUE_UNKNOWN;
    }

    // Evaluate current position
    Value staticEval = evaluate(*pos, depth);
    
    // Only try null move if we're significantly above beta
    if (staticEval < beta + 50) {
        return VALUE_UNKNOWN;
    }

    // Don't use null move in very simple endgames (less than 6 pieces total)
    int totalPieces = pos->piece_on_board_count(WHITE) + pos->piece_on_board_count(BLACK);
    if (totalPieces <= 6) {
        return VALUE_UNKNOWN;
    }

    // Check if current position might lead to mill formation
    // If so, avoid null move as it might give consecutive moves
    bool nearMill = false;
    if (pos->get_phase() == Phase::placing || pos->get_phase() == Phase::moving) {
        // Simple heuristic: check if we're close to forming a mill
        // This is conservative but safer for Mill Game dynamics
        int totalMills = 0;
        for (Square sq = SQ_A1; sq <= SQ_C7; ++sq) {
            if (pos->potential_mills_count(sq, pos->sideToMove) > 0) {
                totalMills++;
            }
        }
        // If too many potential mill-forming squares, be conservative
        if (totalMills > 3) {
            nearMill = true;
        }
    }

    if (nearMill) {
        return VALUE_UNKNOWN;
    }

    // Store original game state
    Color originalSide = pos->sideToMove;
    
    // Create a null move: switch sides without making a move
    // This simulates "passing the turn" which doesn't exist in Mill Game
    // but helps with pruning in positions where the current player 
    // doesn't have threatening moves
    pos->sideToMove = ~pos->sideToMove;
    
    // Note: In Mill Game, Action states are:
    // - none: neutral state
    // - select: player has selected a piece (in moving phase)  
    // - place: player is placing/moving a piece
    // - remove: player must remove opponent's piece
    // 
    // For null move, we keep the action unchanged since we're just
    // switching the active player without actually making a move
    
    // Calculate reduction (less aggressive than chess due to Mill Game dynamics)
    Depth reduction = 2 + depth / 5;  // Less aggressive reduction
    if (staticEval >= beta + 200) {
        reduction++; // Extra reduction for very good positions
    }
    
    Depth nullDepth = (depth > reduction) ? (depth - reduction) : Depth(0);
    
    // Perform null window search
    Value nullValue = -search(searchEngine, pos, nullDepth, originDepth, -beta, -beta + 1, bestMove);
    
    // Restore original game state
    pos->sideToMove = originalSide;
    // Note: action should remain the same as we didn't actually change it
    
    // Return early if null move search indicates beta cutoff
    if (nullValue >= beta) {
        // Don't return mate scores from null move
        return (nullValue >= VALUE_MATE - MAX_PLY) ? beta : nullValue;
    }
    
    return VALUE_UNKNOWN;
}

// Update history tables based on search results
void Search::update_history(Position *pos, Move move, Depth depth, bool good)
{
    if (move == MOVE_NONE) return;
    
    Color color = pos->sideToMove;
    Square from = from_sq(move);
    Square to = to_sq(move);
    
    // Calculate bonus/malus based on depth (deeper searches get higher weight)
    int bonus = good ? (depth * depth + depth * 32) : -(depth * depth + depth * 32);
    bonus = std::clamp(bonus, -HISTORY_MAX/2, HISTORY_MAX/2);
    
    // Update butterfly history (for quiet moves, not removal moves)
    if (type_of(move) != MOVETYPE_REMOVE) {
        mainHistory(color, from, to).update(bonus);
    }
    
    // Update piece-to history
    Piece piece = pos->moved_piece(move);
    if (piece != NO_PIECE) {
        pieceToHistory(piece, to).update(bonus);
    }
}

// Update killer moves when a move causes beta cutoff
void Search::update_killers(Move move, int ply)
{
    if (move != MOVE_NONE) {
        killerMoves.add(move, ply);
    }
}

// Get history score for move ordering
int Search::move_history_score(Position *pos, Move move)
{
    if (move == MOVE_NONE) return 0;
    
    Color color = pos->sideToMove;
    Square from = from_sq(move);
    Square to = to_sq(move);
    
    int score = 0;
    
    // Add butterfly history score (for quiet moves, not removal moves)
    if (type_of(move) != MOVETYPE_REMOVE) {
        score += mainHistory(color, from, to);
    }
    
    // Add piece-to history score
    Piece piece = pos->moved_piece(move);
    if (piece != NO_PIECE) {
        score += pieceToHistory(piece, to);
    }
    
    return score;
}

// Check if move is a killer move
bool Search::is_killer_move(Move move, int ply)
{
    return killerMoves.is_killer(move, ply);
}
