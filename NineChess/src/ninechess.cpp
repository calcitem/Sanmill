/****************************************************************************
** by liuweilhy, 2013.01.14
** Mail: liuweilhy@163.com
** This file is part of the NineChess game.
****************************************************************************/
#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

#include "ninechess.h"

// 对静态常量数组的定义要放在类外，不要放在头文件
// 预定义的4套规则
const struct NineChess::Rule NineChess::RULES[RULENUM] = {
{
    "成三棋",   // 成三棋
    // 规则说明
    "1. 双方各9颗子，开局依次摆子；\n"
    "2. 凡出现三子相连，就提掉对手一子；\n"
    "3. 不能提对手的“三连”子，除非无子可提；\n"
    "4. 同时出现两个“三连”只能提一子；\n"
    "5. 摆完后依次走子，每次只能往相邻位置走一步；\n"
    "6. 把对手棋子提到少于3颗时胜利；\n"
    "7. 走棋阶段不能行动（被“闷”）算负。",
    9,          // 双方各9子
    3,          // 赛点子数为3
    false,      // 没有斜线
    false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
    false,      // 先摆棋者先行棋
    true,       // 可以重复成三
    false,      // 多个“三连”只能提一子
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    true,       // 走棋阶段不能行动（被“闷”）算负
    false,      // 剩三子时不可以飞棋
    0,          // 不计步数
    0           // 不计时
},
{
    "打三棋(12连棋)",           // 打三棋
    // 规则说明
    "1. 双方各12颗子，棋盘有斜线；\n"
    "2. 摆棋阶段被提子的位置不能再摆子，直到走棋阶段；\n"
    "3. 摆棋阶段，摆满棋盘算先手负；\n"
    "4. 走棋阶段，后摆棋的一方先走；\n"
    "5. 一步出现几个“三连”就可以提几个子；\n"
    "6. 其它规则与成三棋基本相同。",
    12,          // 双方各12子
    3,          // 赛点子数为3
    true,       // 有斜线
    true,       // 有禁点，摆棋阶段被提子的点不能再摆子
    true,       // 后摆棋者先行棋
    true,       // 可以重复成三
    true,       // 出现几个“三连”就可以提几个子
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    true,       // 走棋阶段不能行动（被“闷”）算负
    false,      // 剩三子时不可以飞棋
    0,          // 不计步数
    0           // 不计时
},
{
    "九连棋",   // 九连棋
    // 规则说明
    "1. 规则与成三棋基本相同，只是它的棋子有序号，\n"
    "2. 相同序号、位置的“三连”不能重复提子；\n"
    "3. 走棋阶段不能行动（被“闷”），则由对手继续走棋；\n"
    "4. 一步出现几个“三连”就可以提几个子。",
    9,          // 双方各9子
    3,          // 赛点子数为3
    false,      // 没有斜线
    false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
    false,      // 先摆棋者先行棋
    false,      // 不可以重复成三
    true,       // 出现几个“三连”就可以提几个子
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    false,      // 走棋阶段不能行动（被“闷”），则由对手继续走棋
    false,      // 剩三子时不可以飞棋
    0,          // 不计步数
    0           // 不计时
},
{
    "莫里斯九子棋",      // 莫里斯九子棋
    // 规则说明
    "规则与成三棋基本相同，只是在走子阶段，当一方仅剩3子时，他可以飞子到任意空位。",
    9,          // 双方各9子
    3,          // 赛点子数为3
    false,      // 没有斜线
    false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
    false,      // 先摆棋者先行棋
    true,       // 可以重复成三
    false,      // 多个“三连”只能提一子
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    true,       // 走棋阶段不能行动（被“闷”）算负
    true,       // 剩三子时可以飞棋
    0,          // 不计步数
    0           // 不计时
}
};

const char NineChess::inBoard[(RING + 2)*SEAT] = {
        '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00'
};

char NineChess::moveTable[(RING + 2)*SEAT][4] = { 0 };
char NineChess::millTable[(RING + 2)*SEAT][3][2] = { 0 };

NineChess::NineChess()
{
    // 默认选择第0号规则，即“成三棋”
    setData(&RULES[0]);
}

NineChess::~NineChess()
{
}

