/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#ifndef NINECHESSAI_AB
#define NINECHESSAI_AB

#include <list>
#include <stack>
#include <unordered_map>
#include <mutex>
#include <string>
#include <Qdebug>

#include "ninechess.h"

using namespace std;

// 注意：NineChess类不是线程安全的！
// 所以不能在ai类中修改NineChess类的静态成员变量，切记！
// 另外，AI类是NineChess类的友元类，可以访问其私有变量
// 尽量不要使用NineChess的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class NineChessAi_ab
{
public:
    // 定义哈希表的值
    struct HashValue
    {
        int16_t value;
        int16_t depth;
    };

    // 定义一个节点结构体
    struct Node
    {
        int move;                      // 招法的命令行指令，图上标示为节点前的连线
        int value;                     // 节点的值
        list<struct Node*> children;  // 子节点列表
        struct Node* parent;           // 父节点
        size_t id;                      // 结点编号
        int rand;                       // 随机数，对于 value 一致的结点随机排序用
#ifdef DEBUG_AB_TREE
        string cmd;
        enum NineChess::Player player;  // 此招是谁下的
        int depth;
        bool evaluated;                 // 是否评估过局面
        int alpha;
        int beta;
        int minMax;
        bool isTimeout;                 // 是否遍历到此结点时因为超时而被迫退出
        bool isLeaf;                    // 是否为叶子结点, 叶子结点是决胜局面
        NineChess::GameStage stage;     // 摆棋阶段还是走棋阶段
        NineChess::Action action;       // 动作状态
        int nPiecesOnBoardDiff;         // 场上棋子个数和对手的差值
        int nPiecesInHandDiff;          // 手中的棋子个数和对手的差值
        int nPiecesNeedRemove;          // 手中有多少可去的子，如对手有可去的子则为负数
        int result;                     // 终局结果，-1为负，0为未到终局，1为胜，走棋阶段被闷棋则为 -2/2，布局阶段闷棋为 -3
        struct Node* root;              // 根节点
#endif /* DEBUG_AB_TREE */
    };

public:
    NineChessAi_ab();
    ~NineChessAi_ab();

    void setChess(const NineChess &chess);

    void quit()
    {
        qDebug() << "Timeout\n";
        requiredQuit = true;
    }

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

    // 构造根节点
    void buildRoot();

    // 增加新节点
    struct Node *addNode(Node *parent, int value, NineChess::move_t move, enum NineChess::Player player);

    // 评价函数
    int evaluate(Node *node);

    // Alpha-Beta剪枝算法
    int alphaBetaPruning(int depth, int alpha, int beta, Node *node);

    // 返回招法的命令行
    const char *move2string(int move);

    // 篡改深度
    int changeDepth(int originalDepth);

    // 判断是否在哈希表中
    unordered_map<uint64_t, NineChessAi_ab::HashValue>::iterator findHash(uint64_t hash);

private:
    // 原始模型
    NineChess chess_;

    // 演算用的模型
    NineChess chessTemp;

    NineChess::ChessContext *chessContext;

    // hash计算时，各种转换用的模型
    NineChess chessTempShift;

    // 根节点
    Node *rootNode;

    // 结点个数;
    size_t nodeCount;

    // 评估过的结点个数
    size_t evaluatedNodeCount;

    // 局面数据栈
    stack<NineChess::ChessContext> contextStack;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit;

    // 互斥锁
    static mutex mtx;

    // 局面数据哈希表
    static unordered_map<uint64_t, HashValue> hashmap;

    // 哈希表的默认大小
    static const size_t maxHashCount = 1024 * 1024;

    // 定义极大值，等于16位有符号整形数字的最大值
    static const int INF_VALUE = INT32_MAX;

private:
    // 命令行
    char cmdline[32];
};

#endif
