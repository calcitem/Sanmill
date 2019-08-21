/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include <cmath>
#include <time.h>
#include <QDebug>
#include <QTime>
#include <array>
#include <random>
#include <chrono>
#include <algorithm>

#include "ninechessai_ab.h"
#include "hashmap.h"

using namespace CTSL;

#ifdef HASH_MAP_ENABLE
static constexpr int hashsize = 0x2000000; // 8-128M:102s, 4-64M:93s 2-32M:91s 1-16M: 冲突
HashMap<NineChess::hash_t, NineChessAi_ab::HashValue> hashmap(hashsize);
#endif // HASH_MAP_ENABLE

#ifdef BOOK_LEARNING
static constexpr int bookHashsize = 0x1000000; // 16M
HashMap<NineChess::hash_t, NineChessAi_ab::HashValue> bookHashMap(bookHashsize);
vector<NineChess::hash_t> openingBook;
#endif // BOOK_LEARNING

#ifdef THREEFOLD_REPETITION
vector<NineChess::hash_t> positions;
#endif

NineChessAi_ab::NineChessAi_ab() :
    rootNode(nullptr),
    nodeCount(0),
    evaluatedNodeCount(0),
#ifdef HASH_MAP_ENABLE
#ifdef HASH_MAP_DEBUG
    hashEntryCount(0),
    hashHitCount(0),
    hashInsertNewCount(0),
    hashAddrHitCount(0),
    hashReplaceCozDepthCount(0),
    hashReplaceCozHashCount(0),
#endif
#endif
    requiredQuit(false)
{
    buildRoot();
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
    rootNode = nullptr;
}

NineChessAi_ab::depth_t NineChessAi_ab::changeDepth(depth_t originalDepth)
{
    depth_t newDepth = originalDepth;

    if ((chessTemp.context.stage) & (NineChess::GAME_PLACING)) {
#ifdef GAME_PLACING_DYNAMIC_DEPTH
#ifdef DEAL_WITH_HORIZON_EFFECT
#ifdef HASH_MAP_ENABLE
        depth_t depthTable[] = { 4, 11, 12, 13, 14, 14,  14, 12, 11, 10, 6, 6, 1 };
#else // HASH_MAP_ENABLE
        depth_t depthTable[] = { 2, 11, 11, 11, 11, 10,   9,  8,  8, 8, 7, 7, 1 };
#endif // HASH_MAP_ENABLE
#else // DEAL_WITH_HORIZON_EFFECT
#ifdef HASH_MAP_ENABLE
#ifdef RAPID_CHESS
        depth_t depthTable[] = { 6, 14, 15, 16, 15, 15, 15, 13, 10,  9, 8, 7, 1 };
#else
        depth_t depthTable[] = { 6, 15, 16, 17, 16, 16, 16, 12, 12, 12, 9, 7, 1 };
#endif  // RAPID_CHESS
#else // HASH_MAP_ENABLE
        depth_t depthTable[] = { 2, 13, 13, 13, 12, 11, 10,  9,  9,  8, 8, 7, 1 };
#endif
#endif // DEAL_WITH_HORIZON_EFFECT
        newDepth = depthTable[chessTemp.getPiecesInHandCount_1()];
#elif defined GAME_PLACING_FIXED_DEPTH
        newDepth = GAME_PLACING_FIXED_DEPTH;
#endif // GAME_PLACING_DYNAMIC_DEPTH
    }

#ifdef GAME_MOVING_FIXED_DEPTH
    // 走棋阶段将深度调整
    if ((chessTemp.context.stage) & (NineChess::GAME_MOVING)) {
        newDepth = GAME_MOVING_FIXED_DEPTH;
    }
#endif /* GAME_MOVING_FIXED_DEPTH */

    qDebug() << "Depth:" << newDepth;

    return newDepth;
}

void NineChessAi_ab::buildRoot()
{
    rootNode = addNode(nullptr, 0, 0, 0, NineChess::NOBODY);
}

