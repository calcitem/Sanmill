/****************************************************************************
** by liuweilhy, 2013.01.14
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/

#ifndef NINECHESS
#define NINECHESS

#include <sys/timeb.h>
#include <string>
#include <cstring>
#include <list>

using std::string;
using std::list;

// 棋类（在数据模型内，玩家只分先后手，不分黑白）
class NineChess
{
public:
    // 公有的结构体和枚举，只是类型定义，不是变量！
    // 规则结构体
    struct Rule
    {
        // 规则名称
        const char *name;
        // 规则介绍
        const char *info;
        // 任一方子数，各9子或各12子
        int numOfChess;
        // 赛点子数，少于则判负
        int numAtLest;
        // 是否有斜线
        bool hasObliqueLine;
        // 是否有禁点（摆棋阶段被提子的点不能再摆子）
        bool hasForbidden;
        // 是否后摆棋者先行棋
        bool isDefensiveMoveFirst;
        // 相同顺序和位置的重复“三连”是否可反复提子
        bool canRepeated;
        // 多个“三连”能否多提子
        bool removeMore;
        // 摆棋满子（闷棋，只有12子棋才出现），是否算先手负，false为和棋
        bool isFullLose;
        // 走棋阶段不能行动（被“闷”）是否算负，false则轮空（由对手走棋）
        bool isNoWayLose;
        // 剩三子时是否可以飞棋
        bool canFly;
        // 最大步数，超出判和
        int maxSteps;
        // 包干最长时间（秒），超出判负，为0则不计时
        int maxTime;
    };

    // 局面阶段标识
    enum Phases {
        GAME_NOTSTARTED = 0x00000001,  // 未开局
        GAME_OPENING = 0x00000002,    // 开局（摆棋）
        GAME_MID = 0x00000004,        // 中局（走棋）
        GAME_OVER = 0x00000008        // 结局
    };

    // 玩家标识,轮流状态,胜负标识
    enum Player {
        PLAYER1 = 0x00000010,         // 玩家1
        PLAYER2 = 0x00000020,         // 玩家2
        DRAW = 0x00000040,            // 双方和棋
        NOBODY = 0x00000080           // 胜负未分
    };

    // 动作状态标识
    enum Actions {
        ACTION_CHOOSE = 0x00000100,   // 选子
        ACTION_PLACE = 0x00000200,    // 落子
        ACTION_REMOVE = 0x00000400    // 提子
    };

    // 5个静态成员常量
    // 3圈，禁止修改！
    static const int RING = 3;
    // 8位，禁止修改！
    static const int SEAT = 8;
    // 预定义的规则数目
    static const int RULENUM = 4;
    // 预定义的规则
    static const struct Rule RULES[RULENUM];

public:
    NineChess();
    virtual ~NineChess();
    // 设置棋局状态和棋盘数据，用于初始化
    bool setData(const struct Rule *rule,
        int s = 0,   // 限制步数
        int t = 0,   // 限制时间
        int step = 0,   // 默认起始步数为0
        int flags = GAME_NOTSTARTED | PLAYER1 | ACTION_PLACE | NOBODY, // 默认状态
        const char *boardsource = nullptr,   // 默认空棋盘
        int p1_InHand = 12,     // 玩家1剩余未放置子数
        int p2_InHand = 12,     // 玩家2剩余未放置子数
        int num_NeedRemove = 0  // 尚待去除的子数
    );

    // 获取棋局状态和棋盘数据
    void getData(struct Rule &rule, int &step, int &flags, const char *&boardsource, int &p1_InHand, int &p2_InHand, int &num_NeedRemove);
    // 获取棋盘数据
    const char *getBoard();
    // 获取当前规则
    const struct Rule *getRule() { return &rule; }
    // 获取当前点
    int getCurrentPos() { return currentPos; }
    // 获取当前步数
    int getStep() { return step; }
    // 获取局面阶段标识
    enum Phases getPhase() { return phase; }
    // 获取轮流状态标识
    enum Player whosTurn() { return turn; }
    // 获取动作状态标识
    enum Actions getAction() { return action; }
    // 判断胜负
    enum Player whoWin() { return winner; }
    // 玩家1和玩家2的用时
    void getPlayer_TimeMS(int &p1_ms, int &p2_ms);
    // 获取棋局的字符提示
    const string getTip() { return tip; }
    // 获取位置点棋子的归属人
    enum Player getWhosPiece(int c, int p);
    // 获取位置点棋子的序号
    int getPieceNum(int c, int p);
    // 获取当前招法
    const char *getCmdLine() { return cmdline; }
    // 获得棋谱
    const list<string> * getCmdList() { return &cmdlist; }
    // 获取开局时间
    timeb getStartTimeb() { return startTimeb; }
    // 重新设置开局时间
    void setStartTimeb(timeb stimeb) { startTimeb = stimeb; }

    // 玩家1剩余未放置子数
    int getPlayer1_InHand() { return player1_InHand; }
    // 玩家2剩余未放置子数
    int getPlayer2_InHand() { return player2_InHand; }
    // 玩家1盘面剩余子数
    int getPlayer1_Remain() { return player1_Remain; }
    // 玩家1盘面剩余子数
    int getPlayer2_Remain() { return player2_Remain; }
    // 尚待去除的子数
    int getNum_NeedRemove() { return num_NeedRemove; }

    // 游戏重置
    bool reset();
    // 游戏开始
    bool start();
    // 选子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool choose(int c, int p);
    // 落子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool place(int c, int p, long time_p = -1);
    // 去子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool remove(int c, int p, long time_p = -1);
	// 认输
	bool giveup(Player loser);
    // 命令行解析函数
    bool command(const char *cmd);

protected:
    // 判断棋盘pos处的棋子处于几个“三连”中
    int isInMills(int pos);
    // 判断玩家的所有棋子是否都处于“三连”状态
    bool isAllInMills(enum Player);
    // 判断玩家的棋子是否被围
    bool isSurrounded(int pos);
    // 判断玩家的棋子是否全部被围
    bool isAllSurrounded(enum Player);
    // 三连加入列表
    int addMills(int pos);
    // 将第c圈，第p位转化为棋盘下标形式，c和p下标都从1开始
    int cp2pos(int c, int p);
    // 更新时间和状态，用内联函数以提高效率
    inline long update(long time_p = -1);
    // 是否分出胜负
    bool win();
    // 清除所有禁点
    void cleanForbidden();
    // 改变轮流
    enum NineChess::Player changeTurn();
    // 设置提示
    void setTip();

private:
    // 当前使用的规则
    struct Rule rule;
    // 当前步数
    int step;
    // 局面阶段标识
    enum Phases phase;
    // 轮流状态标识
    enum Player turn;
    // 动作状态标识
    enum Actions action;
    // 赢家
    enum Player winner;

    // 玩家1剩余未放置子数
    int player1_InHand;
    // 玩家2剩余未放置子数
    int player2_InHand;
    // 玩家1盘面剩余子数
    int player1_Remain;
    // 玩家1盘面剩余子数
    int player2_Remain;
    // 尚待去除的子数
    int num_NeedRemove;

    // 游戏起始时间
    timeb startTimeb;
    // 当前游戏时间
    timeb currentTimeb;
    // 玩家1用时（毫秒）
    long player1_MS;
    // 玩家2用时（毫秒）
    long player2_MS;

    /* 棋局，抽象为一个（5×8）的char数组，上下两行留空
     * 0x00代表无棋子
     * 0x0F代表禁点
     * 0x10～(N-1)+0x10代表先手第1～N子
     * 0x20～(N-1)+0x20代表后手第1～N子
     * 判断棋子是先手的用(board[i] & 0x10)
     * 判断棋子是后手的用(board[i] & 0x20)
     */
    char board[(RING + 2)*SEAT];
    // 选中的棋子在board中的位置
    int currentPos;
    // 空棋盘点位，用于判断一个棋子位置是否在棋盘上
    static const char inBoard[(RING + 2)*SEAT];
    // 招法表，每个位置有最多4种走法：顺时针、逆时针、向内、向外
    static char moveTable[(RING + 2)*SEAT][4];
    // 成三表，表示棋盘上各个位置有成三关系的对应位置表
    static char millTable[(RING + 2)*SEAT][3][2];

    /* 本打算用如下的结构体来表示“三连”
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
    */
    // “三连列表”
    list <long long> millList;

    // 当前招法的命令行指令，即一招棋谱
    char cmdline[32];
    // 棋谱
    list <string> cmdlist;
    // 当前棋局的字符提示
    string tip;
};

#endif