bool NineChess::setData(const struct Rule *rule, int s, int t, int step, int flags, const char *boardsource,
    int p1_InHand, int p2_InHand, int num_NeedRemove)
{
    // 有效性判断
    if (s < 0 || t < 0 || step < 0 || p1_InHand < 0 || p2_InHand < 0 || num_NeedRemove < 0)
        return false;

    // 根据规则
    this->rule = *rule;
    this->rule.maxSteps = s;
    this->rule.maxTime = t;
    // 设置步数
    this->step = step;

    // 设置状态

    // 局面阶段标识
    if (flags & GAME_NOTSTARTED)
        phase = GAME_NOTSTARTED;
    else if (flags & GAME_OPENING)
        phase = GAME_OPENING;
    else if (flags & GAME_MID)
        phase = GAME_MID;
    else if (flags & GAME_OVER)
        phase = GAME_OVER;
    else
        return false;
    // 轮流状态标识
    if (flags & PLAYER1)
        turn = PLAYER1;
    else if (flags & PLAYER2)
        turn = PLAYER2;
    else
        return false;
    // 动作状态标识
    if (flags & ACTION_CHOOSE)
        action = ACTION_CHOOSE;
    else if (flags & ACTION_PLACE)
        action = ACTION_PLACE;
    else if (flags & ACTION_REMOVE)
        action = ACTION_REMOVE;
    else
        return false;
    // 胜负标识
    winner = NOBODY;
    // 当前棋局（3×8）
    if (boardsource == NULL)
        memset(this->board, 0, sizeof(this->board));
    else
        memcpy(this->board, boardsource, sizeof(this->board));
    // 生成招法表
    for (int i = 1; i <= RING; i++)
    {
        for (int j = 0; j < SEAT; j++)
        {
            // 顺时针走一步的位置
            moveTable[i*SEAT + j][0] = i * SEAT + (j + 1) % SEAT;
            // 逆时针走一步的位置
            moveTable[i*SEAT + j][1] = i * SEAT + (j + SEAT - 1) % SEAT;
            // 如果是0、2、4、6位（偶数位）或是有斜线
            if (!(j & 1) || this->rule.hasObliqueLine) {
                if (i > 1) {
                    // 向内走一步的位置
                    moveTable[i*SEAT + j][2] = (i - 1)*SEAT + j;
                }
                if (i < RING) {
                    // 向外走一步的位置
                    moveTable[i*SEAT + j][3] = (i + 1)*SEAT + j;
                }
            }
            // 对于无斜线情况下的1、3、5、7位（奇数位），则都设为棋盘外点（默认'\x00'）
            //else {
            //    // 向内走一步的位置设为随便棋盘外一点
            //    moveTable[i*SEAT+j][2] = '\x00';
            //    // 向外走一步的位置设为随便棋盘外一点
            //    moveTable[i*SEAT+j][3] = '\x00';
            //}
        }
    }
    // 生成成三表
    for (int j = 0; j < SEAT; j++)
    {
        // 内外方向的“成三”
        // 如果是0、2、4、6位（偶数位）或是有斜线
        if (!(j & 1) || this->rule.hasObliqueLine) {
            millTable[1 * SEAT + j][0][0] = 2 * SEAT + j;
            millTable[1 * SEAT + j][0][1] = 3 * SEAT + j;
            millTable[2 * SEAT + j][0][0] = 1 * SEAT + j;
            millTable[2 * SEAT + j][0][1] = 3 * SEAT + j;
            millTable[3 * SEAT + j][0][0] = 1 * SEAT + j;
            millTable[3 * SEAT + j][0][1] = 2 * SEAT + j;
        }
        // 对于无斜线情况下的1、3、5、7位（奇数位）
        else {
            // 置空该组“成三”
            millTable[1 * SEAT + j][0][0] = 0;
            millTable[1 * SEAT + j][0][1] = 0;
            millTable[2 * SEAT + j][0][0] = 0;
            millTable[2 * SEAT + j][0][1] = 0;
            millTable[3 * SEAT + j][0][0] = 0;
            millTable[3 * SEAT + j][0][1] = 0;
        }
        // 当前圈上的“成三”
        // 如果是0、2、4、6位
        if (!(j & 1)) {
            millTable[1 * SEAT + j][1][0] = 1 * SEAT + (j + 1) % SEAT;
            millTable[1 * SEAT + j][1][1] = 1 * SEAT + (j + SEAT - 1) % SEAT;
            millTable[2 * SEAT + j][1][0] = 2 * SEAT + (j + 1) % SEAT;
            millTable[2 * SEAT + j][1][1] = 2 * SEAT + (j + SEAT - 1) % SEAT;
            millTable[3 * SEAT + j][1][0] = 3 * SEAT + (j + 1) % SEAT;
            millTable[3 * SEAT + j][1][1] = 3 * SEAT + (j + SEAT - 1) % SEAT;
            // 置空另一组“成三”
            millTable[1 * SEAT + j][2][0] = 0;
            millTable[1 * SEAT + j][2][1] = 0;
            millTable[2 * SEAT + j][2][0] = 0;
            millTable[2 * SEAT + j][2][1] = 0;
            millTable[3 * SEAT + j][2][0] = 0;
            millTable[3 * SEAT + j][2][1] = 0;
        }
        // 对于1、3、5、7位（奇数位）
        else {
            // 当前圈上逆时针的“成三”
            millTable[1 * SEAT + j][1][0] = 1 * SEAT + (j + SEAT - 2) % SEAT;
            millTable[1 * SEAT + j][1][1] = 1 * SEAT + (j + SEAT - 1) % SEAT;
            millTable[2 * SEAT + j][1][0] = 2 * SEAT + (j + SEAT - 2) % SEAT;
            millTable[2 * SEAT + j][1][1] = 2 * SEAT + (j + SEAT - 1) % SEAT;
            millTable[3 * SEAT + j][1][0] = 3 * SEAT + (j + SEAT - 2) % SEAT;
            millTable[3 * SEAT + j][1][1] = 3 * SEAT + (j + SEAT - 1) % SEAT;
            // 当前圈上顺时针的“成三”
            millTable[1 * SEAT + j][2][0] = 1 * SEAT + (j + 1) % SEAT;
            millTable[1 * SEAT + j][2][1] = 1 * SEAT + (j + 2) % SEAT;
            millTable[2 * SEAT + j][2][0] = 2 * SEAT + (j + 1) % SEAT;
            millTable[2 * SEAT + j][2][1] = 2 * SEAT + (j + 2) % SEAT;
            millTable[3 * SEAT + j][2][0] = 3 * SEAT + (j + 1) % SEAT;
            millTable[3 * SEAT + j][2][1] = 3 * SEAT + (j + 2) % SEAT;
        }
    }

    // 计算盘面子数
    player1_Remain = player2_Remain = 0;
    for (int i = 1; i < RING + 2; i++)
    {
        for (int j = 0; j < SEAT; j++)
        {
            if (board[i*SEAT + j] & '\x10')
                player1_Remain++;
            else if (board[i*SEAT + j] & '\x20') {
                player2_Remain++;
            }
        }
    }
    // 设置玩家盘面剩余子数和未放置子数
    if (player1_Remain > rule->numOfChess || player2_Remain > rule->numOfChess)
        return false;
    if (p1_InHand < 0 || p2_InHand < 0)
        return false;
    player1_InHand = rule->numOfChess - player1_Remain;
    player2_InHand = rule->numOfChess - player2_Remain;
    player1_InHand = p1_InHand < player1_InHand ? p1_InHand : player1_InHand;
    player2_InHand = p2_InHand < player2_InHand ? p2_InHand : player2_InHand;

    // 设置去子状态时的剩余尚待去除子数
    if (flags & ACTION_REMOVE) {
        if (num_NeedRemove >= 0 && num_NeedRemove < 3)
            this->num_NeedRemove = num_NeedRemove;
    }
    else
        this->num_NeedRemove = 0;

    // 清空成三记录
    millList.clear();

    // 不选中棋子
    currentPos = 0;

    // 用时置零
    player1_MS = player2_MS = 0;

    // 提示
    setTip();

    // 计棋谱
    cmdlist.clear();
    int i;
    for (i = 0; i < RULENUM; i++) {
        if (strcmp(this->rule.name, RULES[i].name) == 0)
            break;
    }
    if (sprintf(cmdline, "r%1u s%03u t%02u", i + 1, s, t) > 0) {
        cmdlist.push_back(string(cmdline));
        return true;
    }
    else {
        cmdline[0] = '\0';
        return false;
    }

    return true;
}

