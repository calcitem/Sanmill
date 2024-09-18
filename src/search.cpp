// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

#include <iostream>

#include "endgame.h"
#include "evaluate.h"
#include "mcts.h"
#include "misc.h"
#include "option.h"
#include "uci.h"
#include "thread.h"
#include "tt.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect_adaptor.h"
#endif

using Eval::evaluate;
using std::string;

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value do_search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
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
            TT.clear();
#endif
#endif

            if (gameOptions.getAlgorithm() == 2 /* MTD(f) */) {
                // debugPrintf("Algorithm: MTD(f).\n");
                value = MTDF(rootPos, ss, value, i, i, bestMove);
            } else if (gameOptions.getAlgorithm() == 3 /* MCTS */) {
                value = monte_carlo_tree_search(rootPos, bestMove);
            } else if (gameOptions.getAlgorithm() == 4 /* Random */) {
                value = random_search(rootPos, bestMove);
            } else {
                value = do_search(rootPos, ss, i, i, alpha, beta, bestMove);
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
    TT.clear();
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
        value = do_search(rootPos, ss, d, originDepth, alpha, beta, bestMove);
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
    debugPrintf(
        "Total Time: %llus\n",
        std::chrono::duration_cast<std::chrono::seconds>(timeEnd - timeStart)
            .count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

///////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////

vector<Key> posKeyHistory;

Value do_search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    Depth epsilon;

    if (pos->rule50_count() > rule.nMoveRule ||
        (rule.endgameNMoveRule < rule.nMoveRule && pos->is_three_endgame() &&
         pos->rule50_count() >= rule.endgameNMoveRule)) {
        alpha = VALUE_DRAW;
        if (alpha >= beta) {
            return alpha;
        }
    }

    const Key posKey = pos->key();

    // 保存原始的 alpha 值
    const Value alphaOrig = alpha;

    // 探测置换表
    bool ttHit;
    TTEntry *tte = TT.probe(posKey, ttHit);
    const Depth ttDepth = depth;

    // 如果命中置换表，尝试使用已存储的值
    if (ttHit) {
        Depth tteDepth = tte->depth();
        Value ttValue = tte->value();
        Bound ttBound = tte->bound();

        // 如果置换表中的深度足够
        if (tteDepth >= ttDepth) {
            if (ttBound == BOUND_EXACT) {
                return ttValue;
            } else if (ttBound == BOUND_LOWER && ttValue >= beta) {
                return ttValue;
            } else if (ttBound == BOUND_UPPER && ttValue <= alpha) {
                return ttValue;
            }
        }
    }

    if (unlikely(pos->phase == Phase::gameOver) ||
        depth <= 0 || Threads.stop.load(std::memory_order_relaxed)) {
        bestValue = Eval::evaluate(*pos);

        // 对快速胜利进行调整
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

        // 在这里保存置换表
        if (tte) {
            Bound ttBound = bestValue <= alphaOrig ? BOUND_UPPER :
                            bestValue >= beta ? BOUND_LOWER : BOUND_EXACT;

            tte->save(posKey, bestValue, false /* pv */, ttBound, ttDepth,
                      MOVE_NONE, bestValue);
        }

        return bestValue;
    }

    if (rule.threefoldRepetitionRule && depth != originDepth &&
        pos->has_repeated(ss)) {
        return VALUE_DRAW + 1;
    }

    // 初始化 MovePicker 对象
    MovePicker mp(*pos, ttHit ? tte->move() : MOVE_NONE);
    mp.next_move();
    //const Move nextMove = mp.next_move();
    const int moveCount = mp.move_count();

    Move localBestMove = MOVE_NONE; // 用于在本层跟踪最佳着法

    for (int i = 0; i < moveCount; i++) {
        ss.push(*pos);
        const Color before = pos->sideToMove;
        const Move move = mp.moves[i].move;

        pos->do_move(move);
        const Color after = pos->sideToMove;

        if (gameOptions.getDepthExtension() == true && moveCount == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

        if (gameOptions.getAlgorithm() == 1 /* PVS */) {
            if (i == 0) {
                if (after != before) {
                    value = -do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                     -beta, -alpha, bestMove);
                } else {
                    value = do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                    alpha, beta, bestMove);
                }
            } else {
                if (after != before) {
                    value = -do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                     -alpha - VALUE_PVS_WINDOW, -alpha,
                                     bestMove);

                    if (value > alpha && value < beta) {
                        value = -do_search(pos, ss, depth - 1 + epsilon,
                                         originDepth, -beta, -alpha, bestMove);
                    }
                } else {
                    value = do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                    alpha, alpha + VALUE_PVS_WINDOW, bestMove);

                    if (value > alpha && value < beta) {
                        value = do_search(pos, ss, depth - 1 + epsilon,
                                        originDepth, alpha, beta, bestMove);
                    }
                }
            }
        } else {
            if (after != before) {
                value = -do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                 -beta, -alpha, bestMove);
            } else {
                value = do_search(pos, ss, depth - 1 + epsilon, originDepth,
                                alpha, beta, bestMove);
            }
        }

        pos->undo_move(ss);

        if (Threads.stop.load(std::memory_order_relaxed))
            return VALUE_ZERO;

        if (value > bestValue) {
            bestValue = value;
            localBestMove = move; // 更新本层的最佳着法

            if (value > alpha) {
                alpha = value;

                if (alpha >= beta) {
                    // Beta 剪枝
                    break;
                }
            }
        }
    }

    // 在返回前保存置换表
    if (tte) {
        Bound ttBound = bestValue <= alphaOrig ? BOUND_UPPER :
                        bestValue >= beta ? BOUND_LOWER : BOUND_EXACT;

        // 如果当前节点是 PV 节点，则设置 pv 标志
        bool isPvNode = ttBound == BOUND_EXACT;

        // 仅当 localBestMove 不是 MOVE_NONE 时，才保存到置换表
        if (localBestMove != MOVE_NONE) {
            tte->save(posKey, bestValue, isPvNode, ttBound, ttDepth, localBestMove, bestValue);
        }
    }

    // 如果在根节点，更新最佳着法
    if (depth == originDepth && localBestMove != MOVE_NONE) {
        bestMove = localBestMove;
    }

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

        g = do_search(pos, ss, depth, originDepth, beta - VALUE_MTDF_WINDOW, beta,
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
