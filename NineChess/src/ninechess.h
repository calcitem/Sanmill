/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
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

#ifndef NINECHESS
#define NINECHESS

//#include <sys/timeb.h>
#include <string>
#include <cstring>
#include <list>

#include "config.h"

using std::string;
using std::list;

// 棋类（在数据模型内，玩家只分先后手，不分黑白）
// 注意：NineChess类不是线程安全的！
// 所以不能跨线程修改NineChess类的静态成员变量，切记！
class NineChess
{
    // AI友元类
    friend class NineChessAi_ab;

public:
    // 静态成员常量
    // 3圈，禁止修改！
    static const int N_RINGS = 3;

    // 8位，禁止修改！
    static const int N_SEATS = 8;

    // 横直斜3个方向，禁止修改！
    static const int N_DIRECTIONS = 3;

    // 棋盘点的个数：40
    static const int N_POINTS = (NineChess::N_RINGS + 2) * NineChess::N_SEATS;

    // 移动方向，包括顺时针、逆时针、向内、向外4个方向
    enum MoveDirection
    {
        MOVE_DIRECTION_CLOCKWISE = 0,       // 顺时针
        MOVE_DIRECTION_ANTICLOCKWISE = 1,   // 逆时针
        MOVE_DIRECTION_INWARD = 2,          // 向内
        MOVE_DIRECTION_OUTWARD = 3,         // 向外
        MOVE_DIRECTION_FLY = 4,             // 飞子
        N_MOVE_DIRECTIONS = 4               // 移动方向数
    };

    // 遍历棋盘点所用的起始位置，即 [8, 32)
    static const int POS_BEGIN = N_SEATS;
    static const int POS_END = ((N_RINGS + 1) * N_SEATS);

    // 预定义的规则数目
    static const int N_RULES = 4;

    // 定义类型
    using move_t = int32_t;
    using step_t = uint16_t;

#ifdef HASH_MAP_CUTDOWN
    using hash_t = uint32_t;
#else
    using hash_t = uint64_t;
#endif /* HASH_MAP_CUTDOWN */

    // 位置迭代器
    // typedef typename std::vector<move_t>::iterator posIterator;
    // typedef typename std::vector<move_t>::const_iterator constPosIterator;

    // 赢盘数
    int score_1 {};
    int score_2 {};
    int score_draw {};

    // 嵌套的规则结构体
    struct Rule
    {
        // 规则名称
        const char *name;

        // 规则介绍
        const char *description;

        // 任一方子数，各9子或各12子
        int nTotalPiecesEachSide;

        // 赛点子数，少于则判负
        int nPiecesAtLeast;

        // 是否有斜线
        bool hasObliqueLines;

        // 是否有禁点（摆棋阶段被提子的点不能再摆子）
        bool hasForbiddenPoint;

        // 是否后摆棋者先行棋
        bool isDefenderMoveFirst;

        // 相同顺序和位置的重复“三连”是否可反复提子
        bool allowRemovePiecesRepeatedly;

        // 多个“三连”能否多提子
        bool allowRemoveMultiPieces;

        // 能否提“三连”的子
        bool allowRemoveMill;

        // 摆棋满子（闷棋，只有12子棋才出现），是否算先手负，false为和棋
        bool isStartingPlayerLoseWhenBoardFull;

        // 走棋阶段不能行动（被“闷”）是否算负，false则轮空（由对手走棋）
        bool isLoseWhenNoWay;

        // 剩三子时是否可以飞棋
        bool allowFlyWhenRemainThreePieces;

        // 最大步数，超出判和
        step_t maxStepsLedToDraw;

        // 包干最长时间（秒），超出判负，为0则不计时
        int maxTimeLedToLose;
    };

    // 预定义的规则
    static const struct Rule RULES[N_RULES];

    // 局面阶段标识
    enum GameStage : uint16_t
    {
        GAME_NONE = 0x0000,
        GAME_NOTSTARTED = 0x0001,   // 未开局
        GAME_PLACING = 0x0002,      // 开局（摆棋）
        GAME_MOVING = 0x0004,       // 中局（走棋）
        GAME_OVER = 0x0008          // 结局
    };

    uint64_t rand64() {
        return static_cast<uint64_t>(rand()) ^
                (static_cast<uint64_t>(rand()) << 15) ^
                (static_cast<uint64_t>(rand()) << 30) ^
                (static_cast<uint64_t>(rand()) << 45) ^
                (static_cast<uint64_t>(rand()) << 60);
    }

    uint64_t rand56()
    {
        return rand64() << 8;
    }

    // 玩家标识, 轮流状态, 胜负标识
    enum Player : uint16_t
    {
        PLAYER1 = 0x0010,   // 玩家1
        PLAYER2 = 0x0020,   // 玩家2
        DRAW = 0x0040,      // 双方和棋
        NOBODY = 0x0080     // 胜负未分
    };

    static Player getOpponent(enum Player player);

    // 动作状态标识
    enum Action : uint16_t
    {
        ACTION_NONE =  0x0000,
        ACTION_CHOOSE = 0x0100,    // 选子
        ACTION_PLACE = 0x0200,     // 落子
        ACTION_CAPTURE = 0x0400    // 提子
    };

