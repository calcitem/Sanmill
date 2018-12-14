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
// 注意：NineChess类不是线程安全的！
// 所以不能跨线程修改NineChess类的静态成员变量，切记！
class NineChess
{
    // AI友元类
    friend class NineChessAi_ab;
public:
    // 5个静态成员常量
    // 3圈，禁止修改！
    static const int RING = 3;
    // 8位，禁止修改！
    static const int SEAT = 8;
    // 预定义的规则数目
    static const int RULENUM = 4;

    // 嵌套的规则结构体
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
    // 预定义的规则
    static const struct Rule RULES[RULENUM];

    // 局面阶段标识
    enum Phases : uint16_t {
        GAME_NOTSTARTED = 0x0001,  // 未开局
        GAME_OPENING    = 0x0002,  // 开局（摆棋）
        GAME_MID        = 0x0004,  // 中局（走棋）
        GAME_OVER       = 0x0008   // 结局
    };

    // 玩家标识,轮流状态,胜负标识
    enum Players : uint16_t {
        PLAYER1 = 0x0010,   // 玩家1
        PLAYER2 = 0x0020,   // 玩家2
        DRAW    = 0x0040,   // 双方和棋
        NOBODY  = 0x0080    // 胜负未分
    };

    // 动作状态标识
    enum Actions : uint16_t {
        ACTION_CHOOSE = 0x0100,   // 选子
        ACTION_PLACE  = 0x0200,   // 落子
        ACTION_CAPTURE = 0x0400    // 提子
    };

    // 棋局结构体，算法相关，包含当前棋盘数据
    // 单独分离出来供AI判断局面用，生成置换表时使用
    struct ChessData {
        // 棋局，抽象为一个（5×8）的char数组，上下两行留空
        /* 0x00代表无棋子
           0x0F代表禁点
           0x11～0x1C代表先手第1～12子
           0x21～0x2c代表后手第1～12子
           判断棋子是先手的用(board[i] & 0x10)
           判断棋子是后手的用(board[i] & 0x20) */
        char board[(NineChess::RING + 2)*NineChess::SEAT];

        // 当前步数
        int step;
        // 局面阶段标识
        enum NineChess::Phases phase;
        // 轮流状态标识
        enum NineChess::Players turn;
        // 动作状态标识
        enum NineChess::Actions action;

        // 玩家1剩余未放置子数
        char player1_InHand;
        // 玩家2剩余未放置子数
        char player2_InHand;
        // 玩家1盘面剩余子数
        char player1_Remain;
        // 玩家1盘面剩余子数
        char player2_Remain;
        // 尚待去除的子数
        char num_NeedRemove;

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
        list <uint64_t> millList;
    };

private:
    // 空棋盘点位，用于判断一个棋子位置是否在棋盘上
    static const char inBoard[(RING + 2)*SEAT];

    // 招法表，每个位置有最多4种走法：顺时针、逆时针、向内、向外
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static char moveTable[(RING + 2)*SEAT][4];

    // 成三表，表示棋盘上各个位置有成三关系的对应位置表
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static char millTable[(RING + 2)*SEAT][3][2];

public:
    explicit NineChess();
    virtual ~NineChess();
    // 拷贝构造函数
    explicit NineChess(const NineChess &);
    // 运算符重载
    const NineChess & operator=(const NineChess &);

    // 设置棋局状态和棋盘数据，用于初始化
    bool setData(const struct Rule *rule,
        int s = 0,   // 限制步数
        int t = 0,   // 限制时间
        int step = 0,   // 默认起始步数为0
        int flags = GAME_NOTSTARTED | PLAYER1 | ACTION_PLACE, // 默认状态
        const char *boardsource = nullptr,   // 默认空棋盘
        int p1_InHand = 12,     // 玩家1剩余未放置子数
        int p2_InHand = 12,     // 玩家2剩余未放置子数
        int num_NeedRemove = 0  // 尚待去除的子数
    );