struct NineChessAi_ab::Node *NineChessAi_ab::addNode(
    Node *parent,
    value_t value,
    move_t move,
    move_t bestMove,
    enum NineChess::Player player
)
{
#ifdef MEMORY_POOL
    Node *newNode = pool.newElement();
#else
    Node *newNode = new Node;
#endif

    newNode->parent = parent;
    newNode->value = value;
    newNode->move = move;

    nodeCount++;
#ifdef DEBUG_AB_TREE
    newNode->id = nodeCount;
#endif

#ifdef SORT_CONSIDER_PRUNED
    newNode->pruned = false;
#endif

#ifdef DEBUG_AB_TREE
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
    newNode->hash = 0;
#endif
#endif

#ifdef DEBUG_AB_TREE
#ifdef HASH_MAP_ENABLE
    newNode->isHash = false;
#endif
#endif

    newNode->player = player;

#ifdef DEBUG_AB_TREE
    newNode->root = rootNode;
    newNode->stage = chessTemp.context.stage;
    newNode->action = chessTemp.context.action;
    newNode->evaluated = false;
    newNode->nPiecesInHandDiff = INT_MAX;
    newNode->nPiecesOnBoardDiff = INT_MAX;
    newNode->nPiecesNeedRemove = INT_MAX;
    newNode->alpha = -INF_VALUE;
    newNode->beta = INF_VALUE;
    newNode->result = 0;
    newNode->visited = false;

    int c, p;
    char cmd[32] = { 0 };

    if (move < 0) {
        chessTemp.pos2cp(-move, c, p);
        sprintf(cmd, "-(%1u,%1u)", c, p);
    } else if (move & 0x7f00) {
        int c1, p1;
        chessTemp.pos2cp(move >> 8, c1, p1);
        chessTemp.pos2cp(move & 0x00ff, c, p);
        sprintf(cmd, "(%1u,%1u)->(%1u,%1u)", c1, p1, c, p);
    } else {
        chessTemp.pos2cp(move & 0x007f, c, p);
        sprintf(cmd, "(%1u,%1u)", c, p);
    }

    newNode->cmd = cmd;
#endif // DEBUG_AB_TREE

    if (parent) {
        // 若没有启用置换表，或启用了但为叶子节点，则 bestMove 为0
        if (bestMove == 0 || move != bestMove) {
#ifdef MILL_FIRST
            // 优先成三
            if (chessTemp.getStage() == NineChess::GAME_PLACING && move > 0 && chessTemp.isInMills(move, true)) {
                parent->children.insert(parent->children.begin(), newNode);
            } else {
                parent->children.push_back(newNode);
            }
#else
            parent->children.push_back(newNode);
#endif
        } else {
            // 如果启用了置换表并且不是叶子结点，把哈希得到的最优着法换到首位
            parent->children.insert(parent->children.begin(), newNode);
        }
    }

    return newNode;
}

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE
void NineChessAi_ab::shuffleMovePriorityTable()
{
    array<int, 4> movePriorityTable0 = { 17, 19, 21, 23 }; // 中圈四个顶点 (星位)
    array<int, 8> movePriorityTable1 = { 25, 27, 29, 31, 9, 11, 13, 15 }; // 外圈和内圈四个顶点
    array<int, 4> movePriorityTable2 = { 16, 18, 20, 22 }; // 中圈十字架
    array<int, 8> movePriorityTable3 = { 8, 10, 12, 14, 24, 26, 28, 30 }; // 内外圈十字架

    unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

    std::shuffle(movePriorityTable0.begin(), movePriorityTable0.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable1.begin(), movePriorityTable1.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable2.begin(), movePriorityTable2.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable3.begin(), movePriorityTable3.end(), std::default_random_engine(seed));

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 0] = movePriorityTable0[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 4] = movePriorityTable1[i];
    }

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 12] = movePriorityTable2[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 16] = movePriorityTable3[i];
    }
}
#endif // #ifdef RANDOM_MOVE
#endif // MOVE_PRIORITY_TABLE_SUPPORT

