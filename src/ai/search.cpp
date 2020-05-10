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

#include <cmath>
#include <array>
#include <chrono>
#include <algorithm>

#include "search.h"
#include "evaluate.h"
#include "movegen.h"
#include "hashmap.h"
#include "tt.h"
#include "endgame.h"
#include "types.h"
#include "option.h"
#include "misc.h"
#include "movepick.h"

player_t gSideToMove;

using namespace CTSL;

// 用于检测重复局面 (Position)
vector<hash_t> moveHistory;

AIAlgorithm::AIAlgorithm()
{
    state = new StateInfo();
    st = new StateInfo();
    //movePicker = new MovePicker();
}

AIAlgorithm::~AIAlgorithm()
{
    delete st;
    //delete state;
}

depth_t AIAlgorithm::changeDepth(depth_t origDepth)
{
    depth_t d = origDepth;

#ifdef _DEBUG
    // 当 VC 下编译为 Debug 时
    depth_t reduce = 0;
#else
    depth_t reduce = 0;
#endif

    const depth_t placingDepthTable_12[] = {
         +1,  2,  +2,  4,     /* 0 ~ 3 */
         +4, 12, +12, 18,     /* 4 ~ 7 */
        +12, 16, +16, 16,     /* 8 ~ 11 */
        +16, 16, +16, 17,     /* 12 ~ 15 */
        +17, 16, +16, 15,     /* 16 ~ 19 */
        +15, 14, +14, 14,     /* 20 ~ 23 */
    };

    const depth_t placingDepthTable_9[] = {
         +1, 7,  +7,  10,     /* 0 ~ 3 */
        +10, 12, +12, 12,     /* 4 ~ 7 */
        +12, 13, +13, 13,     /* 8 ~ 11 */
        +13, 13, +13, 13,     /* 12 ~ 15 */
        +13, 13,              /* 16 ~ 18 */
    };

    const depth_t movingDepthTable[] = {
         1,  1,  1,  1,     /* 0 ~ 3 */
         1,  1, 11, 11,     /* 4 ~ 7 */
        11, 11, 11, 11,     /* 8 ~ 11 */
        11, 11, 11, 11,     /* 12 ~ 15 */
        11, 11, 11, 11,     /* 16 ~ 19 */
        12, 12, 13, 14,     /* 20 ~ 23 */
    };

#ifdef ENDGAME_LEARNING
    const depth_t movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        0, 0, 0, 0, 0,       /* 3 ~ 7 */
        0, 0, 0, 0, 0          /* 8 ~ 12 */
    };
#else
    const depth_t movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        11, 11, 10, 9, 8,       /* 3 ~ 7 */
        7, 6, 5, 4, 3          /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    if (st->position->phase & PHASE_PLACING) {
        if (rule.nTotalPiecesEachSide == 12) {
            d = placingDepthTable_12[rule.nTotalPiecesEachSide * 2 - st->position->getPiecesInHandCount(BLACK) - st->position->getPiecesInHandCount(WHITE)];
        } else {
            d = placingDepthTable_9[rule.nTotalPiecesEachSide * 2 - st->position->getPiecesInHandCount(BLACK) - st->position->getPiecesInHandCount(WHITE)];
        }
    }

    if (st->position->phase & PHASE_MOVING) {
        int pb = st->position->getPiecesOnBoardCount(BLACK);
        int pw = st->position->getPiecesOnBoardCount(WHITE);

        int pieces = pb + pw;
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }
    }

    // Debug 下调低深度
    if (unlikely(d > reduce)) {
        d -= reduce;
    }

    d += DEPTH_ADJUST;

    d = d >= 1 ? d : 1;

#if defined(FIX_DEPTH)
    d = FIX_DEPTH;
#endif

    loggerDebug("Depth: %d\n", d);

    return d;
}

void AIAlgorithm::setState(const StateInfo &g)
{
    // 如果规则改变，重建hashmap
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TT::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

#ifdef ENDGAME_LEARNING
        // TODO: 规则改变时清空残局库
        //clearEndgameHashMap();
        //endgameList.clear();
#endif // ENDGAME_LEARNING

        moveHistory.clear();
    }

    *state = g;
    *st = g;

    //memcpy(this->state, &g, sizeof(StateInfo));
    //memcpy(this->st, &this->state, sizeof(StateInfo));

    position = st->position;
    requiredQuit = false;
}

