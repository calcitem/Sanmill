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

#ifndef POSITION_H
#define POSITION_H

#include <string>
#include <cstring>
#include <list>

#include "config.h"
#include "types.h"
#include "rule.h"
#include "board.h"

using namespace std;

// 棋局结构体，算法相关，包含当前棋盘数据
// 单独分离出来供AI判断局面用，生成置换表时使用
class PositionContext
{
public:
    Board board;

    // 局面的哈希值
    hash_t hash{};

    // Zobrist 数组
    hash_t zobrist[Board::N_LOCATIONS][PIECE_TYPE_COUNT]{};

    // 局面阶段标识
    enum phase_t phase;

    // 轮流状态标识
    enum player_t turn;

    // 动作状态标识
    enum action_t action
    {
    };

    // 玩家剩余未放置子数
    int nPiecesInHand[3]{0};

    // 玩家盘面剩余子数
    int nPiecesOnBoard[3] {0};

    // 尚待去除的子数
    int nPiecesNeedRemove{};
};

// 棋类（在数据模型内，玩家只分先后手，不分黑白）
// 注意：Position 类不是线程安全的！
// 所以不能跨线程修改 Position 类的静态成员变量，切记！
class Position
{
    // AI友元类
    friend class MillGameAi_ab;

public:
    // 赢盘数
    int score_1 {};
    int score_2 {};
    int score_draw {};

    static int playerToId(enum player_t player);

    static player_t getOpponent(enum player_t player);

private:

    // 创建哈希值
    void constructHash();

public:
    explicit Position();
    virtual ~Position();

    // 拷贝构造函数
    explicit Position(const Position &);

    // 运算符重载
    Position &operator=(const Position &);

    // 设置配置
    bool configure(bool giveUpIfMostLose, bool randomMove);

    // 设置棋局状态和棋盘上下文，用于初始化
    bool setContext(const struct Rule *rule,
                 step_t maxStepsLedToDraw = 0,     // 限制步数
                 int maxTimeLedToLose = 0,      // 限制时间
                 step_t initialStep = 0,           // 默认起始步数为0
                 phase_t phase = PHASE_NOTSTARTED, player_t turn = PLAYER_1, action_t action = ACTION_PLACE,
                 const char *locations = nullptr,   // 默认空棋盘
                 int nPiecesInHand_1 = 12,      // 玩家1剩余未放置子数
                 int nPiecesInHand_2 = 12,      // 玩家2剩余未放置子数
                 int nPiecesNeedRemove = 0      // 尚待去除的子数
    );

    // 获取棋局状态和棋盘上下文
    void getContext(struct Rule &rule, step_t &step,
                    phase_t &phase, player_t &turn, action_t &action,
                    int *&board,
                    int &nPiecesInHand_1, int &nPiecesInHand_2, int &nPiecesNeedRemove);

    // 获取当前规则
    const struct Rule *getRule() const
    {
        return &currentRule;
    }

    // 获取棋盘数据
    int *getBoardLocations() const
    {
        return boardLocations;
    }

    // 获取当前棋子位置点
    int getCurrentLocation() const
    {
        return currentLocation;
    }

    // 获取当前步数
    int getStep() const
    {
        return currentStep;
    }

    // 获取从上次吃子开始经历的移动步数
    int getMoveStep() const
    {
        return moveStep;
    } 

    // 获取是否必败时认输
    bool getGiveUpIfMostLose() const
    {
        return giveUpIfMostLose_;
    }

    // 获取 AI 是否随机走子
    bool randomMoveEnabled() const
    {
        return isRandomMove;
    }

    // 获取局面阶段标识
    enum phase_t getPhase() const
    {
        return context.phase;
    }

    // 获取轮流状态标识
    enum player_t whosTurn() const
    {
        return context.turn;
    }

    // 获取动作状态标识
    enum action_t getAction() const
    {
        return context.action;
    }

    // 判断胜负
    enum player_t whoWin() const
    {
        return winner;
    }

    // 玩家1和玩家2的用时
    void getElapsedTime(time_t &p1_ms, time_t &p2_ms);

    // 获取棋局的字符提示
    const string getTips() const
    {
        return tips;
    }

    // 获取当前着法
    const char *getCmdLine() const
    {
        return cmdline;
    }

