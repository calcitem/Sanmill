/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#include "ninechessai_ab.h"
#include <cmath>
#include <time.h>
#include <Qdebug>
#include <QTime>
#include <array>
#include <random>
#include <chrono>
#include <algorithm>


NineChessAi_ab::NineChessAi_ab() :
    rootNode(nullptr),
    requiredQuit(false),
    nodeCount(0),
    evaluatedNodeCount(0),
    hashHitCount(0)
{
    buildRoot();
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
    rootNode = nullptr;
}

void NineChessAi_ab::clearHashMap()
{
    hashMapMutex.lock();
    hashmap.clear();
    hashmap.reserve(maxHashCount);
    hashMapMutex.unlock();
}

void NineChessAi_ab::buildRoot()
{
    rootNode = addNode(nullptr, 0, 0, NineChess::NOBODY);
}

struct NineChessAi_ab::Node *NineChessAi_ab::addNode(Node *parent, int value, int move, enum NineChess::Player player)
{
    Node *newNode = new Node;   // (10%)
    newNode->parent = parent;
    newNode->value = value;
    newNode->move = move;
    
    nodeCount++;
    newNode->id = nodeCount;

    //newNode->rand = rand() % 24; // (1%)

    newNode->pruned = false;

#ifdef DEBUG_AB_TREE
    newNode->player = player;
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
    newNode->isHash = false;
    newNode->visited = false;

    int c, p;
    char cmd[32] = { 0 };

    if (move < 0) {
        chessTemp.pos2cp(-move, c, p);
        sprintf(cmd, "-(%1u,%1u)", c, p);   // (3%)
    } else if (move & 0x7f00) {
        int c1, p1;
        chessTemp.pos2cp(move >> 8, c1, p1);
        chessTemp.pos2cp(move & 0x00ff, c, p);
        sprintf(cmd, "(%1u,%1u)->(%1u,%1u)", c1, p1, c, p);     // (7%)
    } else {
        chessTemp.pos2cp(move & 0x007f, c, p);
        sprintf(cmd, "(%1u,%1u)", c, p);    // (12%)
    }

    newNode->cmd = cmd;
#endif

    if (parent) {
        parent->children.push_back(newNode); // (7%)
    }

    return newNode;
}

// 静态hashmap初始化
mutex NineChessAi_ab::hashMapMutex;
unordered_map<uint64_t, NineChessAi_ab::HashValue> NineChessAi_ab::hashmap;

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE
void NineChessAi_ab::shuffleMovePriorityTable()
{
    array<int, 4> movePriorityTable0 = { 17, 19, 21, 23 }; // 中圈四个顶点 (星位)
    array<int, 8> movePriorityTable1 = { 25, 27, 29, 31, 9, 11, 13, 15 }; // 外圈和内圈四个顶点
    array<int, 4> movePriorityTable2 = { 16, 18, 20, 22 }; // 中圈十字架
    array<int, 4> movePriorityTable3 = { 8, 10, 12, 14 }; // 内圈十字架
    array<int, 4> movePriorityTable4 = { 24, 26, 28, 30 }; // 外圈十字架

    unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

    std::shuffle(movePriorityTable0.begin(), movePriorityTable0.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable1.begin(), movePriorityTable1.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable2.begin(), movePriorityTable2.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable3.begin(), movePriorityTable3.end(), std::default_random_engine(seed));
    std::shuffle(movePriorityTable4.begin(), movePriorityTable4.end(), std::default_random_engine(seed));

    for (int i = 0; i < 4; i++) {
        movePriorityTable[i + 0] = movePriorityTable0[i];
    }

    for (int i = 0; i < 8; i++) {
        movePriorityTable[i + 4] = movePriorityTable1[i];
    }

    for (int i = 0; i < 4; i++) {
        movePriorityTable[i + 12] = movePriorityTable2[i];
    }

    for (int i = 0; i < 4; i++) {
        movePriorityTable[i + 16] = movePriorityTable3[i];
    }

    for (int i = 0; i < 4; i++) {
        movePriorityTable[i + 20] = movePriorityTable4[i];
    }
}
#endif // #ifdef RANDOM_MOVE
#endif // MOVE_PRIORITY_TABLE_SUPPORT