#ifdef ALPHABETA_AI
int AIAlgorithm::search(depth_t depth)
{
    value_t value = VALUE_ZERO;

    depth_t d = changeDepth(depth);

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

    if (state->position->getPhase() == PHASE_MOVING) {
        hash_t hash = state->position->getPosKey();
        
        if (std::find(moveHistory.begin(), moveHistory.end(), hash) != moveHistory.end()) {
            nRepetition++;
            if (nRepetition == 3) {
                nRepetition = 0;
                return 3;
            }
        } else {
            moveHistory.push_back(hash);
        }
    }

    if (state->position->getPhase() == PHASE_PLACING) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    // 随机打乱着法顺序
    MoveList::shuffle();   

    value_t alpha = -VALUE_INFINITE;
    value_t beta = VALUE_INFINITE;

    if (gameOptions.getIDSEnabled()) {
        // 深化迭代

        loggerDebug("IDS: ");

        depth_t depthBegin = 2;
        value_t lastValue = VALUE_ZERO;

        loggerDebug("\n==============================\n");
        loggerDebug("==============================\n");
        loggerDebug("==============================\n");

        for (depth_t i = depthBegin; i < d; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TT::clear();   // 每次走子前清空哈希表
#endif
#endif

#ifdef MTDF_AI
            value = MTDF(value, i);
#else
            value = search(i, alpha, beta);
#endif

            loggerDebug("%d(%d) ", value, value - lastValue);

            lastValue = value;

#ifdef IDS_WINDOW
            alpha = value - VALUE_IDS_WINDOW;
            beta = value + VALUE_IDS_WINDOW;
#endif // IDS_WINDOW
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        loggerDebug("\nIDS Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
        TT::clear();  // 每次走子前清空哈希表
#endif
#endif

    if (gameOptions.getIDSEnabled()) {
#ifdef IDS_WINDOW
        value_t window = state->position->getPhase() == PHASE_PLACING ? VALUE_PLACING_WINDOW : VALUE_MOVING_WINDOW;
        alpha = value - window;
        beta = value + window;
#else
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
#endif // IDS_WINDOW
    }

    originDepth = d;

#ifdef MTDF_AI
    value = MTDF(value, d);
#else
    value = search(d, alpha, beta);
#endif

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    // 生成了 Alpha-Beta 树

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

value_t AIAlgorithm::MTDF(value_t firstguess, depth_t depth)
{
    value_t g = firstguess;
    value_t lowerbound = -VALUE_INFINITE;
    value_t upperbound = VALUE_INFINITE;
    value_t beta;

    while (lowerbound < upperbound) {
        if (g == lowerbound) {
            beta = g + VALUE_MTDF_WINDOW;
        } else {
            beta = g;
        }

        g = search(depth, beta - VALUE_MTDF_WINDOW, beta);

        if (g < beta) {
            upperbound = g;    // fail low
        } else {
            lowerbound = g;    // fail high
        }
    }

    return g;
}

value_t AIAlgorithm::search(depth_t depth, value_t alpha, value_t beta)
{
    // 评价值
    value_t value;
    value_t bestValue = -VALUE_INFINITE;

    // 临时增加的深度，克服水平线效应用
    depth_t epsilon;

#ifdef TT_MOVE_ENABLE
    // 置换表中读取到的最优着法
    move_t ttMove = MOVE_NONE;
#endif // TT_MOVE_ENABLE

#if defined (TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    // 获取哈希值
    hash_t posKey = st->position->getPosKey();
#endif

#ifdef ENDGAME_LEARNING
    // 检索残局库
    Endgame endgame;

    if (gameOptions.getLearnEndgameEnabled() &&
        findEndgameHash(posKey, endgame)) {
        switch (endgame.type) {
        case ENDGAME_PLAYER_BLACK_WIN:
            bestValue = VALUE_WIN;
            bestValue += depth;
            break;
        case ENDGAME_PLAYER_WHITE_WIN:
            bestValue = -VALUE_WIN;
            bestValue -= depth;
            break;
        default:
            break;
        }

        return bestValue;
    }
#endif /* ENDGAME_LEARNING */

#ifdef TRANSPOSITION_TABLE_ENABLE
    bound_t type = BOUND_NONE;

    value_t probeVal = TT::probeHash(posKey, depth, alpha, beta, type
#ifdef TT_MOVE_ENABLE
                                     , ttMove
#endif // TT_MOVE_ENABLE                                     
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        hashHitCount++;
#endif

        bestValue = probeVal;

#if 0
        // TODO: 有必要针对深度微调 value?
        if (position->turn == PLAYER_BLACK)
            bestValue += hashValue.depth - depth;
        else
            bestValue -= hashValue.depth - depth;
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
        hashMissCount++;
    }
#endif

    //hashMapMutex.unlock();
#endif /* TRANSPOSITION_TABLE_ENABLE */

#if 0
    if (position->phase == PHASE_PLACING && depth == 1 && st->position->nPiecesNeedRemove > 0) {
        depth--;
    }
#endif

    if (unlikely(position->phase == PHASE_GAMEOVER) ||   // 搜索到叶子节点（决胜局面） // TODO: 对哈希进行特殊处理
        depth <= 0 ||
        unlikely(requiredQuit)) {
        // 局面评估
        bestValue = Evaluation::getValue(position);

        // 为争取速胜，value 值 +- 深度
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

#ifdef NULL_MOVE
        if (depth % 2 == 1)
        {
            // 空着向前裁剪 (WIP)        
            st->generateNullMove(moves);
            st->generateChildren(moves, this, node);
            doNullMove();
            int moveCount = st->generateMoves(moves);
            if (moveCount)
            {
                st->generateChildren(moves, this, node->children[0]);
                value = -search(depth - 1 - 2, -beta, -beta + 1, node->children[0]);
                undoNullMove();

                if (value >= beta) {
                    bestValue = beta;
                    return beta;
                }
            }

        }
#endif

#ifdef TRANSPOSITION_TABLE_ENABLE
        // 记录确切的哈希值
        TT::recordHash(bestValue,
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

    ExtMove extMoves[MAX_MOVES];
    memset(extMoves, 0, sizeof(extMoves));
    ExtMove *end = generate(st->position, extMoves);
    MovePicker mp(st->position, extMoves);
    mp.score();

    partial_insertion_sort(extMoves, end, -100);
    ExtMove *cur = extMoves;

    int nchild = end - cur;

    if (nchild == 1 && depth == originDepth) {
        bestMove = extMoves[0].move;
        bestValue = VALUE_UNIQUE;
        return bestValue;
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef PREFETCH_SUPPORT
    for (int i = 0; i < nchild; i++) {
        TT::prefetchHash(st->position->getNextMainHash(extMoves[i].move));
    }

#ifdef PREFETCH_DEBUG
    if (posKey << 8 >> 8 == 0x0)
    {
        int pause = 1;
    }
#endif // PREFETCH_DEBUG
#endif // PREFETCH_SUPPORT
#endif // TRANSPOSITION_TABLE_ENABLE

    for (int i = 0; i < nchild; i++) {
        // 棋局入栈保存，以便后续撤销着法
        stashPosition();
        player_t before = st->position->sideToMove;
        move_t move = extMoves[i].move;
        doMove(move);
        player_t after = st->position->sideToMove;

        if (gameOptions.getDepthExtension() == true && nchild == 1) {
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
            value = -search(depth - 1 + epsilon, -beta, -alpha);
        } else {
            value = search(depth - 1 + epsilon, alpha, beta);
        }
#endif // PVS_AI

        undoMove();

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
    TT::recordHash(bestValue,
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
#endif // ALPHABETA_AI

void AIAlgorithm::stashPosition()
{
    // 棋局入栈保存，以便后续撤销着法
    positionStack.push(*(st->position));
}

void AIAlgorithm::doMove(move_t move)
{
    // 执行着法
    st->position->doMove(move);
}

void AIAlgorithm::undoMove()
{
    // 棋局弹出栈，撤销着法
    memcpy(st->position, positionStack.top(), sizeof(Position));
    //st->position = positionStack.top();
    positionStack.pop();
}

void AIAlgorithm::doNullMove()
{
    // 执行空着
    st->position->doNullMove();
}

void AIAlgorithm::undoNullMove()
{
    // 执行空着
    st->position->undoNullMove();
}

#ifdef ALPHABETA_AI
const char* AIAlgorithm::nextMove()
{
    return moveToCommand(bestMove);

#if 0
    char charSelect = '*';

    Board::printBoard();

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

        loggerDebug("[%.2d] %d\t%s\t%d\t%d\t%u %c\n", moveIndex,
                    root->children[i]->move,
                    moveToCommand(root->children[i]->move),
                    root->children[i]->value,
                    root->children[i]->rating,
#ifdef HOSTORY_HEURISTIC
                    root->children[i]->score,
#else
                    0,
#endif
                    charSelect);

        moveIndex++;
    }

    //player_t side = state->position->sideToMove;

#ifdef ENDGAME_LEARNING
    // 检查是否明显劣势
    if (gameOptions.getLearnEndgameEnabled()) {
        if (bestValue <= -VALUE_STRONG) {
            Endgame endgame;
            endgame.type = state->position->sideToMove == PLAYER_BLACK ?
                ENDGAME_PLAYER_WHITE_WIN : ENDGAME_PLAYER_BLACK_WIN;
            hash_t endgameHash = state->position->getPosKey(); // TODO: 减少重复计算哈希
            recordEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    // 检查是否必败
    if (gameOptions.getGiveUpIfMostLose() == true) {
        // 自动认输
        if (root->value <= -VALUE_WIN) {
            sprintf(cmdline, "Player%d give up!", state->position->sideId);
            return cmdline;
        }
    }

    nodeCount = 0;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = hashHitCount + hashMissCount;
    if (hashProbeCount)
    {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, hashHitCount, hashMissCount, hashHitCount * 100 / hashProbeCount);
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

const char *AIAlgorithm::moveToCommand(move_t move)
{
    ring_t rto;
    seat_t sto;
    Board::squareToPolar(to_sq(move), rto, sto);

    if (move < 0) {
        sprintf(cmdline, "-(%1u,%1u)", rto, sto);
    } else if (move & 0x7f00) {
        ring_t rfrom;
        seat_t sfrom;
        Board::squareToPolar(from_sq(move), rfrom, sfrom);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", rfrom, sfrom, rto, sto);
    } else {
        sprintf(cmdline, "(%1u,%1u)", rto, sto);
    }

    return cmdline;
}

#ifdef ENDGAME_LEARNING
bool AIAlgorithm::findEndgameHash(hash_t posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int AIAlgorithm::recordEndgameHash(hash_t posKey, const Endgame &endgame)
{
    //hashMapMutex.lock();
    hash_t hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, HashValue: 0x%08I32x, Address: 0x%08I32x\n", posKey, endgame.type, hashValue, addr);

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