    // 棋盘点上棋子的类型
    enum PointType : uint16_t
    {
        POINT_TYPE_EMPTY = 0,   // 没有棋子
        POINT_TYPE_PLAYER1 = 1,    // 先手的子
        POINT_TYPE_PLAYER2 = 2,     // 后手的子
        POINT_TYPE_FORBIDDEN = 3,    // 禁点
        POINT_TYPE_COUNT = 4
    };

    // 棋局结构体，算法相关，包含当前棋盘数据
    // 单独分离出来供AI判断局面用，生成置换表时使用
    struct ChessContext
    {
        // 棋局，抽象为一个（5×8）的数组，上下两行留空
        /*
            0x00 代表无棋子
            0x0F 代表禁点
            0x11～0x1C 代表先手第 1～12 子
            0x21～0x2C 代表后手第 1～12 子
            判断棋子是先手的用 (board[i] & 0x10)
            判断棋子是后手的用 (board[i] & 0x20)
         */
        int board[N_POINTS] {};

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        // 局面的哈希值
        hash_t hash {};

        // 标记处于走子阶段的哈希
        hash_t gameMovingHash {};

        // 吃子动作的哈希
        hash_t actionCaptureHash {};

        // 标记轮到玩家2行棋的哈希
        hash_t player2sTurnHash {};

        // Zobrist 数组
        hash_t zobrist[N_POINTS][POINT_TYPE_COUNT] {};
#endif /* HASH_MAP_ENABLE */

        // 局面阶段标识
        enum NineChess::GameStage stage;

        // 轮流状态标识
        enum NineChess::Player turn;

        // 动作状态标识
        enum NineChess::Action action {};

        // 玩家1剩余未放置子数
        int nPiecesInHand_1 {};

        // 玩家2剩余未放置子数
        int nPiecesInHand_2 {};

        // 玩家1盘面剩余子数
        int nPiecesOnBoard_1 {};

        // 玩家1盘面剩余子数
        int nPiecesOnBoard_2 {};

        // 尚待去除的子数
        int nPiecesNeedRemove {};

#if 0
        本打算用如下的结构体来表示“三连”
        struct Mill {
            char piece1;    // “三连”中最小的棋子
            char pos1;      // 最小棋子的位置
            char piece2;    // 次小的棋子
            char pos2;      // 次小棋子的位置
            char piece3;    // 最大的棋子
            char pos3;      // 最大棋子的位置
        };
        但为了提高执行效率改用一个64位整数了，规则如下
        0x   00     00     00    00    00    00    00    00
           unused unused piece1 pos1 piece2 pos2 piece3 pos3
#endif

        // “三连列表”
        list <uint64_t> millList;
    };

private:
    // 空棋盘点位，用于判断一个棋子位置是否在棋盘上
    static const int onBoard[(N_RINGS + 2) * N_SEATS];

    // 着法表，每个位置有最多4种走法：顺时针、逆时针、向内、向外
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static int moveTable[(N_RINGS + 2) * N_SEATS][N_MOVE_DIRECTIONS];

    // 成三表，表示棋盘上各个位置有成三关系的对应位置表
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static int millTable[(N_RINGS + 2) * N_SEATS][3][2];

    // 生成着法表
    void createMoveTable();

    // 生成成三表
    void createMillTable();

    // 创建哈希值
    void constructHash();

public:
    explicit NineChess();
    virtual ~NineChess();

    // 拷贝构造函数
    explicit NineChess(const NineChess &);

    // 运算符重载
    NineChess &operator=(const NineChess &);

    // 设置棋局状态和棋盘上下文，用于初始化
    bool setContext(const struct Rule *rule,
                 step_t maxStepsLedToDraw = 0,     // 限制步数
                 int maxTimeLedToLose = 0,      // 限制时间
                 step_t initialStep = 0,           // 默认起始步数为0
                 int flags = GAME_NOTSTARTED | PLAYER1 | ACTION_PLACE, // 默认状态
                 const char *board = nullptr,   // 默认空棋盘
                 int nPiecesInHand_1 = 12,      // 玩家1剩余未放置子数
                 int nPiecesInHand_2 = 12,      // 玩家2剩余未放置子数
                 int nPiecesNeedRemove = 0      // 尚待去除的子数
    );

    // 获取棋局状态和棋盘上下文
    void getContext(struct Rule &rule, step_t &step, int &flags, int *&board,
                    int &nPiecesInHand_1, int &nPiecesInHand_2, int &nPiecesNeedRemove);

    // 获取当前规则
    const struct Rule *getRule() const
    {
        return &currentRule;
    }

    // 获取棋盘数据
    const int *getBoard() const
    {
        return context.board;
    }

    // 获取棋子位置(c, p)
    bool getPieceCP(const Player &player, const int &number, int &c, int &p);

    // 获取当前棋子
    bool getCurrentPiece(Player &player, int &number);

    // 获取当前棋子位置点
    int getCurrentPos() const
    {
        return currentPos;
    }