void NineChess::getData(struct Rule &rule, int &step, int &chess, const char *&board,
    int &p1_InHand, int &p2_InHand, int &num_NeedRemove)
{
    rule = this->rule;
    step = this->step;
    chess = phase | turn | action | winner;
    board = this->board;
    p1_InHand = player1_InHand;
    p2_InHand = player2_InHand;
    num_NeedRemove = this->num_NeedRemove;
}

const char * NineChess::getBoard()
{
    return board;
}

bool NineChess::reset()
{
    if (phase == GAME_NOTSTARTED && player1_MS == player2_MS == 0)
        return true;

    // 步数归零
    step = 0;

    // 局面阶段标识
    phase = GAME_NOTSTARTED;

    // 轮流状态标识
    turn = PLAYER1;

    // 动作状态标识
    action = ACTION_PLACE;

    // 胜负标识
    winner = NOBODY;

    // 当前棋局（3×8）
    memset(board, 0, sizeof(board));

    // 盘面子数归零
    player1_Remain = player2_Remain = 0;

    // 设置玩家盘面剩余子数和未放置子数
    player1_InHand = player2_InHand = rule.numOfChess;

    // 设置去子状态时的剩余尚待去除子数
    num_NeedRemove = 0;

    // 清空成三记录
    millList.clear();

    // 不选中棋子
    currentPos = 0;

    // 用时置零
    player1_MS = player2_MS = 0;

    // 提示
    setTip();

    // 计棋谱
    cmdlist.clear();
    int i;
    for (i = 0; i < RULENUM; i++) {
        if (strcmp(this->rule.name, RULES[i].name) == 0)
            break;
    }
    if (sprintf(cmdline, "r%1u s%03u t%02u", i + 1, rule.maxSteps, rule.maxTime) > 0) {
        cmdlist.push_back(string(cmdline));
        return true;
    }
    else {
        cmdline[0] = '\0';
        return false;
    }

    return true;
}

