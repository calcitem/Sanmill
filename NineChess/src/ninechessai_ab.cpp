/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#include "ninechessai_ab.h"
#include <cmath>
#include <time.h>
#include <Qdebug>

NineChessAi_ab::NineChessAi_ab() :
    rootNode(nullptr),
    requiredQuit(false),
    nodeCount(0),
    evaluatedNodeCount(0)
{
    buildRoot();
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
    rootNode = nullptr;
}

void NineChessAi_ab::buildRoot()
{
    rootNode = new Node;
    rootNode->value = 0;
    rootNode->move = 0;
    rootNode->parent = nullptr;
}

void NineChessAi_ab::addNode(Node *parent, int value, int move)
{
    Node *newNode = new Node;
    newNode->parent = parent;
    newNode->value = value;
    newNode->move = move;
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
#endif
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

#ifdef DEBUG_AB_TREE
    newNode->cmd = cmd;
#endif

    parent->children.push_back(newNode);
}

// 静态hashmap初始化
mutex NineChessAi_ab::mtx;
unordered_map<uint64_t, NineChessAi_ab::HashValue> NineChessAi_ab::hashmap;

void NineChessAi_ab::buildChildren(Node *node)
{
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
            for (int pos = NineChess::POS_BEGIN; pos < NineChess::POS_END; pos++) {
                if (!chessTemp.board_[pos]) {
                    if (node == rootNode && chessTemp.context.stage == NineChess::GAME_NOTSTARTED) {
                        // 若为先手，则抢占星位
                        if (NineChess::isStartPoint(pos)) {
                            addNode(node, INF_VALUE, pos);
                        }
                    } else {
                        addNode(node, 0, pos);
                    }
                }
            }
            break;
        } 
        
        // 对于移子阶段
        if (chessTemp.context.stage & NineChess::GAME_MOVING) {
            int newPos;
            for (int oldPos = NineChess::POS_BEGIN; oldPos < NineChess::POS_END; oldPos++) {
                if (!chessTemp.choose(oldPos))
                    continue;

                if ((chessTemp.context.turn == NineChess::PLAYER1 &&
                    (chessTemp.context.nPiecesOnBoard_1 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces)) ||
                    (chessTemp.context.turn == NineChess::PLAYER2 &&
                    (chessTemp.context.nPiecesOnBoard_2 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces))) {
                    // 对于棋盘上还有3个子以上，或不允许飞子的情况，要求必须在招法表中
                    for (int moveDirection = NineChess::MOVE_DIRECTION_CLOCKWISE; moveDirection <= NineChess::MOVE_DIRECTION_OUTWARD; moveDirection++) {
                        // 对于原有位置，遍历四个方向的招法，如果棋盘上为空位就加到结点列表中
                        newPos = chessTemp.moveTable[oldPos][moveDirection];
                        if (newPos && !chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            addNode(node, 0, move);
                        }
                    }
                } else {
                    // 对于棋盘上还有不到3个字，但允许飞子的情况，不要求在招法表中，是空位就行
                    for (newPos = NineChess::POS_BEGIN; newPos < NineChess::POS_END; newPos++) {
                        if (!chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            addNode(node, 0, move);
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
            for (int pos = NineChess::POS_BEGIN; pos < NineChess::POS_END; pos++) {
                if (chessTemp.board_[pos] & opponent) {
                    addNode(node, 0, -pos);
                }
            }
        } else {
            // 不是全成三的情况
            for (int pos = NineChess::POS_BEGIN; pos < NineChess::POS_END; pos++) {
                if (chessTemp.board_[pos] & opponent) {
                    if (chessTemp.getRule()->allowRemoveMill || !chessTemp.isInMills(pos)) {
                        addNode(node, 0, -pos);
                    }
                }
            }
        }
        break;

    default:
        break;
    }
}

void NineChessAi_ab::sortChildren(Node *node)
{
    // 这个函数对效率的影响很大，排序好的话，剪枝较早，节省时间，但不能在此函数耗费太多时间
#ifdef AB_RANDOM_SORT_CHILDREN
    // 这里我用一个随机排序，使AI不至于每次走招相同
    srand((unsigned)time(0));
    for (auto i : node->children) {
        i->value = rand();
    }
#endif /* AB_RANDOM_SORT_CHILDREN */

    // 排序
    if (chessTemp.whosTurn() == NineChess::PLAYER1)
        node->children.sort([](Node *n1, Node *n2) { return n1->value > n2->value; });
    else
        node->children.sort([](Node *n1, Node *n2) { return n1->value < n2->value; });
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
        mtx.lock();
        hashmap.clear();
        hashmap.reserve(maxHashCount);
        mtx.unlock();
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

int NineChessAi_ab::alphaBetaPruning(int depth)
{
#ifdef GAME_PLACING_DYNAMIC_DEPTH
    if ((chessTemp.context.stage) & (NineChess::GAME_PLACING)) {
#ifdef GAME_PLACING_FIXED_DEPTH
        depth = GAME_PLACING_FIXED_DEPTH;
#else
        switch (chessTemp.getPiecesInHandCount_1())
        {
        case 12:
            depth = 1;
            break;
        case 11:
            depth = 7;
            break;
        case 10:
            depth = 8;
            break;
        case 9:
            depth = 9;
            break;
        case 8:
        case 7:
            depth = 9;
            break;
        case 6:
            depth = 9;
            break;
        case  5:
            depth = 11;
            break;
        case 4:
            depth = 12;
            break;
        case 3:
            depth = 12;
            break;
        case 2:
            depth = 12;
            break;
        case 1:
            depth = 12;
            break;
        case 0:
            depth = 2;
            break;
        default:
            depth = 7;
            break;
        }
#endif /* GAME_PLACING_FIXED_DEPTH */
    }
#endif /* GAME_PLACING_DYNAMIC_DEPTH */

#ifdef GAME_MOVING_FIXED_DEPTH    
    // 走棋阶段将深度调整
    if ((chessTemp.context.stage) & (NineChess::GAME_MOVING)) {
        depth = GAME_MOVING_FIXED_DEPTH;
    }
#endif /* GAME_MOVING_FIXED_DEPTH */

    qDebug() << "Depth:" << depth;

    return alphaBetaPruning(depth, -INF_VALUE, INF_VALUE, rootNode);
    // 生成了 Alpha-Beta 树
}

int NineChessAi_ab::alphaBetaPruning(int depth, int alpha, int beta, Node *node)
{
    // 评价值
    int value;

    // 当前节点的MinMax值，最终赋值给节点value，与alpha和Beta不同
    int minMax;

#ifdef DEBUG_AB_TREE
    node->depth = depth;
    node->root = rootNode;
    node->id = nodeCount;
    node->player = chessContext->turn;
    // 初始化
    node->isLeaf = false;
    node->isTimeout = false;
#endif

    // 遍历总次数增加
    nodeCount++;

    // 搜索到叶子节点（决胜局面）
    if (chessContext->stage == NineChess::GAME_OVER) {
        node->value = evaluate(node);
        
        if (node->value > 0)
            node->value += depth;
        else
            node->value -= depth;

#ifdef DEBUG_AB_TREE
        node->isLeaf = true;
#endif

        return node->value;
    }

    // 搜索到第0层或需要退出
    if (!depth || requiredQuit) {
        node->value = evaluate(node);
        if (chessContext->turn == NineChess::PLAYER1)
            node->value += depth;
        else
            node->value -= depth;

#ifdef DEBUG_AB_TREE
        if (requiredQuit) {
            node->isTimeout = true;
        }
#endif 
        return node->value;
    }

#if 0
    // 检索hashmap
    uint64_t hash = chessTemp.chessHash();
    mtx.lock();
    auto iter = findHash(hash);
    if (node != rootNode) {
        if (iter != hashmap.end()) {
            if (iter->second.depth >= depth) {
                node->value = iter->second.value;
                if (chessData->turn == NineChess::PLAYER1)
                    node->value += iter->second.depth - depth;
                else
                    node->value -= iter->second.depth - depth;
                mtx.unlock();
                return node->value;
            }
        }
    }
    mtx.unlock();
#endif

    // 生成子节点树
    buildChildren(node);

    // 排序子节点树
    sortChildren(node);

    // 根据演算模型执行 MiniMax 检索，对先手，搜索 Max, 对后手，搜索 Min

    minMax = chessTemp.whosTurn() == NineChess::PLAYER1 ? -INF_VALUE : INF_VALUE;

    for (auto child : node->children) {
        dataStack.push(chessTemp.context);
        chessTemp.command(child->move);
        value = alphaBetaPruning(depth - 1, alpha, beta, child);
        chessTemp.context = dataStack.top();
        dataStack.pop();

        if (chessTemp.whosTurn() == NineChess::PLAYER1) {
            // 取最大值
            minMax = std::max(value, minMax);
            alpha = std::max(value, alpha);
        } else {
            // 取最小值
            minMax = std::min(value, minMax);
            beta = std::min(value, beta);
        }

        // 剪枝返回
        if (alpha >= beta)
            break;
    }

    node->value = minMax;

#ifdef DEBUG_AB_TREE
    node->alpha = alpha;
    node->beta = beta;
    node->minMax = minMax;
#endif 

    // 删除“孙子”节点，防止层数较深的时候节点树太大
#ifndef DEBUG_AB_TREE
    for (auto child : node->children) {
        for (auto grandChild : child->children)
            deleteTree(grandChild);
        child->children.clear();
    }
#endif

#if 0
        // 添加到hashmap
        mtx.lock();
        if (iter == hashmap.end()) {
            HashValue hashValue;
            hashValue.value = node->value;
            hashValue.depth = depth;
            if (hashmap.size() <= maxHashCount)
                hashmap.insert({hash, hashValue});
        }
        // 更新更深层数据
        else {
            if (iter->second.depth < depth) {
                iter->second.value = node->value;
                iter->second.depth = depth;
            }
        }
        mtx.unlock();
#endif

    // 返回
    return node->value;
}

const char *NineChessAi_ab::bestMove()
{
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

    string moves = "";
    for (auto child : rootNode->children) {
        if (child->value == rootNode->value)
            qDebug() << "[" << child->move << "] " << move2string(child->move) << " : " << child->value << "*";
        else
            qDebug() << "[" << child->move << "] " << move2string(child->move) << " : " << child->value;
    }

    for (auto child : rootNode->children) {
        if (child->value == rootNode->value) {
            qDebug() << "Evaluated: " << evaluatedNodeCount << "/" << nodeCount << " = " << evaluatedNodeCount * 100 / nodeCount << "%";
            nodeCount = 0;
            evaluatedNodeCount = 0;
            return move2string(child->move);
        }
    }

    return "error!";
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
                iter = hashmap.find(chessTempShift.chessHash());
                if (iter != hashmap.end())
                    return iter;
            }
        }
    }
    return iter;
}
