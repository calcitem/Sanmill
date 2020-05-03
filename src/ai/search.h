﻿/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef SEARCH_H
#define SEARCH_H

#include "config.h"

#ifdef USE_STD_STACK
#include <stack>
#include <vector>
#else
#include "stack.h"
#endif // USE_STD_STACK

#include <mutex>
#include <string>
#include <array>

#include "position.h"
#include "tt.h"
#include "hashmap.h"
#include "endgame.h"
#include "types.h"
#include "memmgr.h"
#include "misc.h"
#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

#ifdef MCTS_AI
#include "mcts.h"
#endif

class AIAlgorithm;
class StateInfo;
class Node;
class Position;

using namespace std;
using namespace CTSL;

// 注意：StateInfo类不是线程安全的！
// 所以不能在ai类中修改StateInfo类的静态成员变量，切记！
// 另外，AI类是StateInfo类的友元类，可以访问其私有变量
// 尽量不要使用StateInfo的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class Node
{
public:
    Node();
    ~Node();

#ifdef MCTS_AI
    Node(StateInfo &state);
    Node(StateInfo &state, const move_t &move, Node *parent);
#endif // MCTS_AI

    bool hasChildren() const;

    Node *addChild(
        const move_t &move, 
        AIAlgorithm *ai,
        StateInfo *st
#ifdef TT_MOVE_ENABLE
        , const move_t &ttMove
#endif // TT_MOVE_ENABLE
    );

#ifdef MCTS_AI
    bool hasUntriedMoves() const;
    template<typename RandomEngine>
    move_t getUntriedMove(RandomEngine *engine) const;
    Node *bestChildren() const;
    Node *selectChild() const;
    Node *addChild(const move_t &move, StateInfo &state);
    void update(double result);
    string toString();
    string treeToString(int max_depth = 1000000, int indent = 0) const;
    string indentString(int indent) const;
#endif // MCTS_AI

    static const int NODE_CHILDREN_SIZE = MOVE_COUNT;

    Node *children[NODE_CHILDREN_SIZE];
    Node *parent { nullptr };

#ifdef MCTS_AI
    //atomic<double> wins;
    //atomic<int> visits;
    double wins { 0 };
    double score { 0 };
    Stack<move_t, NODE_CHILDREN_SIZE> moves;
    int visits { 0 };
#else
    move_t moves[NODE_CHILDREN_SIZE];
#endif // MCTS_AI

    move_t move { MOVE_NONE };
    int childrenSize { 0 };

#ifdef ALPHABETA_AI
    value_t value { VALUE_UNKNOWN };
    rating_t rating { RATING_ZERO };
#endif // ALPHABETA_AI

    player_t sideToMove { PLAYER_NOBODY };

#ifdef DEBUG_AB_TREE
    size_t id;                      // 结点编号
    char cmd[32];
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
    struct Node *root;              // 根节点
#ifdef TRANSPOSITION_TABLE_ENABLE
    bool isHash;                    //  是否从 Hash 读取
#endif /* TRANSPOSITION_TABLE_ENABLE */
    hash_t hash;                  //  哈希值
#endif /* DEBUG_AB_TREE */
};

class AIAlgorithm
{
public:
    MemoryManager memmgr;

#ifdef TIME_STAT
    // 排序算法耗时 (ms)
    TimePoint sortTime { 0 };
#endif
#ifdef CYCLE_STAT
    // 排序算法耗费时间周期 (TODO: 计算单次或平均)
    stopwatch::rdtscp_clock::time_point sortCycle;
    stopwatch::timer::duration sortCycle { 0 };
    stopwatch::timer::period sortCycle;
#endif

public:
    AIAlgorithm();
    ~AIAlgorithm();

    void setState(const StateInfo &state);

    void quit()
    {
        loggerDebug("Timeout\n");
        requiredQuit = true;
    }

#ifdef ALPHABETA_AI
    // Alpha-Beta剪枝算法
    int search(depth_t depth);

    // 返回最佳走法的命令行
    const char *ttMove();
#endif // ALPHABETA_AI

    // 暂存局面
    void stashPosition();

    // 执行着法
    void doMove(move_t move);

    // 撤销着法
    void undoMove();

    void doNullMove();
    void undoNullMove();

#ifdef TRANSPOSITION_TABLE_ENABLE
    // 清空哈希表
    void clearTT();
#endif

#ifdef ALPHABETA_AI
    // 比较函数
    static int nodeCompare(const Node *first, const Node *second);
#endif // ALPHABETA_AI

#ifdef MCTS_AI
    // TODO: 分离到 MCTS 算法类
    Node *computeTree(StateInfo state,
                      const MCTSOptions options,
                      mt19937_64::result_type initialSeed);
    move_t AIAlgorithm::computeMove(StateInfo state,
                                    const MCTSOptions options);
#endif

#ifdef ENDGAME_LEARNING
    bool findEndgameHash(hash_t hash, Endgame &endgame);
    static int recordEndgameHash(hash_t hash, const Endgame &endgame);
    void clearEndgameHashMap();
    static void recordEndgameHashMapToFile();
    static void loadEndgameFileToHashMap();
#endif // ENDGAME_LEARNING


public: /* TODO: Move to private or protected */

    // 结点个数;
    size_t nodeCount { 0 };

    // 对合法的着法降序排序
    void sortMoves(Node *node);

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
    value_t search(depth_t depth, value_t alpha, value_t beta, Node *node);

public:
    // 返回着法的命令行
    const char *moveToCommand(move_t move);
protected:
    // 篡改深度
    depth_t changeDepth(depth_t origDepth);
       
public:
    // 原始模型
    StateInfo *state { nullptr };

private:

    // 演算用的模型
    StateInfo *st { nullptr };

    Position *position { nullptr };

    // 根节点
    Node *root {nullptr};

    // 评估过的结点个数
    size_t evaluatedNodeCount {0};

    // 局面数据栈
#ifdef USE_STD_STACK
    stack<Position, vector<Position> > positionStack;
#else
    Stack<Position> positionStack;
#endif /* USE_STD_STACK */

    Stack<move_t, MOVE_COUNT> moves;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit {false};

    move_t best { MOVE_NONE };
    depth_t originDepth { 0 };

private:
    // 命令行
    char cmdline[64] {};

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
public:
    // Hash 统计数据
    size_t hashEntryCount{ 0 };
    size_t hashHitCount{ 0 };
    size_t hashMissCount{ 0 };
    size_t hashInsertNewCount{ 0 };
    size_t hashAddrHitCount{ 0 };
    size_t hashReplaceCozDepthCount{ 0 };
    size_t hashReplaceCozHashCount{ 0 };
#endif
#endif
};

#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<hash_t> moveHistory;
#endif

#endif /* SEARCH_H */
