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

#define SORT_NAME nodep
#define SORT_TYPE Node*
#ifdef ALPHABETA_AI
#define SORT_CMP(x, y) (AIAlgorithm::nodeCompare((x), (y)))
#endif

player_t gSideToMove;

#include "sort.h"

using namespace CTSL;

// 用于检测重复局面 (Position)
vector<hash_t> moveHistory;

AIAlgorithm::AIAlgorithm()
{
    state = new StateInfo();
    st = new StateInfo();

    memmgr.memmgr_init();

    buildRoot();
}

AIAlgorithm::~AIAlgorithm()
{
    deleteTree(root);
    root = nullptr;

    memmgr.memmgr_exit();

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
         +4, 12, +12, 12,     /* 4 ~ 7 */
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
            d = placingDepthTable_12[rule.nTotalPiecesEachSide * 2 - st->getPiecesInHandCount(BLACK) - st->getPiecesInHandCount(WHITE)];
        } else {
            d = placingDepthTable_9[rule.nTotalPiecesEachSide * 2 - st->getPiecesInHandCount(BLACK) - st->getPiecesInHandCount(WHITE)];
        }
    }

    if (st->position->phase & PHASE_MOVING) {
        int pb = st->getPiecesOnBoardCount(BLACK);
        int pw = st->getPiecesOnBoardCount(WHITE);

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

void AIAlgorithm::buildRoot()
{
    root = (Node *)memmgr.memmgr_alloc(sizeof(Node));

    assert(root != nullptr);

    root->parent = nullptr;
    root->move = MOVE_NONE;

#ifdef ALPHABETA_AI
    root->value = VALUE_ZERO;
    root->rating = RATING_ZERO;
#endif // ALPHABETA_AI

    root->sideToMove = PLAYER_NOBODY;

#ifdef BEST_MOVE_ENABLE
    root->bestMove = MOVE_NONE;
#endif // BEST_MOVE_ENABLE
}

Node *Node::addChild(
    const move_t &m,
    AIAlgorithm *ai,
    StateInfo *st
#ifdef BEST_MOVE_ENABLE
    , const move_t &bestMove
#endif // BEST_MOVE_ENABLE
)
{
    Node *newNode = (Node *)ai->memmgr.memmgr_alloc(sizeof(Node));

    if (unlikely(newNode == nullptr)) {
        ai->memmgr.memmgr_print_stats();
        loggerDebug("Memory Manager Alloc failed\n");
        // TODO: Deal with alloc failed
        return nullptr;
    }

    newNode->move = m;

#ifdef ALPHABETA_AI
    newNode->value = VALUE_ZERO;
    newNode->rating = RATING_ZERO;

#ifdef SORT_CONSIDER_PRUNED
    newNode->pruned = false;
#endif
#endif // ALPHABETA_AI

    newNode->childrenSize = 0;  // Important
    newNode->parent = this;

    ai->nodeCount++;
#ifdef DEBUG_AB_TREE
    newNode->id = nodeCount;
#endif

#ifdef DEBUG_AB_TREE
    newNode->hash = 0;
#endif

#ifdef DEBUG_AB_TREE
#ifdef TRANSPOSITION_TABLE_ENABLE
    newNode->isHash = false;
#endif
#endif

#ifdef DEBUG_AB_TREE
    newNode->root = root;
    newNode->phase = st->position.phase;
    newNode->action = st->position.action;
    newNode->evaluated = false;
    newNode->nPiecesInHandDiff = std::numeric_limits<int>::max();
    newNode->nPiecesOnBoardDiff = std::numeric_limits<int>::max();
    newNode->nPiecesNeedRemove = std::numeric_limits<int>::max();
    newNode->alpha = -VALUE_INFINITE;
    newNode->beta = VALUE_INFINITE;
    newNode->visited = false;

    int r, s;
    char cmd[32] = { 0 };

    if (move < 0) {
        st->position.board.squareToPolar(static_cast<square_t>(-move), r, s);
        sprintf(cmd, "-(%1u,%1u)", r, s);
    } else if (move & 0x7f00) {
        int r1, s1;
        st->position.board.squareToPolar(static_cast<square_t>(move >> 8), r1, s1);
        st->position.board.squareToPolar(static_cast<square_t>(move & 0x00ff), r, s);
        sprintf(cmd, "(%1u,%1u)->(%1u,%1u)", r1, s1, r, s);
    } else {
        st->position.board.squareToPolar(static_cast<square_t>(move & 0x007f), r, s);
        sprintf(cmd, "(%1u,%1u)", r, s);
    }

    strcpy(newNode->cmd, cmd);
#endif // DEBUG_AB_TREE

    children[childrenSize] = newNode;
    childrenSize++;

#ifdef BEST_MOVE_ENABLE
    // 如果启用了置换表并且不是叶子结点
    if (move == bestMove && move != 0) {
        newNode->rating += RATING_TT;
        return newNode;
    }
#endif // BEST_MOVE_ENABLE

    // 若没有启用置换表，或启用了但为叶子节点，则 bestMove 为0
    square_t sq = SQ_0;

    if (m > 0) {
        // 摆子或者走子
        sq = (square_t)(m & 0x00ff);
    } else {
        // 吃子
        sq = (square_t)((-m) & 0x00ff);
    }

    int nMills = st->position->board.inHowManyMills(sq, st->position->sideToMove);
    int nopponentMills = 0;

#ifdef SORT_MOVE_WITH_HUMAN_KNOWLEDGES
    // TODO: rule.allowRemoveMultiPieces 以及 适配打三棋之外的其他规则
    if (m > 0) {
        // 在任何阶段, 都检测落子点是否能使得本方成三
        // TODO: 为走子之前的统计故走棋阶段可能会从 @-0-@ 走成 0-@-@, 并未成三
        if (nMills > 0) {
#ifdef ALPHABETA_AI
            newNode->rating += static_cast<rating_t>(RATING_ONE_MILL * nMills);
#endif
        } else if (st->getPhase() == PHASE_PLACING) {
            // 在摆棋阶段, 检测落子点是否能阻止对方成三
            nopponentMills = st->position->board.inHowManyMills(sq, st->position->opponent);
#ifdef ALPHABETA_AI
            newNode->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
#endif
        }
#if 1
        else if (st->getPhase() == PHASE_MOVING) {
            // 在走棋阶段, 检测落子点是否能阻止对方成三
            nopponentMills = st->position->board.inHowManyMills(sq, st->position->opponent);

            if (nopponentMills) {
                int nPlayerPiece = 0;
                int nOpponentPiece = 0;
                int nForbidden = 0;
                int nEmpty = 0;

                st->position->board.getSurroundedPieceCount(sq, st->position->sideId,
                                                                nPlayerPiece, nOpponentPiece, nForbidden, nEmpty);

#ifdef ALPHABETA_AI
                if (sq % 2 == 0 && nOpponentPiece == 3) {
                    newNode->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
                } else if (sq % 2 == 1 && nOpponentPiece == 2 && rule.nTotalPiecesEachSide == 12) {
                    newNode->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
                }
#endif
            }
        }
#endif

        //newNode->rating += static_cast<rating_t>(nForbidden);  // 摆子阶段尽量往禁点旁边落子

        // 对于12子棋, 白方第2着走星点的重要性和成三一样重要 (TODO)
#ifdef ALPHABETA_AI
        if (rule.nTotalPiecesEachSide == 12 &&
            st->getPiecesOnBoardCount(2) < 2 &&    // patch: 仅当白方第2着时
            Board::isStar(static_cast<square_t>(m))) {
            newNode->rating += RATING_STAR_SQUARE;
        }
#endif
    } else if (m < 0) {
        int nPlayerPiece = 0;
        int nOpponentPiece = 0;
        int nForbidden = 0;
        int nEmpty = 0;

        st->position->board.getSurroundedPieceCount(sq, st->position->sideId,
                                                        nPlayerPiece, nOpponentPiece, nForbidden, nEmpty);

#ifdef ALPHABETA_AI
        if (nMills > 0) {
            // 吃子点处于我方的三连中
            //newNode->rating += static_cast<rating_t>(RATING_CAPTURE_ONE_MILL * nMills);
       
            if (nOpponentPiece == 0) {
                // 吃子点旁边没有对方棋子则优先考虑     
                newNode->rating += static_cast<rating_t>(1);
                if (nPlayerPiece > 0) {
                    // 且吃子点旁边有我方棋子则更优先考虑
                    newNode->rating += static_cast<rating_t>(nPlayerPiece);
                }
            }
        }

        // 吃子点处于对方的三连中
        nopponentMills = st->position->board.inHowManyMills(sq, st->position->opponent);
        if (nopponentMills) {
            if (nOpponentPiece >= 2) {
                // 旁边对方的子较多, 则倾向不吃
                newNode->rating -= static_cast<rating_t>(nOpponentPiece);

                if (nPlayerPiece == 0) {
                    // 如果旁边无我方棋子, 则更倾向不吃
                    newNode->rating -= static_cast<rating_t>(1);
                }
            }
        }

        // 优先吃活动力强的棋子
        newNode->rating += static_cast<rating_t>(nEmpty);
#endif
    }
#endif // SORT_MOVE_WITH_HUMAN_KNOWLEDGES

    return newNode;
}

#ifdef ALPHABETA_AI
int AIAlgorithm::nodeCompare(const Node *first, const Node *second)
{
    //return second->rating - first->rating;

    if (first->rating == second->rating) {
        if (first->value == second->value) {
            return 0;
        }

        int ret = (gSideToMove == PLAYER_BLACK ? 1 : -1);

        return (first->value < second->value ? ret : -ret);
    }

    return (first->rating < second->rating ? 1 : -1);
}
#endif

void AIAlgorithm::sortMoves(Node *node)
{
    // 这个函数对效率的影响很大，排序好的话，剪枝较早，节省时间，但不能在此函数耗费太多时间
    assert(node->childrenSize != 0);

    //#define DEBUG_SORT
#ifdef DEBUG_SORT
    for (int i = 0; i < node->childrenSize; i++) {
        loggerDebug("* [%d] %p: %d = %d %d (%d)\n",
                    i, &(node->children[i]), node->children[i]->move, node->children[i]->value, node->children[i]->rating, !node->children[i]->pruned);
    }
    loggerDebug("\n");
#endif

#define NODE_PTR_SORT_FUN(x) nodep_##x

    gSideToMove = st->position->sideToMove; // TODO: 暂时用全局变量

    // 此处选用排序算法, 各算法耗时统计如下:
    /*
     * sqrt_sort_sort_ins:          100% (4272)
     * bubble_sort:                 115% (4920)
     * binary_insertion_sort:       122% (5209)
     * merge_sort:                  131% (5612)
     * grail_lazy_stable_sort:      175% (7471)
     * tim_sort:                    185% (7885)
     * selection_sort:              202% (8642)
     * rec_stable_sort:             226% (9646)
     * sqrt_sort:                   275% (11729)
     */
#ifdef TIME_STAT
    auto timeStart = now();
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
#endif

    NODE_PTR_SORT_FUN(sqrt_sort_sort_ins)(node->children, node->childrenSize);

#ifdef TIME_STAT
    auto timeEnd = now();
    sortTime += (timeEnd - timeStart);
#endif
#ifdef CYCLE_STAT
    auto cycleEnd = stopwatch::rdtscp_clock::now();
    sortCycle += (cycleEnd - cycleStart);
#endif

#ifdef DEBUG_SORT
    if (st->position.sideToMove == PLAYER_BLACK) {
        for (int i = 0; i < node->childrenSize; i++) {
            loggerDebug("+ [%d] %p: %d = %d %d (%d)\n",
                        i, &(node->children[i]), node->children[i]->move, node->children[i]->value, node->children[i]->rating, !node->children[i]->pruned);
        }
     } else {
        for (int i = 0; i < node->childrenSize; i++) {
            loggerDebug("- [%d] %p: %d = %d %d (%d)\n",
                        i, &(node->children[i]), node->children[i]->move, node->children[i]->value, node->children[i]->rating, !node->children[i]->pruned);
        }
    }
    loggerDebug("\n----------------------------------------\n");
#endif

    assert(node->childrenSize != 0);
}

void AIAlgorithm::deleteTree(Node *node)
{
    int nchild = node->childrenSize;

    for (int i = 0; i < nchild; i++) {
        deleteTree(node->children[i]);
    }

    node->childrenSize = 0;

    memmgr.memmgr_free(node);
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
    deleteTree(root);

    root = (Node *)memmgr.memmgr_alloc(sizeof(Node));
    assert(root != nullptr);

    memset(root, 0, sizeof(Node));
 
#ifdef DEBUG_AB_TREE
    root->root = root;
#endif
}

#ifdef ALPHABETA_AI
int AIAlgorithm::search(depth_t depth)
{
    assert(root != nullptr);

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

    if (state->getPhase() == PHASE_MOVING) {
        hash_t hash = state->getHash();
        
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

    if (state->getPhase() == PHASE_PLACING) {
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
            value = search(i, alpha, beta, root);

            loggerDebug("%d(%d) ", value, value - lastValue);

#ifdef IDS_DEBUG
            loggerDebug(": --------------- depth = %d/%d ---------------\n", i, d);
            int k = 0;
            int cs = root->childrenSize;
            for (int j = 0; j < cs; j++) {
                if (root->children[j]->value == root->value
#ifdef SORT_CONSIDER_PRUNED
                    && !root->children[j]->pruned
#endif
                    ) {
                    loggerDebug("[%.2d] %d\t%s\t%d\t%d *\n", k,
                                root->children[j]->move,
                                moveToCommand(root->children[j]->move),
                                root->children[j]->value,
                                root->children[j]->rating);
                } else {
                    loggerDebug("[%.2d] %d\t%s\t%d\t%d\n", k,
                                root->children[j]->move,
                                moveToCommand(root->children[j]->move),
                                root->children[j]->value,
                                root->children[j]->rating);
                }

                k++;
            }
            loggerDebug("\n");
#endif // IDS_DEBUG

            lastValue = value;

#if 0
            if (value <= alpha) {
                alpha = -VALUE_INFINITE;
                beta = value + 1;   // X
                continue;
            }
            if (value >= beta) {
                beta = VALUE_INFINITE;
                alpha = value - 1;
                continue;
            }
#endif

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
        value_t window = state->getPhase() == PHASE_PLACING ? VALUE_PLACING_WINDOW : VALUE_MOVING_WINDOW;
        alpha = value - window;
        beta = value + window;
#else
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
#endif // IDS_WINDOW
    }

    value = search(d, alpha, beta, root);

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    // 生成了 Alpha-Beta 树

    return 0;
}

value_t AIAlgorithm::search(depth_t depth, value_t alpha, value_t beta, Node *node)
{
    assert(node != nullptr);
    
    // 评价值
    value_t value;

    // 当前节点的 MinMax 值，最终赋值给节点 value，与 alpha 和 Beta 不同
    value_t minMax;

    // 临时增加的深度，克服水平线效应用
    depth_t epsilon = 0;

#ifdef BEST_MOVE_ENABLE
    // 子节点的最优着法
    move_t bestMove = MOVE_NONE;
#endif // BEST_MOVE_ENABLE

#if defined (TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    // 获取哈希值
    hash_t hash = st->getHash();
#endif

#ifdef ENDGAME_LEARNING
    // 检索残局库
    Endgame endgame;

    if (gameOptions.getLearnEndgameEnabled() &&
        findEndgameHash(hash, endgame)) {
        switch (endgame.type) {
        case ENDGAME_PLAYER_BLACK_WIN:
            node->value = VALUE_WIN;
            node->value += depth;
            break;
        case ENDGAME_PLAYER_WHITE_WIN:
            node->value = -VALUE_WIN;
            node->value -= depth;
            break;
        default:
            break;
        }

        return node->value;
    }
#endif /* ENDGAME_LEARNING */

#ifdef TRANSPOSITION_TABLE_ENABLE
    // 哈希类型
    enum TT::HashType hashf = TT::hashfALPHA;
    
#ifdef DEBUG_AB_TREE
    node->hash = hash;
#endif

    TT::HashType type = TT::hashfEMPTY;

    value_t probeVal = TT::probeHash(hash, depth, alpha, beta, type
#ifdef BEST_MOVE_ENABLE
                                     , bestMove
#endif // BEST_MOVE_ENABLE                                     
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef DEBUG_MODE
        assert(node != root);
#endif
#ifdef TRANSPOSITION_TABLE_DEBUG
        hashHitCount++;
#endif
#ifdef DEBUG_AB_TREE
        node->isHash = true;
#endif
        node->value = probeVal;

#ifdef SORT_CONSIDER_PRUNED
        if (type != TT::hashfEXACT && type != TT::hashfEMPTY) {
            node->pruned = true;    // TODO: 是否有用?
        }
#endif

#if 0
        // TODO: 有必要针对深度微调 value?
        if (position->turn == PLAYER_BLACK)
            node->value += hashValue.depth - depth;
        else
            node->value -= hashValue.depth - depth;
#endif

        return node->value;
    }
#ifdef TRANSPOSITION_TABLE_DEBUG
    else {
        hashMissCount++;
    }
#endif

    //hashMapMutex.unlock();
#endif /* TRANSPOSITION_TABLE_ENABLE */

#ifdef DEBUG_AB_TREE
    node->depth = depth;
    node->root = root;
    // node->player = position->turn;
    // 初始化
    node->isLeaf = false;
    node->isTimeout = false;
    node->visited = true;
#ifdef TRANSPOSITION_TABLE_ENABLE
    node->isHash = false;
    node->hash = 0;
#endif // TRANSPOSITION_TABLE_ENABLE
#endif // DEBUG_AB_TREE

#if 0
    if (position->phase == PHASE_PLACING && depth == 1 && st->position->nPiecesNeedRemove > 0) {
        depth--;
    }
#endif

    if (unlikely(position->phase == PHASE_GAMEOVER) ||   // 搜索到叶子节点（决胜局面） // TODO: 对哈希进行特殊处理
        !depth ||   // 搜索到第0层
        unlikely(requiredQuit)) {
        // 局面评估
        node->value = Evaluation::getValue(st, position, node);
        evaluatedNodeCount++;

        // 为争取速胜，value 值 +- 深度
        if (node->value > 0) {
            node->value += depth;
        } else {
            node->value -= depth;
        }

#ifdef DEBUG_AB_TREE
        if (requiredQuit) {
            node->isTimeout = true;
        } else {
            node->isLeaf = true;
        }
#endif

#ifdef TRANSPOSITION_TABLE_ENABLE
        // 记录确切的哈希值
        TT::recordHash(node->value,
                       depth,
                       TT::hashfEXACT,
                       hash
#ifdef BEST_MOVE_ENABLE
                       , MOVE_NONE
#endif // BEST_MOVE_ENABLE
                      );
#endif

        return node->value;
    }

    // 生成子节点树，即生成每个合理的着法
    if (node->childrenSize == 0) {
        int moveSize = st->generateMoves(moves);

        st->generateChildren(moves, this, node
#ifdef BEST_MOVE_ENABLE
                             , bestMove
#endif // BEST_MOVE_ENABLE
                             );

        if (node == root && moveSize == 1) {
            return node->value;
        }
    }

    // 排序子节点树
    sortMoves(node);

    // 根据演算模型执行 MiniMax 检索，对先手，搜索 Max, 对后手，搜索 Min

    minMax = st->position->sideToMove == PLAYER_BLACK ? -VALUE_INFINITE : VALUE_INFINITE;

    assert(node->childrenSize != 0);

#ifdef CLEAR_PRUNED_FLAG_BEFORE_SEARCH
#ifdef SORT_CONSIDER_PRUNED
    node->pruned = false;
#endif  // SORT_CONSIDER_PRUNED
#endif // CLEAR_PRUNED_FLAG_BEFORE_SEARCH

    int nchild = node->childrenSize;

#ifdef PREFETCH_SUPPORT
    for (int i = 0; i < nchild; i++) {
        TT::prefetchHash(st->getNextMainHash(node->children[i]->move));
    }
#endif // PREFETCH_SUPPORT

    for (int i = 0; i < nchild; i++) {
        // 棋局入栈保存，以便后续撤销着法
        stashPosition();

        doMove(node->children[i]->move);

        if (gameOptions.getDepthExtension() == true && nchild == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

        // 递归 Alpha-Beta 剪枝
        value = search(depth - 1 + epsilon, alpha, beta, node->children[i]);

        undoMove();

        switch (st->position->sideToMove) {
        case PLAYER_BLACK:
            // 为走棋一方的层, 局面对走棋的一方来说是以 α 为评价

            // 取最大值
            minMax = std::max(value, minMax);

            // α 为走棋一方搜索到的最好值，任何比它小的值对当前结点的走棋方都没有意义
            // 如果某个着法的结果小于或等于 α，那么它就是很差的着法，因此可以抛弃

            if (value > alpha) {
#ifdef TRANSPOSITION_TABLE_ENABLE
                hashf = TT::hashfEXACT;
#endif
                alpha = value;
            }

            break;

        case PLAYER_WHITE:
            // 为走棋方的对手一方的层, 局面对对手一方来说是以 β 为评价

           // 取最小值
            minMax = std::min(value, minMax);

            // β 表示对手目前的劣势，这是对手所能承受的最坏结果
            // β 值越大，表示对手劣势越明显
            // 在对手看来，他总是会找到一个对策不比 β 更坏的
            // 如果当前结点返回 β 或比 β 更好的值，作为父结点的对方就绝对不会选择这种策略，
            // 如果搜索过程中返回 β 或比 β 更好的值，那就够好的了，走棋的一方就没有机会使用这种策略了。
            // 如果某个着法的结果大于或等于 β，那么整个结点就作废了，因为对手不希望走到这个局面，而它有别的着法可以避免到达这个局面。
            // 因此如果我们找到的评价大于或等于β，就证明了这个结点是不会发生的，因此剩下的合理着法没有必要再搜索。

            // TODO: 本意是要删掉这句，忘了删，结果反而棋力没有明显问题，待查
            // 如果删掉这句，启用下面这段代码，则三有时不会堵并且计算效率较低
            // 有了这句之后，hashf 不可能等于 hashfBETA
            beta = std::min(value, beta);

#if 0
            if (value < beta) {
#ifdef TRANSPOSITION_TABLE_ENABLE
                hashf = hashfBETA;
#endif
                beta = value;
            }
#endif
            break;
        default:
            break;
        }
        
#ifndef MIN_MAX_ONLY
        // 如果某个着法的结果大于 α 但小于β，那么这个着法就是走棋一方可以考虑走的
        // 否则剪枝返回
        if (alpha >= beta) {
#ifdef SORT_CONSIDER_PRUNED
            node->pruned = true;
#endif
            break;
        }
#endif /* !MIN_MAX_ONLY */
    }

    node->value = minMax;

#ifdef DEBUG_AB_TREE
    node->alpha = alpha;
    node->beta = beta;
#endif

    // 删除“孙子”节点，防止层数较深的时候节点树太大
#ifndef DONOT_DELETE_TREE
    int cs =  node->childrenSize;
    for (int i = 0; i < cs; i++) {
        Node *c = node->children[i];
        int size = c->childrenSize;
        for (int j = 0; j < size; j++) {
            deleteTree(c->children[j]);
        }
        c->childrenSize = 0;
    }
#endif // DONOT_DELETE_TREE

    if (gameOptions.getIDSEnabled()) {
#ifdef IDS_ADD_VALUE
        if (st->position->sideToMove == PLAYER_BLACK) {
            node->children[0]->value += 1;
            node->value += 1;
        } else {
            node->children[0]->value -= 1;
            node->value -= 1;
        }
#endif /* IDS_ADD_VALUE */
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
    // 记录不一定确切的哈希值
    TT::recordHash(node->value,
                   depth,
                   hashf,
                   hash
#ifdef BEST_MOVE_ENABLE
                   , node->children[0]->move
#endif // BEST_MOVE_ENABLE
                  );
#endif /* TRANSPOSITION_TABLE_ENABLE */

    // 返回
    return node->value;
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
    st->doMove(move);
}

void AIAlgorithm::undoMove()
{
    // 棋局弹出栈，撤销着法
    memcpy(st->position, positionStack.top(), sizeof(Position));
    //st->position = positionStack.top();
    positionStack.pop();
}

#ifdef ALPHABETA_AI
const char* AIAlgorithm::bestMove()
{
    vector<Node*> bestMoves;
    size_t bestMovesSize = 0;

    if (!root->childrenSize) {
        return "error!";
    }

    Board::printBoard();

    int i = 0;

    int cs = root->childrenSize;
    for (int j = 0; j < cs; j++) {
        if (root->children[j]->value == root->value
#ifdef SORT_CONSIDER_PRUNED
            && !root->children[j]->pruned
#endif
            ) {
            loggerDebug("[%.2d] %d\t%s\t%d\t%d *\n", i, root->children[j]->move, moveToCommand(root->children[j]->move), root->children[j]->value, root->children[j]->rating);
        } else {
            loggerDebug("[%.2d] %d\t%s\t%d\t%d\n", i, root->children[j]->move, moveToCommand(root->children[j]->move), root->children[j]->value, root->children[j]->rating);
        }

        i++;
    }

    player_t side = state->position->sideToMove;

#ifdef ENDGAME_LEARNING
    // 检查是否明显劣势
    if (gameOptions.getLearnEndgameEnabled()) {
        bool isMostWeak = true; // 是否明显劣势

        for (int j = 0; j < root->childrenSize; j++) {
            if ((side == PLAYER_BLACK && root->children[j]->value > -VALUE_STRONG) ||
                (side == PLAYER_WHITE && root->children[j]->value < VALUE_STRONG)) {
                isMostWeak = false;
                break;
            }
        }

        if (isMostWeak) {
            Endgame endgame;
            endgame.type = state->position->sideToMove == PLAYER_BLACK ?
                ENDGAME_PLAYER_WHITE_WIN : ENDGAME_PLAYER_BLACK_WIN;
            hash_t endgameHash = this->state->getHash(); // TODO: 减少重复计算哈希
            recordEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    // 检查是否必败
    if (gameOptions.getGiveUpIfMostLose() == true) {
        bool isMostLose = true; // 是否必败

        for (int j = 0; j < root->childrenSize; j++) {
            if ((side == PLAYER_BLACK && root->children[j]->value > -VALUE_WIN) ||
                (side == PLAYER_WHITE && root->children[j]->value < VALUE_WIN)) {
                isMostLose = false;
                break;
            }
        }

        // 自动认输
        if (isMostLose) {
            sprintf(cmdline, "Player%d give up!", state->position->sideId);
            return cmdline;
        }
    }

    int nchild = root->childrenSize;
    for (int j = 0; j < nchild; j++) {
        if (root->children[j]->value == root->value) {
            bestMoves.push_back(root->children[j]);
        }
    }

    bestMovesSize = bestMoves.size();

    if (bestMovesSize == 0) {
        loggerDebug("Not any child value is equal to root value\n");

        for (int j = 0; j < root->childrenSize; j++) {
            bestMoves.push_back(root->children[j]);
        }
    }

    loggerDebug("Evaluated: %llu / %llu = %llu%%\n", evaluatedNodeCount, nodeCount, evaluatedNodeCount * 100 / nodeCount);
    memmgr.memmgr_print_stats();

    nodeCount = 0;
    evaluatedNodeCount = 0;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = hashHitCount + hashMissCount;
    if (hashProbeCount)
    {
        loggerDebug("[hash] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, hashHitCount, hashMissCount, hashHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    if (bestMoves.empty()) {
        return nullptr;
    }

    return moveToCommand(bestMoves[0]->move);
}
#endif // ALPHABETA_AI

const char *AIAlgorithm::moveToCommand(move_t move)
{
    int r, s;

    if (move < 0) {
        Board::squareToPolar(static_cast<square_t>(-move), r, s);
        sprintf(cmdline, "-(%1u,%1u)", r, s);
    } else if (move & 0x7f00) {
        int r1, s1;
        Board::squareToPolar(static_cast<square_t>(move >> 8), r1, s1);
        Board::squareToPolar(static_cast<square_t>(move & 0x00ff), r, s);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", r1, s1, r, s);
    } else {
        Board::squareToPolar(static_cast<square_t>(move & 0x007f), r, s);
        sprintf(cmdline, "(%1u,%1u)", r, s);
    }

    return cmdline;
}

#ifdef ENDGAME_LEARNING
bool AIAlgorithm::findEndgameHash(hash_t hash, Endgame &endgame)
{
    return endgameHashMap.find(hash, endgame);
}

int AIAlgorithm::recordEndgameHash(hash_t hash, const Endgame &endgame)
{
    //hashMapMutex.lock();
    hash_t hashValue = endgameHashMap.insert(hash, endgame);
    unsigned addr = hashValue * (sizeof(hash) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, HashValue: 0x%08I32x, Address: 0x%08I32x\n", hash, endgame.type, hashValue, addr);

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
