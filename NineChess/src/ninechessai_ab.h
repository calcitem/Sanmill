#ifndef NINECHESSAI_AB
#define NINECHESSAI_AB

#include "ninechess.h"
#include <list>

// 注意：NineChess类不是线程安全的！
// 所以不能在ai类中修改NineChess类的静态成员变量，切记！


class NineChessAi_ab
{
public:
    // 定义一个节点结构体
    struct Node{
        int value;                     // 节点的值
        short move_;                   // 招法的命令行指令，图上标示为节点前的连线
        struct Node * parent;          // 父节点
        list<struct Node *> children;  // 子节点列表
    };

public:
    NineChessAi_ab();
    ~NineChessAi_ab();

    void setChess(const NineChess &chess);
    void setDepth(int depth) { this->depth = depth; }
    void quit() { requiredQuit = true; }

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

    // 局面逆序
    void reverse(const NineChess *node1, NineChess *node2, int i);
    // 局面层次翻转
    void turn(const NineChess *node1, NineChess *node2, int i);
    // 局面旋转
    void rotate(const NineChess *node1, NineChess *node2, int i);
    // 判断是否在缓存中
    bool isInCache(Node * node, int &value);

private:
    // 原始模型
    NineChess chess;
    // 演算用的模型
    NineChess chessTemp;

    // 根节点
    Node * rootNode;
    // 局面数据缓存区
    list<NineChess> dataCache;
    // 局面数据缓存区最大大小
    size_t cacheMaxSize;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit;
    // 剪枝算法的层深
    int depth;
    // 定义极大值，等于32位有符号整形数字的最大值
    static const int infinity = 0x7fffffff;
};

#endif
