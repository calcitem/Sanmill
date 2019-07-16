/****************************************************************************
** by liuweilhy, 2018.11.29
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#ifndef NINECHESSAI_AB
#define NINECHESSAI_AB

#include <list>
#include <stack>
#include <mutex>
#include <string>
#include <Qdebug>
#include <array>

#include "ninechess.h"
#include "hashMap.h"

using namespace std;
using namespace CTSL;

// 注意：NineChess类不是线程安全的！
// 所以不能在ai类中修改NineChess类的静态成员变量，切记！
// 另外，AI类是NineChess类的友元类，可以访问其私有变量
// 尽量不要使用NineChess的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class NineChessAi_ab
{
public:
#ifdef HASH_MAP_ENABLE
    // 定义哈希值的类型
    enum HashType
    {
        hashfEMPTY = 0,
        hashfALPHA = 1,
        hashfBETA = 2,
        hashfEXACT = 3
    };
#endif

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING)) 
    // 定义哈希表的值
    struct HashValue
    {
        int value;
        int depth;
        int alpha;
        int beta;
        //int power;
        uint64_t hash;
        enum HashType type;
    };
#endif /* HASH_MAP_ENABLE */

    // 定义一个节点结构体
    struct Node
    {
    public:
        int move;                      // 着法的命令行指令，图上标示为节点前的连线
        int value;                     // 节点的值
        vector<struct Node*> children;  // 子节点列表
        struct Node* parent;           // 父节点
        size_t id;                      // 结点编号
        bool pruned;                    // 是否在此处剪枝
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING)) 
        uint64_t hash;                  //  哈希值
#endif
#ifdef HASH_MAP_ENABLE
        bool isHash;                    //  是否从 Hash 读取
#endif /* HASH_MAP_ENABLE */
#ifdef DEBUG_AB_TREE
        string cmd;
        enum NineChess::Player player;  // 此招是谁下的
        int depth;                      // 深度
        bool evaluated;                 // 是否评估过局面
        int alpha;                      // 当前搜索结点走棋方搜索到的最好值，任何比它小的值对当前结点的走棋方都没有意义。当函数递归时 Alpha 和 Beta 不但取负数而且要交换位置
        int beta;                       // 表示对手目前的劣势，这是对手所能承受的最坏结果，Beta 值越大，表示对手劣势越明显，如果当前结点返回  Beta 或比 Beta 更好的值，作为父结点的对方就绝对不会选择这种策略 
        bool isTimeout;                 // 是否遍历到此结点时因为超时而被迫退出
        bool isLeaf;                    // 是否为叶子结点, 叶子结点是决胜局面
        bool visited;                   // 是否在遍历时访问过
        NineChess::GameStage stage;     // 摆棋阶段还是走棋阶段
        NineChess::Action action;       // 动作状态
        int nPiecesOnBoardDiff;         // 场上棋子个数和对手的差值
        int nPiecesInHandDiff;          // 手中的棋子个数和对手的差值
        int nPiecesNeedRemove;          // 手中有多少可去的子，如对手有可去的子则为负数
        int result;                     // 终局结果，-1为负，0为未到终局，1为胜，走棋阶段被闷棋则为 -2/2，布局阶段闷棋为 -3
        struct Node* root;              // 根节点
#endif /* DEBUG_AB_TREE */

#if 0
        bool operator < (const Node &another) const
        {
            return this->value < another.value;
        }

        bool operator > (const Node &another) const
        {
            return this->value > another.value;
        }

        bool operator == (const Node &another) const
        {
            return this->value == another.value;
        }
#endif
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

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING)) 
    // 清空哈希表
    void clearHashMap();
#endif

    // 比较函数
    static bool nodeLess(const Node *first, const Node *second);
    static bool nodeGreater(const Node *first, const Node *second);

#ifdef BOOK_LEARNING
    bool findBookHash(uint64_t hash, HashValue &hashValue);
    static int recordBookHash(const HashValue &hashValue);
    void clearBookHashMap();
    static void recordOpeningBookToHashMap();
#endif // BOOK_LEARNING

protected:
    // 生成所有合法的着法并建立子节点
    void generateLegalMoves(Node *node);

    // 对合法的着法降序排序
    void sortLegalMoves(Node *node);

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

    // 返回着法的命令行
    const char *move2string(int move);

    // 篡改深度
    int changeDepth(int originalDepth);

    // 随机打乱着法搜索顺序
#ifdef MOVE_PRIORITY_TABLE_SUPPORT
#ifdef RANDOM_MOVE
    void shuffleMovePriorityTable();
#endif
#endif

#ifdef HASH_MAP_ENABLE
    // 查找哈希表
    bool findHash(uint64_t hash, HashValue &hashValue);
    int probeHash(uint64_t hash, int depth, int alpha, int beta);

    // 插入哈希表
    int recordHash(const HashValue &hashValue);
    int recordHash(int value, int alpha, int beta, int depth, HashType type, uint64_t hash);
#endif // HASH_MAP_ENABLE

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

#ifdef HASH_MAP_ENABLE
    // Hash 统计数据
    size_t hashEntryCount;
    size_t hashHitCount;
    size_t hashInsertNewCount;
    size_t hashAddrHitCount;
    size_t hashReplaceCozDepthCount;
    size_t hashReplaceCozHashCount;
#endif

    // 局面数据栈
    stack<NineChess::ChessContext> contextStack;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit;

#ifdef MOVE_PRIORITY_TABLE_SUPPORT
    array<int, NineChess::N_RINGS *NineChess::N_SEATS> movePriorityTable;
#endif // MOVE_PRIORITY_TABLE_SUPPORT

    // 定义极大值
    static const int INF_VALUE = 0x1 << 30;

    // 定义未知值
    static const int UNKNOWN_VALUE = INT32_MAX;

private:
    // 命令行
    char cmdline[32];

#ifdef HASH_MAP_ENABLE
    //HashMap<struct HashValue> hashmap;
#endif
};

#endif
