#include "ninechessai_ab.h"
#include <cmath>
#include <time.h>

NineChessAi_ab::NineChessAi_ab():
rootNode(nullptr),
requiredQuit(false),
depth(3)    // 默认3层深度
{
    rootNode = new Node;
    rootNode->value = 0;
    rootNode->move_ = 0;
    rootNode->parent = nullptr;
}

NineChessAi_ab::~NineChessAi_ab()
{
    deleteTree(rootNode);
}

void NineChessAi_ab::buildChildren(Node *node)
{
    // 列出所有合法的下一招
    ;
}

void NineChessAi_ab::sortChildren(Node *node)
{
    // 这个函数对效率的影响很大，排序好的话，剪枝较早，节省时间，但不能在此函数耗费太多时间
    // 先赋初值，初始值不会影响alpha-beta剪枝
    for (auto i : node->children) {
        i->value = evaluate(node);
    }
    // 排序
    node->children.sort([](Node *n1, Node *n2) { return n1->value > n2->value; });
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

void NineChessAi_ab::reverse(const NineChess *node1, NineChess *node2, int i)
{

}

void NineChessAi_ab::turn(const NineChess *node1, NineChess *node2, int i)
{

}

void NineChessAi_ab::rotate(const NineChess *node1, NineChess *node2, int i)
{

}

bool NineChessAi_ab::isInCache(Node * node, int &value)
{
/*    NineChess tempData;
    for (int i = 0; i < 2; i++) {
        reverse(node, &tempData, i);
        for (int j = 0; j < 6; j++) {
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
