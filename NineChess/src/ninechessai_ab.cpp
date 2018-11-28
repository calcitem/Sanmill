#include "NineChessAi_ab.h"

NineChessAi_ab::NineChessAi_ab():
rootNode(nullptr),
requiredQuit(false),
depth(5)    // 默认5层深度
{
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
}

void NineChessAi_ab::buildChildren(Node *node)
{
    ;
}

void NineChessAi_ab::sortChildren(Node *node)
{
    // 这个函数对效率的影响很大，
    // 排序好的话，剪枝较早，节省时间
    // 但不能在此函数耗费太多时间
    ;
}

void NineChessAi_ab::deleteTree(Node *node)
{
    if (rootNode) {
        for (auto i : rootNode->children) {
            deleteTree(i);
        }
        rootNode->children.clear();
        delete rootNode;
    }
}

void NineChessAi_ab::setChess(const NineChess &chess)
{
    this->chess = chess;
    chessTemp = chess;
    requiredQuit = false;
}

int NineChessAi_ab::evaluate(Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    int value = 0;




    // 赋值返回
    node->value = value;
    return value;
}

int NineChessAi_ab::alphaBetaPruning(int depth, int alpha, int beta, Node *node)
{
    // 评价值
    int value;
    if (!depth || !(node->children.size())) {
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
            value = alphaBetaPruning(depth - 1, alpha, beta, child);
            // 取最大值
            if (value > alpha)
                alpha = value;
            // 剪枝返回
            if (alpha >= beta) {
                return value;
            }
        }
        // 取最大值
        node->value = alpha;
    }
    // 对后手，搜索Min
    else {
        for (auto child : node->children) {
            value = alphaBetaPruning(depth - 1, alpha, beta, child);
            // 取最小值
            if (value < beta)
                beta = value;
            // 剪枝返回
            if (alpha >= beta) {
                return value;
            }
        }
        // 取最小值
        node->value = beta;
    }
    // 返回
    return node->value;
}