    // 获取棋局状态和棋盘数据
    void getData(struct Rule &rule, int &step, int &flags, const char *&boardsource, int &p1_InHand, int &p2_InHand, int &num_NeedRemove);
    // 获取当前规则
    const struct Rule *getRule() const { return &rule; }
    // 获取棋盘数据
    const char *getBoard() const { return data.board; }
    // 获取棋子位置(c, p)
    bool getPieceCP(const Players &player, const int &number, int &c, int &p);
    // 获取当前棋子
    bool getCurrentPiece(Players &player, int &number);
    // 获取当前棋子位置点
    int getCurrentPos() const { return currentPos; }
    // 获取当前步数
    int getStep() const { return data.step; }
    // 获取局面阶段标识
    enum Phases getPhase() const { return data.phase; }
    // 获取轮流状态标识
    enum Players whosTurn() const { return data.turn; }
    // 获取动作状态标识
    enum Actions getAction() const { return data.action; }
    // 判断胜负
    enum Players whoWin() const { return winner; }
    // 玩家1和玩家2的用时
    void getPlayer_TimeMS(int &p1_ms, int &p2_ms);
    // 获取棋局的字符提示
    const string getTip() const { return tip; }
    // 获取位置点棋子的归属人
    enum Players getWhosPiece(int c, int p);
    // 获取当前招法
    const char *getCmdLine() const { return cmdline; }
    // 获得棋谱
    const list<string> * getCmdList() const { return &cmdlist; }
    // 获取开局时间
    timeb getStartTimeb() const { return startTimeb; }
    // 重新设置开局时间
    void setStartTimeb(timeb stimeb) { startTimeb = stimeb; }

    // 玩家1剩余未放置子数
    int getPlayer1_InHand() const { return data.player1_InHand; }
    // 玩家2剩余未放置子数
    int getPlayer2_InHand() const { return data.player2_InHand; }
    // 玩家1盘面剩余子数
    int getPlayer1_Remain() const { return data.player1_Remain; }
    // 玩家1盘面剩余子数
    int getPlayer2_Remain() const { return data.player2_Remain; }
    // 尚待去除的子数
    int getNum_NeedRemove() const { return data.num_NeedRemove; }

    // 游戏重置
    bool reset();
    // 游戏开始
    bool start();

    // 选子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool choose(int c, int p);
    // 落子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool place(int c, int p, long time_p = -1);
    // 去子，在第c圈第p个位置，为迎合日常，c和p下标都从1开始
    bool capture(int c, int p, long time_p = -1);
    // 认输
	bool giveup(Players loser);
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
    int isInMills(int pos);
    // 判断玩家的所有棋子是否都处于“三连”状态
    bool isAllInMills(char ch);
    bool isAllInMills(enum Players);
    // 判断玩家的棋子是否被围
    bool isSurrounded(int pos);
    // 判断玩家的棋子是否全部被围
    bool isAllSurrounded(char ch);
    bool isAllSurrounded(enum Players);
    // 三连加入列表
    int addMills(int pos);
    // 将棋盘下标形式转化为第c圈，第p位，c和p下标都从1开始
    bool pos2cp(const int pos, int &c, int &p);
    // 将第c圈，第p位转化为棋盘下标形式，c和p下标都从1开始
    int cp2pos(int c, int p);
    // 更新时间和状态，用内联函数以提高效率
    inline long update(long time_p = -1);
    // 是否分出胜负
    bool win();
    // 清除所有禁点
    void cleanForbidden();
    // 改变轮流
    enum NineChess::Players changeTurn();
    // 设置提示
    void setTip();

    // 下面几个函数没有算法无关判断和无关操作，节约算法时间
    bool command(int16_t move);
    bool choose(int pos);
    bool place(int pos);
    bool capture(int pos);

private:
    // 当前使用的规则
    struct Rule rule;
    // 棋局数据
    struct ChessData data;
    // 棋局数据中的棋盘数据，单独提出来
    char *board;
    // 选中的棋子在board中的位置
    char currentPos;
    // 胜负标识
    enum Players winner;

    // 游戏起始时间
    timeb startTimeb;
    // 当前游戏时间
    timeb currentTimeb;
    // 玩家1用时（毫秒）
    long player1_MS;
    // 玩家2用时（毫秒）
    long player2_MS;

    /* 当前招法，AI会用到，如下表示
    0x   00    00
        pos1  pos2
    开局落子：0x00??，??为棋盘上的位置
    移子：0x__??，__为移动前的位置，??为移动后的位置
    去子：0xFF??，??取位置补码，即为负数
    */
    int16_t move_;

    // 招法命令行用于棋谱的显示和解析
    // 当前招法的命令行指令，即一招棋谱
    char cmdline[32];

    // 棋谱
    list <string> cmdlist;

    // 当前棋局的字符提示
    string tip;
};

#endif