    // 获得棋谱
    const list<string> *getCmdList() const
    {
        return &cmdlist;
    }

    // 获取开局时间
    time_t getStartTimeb() const
    {
        return startTime;
    }

    // 重新设置开局时间
    void setStartTime(int stimeb)
    {
        startTime = stimeb;
    }

    // 玩家剩余未放置子数
    int getPiecesInHandCount(int playerId) const
    {
        return context.nPiecesInHand[playerId];
    }

    // 玩家1盘面剩余子数
    int getPiecesOnBoardCount(int playerId) const
    {
        return context.nPiecesOnBoard[playerId];
    }

    // 尚待去除的子数
    int getNum_NeedRemove() const
    {
        return context.nPiecesNeedRemove;
    }

    // 计算玩家1和玩家2的棋子活动能力之差
    int getMobilityDiff(enum player_t turn, const Rule &rule, int nPiecesOnBoard[], bool includeFobidden);

    // 游戏重置
    bool reset();

    // 游戏开始
    bool start();

    // 选子，在第r圈第s个位置，为迎合日常，r和s下标都从1开始
    bool choose(int r, int s);

    // 落子，在第r圈第s个位置，为迎合日常，r和s下标都从1开始
    bool _place(int r, int s, int time_p = -1);

    // 去子，在第r圈第s个位置，为迎合日常，r和s下标都从1开始
    bool _capture(int r, int s, int time_p = -1);

    // 认输
    bool giveup(player_t loser);

    // 命令行解析函数
    bool command(const char *cmd);

    // 更新时间和状态，用内联函数以提高效率
    inline int update(int time_p = -1);

    // 是否分出胜负
    bool win();
    bool win(bool forceDraw);

    // 清除所有禁点
    void cleanForbiddenLocations();

    // 改变轮流
    enum player_t changeTurn();

    // 设置提示
    void setTips();

    // 下面几个函数没有算法无关判断和无关操作，节约算法时间
    bool command(int move);
    bool choose(int location);
    bool place(int location, int time_p = -1, int8_t cp = 0);
    bool capture(int location, int time_p = -1, int8_t cp = 0);

    // hash 相关
    hash_t getHash();
    hash_t revertHash(int location);
    hash_t updateHash(int location);
    hash_t updateHashMisc();

public: /* TODO: move to private */
    // 棋局上下文
    PositionContext context;

    // 当前使用的规则
    struct Rule currentRule
    {
    };

    // 棋局上下文中的棋盘数据，单独提出来
    int *boardLocations;

    // 棋谱
    list <string> cmdlist;

    // 着法命令行用于棋谱的显示和解析, 当前着法的命令行指令，即一招棋谱
    char cmdline[64]{};

    /* 
        当前着法，AI会用到，如下表示
        0x   00    00
            location1  location2
        开局落子：0x00??，??为棋盘上的位置
        移子：0x__??，__为移动前的位置，??为移动后的位置
        去子：0xFF??，??取位置补码，即为负数

        31 ----- 24 ----- 25
        | \       |      / |
        |  23 -- 16 -- 17  |
        |  | \    |   / |  |
        |  |  15 08 09  |  |
        30-22-14    10-18-26
        |  |  13 12 11  |  |
        |  | /    |   \ |  |
        |  21 -- 20 -- 19  |
        | /       |     \  |
        29 ----- 28 ----- 27
    */
    move_t move_{};

    // 选中的棋子在board中的位置
    int currentLocation{};

private:
    // 棋局哈希值
    // uint64_t hash;

    // 胜负标识
    enum player_t winner;

    // 当前步数
    step_t currentStep {};

    // 从走子阶段开始或上次吃子起的步数
    int moveStep {};

    // 是否必败时认输
    bool giveUpIfMostLose_ {false};

    // AI 是否随机走子
    bool isRandomMove {true};

    // 游戏起始时间
    time_t startTime {};

    // 当前游戏时间
    time_t currentTime {};

    // 玩家1用时（秒）
    time_t elapsedSeconds_1 {};

    // 玩家2用时（秒）
    time_t elapsedSeconds_2 {};

    // 当前棋局的字符提示
    string tips;
};

#endif /* POSITION_H */
