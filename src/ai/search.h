/*
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

#include <mutex>
#include <string>
#include <array>

#include "stack.h"
#include "position.h"
#include "tt.h"
#include "hashmap.h"
#include "endgame.h"
#include "types.h"
#include "memmgr.h"
#include "misc.h"
#include "movepick.h"
#include "movegen.h"
#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

class AIAlgorithm;
class StateInfo;
class Node;
class Position;
class MovePicker;
class ExtMove;

using namespace std;
using namespace CTSL;

// 注意：Position 类不是线程安全的！
// 所以不能在ai类中修改 Position 类的静态成员变量，切记！
// 另外，AI类是 Position 类的友元类，可以访问其私有变量
// 尽量不要使用 Position 的操作函数，因为有参数安全性检测和不必要的赋值，影响效率

class AIAlgorithm
{
public:
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
#ifdef HOSTORY_HEURISTIC
        movePicker->clearHistoryScore();
#endif
    }

#ifdef ALPHABETA_AI
    // Alpha-Beta剪枝算法
    int search(depth_t depth);

    // 返回最佳走法的命令行
    const char *nextMove();
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

#ifdef ENDGAME_LEARNING
    bool findEndgameHash(key_t key, Endgame &endgame);
    static int recordEndgameHash(key_t key, const Endgame &endgame);
    void clearEndgameHashMap();
    static void recordEndgameHashMapToFile();
    static void loadEndgameFileToHashMap();
#endif // ENDGAME_LEARNING

public: /* TODO: Move to private or protected */

#ifdef EVALUATE_ENABLE

        // 评价函数
    value_t evaluate();

#ifdef EVALUATE_MATERIAL
    value_t evaluateMaterial();
#endif
#ifdef EVALUATE_SPACE
    value_t evaluateSpace();
#endif
#ifdef EVALUATE_MOBILITY
    value_t evaluateMobility();
#endif
#ifdef EVALUATE_TEMPO
    value_t evaluateTempo();
#endif
#ifdef EVALUATE_THREAT
    value_t evaluateThreat();
#endif
#ifdef EVALUATE_SHAPE
    value_t evaluateShape();
#endif
#ifdef EVALUATE_MOTIF
    value_t evaluateMotif();
#endif
#endif /* EVALUATE_ENABLE */

    // Alpha-Beta剪枝算法
    value_t search(depth_t depth, value_t alpha, value_t beta);

    // MTD(f)
    value_t MTDF(value_t firstguess, depth_t depth);

public:
    // 返回着法的命令行
    const char *moveToCommand(move_t move);
protected:
    // 篡改深度
    depth_t changeDepth(depth_t origDepth);
       
public:
    // 原始模型
    StateInfo *state { nullptr };

    MovePicker *movePicker { nullptr };

    value_t bestvalue { VALUE_ZERO };
    value_t lastvalue { VALUE_ZERO };

    depth_t originDepth{ 0 };

private:

    // 演算用的模型
    StateInfo *st { nullptr };

    Position *position { nullptr };

    // 局面数据栈
    Stack<Position> positionStack;

    // 标识，用于跳出剪枝算法，立即返回
    bool requiredQuit {false};

    move_t bestMove { MOVE_NONE };

private:
    // 命令行
    char cmdline[64] {};

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
public:
    // TT 统计数据
    size_t tteCount{ 0 };
    size_t ttHitCount{ 0 };
    size_t ttMissCount{ 0 };
    size_t ttInsertNewCount{ 0 };
    size_t ttAddrHitCount{ 0 };
    size_t ttReplaceCozDepthCount{ 0 };
    size_t ttReplaceCozHashCount{ 0 };
#endif
#endif
};

#include "tt.h"

#ifdef THREEFOLD_REPETITION
extern vector<hash_t> moveHistory;
#endif

#endif /* SEARCH_H */