void NineChessAi_ab::generateLegalMoves(Node *node, move_t bestMove)
{
    const int MOVE_PRIORITY_TABLE_SIZE = NineChess::N_RINGS * NineChess::N_SEATS;
    int pos = 0;
    int newCapacity = 24;

    // 留足余量空间避免多次重新分配，此动作本身也占用 CPU/内存 开销
    switch (chessTemp.getStage()) {
    case NineChess::GAME_PLACING:
        if (chessTemp.getAction() == NineChess::ACTION_CAPTURE) {
            if (chessTemp.whosTurn() == NineChess::PLAYER1)
                newCapacity = chessTemp.getPiecesOnBoardCount_2();
            else
                newCapacity = chessTemp.getPiecesOnBoardCount_1();
        } else {
            newCapacity = chessTemp.getPiecesInHandCount_1() + chessTemp.getPiecesInHandCount_2();
        }
        break;
    case NineChess::GAME_MOVING:
        if (chessTemp.getAction() == NineChess::ACTION_CAPTURE) {
            if (chessTemp.whosTurn() == NineChess::PLAYER1)
                newCapacity = chessTemp.getPiecesOnBoardCount_2();
            else
                newCapacity = chessTemp.getPiecesOnBoardCount_1();
        } else {
            newCapacity = 6;
        }
        break;
    case NineChess::GAME_NOTSTARTED:
        newCapacity = 24;
        break;
    default:
        newCapacity = 24;
        break;
    };

    node->children.reserve(newCapacity + 2 /* TODO: 未细调故再多留余量2 */);

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE

#else // RANDOM_MOVE
    int movePriorityTable[MOVE_PRIORITY_TABLE_SIZE] = {
        17, 19, 21, 23, // 星位
        25, 27, 29, 31, // 外圈四个顶点
         9, 11, 13, 15, // 内圈四个顶点
        16, 18, 20, 22, // 中圈十字架
        24, 26, 28, 30, // 外圈十字架
         8, 10, 12, 14, // 中圈十字架
    };
#endif // RANDOM_MOVE
#else // MOVE_PRIORITY_TABLE_SUPPORT
    int movePriorityTable[MOVE_PRIORITY_TABLE_SIZE] = {
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    };
#endif // MOVE_PRIORITY_TABLE_SUPPORT

    // 如果有子节点，则返回，避免重复建立
    if (node->children.size()) {
        return;
    }

    // 对手
    NineChess::Player opponent = NineChess::getOpponent(chessTemp.context.turn);

    // 列出所有合法的下一招
    switch (chessTemp.context.action) {
    // 对于选子和落子动作
    case NineChess::ACTION_CHOOSE:
    case NineChess::ACTION_PLACE:
        // 对于摆子阶段
        if (chessTemp.context.stage & (NineChess::GAME_PLACING | NineChess::GAME_NOTSTARTED)) {
            for (int i = 0; i < MOVE_PRIORITY_TABLE_SIZE; i++) {
                pos = movePriorityTable[i];

                if (chessTemp.board_[pos]) {
                    continue;
                }

                if (chessTemp.context.stage != NineChess::GAME_NOTSTARTED || node != rootNode) {
                    addNode(node, 0, pos, bestMove, chessTemp.context.turn);
                } else {
                    // 若为先手，则抢占星位
                    if (NineChess::isStarPoint(pos)) {
                        addNode(node, INF_VALUE, pos, bestMove, chessTemp.context.turn);
                    }
                }
            }
            break;
        }

        // 对于移子阶段
        if (chessTemp.context.stage & NineChess::GAME_MOVING) {
            int newPos, oldPos;
#ifdef MOVE_PRIORITY_TABLE_SUPPORT
            // 尽量从位置理论上较差的位置向位置较好的地方移动
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
#else
            for (int i = 0; i < MOVE_PRIORITY_TABLE_SIZE; i++) {
#endif // MOVE_PRIORITY_TABLE_SUPPORT
                oldPos = movePriorityTable[i];

                if (!chessTemp.choose(oldPos)) {
                    continue;
                }

                if ((chessTemp.context.turn == NineChess::PLAYER1 &&
                    (chessTemp.context.nPiecesOnBoard_1 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces)) ||
                    (chessTemp.context.turn == NineChess::PLAYER2 &&
                    (chessTemp.context.nPiecesOnBoard_2 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces))) {
                    // 对于棋盘上还有3个子以上，或不允许飞子的情况，要求必须在着法表中
                    for (int moveDirection = NineChess::MOVE_DIRECTION_CLOCKWISE; moveDirection <= NineChess::MOVE_DIRECTION_OUTWARD; moveDirection++) {
                        // 对于原有位置，遍历四个方向的着法，如果棋盘上为空位就加到结点列表中
                        newPos = chessTemp.moveTable[oldPos][moveDirection];
                        if (newPos && !chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            addNode(node, 0, move, bestMove, chessTemp.context.turn); // (12%)
                        }
                    }
                } else {
                    // 对于棋盘上还有不到3个字，但允许飞子的情况，不要求在着法表中，是空位就行
                    for (newPos = NineChess::POS_BEGIN; newPos < NineChess::POS_END; newPos++) {
                        if (!chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            addNode(node, 0, move, bestMove, chessTemp.context.turn);
                        }
                    }
                }
            }
        }
        break;

    // 对于吃子动作
    case NineChess::ACTION_CAPTURE:
        if (chessTemp.isAllInMills(opponent)) {
            // 全成三的情况
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                pos = movePriorityTable[i];
                if (chessTemp.board_[pos] & opponent) {
                    addNode(node, 0, -pos, bestMove, chessTemp.context.turn);
                }
            }
            break;
        }

        // 不是全成三的情况
        for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
            pos = movePriorityTable[i];
            if (chessTemp.board_[pos] & opponent) {
                if (chessTemp.getRule()->allowRemoveMill || !chessTemp.isInMills(pos)) {
                    addNode(node, 0, -pos, bestMove, chessTemp.context.turn);
                }
            }
        }
        break;

    default:
        break;
    }
}

bool NineChessAi_ab::nodeLess(const Node *first, const Node *second)
{
#ifdef SORT_CONSIDER_PRUNED
    if (first->value < second->value) {
        return true;
    } else if ((first->value == second->value) &&
        (first->pruned == false && second->pruned == true)) {
        return true;
    }

    return false;
#else
    return first->value < second->value;
#endif
}