void NineChessAi_ab::generateLegalMoves(Node *node)
{
    const int MOVE_PRIORITY_TABLE_SIZE = NineChess::N_RINGS * NineChess::N_SEATS;
    int pos = 0;

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
#else
    int movePriorityTable[MOVE_PRIORITY_TABLE_SIZE] = {
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    };
#endif

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
                if (!chessTemp.board_[pos]) {
                    if (node == rootNode && chessTemp.context.stage == NineChess::GAME_NOTSTARTED) {
                        // 若为先手，则抢占星位
                        if (NineChess::isStartPoint(pos)) {
                            addNode(node, INF_VALUE, pos, chessTemp.context.turn);
                        }
                    } else {
                        addNode(node, 0, pos, chessTemp.context.turn);  // (24%)
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
                if (!chessTemp.choose(oldPos))
                    continue;

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
                            addNode(node, 0, move, chessTemp.context.turn); // (12%)
                        }
                    }
                } else {
                    // 对于棋盘上还有不到3个字，但允许飞子的情况，不要求在着法表中，是空位就行
                    for (newPos = NineChess::POS_BEGIN; newPos < NineChess::POS_END; newPos++) {
                        if (!chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            addNode(node, 0, move, chessTemp.context.turn);
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
                    addNode(node, 0, -pos, chessTemp.context.turn);
                }
            }
        } else {
            // 不是全成三的情况
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                pos = movePriorityTable[i];
                if (chessTemp.board_[pos] & opponent) {
                    if (chessTemp.getRule()->allowRemoveMill || !chessTemp.isInMills(pos)) {
                        addNode(node, 0, -pos, chessTemp.context.turn); // (6%)
                    }
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
    return first->value < second->value;
}

bool NineChessAi_ab::nodeGreater(const Node *first, const Node *second)
{
    return first->value > second->value;
}

void NineChessAi_ab::sortLegalMoves(Node *node)
{
    // 这个函数对效率的影响很大，排序好的话，剪枝较早，节省时间，但不能在此函数耗费太多时间

#ifdef AB_RANDOM_SORT_CHILDREN
    if (chessTemp.whosTurn() == NineChess::PLAYER1) {
        node->children.sort([](Node* n1, Node* n2) {
            bool ret = false;
            if (n1->value > n2->value) {
                ret = true;
            } else if (n1->value < n2->value) {
                ret = false;
            } else if (n1->value == n2->value) {
                ret = n1->rand < n2->rand;
            }            
            return ret;
            });
    } else {
        node->children.sort([](Node* n1, Node* n2) {
            bool ret = false;
            if (n1->value < n2->value) {
                ret = true;
            } else if (n1->value > n2->value) {
                ret = false;
            } else if (n1->value == n2->value) {
                ret = n1->rand < n2->rand;
            }
            return ret;
    });
    }
#else

    if (chessTemp.whosTurn() == NineChess::PLAYER1) {
        //node->children.sort([](Node *n1, Node *n2) {return n1->value > n2->value; });   // (6%)
        std::stable_sort(node->children.begin(), node->children.end(), nodeGreater);
    } else {
        //node->children.sort([](Node *n1, Node *n2) { return n1->value < n2->value; });  // (6%)
        std::stable_sort(node->children.begin(), node->children.end(), nodeLess);
    }

#if 0
    if (chessTemp.whosTurn() == NineChess::PLAYER1) {
        node->children.sort([](Node *n1, Node *n2) {
            bool ret = false;
            if (n1->value > n2->value) {
                ret = true;
            } else if (n1->value < n2->value) {
                ret = false;
            } else if (n1->value == n2->value) {
                ret = n1->pruned < n2->pruned;
            }
            return ret;
                            });
    } else {
        node->children.sort([](Node *n1, Node *n2) {
            bool ret = false;
            if (n1->value < n2->value) {
                ret = true;
            } else if (n1->value > n2->value) {
                ret = false;
            } else if (n1->value == n2->value) {
                ret = n1->pruned > n2->pruned;
            }
            return ret;
                            });
    }
#endif

#endif
}

void NineChessAi_ab::deleteTree(Node *node)
{
    // 递归删除节点树
    if (node) {
        for (auto i : node->children) {
            deleteTree(i);
        }
        node->children.clear();
        delete node;
    }
}

void NineChessAi_ab::setChess(const NineChess &chess)
{
    // 如果规则改变，重建hashmap
    if (strcmp(this->chess_.currentRule.name, chess.currentRule.name)) {
        clearHashMap();
    }

    this->chess_ = chess;
    chessTemp = chess;
    chessContext = &(chessTemp.context);
    requiredQuit = false;
    deleteTree(rootNode);
    rootNode = new Node;
    rootNode->value = 0;
    rootNode->move = 0;
    rootNode->parent = nullptr;
    rootNode->pruned = false;
#ifdef DEBUG_AB_TREE
    rootNode->action = NineChess::ACTION_NONE;
    rootNode->stage = NineChess::GAME_NONE;
    rootNode->root = rootNode;
#endif
}

int NineChessAi_ab::evaluate(Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    int value = 0;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

    evaluatedNodeCount++;

#if 0
    int loc_value = 0;

    // 根据位置设置分数
    switch (node->move) {
    case 17:
    case 19:
    case 21:
    case 23:
        loc_value = 10;
        break;
    case 25:
    case 27:
    case 29:
    case 31:
    case 9:
    case 11:
    case 13:
    case 15:
        loc_value = 5;
        break;
    case 16:
    case 18:
    case 20:
    case  22:
        loc_value = 1;
        break;
    default:
        break;
    }

    if (chessContext->turn == NineChess::PLAYER1) {
        value += loc_value;
    } else {
        value -= loc_value;
    }
#endif

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
            nPiecesNeedRemove = (chessContext->turn == NineChess::PLAYER1) ? chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
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
            nPiecesNeedRemove = (chessContext->turn == NineChess::PLAYER1) ? chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
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
            }
            else {
                value = 0;
            }
        }

        // 走棋阶段被闷判断
        if (chessContext->action == NineChess::ACTION_CHOOSE && chessTemp.isAllSurrounded(chessContext->turn)) {
            // 规则要求被“闷”判负，则对手获胜
            if (chessTemp.currentRule.isLoseWhenNoWay) {
                if (chessContext->turn == NineChess::PLAYER1) {
                    value -= 10000;
#ifdef DEBUG_AB_TREE
                    node->result = -2;
#endif
                }
                else {
                    value += 10000;
#ifdef DEBUG_AB_TREE
                    node->result = 2;
#endif
                }
            }
        }

        // 剩余棋子个数判断
        if (chessContext->nPiecesOnBoard_1 < chessTemp.currentRule.nPiecesAtLeast) {
            value -= 10000;
#ifdef DEBUG_AB_TREE
            node->result = -1;
#endif
        }
        else if (chessContext->nPiecesOnBoard_2 < chessTemp.currentRule.nPiecesAtLeast) {
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
    node->value = (int16_t)value;
    return value;
}