bool NineChess::start()
{
    // 如果游戏已经开始，则返回false
    if (phase == GAME_OPENING || phase == GAME_MID)
        return false;

    // 如果游戏结束，则重置游戏，进入未开始状态
    if (phase == GAME_OVER)
        reset();

    // 如果游戏处于未开始状态
    if (phase == GAME_NOTSTARTED) {
        phase = GAME_OPENING;
        // 启动计时器
        ftime(&startTimeb);
    }

    // 其它情况
    return false;
}

int NineChess::cp2pos(int c, int p)
{
    if (c < 1 || c > RING || p < 1 || p > SEAT)
        return 0;
    return c * SEAT + p - 1;
}

bool NineChess::place(int c, int p, long time_p /* = -1*/)
{
    // 如果局面为“结局”，返回false
    if (phase == GAME_OVER)
        return false;
    // 如果局面为“未开局”，则开具
    if (phase == GAME_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (action != ACTION_PLACE)
        return false;
    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    int pos = cp2pos(c, p);
    if (!inBoard[pos] || board[pos])
        return false;
    // 时间的临时变量
    long player_ms = -1;

    // 对于开局落子
    char piece = '\x00';
    int n = 0;
    if (phase == GAME_OPENING) {
        // 先手下
        if (turn == PLAYER1)
        {
            piece = '\x11' + rule.numOfChess - player1_InHand;
            board[pos] = piece;
            player1_InHand--;
            player1_Remain++;
        }
        // 后手下
        else
        {
            piece = '\x21' + rule.numOfChess - player2_InHand;
            board[pos] = piece;
            player2_InHand--;
            player2_Remain++;
        }
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u) %02u:%02u.%03u", c, p, player_ms / 60000, player_ms / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        currentPos = pos;
        step++;
        // 如果决出胜负
        if (win()) {
            setTip();
            return true;
        }

        n = addMills(currentPos);
        // 开局阶段未成三
        if (n == 0) {
            // 如果双方都无未放置的棋子
            if (player1_InHand == 0 && player2_InHand == 0) {
                // 进入中局阶段
                phase = GAME_MID;
                // 进入选子状态
                action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (rule.isDefensiveMoveFirst) {
                    turn = PLAYER2;
                }
                else {
                    turn = PLAYER1;
                }
                // 再决胜负
                if (win()) {
                    setTip();
                    return true;
                }
            }
            // 如果双方还有子
            else {
                // 设置轮到谁走
                changeTurn();
            }
        }
        // 如果成三
        else {
            // 设置去子数目
            num_NeedRemove = rule.removeMore ? n : 1;
            // 进入去子状态
            action = ACTION_REMOVE;
        }
        setTip();
        return true;
    }

    // 对于中局落子
    else if (phase == GAME_MID) {
        // 如果落子不合法
        if ((turn == PLAYER1 && (player1_Remain > rule.numAtLest || !rule.canFly)) ||
            (turn == PLAYER2 && (player2_Remain > rule.numAtLest || !rule.canFly))) {
            int i;
            for (i = 0; i < 4; i++) {
                if (pos == moveTable[currentPos][i])
                    break;
            }
            // 不在招法表中
            if (i == 4)
                return false;
        }
        // 移子
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u.%03u", currentPos / SEAT, currentPos % SEAT + 1,
            c, p, player_ms / 60000, player_ms / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        board[pos] = board[currentPos];
        board[currentPos] = '\x00';
        currentPos = pos;
        step++;
        n = addMills(currentPos);

        // 中局阶段未成三
        if (n == 0) {
            // 进入选子状态
            action = ACTION_CHOOSE;
            // 设置轮到谁走
            changeTurn();
            // 如果决出胜负
            if (win()) {
                setTip();
                return true;
            }
        }
        // 中局阶段成三
        else {
            // 设置去子数目
            num_NeedRemove = rule.removeMore ? n : 1;
            // 进入去子状态
            action = ACTION_REMOVE;
            setTip();
        }
        setTip();
        return true;
    }

    return false;
}