bool NineChessAi_ab::nodeGreater(const Node *first, const Node *second)
{
#ifdef SORT_CONSIDER_PRUNED
    if (first->value > second->value) {
        return true;
    } else if ((first->value == second->value) &&
        (first->pruned == false && second->pruned == true)) {
        return true;
    }

    return false;
#else
    return first->value > second->value;
#endif
}

void NineChessAi_ab::sortLegalMoves(Node *node)
{
    // 这个函数对效率的影响很大，排序好的话，剪枝较早，节省时间，但不能在此函数耗费太多时间

    if (chessTemp.whosTurn() == NineChess::PLAYER1) {
        std::stable_sort(node->children.begin(), node->children.end(), nodeGreater);
    } else {
        std::stable_sort(node->children.begin(), node->children.end(), nodeLess);
    }
}

void NineChessAi_ab::deleteTree(Node *node)
{
    // 递归删除节点树
    if (node == nullptr) {
        return;
    }

    for (auto i : node->children) {
        deleteTree(i);
    }

    node->children.clear();

#ifdef MEMORY_POOL
    pool.deleteElement(node);
#else
    delete(node);
#endif  
}

void NineChessAi_ab::setChess(const NineChess &chess)
{
    // 如果规则改变，重建hashmap
    if (strcmp(this->chess_.currentRule.name, chess.currentRule.name)) {
#ifdef HASH_MAP_ENABLE
        clearHashMap();
#endif // HASH_MAP_ENABLE

#ifdef BOOK_LEARNING
        // TODO: 规则改变时清空学习表
        //clearBookHashMap();
        //openingBook.clear();
#endif // BOOK_LEARNING

#ifdef THREEFOLD_REPETITION
        positions.clear();
#endif
    }

    this->chess_ = chess;
    chessTemp = chess;
    chessContext = &(chessTemp.context);
    requiredQuit = false;
    deleteTree(rootNode);
#ifdef MEMORY_POOL
    rootNode = pool.newElement();
#else
    rootNode = new Node;
#endif
    rootNode->value = 0;
    rootNode->move = 0;
    rootNode->parent = nullptr;
#ifdef SORT_CONSIDER_PRUNED
    rootNode->pruned = false;
#endif
#ifdef DEBUG_AB_TREE
    rootNode->action = NineChess::ACTION_NONE;
    rootNode->stage = NineChess::GAME_NONE;
    rootNode->root = rootNode;
#endif
}

// 评估子力
#ifdef EVALUATE_ENABLE

