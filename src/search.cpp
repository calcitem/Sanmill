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

template <NodeType nodeType>
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

int ttTotalProbes = 0;
int ttHits = 0;

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
            // TT.clear();
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
                value = do_search<PV>(rootPos, ss, i, i, alpha, beta, bestMove);
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
    // TT.clear();
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
        value = do_search<PV>(rootPos, ss, d, originDepth, alpha, beta,
                              bestMove);
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

    sync_cout << "################ TT Hit Rate: "
              << (100.0 * ttHits / ttTotalProbes) << "% (" << ttHits << "/"
              << ttTotalProbes << ")" << sync_endl;
    ttTotalProbes = 0;
    ttHits = 0;

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

// 在某个合适的头文件中声明
Value value_to_tt(Value v, int ply);
Value value_from_tt(Value v, int ply, int r50c);

// 在源文件中实现
Value value_to_tt(Value v, int ply)
{
    assert(v != VALUE_NONE);

    if (v >= VALUE_TB_WIN_IN_MAX_PLY) { // 处理将死分数
        return v + ply;
    }

    if (v <= VALUE_TB_LOSS_IN_MAX_PLY) { // 处理被将死分数
        return v - ply;
    }

    return v; // 对于非将死分数，不做调整
}

Value value_from_tt(Value v, int ply, int r50c)
{
    if (v == VALUE_NONE)
        return VALUE_NONE;

    if (v >= VALUE_TB_WIN_IN_MAX_PLY) { // 从 TT 中检索到的将死分数
        // 防止将死分数因 ply 过多而变得不准确
        if (v >= VALUE_MATE_IN_MAX_PLY && VALUE_MATE - v > 99 - r50c)
            return VALUE_MATE_IN_MAX_PLY - 1; // 返回一个保守的将死分数

        return v - ply;
    }

    if (v <= VALUE_TB_LOSS_IN_MAX_PLY) { // 从 TT 中检索到的被将死分数
        // 防止被将死分数因 ply 过多而变得不准确
        if (v <= VALUE_MATED_IN_MAX_PLY && VALUE_MATE + v > 99 - r50c)
            return VALUE_MATED_IN_MAX_PLY + 1; // 返回一个保守的被将死分数

        return v + ply;
    }

    return v; // 对于非将死分数，不做调整
}

