/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
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

#ifndef MILLGAMEAI_AB
#define MILLGAMEAI_AB

#include "config.h"

#include <list>
//#ifdef MEMORY_POOL
//#include "StackAlloc.h"
//#else
#include <stack>
#include <vector>
//#endif
#include <mutex>
#include <string>
#include <array>

#include "position.h"
#include "hashmap.h"

#ifdef MEMORY_POOL
#include "MemoryPool.h"
#endif

using namespace std;
using namespace CTSL;

// 注意：MillGame类不是线程安全的！
// 所以不能在ai类中修改MillGame类的静态成员变量，切记！
// 另外，AI类是MillGame类的友元类，可以访问其私有变量
// 尽量不要使用MillGame的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class MillGameAi_ab
{
public:
    // 定义一个节点结构体
    struct Node
    {
    public:
        vector<struct Node*> children;  // 子节点列表
        struct Node* parent {};            // 父节点
        move_t move {};                  // 着法的命令行指令，图上标示为节点前的连线
        value_t value {};                 // 节点的值
        enum player_t player;  // 此着是谁下的 (目前仅调试用)
#ifdef SORT_CONSIDER_PRUNED
        bool pruned {};                    // 是否在此处剪枝
#endif

#ifdef DEBUG_AB_TREE
        size_t id;                      // 结点编号
        string cmd;
        int depth;                      // 深度
        bool evaluated;                 // 是否评估过局面
        int alpha;                      // 当前搜索结点走棋方搜索到的最好值，任何比它小的值对当前结点的走棋方都没有意义。当函数递归时 Alpha 和 Beta 不但取负数而且要交换位置
        int beta;                       // 表示对手目前的劣势，这是对手所能承受的最坏结果，Beta 值越大，表示对手劣势越明显，如果当前结点返回  Beta 或比 Beta 更好的值，作为父结点的对方就绝对不会选择这种策略
        bool isTimeout;                 // 是否遍历到此结点时因为超时而被迫退出
        bool isLeaf;                    // 是否为叶子结点, 叶子结点是决胜局面
        bool visited;                   // 是否在遍历时访问过
        phase_t phase;     // 摆棋阶段还是走棋阶段
        action_t action;       // 动作状态
        int nPiecesOnBoardDiff;         // 场上棋子个数和对手的差值
        int nPiecesInHandDiff;          // 手中的棋子个数和对手的差值
        int nPiecesNeedRemove;          // 手中有多少可去的子，如对手有可去的子则为负数
        struct Node* root;              // 根节点
#ifdef TRANSPOSITION_TABLE_ENABLE
        bool isHash;                    //  是否从 Hash 读取
#endif /* TRANSPOSITION_TABLE_ENABLE */
        hash_t hash;                  //  哈希值
#endif /* DEBUG_AB_TREE */
    };

#ifdef MEMORY_POOL
    MemoryPool<Node> pool;
#endif

public:
    MillGameAi_ab();
    ~MillGameAi_ab();

    void setPosition(const Game &position);

    void quit()
    {
        loggerDebug("Timeout\n");
        requiredQuit = true;
    }

    // Alpha-Beta剪枝算法
    int alphaBetaPruning(depth_t depth);

    // 返回最佳走法的命令行
    const char *bestMove();

#if ((defined TRANSPOSITION_TABLE_ENABLE) || (defined BOOK_LEARNING))
    // 清空哈希表
    void clearTranspositionTable();
#endif

    // 比较函数
    static bool nodeLess(const Node *first, const Node *second);
    static bool nodeGreater(const Node *first, const Node *second);

#ifdef BOOK_LEARNING
    bool findBookHash(hash_t hash, HashValue &hashValue);
    static int recordBookHash(hash_t hash, const HashValue &hashValue);
    void clearBookHashMap();
    static void recordOpeningBookToHashMap();
    static void recordOpeningBookHashMapToFile();
    static void loadOpeningBookFileToHashMap();
#endif // BOOK_LEARNING

public: /* TODO: Move to private or protected */
    // 增加新节点
    struct Node *addNode(Node *parent, value_t value,
                         move_t move, move_t bestMove,
                         enum player_t player);

protected:
    // 对合法的着法降序排序
    void sortLegalMoves(Node *node);

    // 清空节点树
    void deleteTree(Node *node);

    // 构造根节点
    void buildRoot();

    // 评价函数
    value_t evaluate(Node *node);
#ifdef EVALUATE_ENABLE
#ifdef EVALUATE_MATERIAL
    value_t evaluateMaterial(Node *node);
#endif
#ifdef EVALUATE_SPACE
    value_t evaluateSpace(Node *node);
#endif
#ifdef EVALUATE_MOBILITY
    value_t evaluateMobility(Node *node);
#endif
#ifdef EVALUATE_TEMPO
    value_t evaluateTempo(Node *node);
#endif
#ifdef EVALUATE_THREAT
    value_t evaluateThreat(Node *node);
#endif
#ifdef EVALUATE_SHAPE
    value_t evaluateShape(Node *node);
#endif
#ifdef EVALUATE_MOTIF
    value_t evaluateMotif(Node *node);
#endif
#endif /* EVALUATE_ENABLE */

    // Alpha-Beta剪枝算法
    value_t alphaBetaPruning(depth_t depth, value_t alpha, value_t beta, Node *node);

    // 返回着法的命令行
    const char *move2string(move_t move);

    // 篡改深度
    depth_t changeDepth(depth_t originalDepth);
       
private:
    // 原始模型
    Game position_;

    // 演算用的模型
    Game dummyGame;

    PositionContext *positionContext {};

    // hash 计算时，各种转换用的模型
    Game dummyGameShift;

    // 根节点
    Node *rootNode {nullptr};

    // 结点个数;
    size_t nodeCount {0};

    // 评估过的结点个数
    size_t evaluatedNodeCount {0};

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    // Hash 统计数据
    size_t hashEntryCount;
    size_t hashHitCount;
    size_t hashInsertNewCount;
    size_t hashAddrHitCount;
    size_t hashReplaceCozDepthCount;
    size_t hashReplaceCozHashCount;
#endif
#endif

    // 局面数据栈
//#ifdef MEMORY_POOL
//    StackAlloc<MillGame::PositionContext, MemoryPool<MillGame::PositionContext> > contextStack;
//#else
    stack<PositionContext, vector<PositionContext> > contextStack;
//#endif

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit {false};

private:
    // 命令行
    char cmdline[64] {};
};

#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<hash_t> positions;
#endif

#endif
