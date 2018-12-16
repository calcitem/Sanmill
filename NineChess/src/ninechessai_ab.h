/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#ifndef NINECHESSAI_AB
#define NINECHESSAI_AB

#include "ninechess.h"
#include <list>
#include <stack>

using namespace std;

// 注意：NineChess类不是线程安全的！
// 所以不能在ai类中修改NineChess类的静态成员变量，切记！
// 另外，AI类是NineChess类的友元类，可以访问其私有变量
// 尽量不要使用NineChess的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class NineChessAi_ab
{
public:
    // 定义哈希表
    struct Hash{
        NineChess::ChessData data;
        uint64_t value;
        int depth;
    };

    // 定义一个节点结构体
    struct Node {
        uint64_t hash;                 // 当前局面的哈希值
        int value;                     // 节点的值
        int16_t move;                 // 招法的命令行指令，图上标示为节点前的连线
        struct Node * parent;          // 父节点
        list<struct Node *> children;  // 子节点列表
    };

public:
    NineChessAi_ab();
    ~NineChessAi_ab();

    void setChess(const NineChess &chess);
    void quit() { requiredQuit = true; }
    // Alpha-Beta剪枝算法
    int alphaBetaPruning(int depth);
    // 返回最佳走法的命令行
    const char *bestMove();

protected:
    // 建立子节点
    void buildChildren(Node *node);
    // 子节点排序
    void sortChildren(Node *node);
    // 清空节点树
    void deleteTree(Node *node);
    // 评价函数
    int evaluate(Node *node);
    // Alpha-Beta剪枝算法
    int alphaBetaPruning(int depth, int alpha, int beta, Node *node);
    // 返回招法的命令行
    const char *move2string(int16_t move);

    // 判断是否在哈希表中
    bool isInHash(const Node *node);

private:
    // 原始模型
    NineChess chess;
    // 演算用的模型
    NineChess chessTemp;
    NineChess::ChessData *chessData;

    // 根节点
    Node * rootNode;
    // 局面数据栈
    stack<NineChess::ChessData> dataStack;
    // 局面数据哈希表
    list<struct  Hash> hashTable;
    // 哈希表最大大小
    size_t hashTableMaxSize;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit;
    // 剪枝算法的层深
    //    int depth;
    // 定义极大值，等于32位有符号整形数字的最大值
    static const int infinity = INT32_MAX;

private:
    // 命令行
    char cmdline[32];
};

#endif