int NineChessAi_ab::changeDepth(int originalDepth)
{
    int newDepth = originalDepth;

    if ((chessTemp.context.stage) & (NineChess::GAME_PLACING)) {
#ifdef GAME_PLACING_DYNAMIC_DEPTH
#ifdef DEAL_WITH_HORIZON_EFFECT
        int depthTable[] = { 2, 11, 11, 11, 11, 10,  9, 8, 8, 8, 7, 7, 1 };
          //int depthTable[] = { 2, 12, 12, 12, 12, 11, 10, 9, 9, 8, 8, 7, 1 };
#else
        //int depthTable[] = { 2, 12, 12, 12, 12, 11, 10, 9, 8, 8, 8, 7, 1 };
          int depthTable[] = { 2, 13, 13, 13, 12, 11, 10, 9, 9, 8, 8, 7, 1 };
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

int NineChessAi_ab::alphaBetaPruning(int depth)
{
    QTime time1;
    int value = 0;

    int d = changeDepth(depth);

    unsigned int time0 = (unsigned)time(0);
    srand(time0);

    time1.start();

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE
    shuffleMovePriorityTable();
#endif
#endif
    
#ifdef IDS_SUPPORT
    // 深化迭代
    for (int i = 2; i < d; i++) {
        alphaBetaPruning(i, -INF_VALUE, INF_VALUE, rootNode);
    }

    qDebug() << "IDS Time: " << time1.elapsed() / 1000.0 << "s";
#endif /* IDS_SUPPORT */

    value = alphaBetaPruning(d, -INF_VALUE /* alpha */, INF_VALUE /* beta */, rootNode);

    qDebug() << "Total Time: " << time1.elapsed() / 1000.0 << "s\n";

    // 生成了 Alpha-Beta 树

    return value;
}

int NineChessAi_ab::alphaBetaPruning(int depth, int alpha, int beta, Node *node)
{
    // 评价值
    int value;

    // 当前节点的 MinMax 值，最终赋值给节点 value，与 alpha 和 Beta 不同
    int minMax;

    // 临时增加的深度，克服水平线效应用
    int epsilon = 0;

    // 哈希类型
    enum HashType hashf = hashfALPHA;

#ifdef DEBUG_AB_TREE
    node->depth = depth;
    node->root = rootNode;
    // node->player = chessContext->turn;
    // 初始化
    node->isLeaf = false;
    node->isTimeout = false;
    node->isHash = false;
    node->visited = true;
    node->hash = 0;
#endif

#ifdef HASH_MAP_ENABLE
    // 检索 hashmap
    uint64_t hash = chessTemp.getHash();
    node->hash = hash;

    hashMapMutex.lock();

    auto iter = findHash(hash);

    if (node != rootNode &&
        iter != hashmap.end() &&
        iter->second.depth >= depth) {
#ifdef DEBUG_AB_TREE
        node->isHash = true;
#endif

        // TODO: 处理 Alpha/Beta 确切值
        node->value = iter->second.value;

        if (chessContext->turn == NineChess::PLAYER1)
            node->value += iter->second.depth - depth;
        else
            node->value -= iter->second.depth - depth;

        hashMapMutex.unlock();
        hashHitCount++;

        return node->value;
    }

    hashMapMutex.unlock();
#endif /* HASH_MAP_ENABLE */

    // 搜索到叶子节点（决胜局面）
    if (chessContext->stage == NineChess::GAME_OVER) {
        // 局面评估
        node->value = evaluate(node);
        
        // 为争取速胜，value 值 +- 深度
        if (node->value > 0)
            node->value += depth;
        else
            node->value -= depth;

#ifdef DEBUG_AB_TREE
        node->isLeaf = true;
#endif

#ifdef HASH_MAP_ENABLE
        // 记录确切的哈希值
        recordHash(hash, depth, node->value, hashfEXACT);
#endif

        return node->value;
    }

    // 搜索到第0层或需要退出
    if (!depth || requiredQuit) {
        // 局面评估
        node->value = evaluate(node);

        // 为争取速胜，value 值 +- 深度
        if (chessContext->turn == NineChess::PLAYER1)
            node->value += depth;
        else
            node->value -= depth;

#ifdef DEBUG_AB_TREE
        if (requiredQuit) {
            node->isTimeout = true;
        }
#endif 

#ifdef HASH_MAP_ENABLE
        // 记录确切的哈希值
        recordHash(hash, depth, node->value, hashfEXACT);
#endif

        return node->value;
    }

    // 生成子节点树，即生成每个合理的着法
    generateLegalMoves(node);   // (43%)

    // 排序子节点树
    //sortChildren(node);

    // 根据演算模型执行 MiniMax 检索，对先手，搜索 Max, 对后手，搜索 Min

    minMax = chessTemp.whosTurn() == NineChess::PLAYER1 ? -INF_VALUE : INF_VALUE;

    for (auto child : node->children) {
        // 上下文入栈保存，以便后续撤销着法
        contextStack.push(chessTemp.context);   // (7%)

        // 执行着法
        chessTemp.command(child->move);     // (13%)

#ifdef DEAL_WITH_HORIZON_EFFECT
        // 克服“水平线效应”: 若遇到吃子，则搜索深度增加
        if (child->pruned == false && child->move < 0) {
            epsilon = 1;
        }
        else {
            epsilon = 0;
        }
#endif

        // 递归 Alpha-Beta 剪枝
        value = alphaBetaPruning(depth - 1 + epsilon, alpha, beta, child);  // (98%)

        // 上下文弹出栈，撤销着法
        chessTemp.context = contextStack.top(); // (5%)
        contextStack.pop();

        if (chessTemp.whosTurn() == NineChess::PLAYER1) {
            // 为走棋一方的层, 局面对走棋的一方来说是以 α 为评价

            // 取最大值
            minMax = std::max(value, minMax);

            // α 为走棋一方搜索到的最好值，任何比它小的值对当前结点的走棋方都没有意义
            // 如果某个着法的结果小于或等于 α，那么它就是很差的着法，因此可以抛弃
            alpha = std::max(value, alpha);

            hashf = hashfALPHA; // ????

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
            beta = std::min(value, beta);

            hashf = hashfBETA; // ????
        }

        // 如果某个着法的结果大于 α 但小于β，那么这个着法就是走棋一方可以考虑走的
        // 否则剪枝返回
        if (alpha >= beta) {
            node->pruned = true;
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
        for (auto grandChild : child->children)
            deleteTree(grandChild); // (9%)
        child->children.clear();    // (3%)
    }
#endif // DONOT_DELETE_TREE

#ifdef HASH_MAP_ENABLE
    if (iter == hashmap.end()) {
        // 添加到hashmap
        recordHash(hash, depth, node->value, hashf);
    }
    // 更新更深层数据
    else {
        //hashMapMutex.lock();
        //if (iter->second.depth < depth) {
            //iter->second.value = node->value;
            //iter->second.depth = depth;
        //}
        //hashMapMutex.unlock();
    }
#endif

    // 排序子节点树
    sortLegalMoves(node);   // (13%)

    // 返回
    return node->value;
}

int NineChessAi_ab::recordHash(uint64_t hash, int16_t depth, int value, enum HashType type)
{
#ifdef HASH_MAP_ENABLE
    hashMapMutex.lock();

    HashValue hashValue;
    
    hashValue.value = value;
    hashValue.depth = depth;
    hashValue.type = type;

    if (hashmap.size() <= maxHashCount)
        hashmap.insert({ hash, hashValue });

    hashMapMutex.unlock();
#endif // HASH_MAP_ENABLE

    return 0;
}

const char* NineChessAi_ab::bestMove()
{
    vector<Node*> bestMoves;
    size_t retIndex = 0;
    size_t bestMovesSize = 0;

    if ((rootNode->children).size() == 0)
        return "error!";

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
        if (child->value == rootNode->value && !child->pruned)
            qDebug("[%.2d] %d\t%s\t%d *", i, child->move, move2string(child->move), child->value);
        else
            qDebug("[%.2d] %d\t%s\t%d", i, child->move, move2string(child->move), child->value);

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

#ifdef RANDOM_BEST_MOVE
    time_t time0 = time(0);

    if (time0 % 10 == 0) {       
        retIndex = bestMovesSize > 1 ? 1 : 0;
    }
#else
    retIndex = 0;
#endif

#ifdef RANDOM_BEST_MOVE
    qDebug() << "Return" << retIndex << "of" << bestMovesSize << "results" << "(" << time0 << ")";
#endif

#ifdef HASH_MAP_ENABLE
    qDebug() << "Hash hit count:" << hashHitCount;
#endif

    return move2string(bestMoves[retIndex]->move);
}

    

const char *NineChessAi_ab::move2string(int move)
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

unordered_map<uint64_t, NineChessAi_ab::HashValue>::iterator NineChessAi_ab::findHash(uint64_t hash)
{
    auto iter = hashmap.find(hash);

#if 0
    if (iter != hashmap.end())
        return iter;

    // 变换局面，查找hash
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

    return iter;
}