#ifdef EVALUATE_MATERIAL
int NineChessAi_ab::evaluateMaterial(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_SPACE
int NineChessAi_ab::evaluateSpace(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_MOBILITY
int NineChessAi_ab::evaluateMobility(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_TEMPO
int NineChessAi_ab::evaluateTempo(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_THREAT
int NineChessAi_ab::evaluateThreat(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_SHAPE
int NineChessAi_ab::evaluateShape(Node *node)
{
    return 0;
}
#endif

#ifdef EVALUATE_MOTIF
int NineChessAi_ab::evaluateMotif(Node *node)
{
    return 0;
}
#endif
#endif /* EVALUATE_ENABLE */

int NineChessAi_ab::evaluate(Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = 0;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

    evaluatedNodeCount++;

#ifdef DEBUG_AB_TREE
    node->stage = chessContext->stage;
    node->action = chessContext->action;
    node->evaluated = true;
#endif

    switch (chessContext->stage) {
    case NineChess::GAME_NOTSTARTED:
        break;

    case NineChess::GAME_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = chessContext->nPiecesInHand_1 - chessContext->nPiecesInHand_2;
        value += nPiecesInHandDiff * 50;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = chessContext->nPiecesOnBoard_1 - chessContext->nPiecesOnBoard_2;
        value += nPiecesOnBoardDiff * 100;
#ifdef DEBUG_AB_TREE
        node->nPiecesOnBoardDiff = nPiecesOnBoardDiff;
#endif

        switch (chessContext->action) {
        // 选子和落子使用相同的评价方法
        case NineChess::ACTION_CHOOSE:
        case NineChess::ACTION_PLACE:
            break;

        // 如果形成去子状态，每有一个可去的子，算100分
        case NineChess::ACTION_CAPTURE:
            nPiecesNeedRemove = (chessContext->turn == NineChess::PLAYER1) ?
                chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
            value += nPiecesNeedRemove * 100;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    case NineChess::GAME_MOVING:
        // 按场上棋子计分
        value += chessContext->nPiecesOnBoard_1 * 100 - chessContext->nPiecesOnBoard_2 * 100;

        switch (chessContext->action) {
         // 选子和落子使用相同的评价方法
        case NineChess::ACTION_CHOOSE:
        case NineChess::ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算128分
        case NineChess::ACTION_CAPTURE:
            nPiecesNeedRemove = (chessContext->turn == NineChess::PLAYER1) ?
                chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
            value += nPiecesNeedRemove * 128;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    // 终局评价最简单
    case NineChess::GAME_OVER:
        // 布局阶段闷棋判断
        if (chessContext->nPiecesOnBoard_1 + chessContext->nPiecesOnBoard_2 >=
            NineChess::N_SEATS * NineChess::N_RINGS) {
            if (chessTemp.currentRule.isStartingPlayerLoseWhenBoardFull) {
                // winner = PLAYER2;
                value -= 10000;
#ifdef DEBUG_AB_TREE
                node->result = -3;
#endif
            } else {
                value = 0;
            }
        }

        // 走棋阶段被闷判断
        if (chessContext->action == NineChess::ACTION_CHOOSE &&
            chessTemp.isAllSurrounded(chessContext->turn) &&
            chessTemp.currentRule.isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
                if (chessContext->turn == NineChess::PLAYER1) {
                    value -= 10000;
#ifdef DEBUG_AB_TREE
                    node->result = -2;
#endif
                } else {
                    value += 10000;
#ifdef DEBUG_AB_TREE
                    node->result = 2;
#endif
                }
        }

        // 剩余棋子个数判断
        if (chessContext->nPiecesOnBoard_1 < chessTemp.currentRule.nPiecesAtLeast) {
            value -= 10000;
#ifdef DEBUG_AB_TREE
            node->result = -1;
#endif
        } else if (chessContext->nPiecesOnBoard_2 < chessTemp.currentRule.nPiecesAtLeast) {
            value += 10000;
#ifdef DEBUG_AB_TREE
            node->result = 1;
#endif
        }

        break;

    default:
        break;
    }

    // 赋值返回
    node->value = value;
    return value;
}

int NineChessAi_ab::alphaBetaPruning(depth_t depth)
{
    QTime time1;
    value_t value = 0;

    depth_t d = changeDepth(depth);

    unsigned int time0 = (unsigned)time(nullptr);
    srand(time0);

    time1.start();

#ifdef BOOK_LEARNING
    if (chess_.getStage() == NineChess::GAME_PLACING)
    {
        if (chess_.context.nPiecesInHand_1 <= 10) {
            // 开局库只记录摆棋阶段最后的局面
            openingBook.push_back(chess_.getHash());
        } else {
            // 暂时在此处清空开局库
            openingBook.clear();
        }
    }
#endif

#ifdef THREEFOLD_REPETITION
    static int nRepetition = 0;

    if (chess_.getStage() == NineChess::GAME_MOVING) {
        NineChess::hash_t hash = chess_.getHash();
        
        if (std::find(positions.begin(), positions.end(), hash) != positions.end()) {
            nRepetition++;
            if (nRepetition == 3) {
                nRepetition = 0;
                return 3;
            }
        } else {
            positions.push_back(hash);
        }
    }

    if (chess_.getStage() == NineChess::GAME_PLACING) {
        positions.clear();
    }
#endif // THREEFOLD_REPETITION

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE
    shuffleMovePriorityTable();
#endif // RANDOM_MOVE
#endif // MOVE_PRIORITY_TABLE_SUPPORT

#ifdef IDS_SUPPORT
    // 深化迭代
    for (depth_t i = 2; i < d; i += 1) {
#ifdef HASH_MAP_ENABLE
#ifdef CLEAR_HASH_MAP
        clearHashMap();   // 每次走子前清空哈希表
#endif
#endif
        alphaBetaPruning(i, -INF_VALUE, INF_VALUE, rootNode);
    }

    qDebug() << "IDS Time: " << time1.elapsed() / 1000.0 << "s";
#endif /* IDS_SUPPORT */

#ifdef HASH_MAP_ENABLE
#ifdef CLEAR_HASH_MAP
    clearHashMap();  // 每次走子前清空哈希表
#endif
#endif

    value = alphaBetaPruning(d, -INF_VALUE /* alpha */, INF_VALUE /* beta */, rootNode);

    qDebug() << "Total Time: " << time1.elapsed() / 1000.0 << "s\n";

    // 生成了 Alpha-Beta 树

    return 0;
}

int NineChessAi_ab::alphaBetaPruning(depth_t depth, value_t alpha, value_t beta, Node *node)
{
    // 评价值
    value_t value;

    // 当前节点的 MinMax 值，最终赋值给节点 value，与 alpha 和 Beta 不同
    value_t minMax;

    // 临时增加的深度，克服水平线效应用
    int epsilon = 0;

    // 子节点的最优着法
    move_t bestMove = 0;

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING))
    // 哈希值
    HashValue hashValue;
    memset(&hashValue, 0, sizeof(hashValue));

    // 哈希类型
    enum HashType hashf = hashfALPHA;

    // 获取哈希值
    NineChess::hash_t hash = chessTemp.getHash();
#ifdef DEBUG_AB_TREE
    node->hash = hash;
#endif
#endif

#ifdef HASH_MAP_ENABLE
    // 检索 hashmap
    //hashMapMutex.lock();

    HashType type = hashfEMPTY;

    value_t probeVal = probeHash(hash, depth, alpha, beta, bestMove, type);

    if (probeVal != INT16_MIN /* TODO: valUNKOWN */  && node != rootNode) {
#ifdef HASH_MAP_DEBUG
        hashHitCount++;
#endif
#ifdef DEBUG_AB_TREE
        node->isHash = true;
#endif
        node->value = probeVal;

#ifdef SORT_CONSIDER_PRUNED
        if (type != hashfEXACT && type != hashfEMPTY) {
            node->pruned = true;    // TODO: 是否有用?
        }
#endif

#if 0
        // TODO: 有必要针对深度微调 value?
        if (chessContext->turn == NineChess::PLAYER1)
            node->value += hashValue.depth - depth;
        else
            node->value -= hashValue.depth - depth;
#endif

        return node->value;
}

    //hashMapMutex.unlock();
#endif /* HASH_MAP_ENABLE */

#ifdef DEBUG_AB_TREE
    node->depth = depth;
    node->root = rootNode;
    // node->player = chessContext->turn;
    // 初始化
    node->isLeaf = false;
    node->isTimeout = false;
    node->visited = true;
#ifdef HASH_MAP_ENABLE
    node->isHash = false;
    node->hash = 0;
#endif // HASH_MAP_ENABLE
#endif // DEBUG_AB_TREE

    // 搜索到叶子节点（决胜局面） // TODO: 对哈希进行特殊处理
    if (chessContext->stage == NineChess::GAME_OVER) {
        // 局面评估
        node->value = evaluate(node);

        // 为争取速胜，value 值 +- 深度
        if (node->value > 0) {
            node->value += depth;
        } else {
            node->value -= depth;
        }

#ifdef DEBUG_AB_TREE
        node->isLeaf = true;
#endif

#ifdef HASH_MAP_ENABLE
        // 记录确切的哈希值
        recordHash(node->value, depth, hashfEXACT, hash, 0);
#endif

        return node->value;
    }

    // 搜索到第0层或需要退出
    if (!depth || requiredQuit) {
        // 局面评估
        node->value = evaluate(node);

        // 为争取速胜，value 值 +- 深度 (有必要?)
        if (chessContext->turn == NineChess::PLAYER1) {
            node->value += depth;
        } else {
            node->value -= depth;
        }

#ifdef DEBUG_AB_TREE
        if (requiredQuit) {
            node->isTimeout = true;
        }
#endif

#ifdef BOOK_LEARNING
        // 检索开局库
        if (chessContext->stage == NineChess::GAME_PLACING && findBookHash(hash, hashValue)) {
            if (chessContext->turn == NineChess::PLAYER2) {
                // 是否需对后手扣分 // TODO: 先后手都处理
                node->value += 1;
                // qDebug() << ">>>>>>>>>>>>>>> New soccer = " << node->value;
            }
        }
#endif

#ifdef HASH_MAP_ENABLE
        // 记录确切的哈希值
        recordHash(node->value, depth, hashfEXACT, hash, 0);
#endif

        return node->value;
    }

    // 生成子节点树，即生成每个合理的着法
    generateLegalMoves(node, bestMove);

    // 根据演算模型执行 MiniMax 检索，对先手，搜索 Max, 对后手，搜索 Min

    minMax = chessTemp.whosTurn() == NineChess::PLAYER1 ? -INF_VALUE : INF_VALUE;

    for (auto child : node->children) {
        // 上下文入栈保存，以便后续撤销着法
        contextStack.push(chessTemp.context);

        // 执行着法
        chessTemp.command(child->move);

#ifdef DEAL_WITH_HORIZON_EFFECT
        // 克服“水平线效应”: 若遇到吃子，则搜索深度增加
        if (child->pruned == false && child->move < 0) {
            epsilon = 1;
        }
        else {
            epsilon = 0;
        }
#endif // DEAL_WITH_HORIZON_EFFECT

#ifdef DEEPER_IF_ONLY_ONE_LEGAL_MOVE
        if (node->children.size() == 1)
            epsilon++;
#endif /* DEEPER_IF_ONLY_ONE_LEGAL_MOVE */

        // 递归 Alpha-Beta 剪枝
        value = alphaBetaPruning(depth - 1 + epsilon, alpha, beta, child);

        // 上下文弹出栈，撤销着法
        chessTemp.context = contextStack.top();
        contextStack.pop();

        if (chessTemp.whosTurn() == NineChess::PLAYER1) {
            // 为走棋一方的层, 局面对走棋的一方来说是以 α 为评价

            // 取最大值
            minMax = std::max(value, minMax);

            // α 为走棋一方搜索到的最好值，任何比它小的值对当前结点的走棋方都没有意义
            // 如果某个着法的结果小于或等于 α，那么它就是很差的着法，因此可以抛弃

            if (value > alpha) {
#ifdef HASH_MAP_ENABLE
                hashf = hashfEXACT;
#endif
                alpha = value;
            }

        } else {

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
#ifdef HASH_MAP_ENABLE
                hashf = hashfBETA;
#endif
                beta = value;
            }
#endif
        }

        // 如果某个着法的结果大于 α 但小于β，那么这个着法就是走棋一方可以考虑走的
        // 否则剪枝返回
        if (alpha >= beta) {
#ifdef SORT_CONSIDER_PRUNED
            node->pruned = true;
#endif
            break;
        }
    }

    node->value = minMax;

#ifdef DEBUG_AB_TREE
    node->alpha = alpha;
    node->beta = beta;
#endif

    // 删除“孙子”节点，防止层数较深的时候节点树太大
#ifndef DONOT_DELETE_TREE
    for (auto child : node->children) {
        for (auto grandChild : child->children) {
            deleteTree(grandChild);
        }
        child->children.clear();
    }
#endif // DONOT_DELETE_TREE

#ifdef IDS_SUPPORT
    // 排序子节点树
    sortLegalMoves(node);
#endif // IDS_SUPPORT

#ifdef HASH_MAP_ENABLE
    // 记录不一定确切的哈希值
    recordHash(node->value, depth, hashf, hash, node->children[0]->move);
#endif /* HASH_MAP_ENABLE */

    // 返回
    return node->value;
}

const char* NineChessAi_ab::bestMove()
{
    vector<Node*> bestMoves;
    size_t bestMovesSize = 0;

    if ((rootNode->children).size() == 0) {
        return "error!";
    }

    qDebug() << "31 ----- 24 ----- 25";
    qDebug() << "| \\       |      / |";
    qDebug() << "|  23 -- 16 -- 17  |";
    qDebug() << "|  | \\    |   / |  |";
    qDebug() << "|  |  15-08-09  |  |";
    qDebug() << "30-22-14    10-18-26";
    qDebug() << "|  |  13-12-11  |  |";
    qDebug() << "|  | /    |   \\ |  |";
    qDebug() << "|  21 -- 20 -- 19  |";
    qDebug() << "| /       |      \\ |";
    qDebug() << "29 ----- 28 ----- 27";
    qDebug() << "";

    int i = 0;
    string moves = "";

    for (auto child : rootNode->children) {
        if (child->value == rootNode->value
#ifdef SORT_CONSIDER_PRUNED
            && !child->pruned
#endif
            ) {
            qDebug("[%.2d] %d\t%s\t%d *", i, child->move, move2string(child->move), child->value);
        } else {
            qDebug("[%.2d] %d\t%s\t%d", i, child->move, move2string(child->move), child->value);
        }

        i++;
    }

    for (auto child : rootNode->children) {
        if (child->value == rootNode->value) {
            bestMoves.push_back(child);
        }
    }

    bestMovesSize = bestMoves.size();

    if (bestMovesSize == 0) {
        qDebug() << "Not any child value is equal to root value";
        for (auto child : rootNode->children) {
            bestMoves.push_back(child);
        }
    }

    qDebug() << "Evaluated: " << evaluatedNodeCount << "/" << nodeCount << " = "
        << evaluatedNodeCount * 100 / nodeCount << "%";
    nodeCount = 0;
    evaluatedNodeCount = 0;

#ifdef HASH_MAP_ENABLE
#ifdef HASH_MAP_DEBUG
    qDebug() << "Hash hit count:" << hashHitCount;
#endif
#endif
    //qDebug() << "sizeof(Node) = " << sizeof(Node);

    return move2string(bestMoves[0]->move);
}

const char *NineChessAi_ab::move2string(move_t move)
{
    int c, p;

    if (move < 0) {
        chessTemp.pos2cp(-move, c, p);
        sprintf(cmdline, "-(%1u,%1u)", c, p);
    } else if (move & 0x7f00) {
        int c1, p1;
        chessTemp.pos2cp(move >> 8, c1, p1);
        chessTemp.pos2cp(move & 0x00ff, c, p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", c1, p1, c, p);
    } else {
        chessTemp.pos2cp(move & 0x007f, c, p);
        sprintf(cmdline, "(%1u,%1u)", c, p);
    }

    return cmdline;
}

#ifdef HASH_MAP_ENABLE
NineChessAi_ab::value_t NineChessAi_ab::probeHash(NineChess::hash_t hash,
                                                  depth_t depth, value_t alpha, value_t beta,
                                                  move_t &bestMove, HashType &type)
{
    const value_t valUNKNOWN = INT16_MIN;
    HashValue hashValue;

    if (hashmap.find(hash, hashValue) == false) {
        return valUNKNOWN;
    }

    if (depth > hashValue.depth) {
        goto out;
    }

    type = hashValue.type;

    if (hashValue.type == hashfEXACT) {
        return hashValue.value;
    }

    if ((hashValue.type == hashfALPHA) && // 最多是 hashValue.value
        (hashValue.value <= alpha)) {
        return alpha;
    }

    if ((hashValue.type == hashfBETA) && // 至少是 hashValue.value
        (hashValue.value >= beta)) {
        return beta;
    }

out:
    bestMove = hashValue.bestMove;
    return valUNKNOWN;
}

bool NineChessAi_ab::findHash(NineChess::hash_t hash, HashValue &hashValue)
{
    return hashmap.find(hash, hashValue);

    // TODO: 变换局面
#if 0
    if (iter != hashmap.end())
        return iter;

    // 变换局面，查找 hash (废弃)
    chessTempShift = chessTemp;
    for (int i = 0; i < 2; i++) {
        if (i)
            chessTempShift.mirror(false);

        for (int j = 0; j < 2; j++) {
            if (j)
                chessTempShift.turn(false);
            for (int k = 0; k < 4; k++) {
                chessTempShift.rotate(k * 90, false);
                iter = hashmap.find(chessTempShift.getHash());
                if (iter != hashmap.end())
                    return iter;
            }
        }
    }
#endif
}

int NineChessAi_ab::recordHash(value_t value, depth_t depth, HashType type, NineChess::hash_t hash, move_t bestMove)
{
    // 同样深度或更深时替换
    // 注意: 每走一步以前都必须把散列表中所有的标志项置为 hashfEMPTY

    //hashMapMutex.lock();
    HashValue hashValue;
    memset(&hashValue, 0, sizeof(HashValue));

    if (findHash(hash, hashValue) &&
        hashValue.type != hashfEMPTY &&
        hashValue.depth > depth) {
#ifdef DEBUG_MODE
        qDebug() << "Skip recordHash coz depth";
#endif
        return -1;
    }

    hashValue.value = value;
    hashValue.depth = depth;
    hashValue.type = type;
    hashValue.bestMove = bestMove;

    hashmap.insert(hash, hashValue);

    //hashMapMutex.unlock();

    return 0;
}

void NineChessAi_ab::clearHashMap()
{
    //hashMapMutex.lock();
    hashmap.clear();
    //hashMapMutex.unlock();
}
#endif /* HASH_MAP_ENABLE */

#ifdef BOOK_LEARNING

bool NineChessAi_ab::findBookHash(NineChess::hash_t hash, HashValue &hashValue)
{
    return bookHashMap.find(hash, hashValue);
}

int NineChessAi_ab::recordBookHash(NineChess::hash_t hash, const HashValue &hashValue)
{
    //hashMapMutex.lock();
    bookHashMap.insert(hash, hashValue);
    //hashMapMutex.unlock();

    return 0;
}

void NineChessAi_ab::clearBookHashMap()
{
    //hashMapMutex.lock();
    bookHashMap.clear();
    //hashMapMutex.unlock();
}

void NineChessAi_ab::recordOpeningBookToHashMap()
{
    HashValue hashValue;
    NineChess::hash_t hash = 0;

    for (auto iter = openingBook.begin(); iter != openingBook.end(); ++iter)
    {
#if 0
        if (findBookHash(*iter, hashValue))
        {
        }
#endif
        memset(&hashValue, 0, sizeof(HashValue));
        hash = *iter;
        recordBookHash(hash, hashValue);  // 暂时使用直接覆盖策略
    }

    //qDebug("Record %d items to Opening Book\n", openingBook.size());

    openingBook.clear();
}

void NineChessAi_ab::recordOpeningBookHashMapToFile()
{
    const QString bookFileName = "opening-book.txt";
    qDebug() << "Dump Opening Book to file...";
    bookHashMap.dump(bookFileName);
}

void NineChessAi_ab::loadOpeningBookFileToHashMap()
{
    const QString bookFileName = "opening-book.txt";
    qDebug() << "Loading Opening Book from file...";
    bookHashMap.load(bookFileName);
}
#endif // BOOK_LEARNING