bool NineChess::remove(int c, int p, long time_p /* = -1*/)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (phase == GAME_NOTSTARTED || phase == GAME_OVER)
        return false;
    // 如非“去子”状态，返回false
    if (action != ACTION_REMOVE)
        return false;
    // 如果去子完成，返回false
    if (num_NeedRemove <= 0)
        return false;
    // 时间的临时变量
    long player_ms = -1;
    int pos = cp2pos(c, p);
    // 对手
    enum Player opponent = PLAYER2;
    if (turn == PLAYER2)
        opponent = PLAYER1;
    // 判断去子不是对手棋
    if (getWhosPiece(c, p) != opponent)
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (isInMills(pos) && !isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (rule.hasForbidden && phase == GAME_OPENING)
        board[pos] = '\x0f';
    else // 去子
        board[pos] = '\x00';
    if (turn == PLAYER1)
        player2_Remain--;
    else if (turn == PLAYER2)
        player1_Remain--;
    player_ms = update(time_p);
    sprintf(cmdline, "-(%1u,%1u)  %02u:%02u.%03u", c, p, player_ms / 60000, player_ms / 1000, player_ms % 1000);
    cmdlist.push_back(string(cmdline));
    currentPos = 0;
    num_NeedRemove--;
    step++;
    // 去子完成

    // 如果决出胜负
    if (win()) {
        setTip();
        return true;
    }
    // 还有其余的子要去吗
    if (num_NeedRemove > 0) {
        // 继续去子
        return true;
    }
    // 所有去子都完成了
    else {
        // 开局阶段
        if (phase == GAME_OPENING) {
            // 如果双方都无未放置的棋子
            if (player1_InHand == 0 && player2_InHand == 0) {
                // 进入中局阶段
                phase = GAME_MID;
                // 进入选子状态
                action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (rule.isDefensiveMoveFirst) {
                    turn = PLAYER2;
                }
                else {
                    turn = PLAYER1;
                }
                // 再决胜负
                if (win()) {
                    setTip();
                    return true;
                }
            }
            // 如果双方还有子
            else {
                // 进入落子状态
                action = ACTION_PLACE;
                // 设置轮到谁走
                changeTurn();
                // 如果决出胜负
                if (win()) {
                    setTip();
                    return true;
                }
            }
        }
        // 中局阶段
        else {
            // 进入选子状态
            action = ACTION_CHOOSE;
            // 设置轮到谁走
            changeTurn();
            // 如果决出胜负
            if (win()) {
                setTip();
                return true;
            }
        }
    }
    setTip();
    return true;
}

bool NineChess::choose(int c, int p)
{
    // 如果局面不是"中局”，返回false
    if (phase != GAME_MID)
        return false;
    // 如非“选子”或“落子”状态，返回false
    if (action != ACTION_CHOOSE && action != ACTION_PLACE)
        return false;
    int pos = cp2pos(c, p);
    // 根据先后手，判断可选子
    char t;
    if (turn == PLAYER1)
        t = '\x10';
    else if (turn == PLAYER2)
        t = '\x20';
    // 判断选子是否可选
    if (board[pos] & t) {
        // 判断pos处的棋子是否被“闷”
        if (isSurrounded(pos)) {
            return false;
        }
        // 选子
        currentPos = pos;
        // 选子完成，进入落子状态
        action = ACTION_PLACE;
        return true;
    }
    return false;
}

