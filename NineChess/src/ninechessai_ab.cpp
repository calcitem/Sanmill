/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#include "ninechessai_ab.h"
#include <cmath>
#include <time.h>
#include <qdebug.h>

NineChessAi_ab::NineChessAi_ab():
rootNode(nullptr),
requiredQuit(false),
depth(3)    // 默认3层深度
{
    rootNode = new Node;
    rootNode->value = 0;
    rootNode->move = 0;
    rootNode->parent = nullptr;
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
    rootNode = nullptr;
}

void NineChessAi_ab::buildChildren(Node *node)
{
    // 如果有子节点，则返回，避免重复建立
    if (node->children.size())
        return;

    // 临时变量
    char opponent = chessTemp.data.turn == NineChess::PLAYER1 ? 0x20 : 0x10;
    // 列出所有合法的下一招
    switch (chessTemp.data.action)
    {
    case NineChess::ACTION_CHOOSE:
    case NineChess::ACTION_PLACE:
        // 对于开局落子
        if ((chessTemp.data.phase) & (NineChess::GAME_OPENING | NineChess::GAME_NOTSTARTED)) {
            for (int i = NineChess::SEAT; i < (NineChess::RING + 1)*NineChess::SEAT; i++) {
                if (!chessTemp.board[i]) {
                    Node * newNode = new Node;
                    newNode->parent = node;
                    newNode->value = 0;
                    newNode->move = i;
                    node->children.push_back(newNode);
                }
            }
        }
        // 对于中局移子
        else {
            char newPos;
            for (int i = NineChess::SEAT; i < (NineChess::RING + 1)*NineChess::SEAT; i++) {
                if (!chessTemp.choose(i))
                    continue;
                if ((chessTemp.data.turn == NineChess::PLAYER1 && (chessTemp.data.player1_Remain > chessTemp.rule.numAtLest || !chessTemp.rule.canFly)) ||
                    (chessTemp.data.turn == NineChess::PLAYER2 && (chessTemp.data.player2_Remain > chessTemp.rule.numAtLest || !chessTemp.rule.canFly))) {
                    for (int j = 0; j < 4; j++) {
                        newPos = chessTemp.moveTable[i][j];
                        if (newPos && !chessTemp.board[newPos]) {
                            Node * newNode = new Node;
                            newNode->parent = node;
                            newNode->value = 0;
                            newNode->move = (i << 8) + newPos;
                            node->children.push_back(newNode);
                        }
                    }
                }
                else {
                    for (int j = NineChess::SEAT; j < (NineChess::RING + 1)*NineChess::SEAT; j++) {
                        if (!chessTemp.board[j]) {
                            Node * newNode = new Node;
                            newNode->parent = node;
                            newNode->value = 0;
                            newNode->move = (i << 8) + j;
                            node->children.push_back(newNode);
                        }
                    }
                }
            }
        }
        break;

    case NineChess::ACTION_CAPTURE:
        // 全成三的情况
        if (chessTemp.isAllInMills(opponent)) {
            for (int i = NineChess::SEAT; i < (NineChess::RING + 1)*NineChess::SEAT; i++) {
                if (chessTemp.board[i] & opponent) {
                    Node * newNode = new Node;
                    newNode->parent = node;
                    newNode->value = 0;
                    newNode->move = -i;
                    node->children.push_back(newNode);
                }
            }
        }
        else {
            for (int i = NineChess::SEAT; i < (NineChess::RING + 1)*NineChess::SEAT; i++) {
                if (chessTemp.board[i] & opponent) {
                    if (!chessTemp.isInMills(i)) {
                        Node * newNode = new Node;
                        newNode->parent = node;
                        newNode->value = 0;
                        newNode->move = -i;
                        node->children.push_back(newNode);
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
    // 先赋初值，初始值不会影响alpha-beta剪枝
    for (auto i : node->children) {
        i->value = evaluate(node);
    }
    // 排序
    if(chessTemp.whosTurn() == NineChess::PLAYER1)
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
    this->chess = chess;
    chessTemp = chess;
    chessData = &(chessTemp.data);
    deleteTree(rootNode);
    rootNode = new Node;
    rootNode->value = 0;
    rootNode->move = 0;
    rootNode->parent = nullptr;

    requiredQuit = false;
    // 生成棋子价值表
    for (int j = 0; j < NineChess::SEAT; j++)
    {
        // 对于0、2、4、6位（偶数位）
        if (!(j & 1)) {
            boardScore[1 * NineChess::SEAT + j] = 90;
            boardScore[2 * NineChess::SEAT + j] = 100;
            boardScore[3 * NineChess::SEAT + j] = 90;
        }
        // 对于有斜线情况下的1、3、5、7位（奇数位）
        else if(chessTemp.rule.hasObliqueLine) {
            boardScore[1 * NineChess::SEAT + j] = 85;
            boardScore[2 * NineChess::SEAT + j] = 95;
            boardScore[3 * NineChess::SEAT + j] = 85;
        }
        // 对于无斜线情况下的1、3、5、7位（奇数位）
        else {
            boardScore[1 * NineChess::SEAT + j] = 80;
            boardScore[2 * NineChess::SEAT + j] = 85;
            boardScore[3 * NineChess::SEAT + j] = 80;
        }
    }
}

int NineChessAi_ab::evaluate(Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    int value = 0;
    switch (chessData->phase)
    {
    case NineChess::GAME_NOTSTARTED:
        break;

    // 开局和中局阶段用同样的评价方法
    case NineChess::GAME_OPENING:
    case NineChess::GAME_MID:
        // 按手棋数目计分，每子50分
        value += (chessData->player1_InHand) * 50 - (chessData->player2_InHand) * 50;
        // 按场上棋子计分
        for (int i = 1*NineChess::SEAT; i < NineChess::SEAT*(NineChess::RING+1); i++) {
            if (chessData->board[i] & 0x10)
                value += boardScore[i];
            else if (chessData->board[i] & 0x20)
                value -= boardScore[i];
        }
        switch (chessData->action)
        {
        // 选子和落子使用相同的评价方法
        case NineChess::ACTION_CHOOSE:
        case NineChess::ACTION_PLACE:
            break;
        // 如果形成去子状态，每有一个可去的子，算1000分
        case NineChess::ACTION_CAPTURE:
            value += (chessData->turn == NineChess::PLAYER1) ? chessData->num_NeedRemove * 1000 : -chessData->num_NeedRemove * 1000;
            break;
        default:
            break;
        }
        break;

    // 终局评价最简单
    case NineChess::GAME_OVER:
        if (chessData->player1_Remain < chessTemp.rule.numAtLest)
            value = -infinity;
        else if (chessData->player2_Remain < chessTemp.rule.numAtLest)
            value = infinity;
        break;

    default:
        break;
    }

    // 赋值返回
    node->value = value;
    return value;
}

int NineChessAi_ab::alphaBetaPruning(int depth)
{
    return alphaBetaPruning(depth, -infinity, infinity, rootNode);
}

int NineChessAi_ab::alphaBetaPruning(int depth, int alpha, int beta, Node *node)
{
    // 评价值
    int value;
    if (!depth || chessTemp.data.phase == NineChess::GAME_OVER) {
        node->value = evaluate(node);
        return node->value;
    }

    // 生成子节点树
    buildChildren(node);
    // 排序子节点树
    sortChildren(node);

    // 根据演算模型执行MiniMax检索
    // 对先手，搜索Max
    if (chessTemp.whosTurn() == NineChess::PLAYER1) {
        for (auto child : node->children) {
            dataStack.push(chessTemp.data);
            if(!chessTemp.command(child->move))
                qDebug() << child->move;
            value = alphaBetaPruning(depth - 1, alpha, beta, child);
            chessTemp.data = dataStack.top();
            dataStack.pop();
            // 取最大值
            if (value > alpha)
                alpha = value;
            // 剪枝返回
            if (alpha >= beta) {
                node->value = alpha;
                return value;
            }
        }
        // 取最大值
        node->value = alpha;
    }
    // 对后手，搜索Min
    else {
        for (auto child : node->children) {
            dataStack.push(chessTemp.data);
            if(!chessTemp.command(child->move))
                qDebug() << child->move;
            value = alphaBetaPruning(depth - 1, alpha, beta, child);
            chessTemp.data = dataStack.top();
            dataStack.pop();
            // 取最小值
            if (value < beta)
                beta = value;
            // 剪枝返回
            if (alpha >= beta) {
                node->value = beta;
                return value;
            }
        }
        // 取最小值
        node->value = beta;
    }
    // 返回
    return node->value;
}

const char *NineChessAi_ab::bestMove()
{
    if ((rootNode->children).size() == 0)
        return "error!";
    // 在最好的招法中随机挑一个
    int16_t moves[12] = {0};
    int n = 0;
    for (auto child : rootNode->children) {
        if (child->value == rootNode->value)
            moves[n++] = child->move;
        if (n >= 12)
            break;
    }
    srand((unsigned)time(0));
    int i = rand() % n;
    return move2string(moves[i]);
}

const char *NineChessAi_ab::move2string(int16_t move)
{
    int c, p;
    if (move < 0) {
        chessTemp.pos2cp(-move, c, p);
        sprintf(cmdline, "-(%1u,%1u)", c, p);
    }
    else if (move & 0x7f00) {
        int c1, p1;
        chessTemp.pos2cp(move >> 8, c1, p1);
        chessTemp.pos2cp(move & 0x00ff, c, p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", c1, p1, c, p);
    }
    else {
        chessTemp.pos2cp(move & 0x007f, c, p);
        sprintf(cmdline, "(%1u,%1u)", c, p);
    }
    return cmdline;
}


void NineChessAi_ab::reverse(const NineChess *node1, NineChess *node2, int i)
{

}

void NineChessAi_ab::turn(const NineChess *node1, NineChess *node2, int i)
{

}

void NineChessAi_ab::rotate(const NineChess *node1, NineChess *node2, int i)
{

}

bool NineChessAi_ab::isInHash(const Node *node)
{
    /*
    NineChess tempData;
    for (int i = 0; i < 2; i++) {
        reverse(node, &tempData, i);
        for (int j = 0; j < 2; j++) {
            turn(node, &tempData, j);
            int n = chess.rule.hasX ? 8 : 4;
            for (int k = 0; k < n; k++) {
                rotate(node, &tempData, k);
                for (auto i : dataCache) {
                    if (compare(i, &tempData) == 0) {
                        value = i.value;
                        return true;
                    }
                }
            }
        }
    }
    */
    return false;
}