template <NodeType nodeType>
Value do_search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
                Depth originDepth, Value alpha, Value beta, Move &bestMove)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    // `evalValue` 被用于存储静态评估值，而 `bestValue`
    // 可能会在后续逻辑中被修改（例如，加上深度以调整快速胜利）。 `evalValue`
    // 本身只是一个静态评估值，不需要被调整。因此，`evalValue`
    // 不完全是多余的，它提供了一个原始的、不受深度影响的评估值。
    // 在档案吗代码中，`evalValue` 似乎并未在后续逻辑中被充分利用，特别是与
    // Stockfish 的实现相比，Stockfish 更倾向于直接使用
    // `bestValue`(存疑，似乎会使用 eval)。 如果 `evalValue`
    // 不被后续代码有效利用，可以考虑移除它，直接使用 `bestValue`
    // 进行评估和置换表的存储。但是需要搞清楚 Stockfish 是怎么做的。
    Value evalValue = VALUE_NONE;

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
    ttTotalProbes++; // 每次调用 probe 时增加总探测次数
    if (ttHit) {
        ttHits++; // 如果命中，增加命中次数
    }
    const Depth ttDepth = depth;

    // 提取 ttEval，如果存在有效的评估值
    Value ttEval = VALUE_NONE;
    if (ttHit && tte->eval() != 0) {
        ttEval = static_cast<Value>(tte->eval());
    }

    // 如果命中置换表，尝试使用已存储的值
    if (ttHit) {
        Depth tteDepth = tte->depth();
        Value raw_ttValue = tte->value();
        Bound ttBound = tte->bound();

        // 如果置换表中的深度足够
        if (tteDepth >= ttDepth) {
            // 使用 value_from_tt 调整 TT 中的值
            Value ttValue = value_from_tt(raw_ttValue, ss.size(),
                                          pos->rule50_count());

            if (ttBound == BOUND_EXACT) {
                return ttValue;
            } else if (ttBound == BOUND_LOWER && ttValue >= beta) {
                return ttValue;
            } else if (ttBound == BOUND_UPPER && ttValue <= alpha) {
                return ttValue;
            }
        }
    }

    // 当深度为0或者达到终止条件时，计算评估值
    if (unlikely(pos->phase == Phase::gameOver) || depth <= 0 ||
        Threads.stop.load(std::memory_order_relaxed)) {
        // 计算评估值
        evalValue = Eval::evaluate(*pos);

        // 对快速胜利进行调整
        bestValue = evalValue;
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

        Value adjustedValue = value_to_tt(bestValue, ss.size());

        if (tte) {
            Bound ttBound = bestValue <= alphaOrig ? BOUND_UPPER :
                            bestValue >= beta      ? BOUND_LOWER :
                                                     BOUND_EXACT;

            // 如果当前节点是 PV 节点，则设置 pv 标志
            // 只有当边界类型为 `BOUND_EXACT` 时，评估值才被认为是精确的；如果是
            // `BOUND_UPPER` 或 `BOUND_LOWER`，则评估值只是一个上界或下界。
            bool isPvNodeEntry = (nodeType == PV) && (ttBound == BOUND_EXACT);

            // 直接使用缓存的评估值，而不是重新评估
            // 将 `MOVE_NONE`
            // 作为着法保存，因为确实没有可用的着法。这样可以防止在置换表中存储无效或错误的着法信息。
            // 在 Stockfish
            // 中，置换表保存最佳移动（`ttMove`）通常是在成功搜索后，例如当找到一个新的最佳值时。但在进行静态评估时，可能不保存具体的移动，类似于不保存移动
            // (`MOVE_NONE`)。
            // 改进建议：确保在非静态评估阶段（如深度搜索完成后）正确保存
            // `ttMove`，以充分利用置换表的优势。
            tte->save(posKey, adjustedValue, isPvNodeEntry, ttBound, ttDepth,
                      MOVE_NONE, evalValue);
        }

        return bestValue;
    }

    if (rule.threefoldRepetitionRule && depth != originDepth &&
        pos->has_repeated(ss)) {
        return VALUE_DRAW + 1;
    }

    // 传递 ttEval 给 MovePicker
    MovePicker mp(*pos, ttHit ? tte->move() : MOVE_NONE, ttEval);
    mp.next_move();
    const int moveCount = mp.move_count();

    // `localBestMove`
    // 有助于在当前搜索层中独立追踪最佳移动，确保递归搜索的正确性和模块化。
    // 在递归调用中，我们不希望修改
    // `bestMove`，因为那是用于返回根节点的最佳着法。因此，我们使用
    // `localBestMove` 来保存当前层的最佳着法。 localBestMove
    // 可以确保每一层次的最佳走法被正确跟踪并保存到置换表中。
    Move localBestMove = MOVE_NONE;

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
            if (nodeType == PV) {
                if (i == 0) {
                    if (after != before) {
                        value = -do_search<PV>(pos, ss, depth - 1 + epsilon,
                                               originDepth, -beta, -alpha,
                                               bestMove);
                    } else {
                        value = do_search<PV>(pos, ss, depth - 1 + epsilon,
                                              originDepth, alpha, beta,
                                              bestMove);
                    }
                } else {
                    if (after != before) {
                        value = -do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                  originDepth,
                                                  -alpha - VALUE_PVS_WINDOW,
                                                  -alpha, bestMove);

                        if (value > alpha && value < beta) {
                            value = -do_search<NonPV>(pos, ss,
                                                      depth - 1 + epsilon,
                                                      originDepth, -beta,
                                                      -alpha, bestMove);
                        }
                    } else {
                        value = do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                 originDepth, alpha,
                                                 alpha + VALUE_PVS_WINDOW,
                                                 bestMove);

                        if (value > alpha && value < beta) {
                            value = do_search<NonPV>(pos, ss,
                                                     depth - 1 + epsilon,
                                                     originDepth, alpha, beta,
                                                     bestMove);
                        }
                    }
                }
            } else { // NonPV
                if (i == 0) {
                    if (after != before) {
                        value = -do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                  originDepth, -beta, -alpha,
                                                  bestMove);
                    } else {
                        value = do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                 originDepth, alpha, beta,
                                                 bestMove);
                    }
                } else {
                    if (after != before) {
                        value = -do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                  originDepth,
                                                  -alpha - VALUE_PVS_WINDOW,
                                                  -alpha, bestMove);

                        if (value > alpha && value < beta) {
                            value = -do_search<NonPV>(pos, ss,
                                                      depth - 1 + epsilon,
                                                      originDepth, -beta,
                                                      -alpha, bestMove);
                        }
                    } else {
                        value = do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                                 originDepth, alpha,
                                                 alpha + VALUE_PVS_WINDOW,
                                                 bestMove);

                        if (value > alpha && value < beta) {
                            value = do_search<NonPV>(pos, ss,
                                                     depth - 1 + epsilon,
                                                     originDepth, alpha, beta,
                                                     bestMove);
                        }
                    }
                }
            }
        } else {
            // 非PVS算法的情况，继续区分PV和NonPV节点类型
            if (nodeType == PV) {
                if (after != before) {
                    value = -do_search<PV>(pos, ss, depth - 1 + epsilon,
                                           originDepth, -beta, -alpha,
                                           bestMove);
                } else {
                    value = do_search<PV>(pos, ss, depth - 1 + epsilon,
                                          originDepth, alpha, beta, bestMove);
                }
            } else {
                if (after != before) {
                    value = -do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                              originDepth, -beta, -alpha,
                                              bestMove);
                } else {
                    value = do_search<NonPV>(pos, ss, depth - 1 + epsilon,
                                             originDepth, alpha, beta,
                                             bestMove);
                }
            }
        }

        pos->undo_move(ss);

        if (Threads.stop.load(std::memory_order_relaxed))
            return bestValue;

        if (value > bestValue) {
            bestValue = value;
            localBestMove = move; // 更新本层的最佳着法

            if (value > alpha) {
                alpha = value;

                if (alpha >= beta) {
                    break; // Beta 剪枝
                }
            }
        }
    }

    // 在返回前保存置换表
    // 在 Alpha-Beta 剪枝算法中，通常将搜索结果与传入的 `alpha` 和 `beta`
    // 进行比较，以确定边界。`alphaOrig` 是原始的 `alpha` 值，在函数开始时被保存
    // 使用 `alphaOrig` 是合理的，因为在函数逻辑中，`alpha`
    // 可能已经被调整以反映更高的下界。为了保持置换表的一致性，比较应该基于函数入口时的
    // `alpha` (`alphaOrig`) 而非可能被调整后的 `alpha`。 根据最初的搜索窗口
    // `[alphaOrig, beta)`
    // 来判断。这样可以确保置换表中的信息在原始窗口范围内是准确的，便于在后续搜索中正确地使用。
    if (tte) {
        Bound ttBound = bestValue <= alphaOrig ? BOUND_UPPER :
                        bestValue >= beta      ? BOUND_LOWER :
                                                 BOUND_EXACT;

        bool isPvNodeEntry = (nodeType == PV) && (ttBound == BOUND_EXACT);

        Value adjustedValue = value_to_tt(bestValue, ss.size());

        // 保存到置换表，ev 设置为 VALUE_NONE
        tte->save(posKey, adjustedValue, isPvNodeEntry, ttBound, ttDepth,
                  localBestMove, VALUE_NONE);
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

        g = do_search<PV>(pos, ss, depth, originDepth, beta - VALUE_MTDF_WINDOW,
                          beta, bestMove);

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