// 打算用个C++的命令行解析库的，简单的没必要，但中文编码有极小概率出问题
bool NineChess::command(const char *cmd)
{
    int r, s, t;
    int c1, p1, c2, p2;
    int args = 0;
    int mm = 0, ss = 0, mss = 0;
    long tm = -1;

    // 设置规则
    if (sscanf(cmd, "r%1u s%3u t%2u", &r, &s, &t) == 3) {
        if (r <= 0 || r > RULENUM)
            return false;
        return setData(&NineChess::RULES[r - 1], s, t);
    }

    // 选子移动
    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
    if (args >= 4) {
        if (args == 7) {
            if (mm >= 0 && ss >= 0 && mss >= 0)
                tm = mm * 60000 + ss * 1000 + mss;
        }
        if (choose(c1, p1))
            return place(c2, p2, tm);
        else
            return false;
    }

    // 去子
    args = sscanf(cmd, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0 && mss >= 0)
                tm = mm * 60000 + ss * 1000 + mss;
        }
        return remove(c1, p1, tm);
    }

    // 落子
    args = sscanf(cmd, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0 && mss >= 0)
                tm = mm * 60000 + ss * 1000 + mss;
        }
        return place(c1, p1, tm);
    }

    return false;
}

inline long NineChess::update(long time_p /*= -1*/)
{
    long ret = -1;
    long *player_ms = (turn == PLAYER1 ? &player1_MS : &player2_MS);
    long playerNext_ms = (turn == PLAYER1 ? player2_MS : player1_MS);

    // 根据局面调整计时器
    switch (phase)
    {
    case NineChess::GAME_OPENING:
    case NineChess::GAME_MID:
        ftime(&currentTimeb);
        // 更新时间
        if (time_p >= *player_ms)
        {
            *player_ms = ret = time_p;
            long t = player1_MS + player2_MS;
            if (t % 1000 <= currentTimeb.millitm)
            {
                startTimeb.time = currentTimeb.time - (t / 1000);
                startTimeb.millitm = currentTimeb.millitm - (t % 1000);
            }
            else
            {
                startTimeb.time = currentTimeb.time - (t / 1000) - 1;
                startTimeb.millitm = currentTimeb.millitm + 1000 - (t % 1000);
            }
        }
        else
        {
            *player_ms = ret = (long)(currentTimeb.time - startTimeb.time) * 1000
                + (currentTimeb.millitm - startTimeb.millitm) - playerNext_ms;
        }
        // 有限时要求则判断胜负
        if (rule.maxTime > 0)
            win();
        return ret;
    case NineChess::GAME_NOTSTARTED:
        return ret;
    case NineChess::GAME_OVER:
        return ret;
    default:
        return ret;
    }
}