    // 判断位置点是否为星位 (星位是经常会先占的位置)
    static bool isStarPoint(int pos)
    {
        return (pos == 17 || pos == 19 || pos == 21 || pos == 23);
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

    // 获取局面阶段标识
    enum GameStage getStage() const
    {
        return context.stage;
    }

    // 获取轮流状态标识
    enum Player whosTurn() const
    {
        return context.turn;
    }

    // 获取动作状态标识
    enum Action getAction() const
    {
        return context.action;
    }

    // 判断胜负
    enum Player whoWin() const
    {
        return winner;
    }

    // 玩家1和玩家2的用时
    void getElapsedTimeMS(time_t &p1_ms, time_t &p2_ms);

    // 获取棋局的字符提示
    const string getTips() const
    {
        return tips;
    }

    // 获取位置点棋子的归属人
    enum Player getWhosPiece(int c, int p);

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
        return startTimeb;
    }

    // 重新设置开局时间
    void setStartTimeb(int stimeb)
    {
        startTimeb = stimeb;
    }

    // 玩家1剩余未放置子数
    int getPiecesInHandCount_1() const
    {
        return context.nPiecesInHand_1;
    }

    // 玩家2剩余未放置子数
    int getPiecesInHandCount_2() const
    {
        return context.nPiecesInHand_2;
    }

    // 玩家1盘面剩余子数
    int getPiecesOnBoardCount_1() const
    {
        return context.nPiecesOnBoard_1;
    }

    // 玩家1盘面剩余子数
    int getPiecesOnBoardCount_2() const
    {
        return context.nPiecesOnBoard_2;
    }

    // 尚待去除的子数
    int getNum_NeedRemove() const
    {
        return context.nPiecesNeedRemove;
    }

    // 游戏重置
    bool reset();

    // 游戏开始
    bool start();

    // 选子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool choose(int c, int p);

    // 落子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool _place(int c, int p, int time_p = -1);

    // 去子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool _capture(int c, int p, int time_p = -1);

    // 认输
    bool giveup(Player loser);

    // 命令行解析函数
    bool command(const char *cmd);

    // 局面左右镜像
    void mirror(bool cmdChange = true);

    // 局面内外翻转
    void turn(bool cmdChange = true);

    // 局面逆时针旋转
    void rotate(int degrees, bool cmdChange = true);

protected:
    // 判断棋盘pos处的棋子处于几个“三连”中
    int isInMills(int pos, bool test = false);

    // 判断玩家的所有棋子是否都处于“三连”状态
    bool isAllInMills(char ch);
    bool isAllInMills(enum Player);

    // 判断玩家的棋子是否被围
    bool isSurrounded(int pos);

    // 判断玩家的棋子是否全部被围
    bool isAllSurrounded(char ch);

    bool isAllSurrounded(enum Player);

    // 三连加入列表
    int addMills(int pos);

    // 将棋盘下标形式转化为第c圈，第p位，c和p下标都从1开始
    void pos2cp(int pos, int &c, int &p);

    // 将第c圈，第p位转化为棋盘下标形式，c和p下标都从1开始
    int cp2pos(int c, int p);

    // 更新时间和状态，用内联函数以提高效率
    inline int update(int time_p = -1);

    // 是否分出胜负
    bool win();
    bool win(bool forceDraw);

    // 清除所有禁点
    void cleanForbiddenPoints();

    // 改变轮流
    enum NineChess::Player changeTurn();

    // 设置提示
    void setTips();

    // 下面几个函数没有算法无关判断和无关操作，节约算法时间
    bool command(int move);
    bool choose(int pos);
    bool place(int pos, int time_p = -1, int8_t cp = 0);
    bool capture(int pos, int time_p = -1, int8_t cp = 0);

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
    // hash相关
    hash_t getHash();
    hash_t revertHash(int pos);
    hash_t updateHash(int pos);
    hash_t updateHashMisc();
#endif

private:
    // 当前使用的规则
    struct Rule currentRule {};

    // 棋局上下文
    struct ChessContext context;

    // 棋局上下文中的棋盘数据，单独提出来
    int *board_;

    // 棋局哈希值
    // uint64_t hash;

    // 选中的棋子在board中的位置
    int currentPos {};

    // 胜负标识
    enum Player winner;

    // 当前步数
    step_t currentStep {};

    // 从走子阶段开始或上次吃子起的步数
    int moveStep {};

    // 游戏起始时间
    time_t startTimeb {};

    // 当前游戏时间
    time_t currentTimeb {};

    // 玩家1用时（秒）
    time_t elapsedMS_1 {};

    // 玩家2用时（秒）
    time_t elapsedMS_2 {};

    /* 当前着法，AI会用到，如下表示
    0x   00    00
        pos1  pos2
    开局落子：0x00??，??为棋盘上的位置
    移子：0x__??，__为移动前的位置，??为移动后的位置
    去子：0xFF??，??取位置补码，即为负数
    */
    /*
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
    int32_t move_ {};

    // 着法命令行用于棋谱的显示和解析
    // 当前着法的命令行指令，即一招棋谱
    char cmdline[64] {};

    // 棋谱
    list <string> cmdlist;

    // 当前棋局的字符提示
    string tips;
};

#endif