// 是否分出胜负
bool NineChess::win()
{
    if (phase == GAME_OVER)
        return true;
    if (phase == GAME_NOTSTARTED)
        return false;

    // 如果有时间限定
    if (rule.maxTime > 0) {
        // 这里不能update更新时间，否则会形成循环嵌套
        // 如果玩家1超时
        if (player1_MS > rule.maxTime * 60000) {
            player1_MS = rule.maxTime * 60000;
            winner = PLAYER2;
            phase = GAME_OVER;
            tip = "玩家1超时，恭喜玩家2获胜！";
            sprintf(cmdline, "Time over. Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
        // 如果玩家2超时
        else if (player2_MS > rule.maxTime * 60000) {
            player2_MS = rule.maxTime * 60000;
            winner = PLAYER1;
            phase = GAME_OVER;
            tip = "玩家2超时，恭喜玩家1获胜！";
            sprintf(cmdline, "Time over. Player1 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果有步数限定
    if (rule.maxSteps > 0) {
        if (step > rule.maxSteps) {
            winner = DRAW;
            phase = GAME_OVER;
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果玩家1子数小于赛点，则玩家2获胜
    if (player1_Remain + player1_InHand < rule.numAtLest) {
        winner = PLAYER2;
        phase = GAME_OVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
    // 如果玩家2子数小于赛点，则玩家1获胜
    else if (player2_Remain + player2_InHand < rule.numAtLest) {
        winner = PLAYER1;
        phase = GAME_OVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
    // 如果摆满了，根据规则判断胜负
    else if (player1_Remain + player2_Remain >= SEAT * RING) {
        if (rule.isFullLose) {
            winner = PLAYER2;
            phase = GAME_OVER;
            sprintf(cmdline, "Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
        else
        {
            winner = DRAW;
            phase = GAME_OVER;
            sprintf(cmdline, "Full. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }
    // 如果中局被“闷”
    else if (phase == GAME_MID && action == ACTION_CHOOSE && isAllSurrounded(turn)) {
        tip = (turn == PLAYER1) ? "玩家1无子可走，" : "玩家2无子可走，";
        // 规则要求被“闷”判负，则对手获胜
        if (rule.isNoWayLose) {
            winner = (turn == PLAYER1) ? PLAYER2 : PLAYER1;
            phase = GAME_OVER;
            sprintf(cmdline, "Surrounded. Player%1d win!", winner == PLAYER1 ? 1 : 2);
            cmdlist.push_back(string(cmdline));
            return true;
        }
        // 否则让棋，由对手走
        else
        {
            changeTurn();
            return false;
        }
    }

    return false;
}

int NineChess::isInMills(int pos)
{
    int n = 0;
    int pos1, pos2;
    char m = board[pos] & '\x30';
    for (int i = 0; i < 3; i++)
    {
        pos1 = millTable[pos][i][0];
        pos2 = millTable[pos][i][1];
        if (m & board[pos1] & board[pos2])
            n++;
    }
    return n;
}

int NineChess::addMills(int pos)
{
    //成三用一个64位整数了，规则如下
    //0x   00     00     00    00    00    00    00    00
    //   unused unused piece1 pos1 piece2 pos2 piece3 pos3
    //piece1、piece2、piece3按照序号从小到大顺序排放
    long long mill = 0;
    int n = 0;
    int p[3], min, temp;
    char m = board[pos] & '\x30';
    for (int i = 0; i < 3; i++)
    {
        p[0] = pos;
        p[1] = millTable[pos][i][0];
        p[2] = millTable[pos][i][1];
        // 如果成三
        if (m & board[p[1]] & board[p[2]]) {
            // 排序
            for (int j = 0; j < 2; j++) {
                min = j;
                for (int k = j + 1; k < 3; k++) {
                    if (p[min] > p[k])
                        min = k;
                }
                if (min != j) {
                    temp = p[min];
                    p[min] = p[j];
                    p[j] = temp;
                }
            }
            // 成三
            mill = (((long long)board[p[0]]) << 40)
                + (((long long)p[0]) << 32)
                + (((long long)board[p[1]]) << 24)
                + (((long long)p[1]) << 16)
                + (((long long)board[p[2]]) << 8)
                + (long long)p[2];

            // 如果允许相同三连反复去子
            if (rule.canRepeated) {
                n++;
            }
            // 如果不允许相同三连反复去子
            else
            {
                // 迭代器
                list<long long>::iterator itor;
                // 遍历
                for (itor = millList.begin(); itor != millList.end(); itor++)
                {
                    if (mill == *itor)
                        break;
                }
                // 如果没找到历史项
                if (itor == millList.end()) {
                    n++;
                    millList.push_back(mill);
                }
            }
        }
    }
    return n;
}

bool NineChess::isAllInMills(enum Player player)
{
    char ch = '\x00';
    if (player == PLAYER1)
        ch = '\x10';
    else if (player == PLAYER2)
        ch = '\x20';
    else
        return true;

    for (int i = 1; i <= RING; i++)
        for (int j = 0; j < SEAT; j++) {
            if (board[i*SEAT + j] & ch) {
                if (!isInMills(i*SEAT + j)) {
                    return false;
                }
            }
        }
    return true;
}

// 判断玩家的棋子是否被围
bool NineChess::isSurrounded(int pos)
{
    // 判断pos处的棋子是否被“闷”
    if ((turn == PLAYER1 && (player1_Remain > rule.numAtLest || !rule.canFly)) ||
        (turn == PLAYER2 && (player2_Remain > rule.numAtLest || !rule.canFly)))
    {
        int i, movePos;
        for (i = 0; i < 4; i++) {
            movePos = moveTable[pos][i];
            if (movePos && !board[movePos])
                break;
        }
        // 被围住
        if (i == 4)
            return true;
    }
    // 没被围住
    return false;
}

// 判断玩家的棋子是否全部被围
bool NineChess::isAllSurrounded(enum Player ply)
{
    char t = '\x30';
    if (ply == PLAYER1)
        t &= '\x10';
    else if (ply == PLAYER2)
        t &= '\x20';
    // 如果摆满
    if (player1_Remain + player2_Remain >= SEAT * RING)
        return true;
    // 判断是否可以飞子
    if ((turn == PLAYER1 && (player1_Remain <= rule.numAtLest && rule.canFly)) ||
        (turn == PLAYER2 && (player2_Remain <= rule.numAtLest && rule.canFly)))
    {
        return false;
    }
    // 查询整个棋盘
    for (int i = 1; i <= RING; i++)
    {
        for (int j = 0; j < SEAT; j++)
        {
            int movePos;
            if (t & board[i*SEAT + j]) {
                for (int k = 0; k < 4; k++) {
                    movePos = moveTable[i*SEAT + j][k];
                    if (movePos && !board[movePos])
                        return false;
                }
            }
        }
    }
    return true;
}

void NineChess::cleanForbidden()
{
    for (int i = 1; i <= RING; i++)
        for (int j = 0; j < SEAT; j++) {
            if (board[i*SEAT + j] == '\x0f')
                board[i*SEAT + j] = '\x00';
        }
}

enum NineChess::Player NineChess::changeTurn()
{
    // 设置轮到谁走
    return turn = (turn == PLAYER1) ? PLAYER2 : PLAYER1;
}

void NineChess::setTip()
{
    switch (phase)
    {
    case NineChess::GAME_NOTSTARTED:
        tip = "轮到玩家1落子，剩余" + std::to_string(player1_InHand) + "子";
        break;
    case NineChess::GAME_OPENING:
        if (action == ACTION_PLACE) {
            if (turn == PLAYER1) {
                tip = "轮到玩家1落子，剩余" + std::to_string(player1_InHand) + "子";
            }
            else if (turn == PLAYER2) {
                tip = "轮到玩家2落子，剩余" + std::to_string(player2_InHand) + "子";
            }
        }
        else if (action == ACTION_REMOVE) {
            if (turn == PLAYER1) {
                tip = "轮到玩家1去子，需去" + std::to_string(num_NeedRemove) + "子";
            }
            else if (turn == PLAYER2) {
                tip = "轮到玩家2去子，需去" + std::to_string(num_NeedRemove) + "子";
            }
        }
        break;
    case NineChess::GAME_MID:
        if (action == ACTION_PLACE || action == ACTION_CHOOSE) {
            if (turn == PLAYER1) {
                tip = "轮到玩家1选子移动";
            }
            else if (turn == PLAYER2) {
                tip = "轮到玩家2选子移动";
            }
        }
        else if (action == ACTION_REMOVE) {
            if (turn == PLAYER1) {
                tip = "轮到玩家1去子，需去" + std::to_string(num_NeedRemove) + "子";
            }
            else if (turn == PLAYER2) {
                tip = "轮到玩家2去子，需去" + std::to_string(num_NeedRemove) + "子";
            }
        }
        break;
    case NineChess::GAME_OVER:
        if (winner == DRAW)
            tip = "超出限定步数，双方平局";
        else if (winner == PLAYER1) {
            if (tip.find("无子可走") != tip.npos)
                tip += "恭喜玩家1获胜！";
            else
                tip = "恭喜玩家1获胜！";
        }
        else if (winner == PLAYER2) {
            if (tip.find("无子可走") != tip.npos)
                tip += "恭喜玩家2获胜！";
            else
                tip = "恭喜玩家2获胜！";
        }
        break;
    default:
        break;
    }
}

enum NineChess::Player NineChess::getWhosPiece(int c, int p)
{
    int pos = cp2pos(c, p);
    if (board[pos] & '\x10')
        return PLAYER1;
    else if (board[pos] & '\x20')
        return PLAYER2;
    return NOBODY;
}

int NineChess::getPieceNum(int c, int p)
{
    int pos = cp2pos(c, p);
    int n = 0x0f & board[pos];
    return n;
}

void NineChess::getPlayer_TimeMS(int &p1_ms, int &p2_ms)
{
    update();
    p1_ms = player1_MS;
    p2_ms = player2_MS;
}
