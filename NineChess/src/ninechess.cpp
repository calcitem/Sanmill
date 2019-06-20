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
    "5. 同时出现两个“三连”只能提一子；\n"
    "6. 其它规则与成三棋基本相同。",
    12,          // 双方各12子
    3,          // 赛点子数为3
    true,       // 有斜线
    true,       // 有禁点，摆棋阶段被提子的点不能再摆子
    true,       // 后摆棋者先行棋
    true,       // 可以重复成三
    false,      // 多个“三连”只能提一子
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

// 名义上是个数组，实际上相当于一个判断是否在棋盘上的函数
const char NineChess::inBoard[(RING + 2) * SEAT] = {
        '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff', '\xff',
        '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00'
};

// 招法表
int NineChess::moveTable[(RING + 2) * SEAT][4] = { 0 };

// 成三表
int NineChess::millTable[(RING + 2) * SEAT][3][2] = { 0 };

NineChess::NineChess()
{
    // 单独提出board，免得每次都写data.board;
    board_ = data.board;
    // 默认选择第0号规则，即“成三棋”
    setData(&RULES[0]);
}

NineChess::NineChess(const NineChess &chess)
{
    currentRule = chess.currentRule;
    data = chess.data;
    currentStep = chess.currentStep;
    board_ = data.board;
    currentPos = chess.currentPos;
    winner = chess.winner;
    startTimeb = chess.startTimeb;
    currentTimeb = chess.currentTimeb;
    player1_MS = chess.player1_MS;
    player2_MS = chess.player2_MS;
    move_ = chess.move_;
    memcpy(cmdline, chess.cmdline, sizeof(cmdline));
    cmdlist = chess.cmdlist;
    tip = chess.tip;
}

const NineChess &NineChess::operator=(const NineChess &chess)
{
    if (this == &chess)
        return *this;
    currentRule = chess.currentRule;
    data = chess.data;
    currentStep = chess.currentStep;
    board_ = data.board;
    currentPos = chess.currentPos;
    winner = chess.winner;
    startTimeb = chess.startTimeb;
    currentTimeb = chess.currentTimeb;
    player1_MS = chess.player1_MS;
    player2_MS = chess.player2_MS;
    move_ = chess.move_;
    memcpy(cmdline, chess.cmdline, sizeof(cmdline));
    cmdlist = chess.cmdlist;
    tip = chess.tip;
    return *this;
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
    this->currentRule = *rule;
    this->currentRule.maxSteps = s;
    this->currentRule.maxTime = t;

    // 设置棋局数据
    {
        // 设置步数
        this->currentStep = step;

        // 局面阶段标识
        if (flags & GAME_NOTSTARTED)
            data.phase = GAME_NOTSTARTED;
        else if (flags & GAME_OPENING)
            data.phase = GAME_OPENING;
        else if (flags & GAME_MID)
            data.phase = GAME_MID;
        else if (flags & GAME_OVER)
            data.phase = GAME_OVER;
        else
            return false;
        // 轮流状态标识
        if (flags & PLAYER1)
            data.turn = PLAYER1;
        else if (flags & PLAYER2)
            data.turn = PLAYER2;
        else
            return false;
        // 动作状态标识
        if (flags & ACTION_CHOOSE)
            data.action = ACTION_CHOOSE;
        else if (flags & ACTION_PLACE)
            data.action = ACTION_PLACE;
        else if (flags & ACTION_CAPTURE)
            data.action = ACTION_CAPTURE;
        else
            return false;

        // 当前棋局（3×8）
        if (boardsource == nullptr)
            memset(data.board, 0, sizeof(data.board));
        else
            memcpy(data.board, boardsource, sizeof(data.board));

        // 计算盘面子数
        data.player1_Remain = data.player2_Remain = 0;
        for (int i = 1; i < RING + 2; i++) {
            for (int j = 0; j < SEAT; j++) {
                if (data.board[i * SEAT + j] & '\x10')
                    data.player1_Remain++;
                else if (data.board[i * SEAT + j] & '\x20') {
                    data.player2_Remain++;
                }
            }
        }

        // 设置玩家盘面剩余子数和未放置子数
        if (data.player1_Remain > rule->numOfChess || data.player2_Remain > rule->numOfChess)
            return false;
        if (p1_InHand < 0 || p2_InHand < 0)
            return false;
        data.player1_InHand = rule->numOfChess - data.player1_Remain;
        data.player2_InHand = rule->numOfChess - data.player2_Remain;
        data.player1_InHand = p1_InHand < data.player1_InHand ? p1_InHand : data.player1_InHand;
        data.player2_InHand = p2_InHand < data.player2_InHand ? p2_InHand : data.player2_InHand;

        // 设置去子状态时的剩余尚待去除子数
        if (flags & ACTION_CAPTURE) {
            if (num_NeedRemove >= 0 && num_NeedRemove < 3)
                data.num_NeedRemove = num_NeedRemove;
        } else
            data.num_NeedRemove = 0;

        // 清空成三记录
        data.millList.clear();
    }

    // 胜负标识
    winner = NOBODY;

    // 生成招法表
    for (int i = 1; i <= RING; i++) {
        for (int j = 0; j < SEAT; j++) {
            // 顺时针走一步的位置
            moveTable[i * SEAT + j][0] = i * SEAT + (j + 1) % SEAT;
            // 逆时针走一步的位置
            moveTable[i * SEAT + j][1] = i * SEAT + (j + SEAT - 1) % SEAT;
            // 如果是0、2、4、6位（偶数位）或是有斜线
            if (!(j & 1) || this->currentRule.hasObliqueLine) {
                if (i > 1) {
                    // 向内走一步的位置
                    moveTable[i * SEAT + j][2] = (i - 1) * SEAT + j;
                }
                if (i < RING) {
                    // 向外走一步的位置
                    moveTable[i * SEAT + j][3] = (i + 1) * SEAT + j;
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
    for (int j = 0; j < SEAT; j++) {
        // 内外方向的“成三”
        // 如果是0、2、4、6位（偶数位）或是有斜线
        if (!(j & 1) || this->currentRule.hasObliqueLine) {
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
        if (strcmp(this->currentRule.name, RULES[i].name) == 0)
            break;
    }
    if (sprintf(cmdline, "r%1u s%03u t%02u", i + 1, s, t) > 0) {
        cmdlist.push_back(string(cmdline));
        return true;
    } else {
        cmdline[0] = '\0';
        return false;
    }

    //return true;
}

void NineChess::getData(struct Rule &rule, int &step, int &flags, int *&board, int &p1_InHand, int &p2_InHand, int &num_NeedRemove)
{
    rule = this->currentRule;
    step = this->currentStep;
    flags = data.phase | data.turn | data.action;
    this->board_ = board;
    p1_InHand = data.player1_InHand;
    p2_InHand = data.player2_InHand;
    num_NeedRemove = data.num_NeedRemove;
}

bool NineChess::reset()
{
    if (data.phase == GAME_NOTSTARTED && player1_MS == player2_MS == 0)
        return true;

    // 步数归零
    currentStep = 0;

    // 局面阶段标识
    data.phase = GAME_NOTSTARTED;
    // 轮流状态标识
    data.turn = PLAYER1;
    // 动作状态标识
    data.action = ACTION_PLACE;

    // 胜负标识
    winner = NOBODY;

    // 当前棋局（3×8）
    memset(board_, 0, sizeof(data.board));

    // 盘面子数归零
    data.player1_Remain = data.player2_Remain = 0;

    // 设置玩家盘面剩余子数和未放置子数
    data.player1_InHand = data.player2_InHand = currentRule.numOfChess;

    // 设置去子状态时的剩余尚待去除子数
    data.num_NeedRemove = 0;

    // 清空成三记录
    data.millList.clear();

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
        if (strcmp(this->currentRule.name, RULES[i].name) == 0)
            break;
    }
    if (sprintf(cmdline, "r%1u s%03u t%02u", i + 1, currentRule.maxSteps, currentRule.maxTime) > 0) {
        cmdlist.push_back(string(cmdline));
        return true;
    } else {
        cmdline[0] = '\0';
        return false;
    }

    return true;
}

bool NineChess::start()
{
    switch (data.phase) {
        // 如果游戏已经开始，则返回false
    case GAME_OPENING:
    case GAME_MID:
        return false;
        // 如果游戏结束，则重置游戏，进入未开始状态
    case GAME_OVER:
        reset();   // 这里不要break;
   // 如果游戏处于未开始状态
    case GAME_NOTSTARTED:
        // 启动计时器
        ftime(&startTimeb);
        // 进入开局状态
        data.phase = GAME_OPENING;
        return true;
    default:
        return false;
    }
}

bool NineChess::getPieceCP(const Players &player, const int &number, int &c, int &p)
{
    char piece;

    if (player == PLAYER1)
        piece = 0x10;
    else if (player == PLAYER2)
        piece = 0x20;
    else
        return false;

    if (number > 0 && number <= currentRule.numOfChess)
        piece &= number;
    else
        return false;

    for (int i = SEAT; i < SEAT * (RING + 1); i++) {
        if (board_[i] == piece) {
            pos2cp(i, c, p);
            return true;
        }
    }

    return false;
}

// 获取当前棋子
bool NineChess::getCurrentPiece(Players &player, int &number)
{
    if (!inBoard[currentPos])
        return false;

    if (board_[currentPos] & 0x10) {
        player = PLAYER1;
        number = board_[currentPos] - 0x10;
    } else if (board_[currentPos] & 0x20) {
        player = PLAYER2;
        number = board_[currentPos] - 0x20;
    } else
        return false;

    return true;
}

bool NineChess::pos2cp(const int pos, int &c, int &p)
{
    if (pos < SEAT || pos >= SEAT * (RING + 1))
        return false;
    c = pos / SEAT;
    p = pos % SEAT + 1;
    return true;
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
    if (data.phase == GAME_OVER)
        return false;
    // 如果局面为“未开局”，则开具
    if (data.phase == GAME_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (data.action != ACTION_PLACE)
        return false;
    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    int pos = cp2pos(c, p);
    if (!inBoard[pos] || board_[pos])
        return false;
    // 时间的临时变量
    long player_ms = -1;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;
    if (data.phase == GAME_OPENING) {
        // 先手下
        if (data.turn == PLAYER1) {
            piece = '\x11' + currentRule.numOfChess - data.player1_InHand;
            data.player1_InHand--;
            data.player1_Remain++;
        }
        // 后手下
        else {
            piece = '\x21' + currentRule.numOfChess - data.player2_InHand;
            data.player2_InHand--;
            data.player2_Remain++;
        }
        board_[pos] = piece;
        move_ = pos;
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u) %02u:%02u.%03u", c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        currentPos = pos;
        currentStep++;
        // 如果决出胜负
        if (win()) {
            setTip();
            return true;
        }

        n = addMills(currentPos);
        // 开局阶段未成三
        if (n == 0) {
            // 如果双方都无未放置的棋子
            if (data.player1_InHand == 0 && data.player2_InHand == 0) {
                // 进入中局阶段
                data.phase = GAME_MID;
                // 进入选子状态
                data.action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (currentRule.isDefensiveMoveFirst) {
                    data.turn = PLAYER2;
                } else {
                    data.turn = PLAYER1;
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
            data.num_NeedRemove = currentRule.removeMore ? n : 1;
            // 进入去子状态
            data.action = ACTION_CAPTURE;
        }
        setTip();
        return true;
    }

    // 对于中局落子
    else if (data.phase == GAME_MID) {
        // 如果落子不合法
        if ((data.turn == PLAYER1 && (data.player1_Remain > currentRule.numAtLest || !currentRule.canFly)) ||
            (data.turn == PLAYER2 && (data.player2_Remain > currentRule.numAtLest || !currentRule.canFly))) {
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
        move_ = (currentPos << 8) + pos;
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u.%03u", currentPos / SEAT, currentPos % SEAT + 1,
                c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        board_[pos] = board_[currentPos];
        board_[currentPos] = '\x00';
        currentPos = pos;
        currentStep++;
        n = addMills(currentPos);

        // 中局阶段未成三
        if (n == 0) {
            // 进入选子状态
            data.action = ACTION_CHOOSE;
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
            data.num_NeedRemove = currentRule.removeMore ? n : 1;
            // 进入去子状态
            data.action = ACTION_CAPTURE;
            setTip();
        }
        setTip();
        return true;
    }

    return false;
}

bool NineChess::capture(int c, int p, long time_p /* = -1*/)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (data.phase == GAME_NOTSTARTED || data.phase == GAME_OVER)
        return false;
    // 如非“去子”状态，返回false
    if (data.action != ACTION_CAPTURE)
        return false;
    // 如果去子完成，返回false
    if (data.num_NeedRemove <= 0)
        return false;
    // 时间的临时变量
    long player_ms = -1;
    int pos = cp2pos(c, p);
    // 对手
    char opponent = data.turn == PLAYER1 ? 0x20 : 0x10;
    // 判断去子是不是对手棋
    if (!(opponent & board_[pos]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (isInMills(pos) && !isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (currentRule.hasForbidden && data.phase == GAME_OPENING)
        board_[pos] = '\x0f';
    else // 去子
        board_[pos] = '\x00';
    if (data.turn == PLAYER1)
        data.player2_Remain--;
    else if (data.turn == PLAYER2)
        data.player1_Remain--;
    move_ = -pos;
    player_ms = update(time_p);
    sprintf(cmdline, "-(%1u,%1u)  %02u:%02u.%03u", c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
    cmdlist.push_back(string(cmdline));
    currentPos = 0;
    data.num_NeedRemove--;
    currentStep++;
    // 去子完成

    // 如果决出胜负
    if (win()) {
        setTip();
        return true;
    }
    // 还有其余的子要去吗
    if (data.num_NeedRemove > 0) {
        // 继续去子
        return true;
    }
    // 所有去子都完成了
    else {
        // 开局阶段
        if (data.phase == GAME_OPENING) {
            // 如果双方都无未放置的棋子
            if (data.player1_InHand == 0 && data.player2_InHand == 0) {
                // 进入中局阶段
                data.phase = GAME_MID;
                // 进入选子状态
                data.action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (currentRule.isDefensiveMoveFirst) {
                    data.turn = PLAYER2;
                } else {
                    data.turn = PLAYER1;
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
                data.action = ACTION_PLACE;
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
            data.action = ACTION_CHOOSE;
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
    if (data.phase != GAME_MID)
        return false;
    // 如非“选子”或“落子”状态，返回false
    if (data.action != ACTION_CHOOSE && data.action != ACTION_PLACE)
        return false;
    int pos = cp2pos(c, p);
    // 根据先后手，判断可选子
    char t = '\0';
    if (data.turn == PLAYER1)
        t = '\x10';
    else if (data.turn == PLAYER2)
        t = '\x20';
    // 判断选子是否可选
    if (board_[pos] & t) {
        // 判断pos处的棋子是否被“闷”
        if (isSurrounded(pos)) {
            return false;
        }
        // 选子
        currentPos = pos;
        // 选子完成，进入落子状态
        data.action = ACTION_PLACE;
        return true;
    }
    return false;
}

bool NineChess::place(int pos)
{
    // 如果局面为“结局”，返回false
    if (data.phase == GAME_OVER)
        return false;
    // 如果局面为“未开局”，则开具
    if (data.phase == GAME_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (data.action != ACTION_PLACE)
        return false;
    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!inBoard[pos] || board_[pos])
        return false;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;
    if (data.phase == GAME_OPENING) {
        // 先手下
        if (data.turn == PLAYER1) {
            piece = '\x11' + currentRule.numOfChess - data.player1_InHand;
            data.player1_InHand--;
            data.player1_Remain++;
        }
        // 后手下
        else {
            piece = '\x21' + currentRule.numOfChess - data.player2_InHand;
            data.player2_InHand--;
            data.player2_Remain++;
        }
        board_[pos] = piece;
        move_ = pos;
        currentPos = pos;
        //step++;
        // 如果决出胜负
        if (win()) {
            //setTip();
            return true;
        }

        n = addMills(currentPos);
        // 开局阶段未成三
        if (n == 0) {
            // 如果双方都无未放置的棋子
            if (data.player1_InHand == 0 && data.player2_InHand == 0) {
                // 进入中局阶段
                data.phase = GAME_MID;
                // 进入选子状态
                data.action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (currentRule.isDefensiveMoveFirst) {
                    data.turn = PLAYER2;
                } else {
                    data.turn = PLAYER1;
                }

                // 再决胜负
                if (win()) {
                    //setTip();
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
            data.num_NeedRemove = currentRule.removeMore ? n : 1;
            // 进入去子状态
            data.action = ACTION_CAPTURE;
        }
        setTip();
        return true;
    }

    // 对于中局落子
    else if (data.phase == GAME_MID) {
        // 如果落子不合法
        if ((data.turn == PLAYER1 && (data.player1_Remain > currentRule.numAtLest || !currentRule.canFly)) ||
            (data.turn == PLAYER2 && (data.player2_Remain > currentRule.numAtLest || !currentRule.canFly))) {
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
        move_ = (currentPos << 8) + pos;
        board_[pos] = board_[currentPos];
        board_[currentPos] = '\x00';
        currentPos = pos;
        //step++;
        n = addMills(currentPos);

        // 中局阶段未成三
        if (n == 0) {
            // 进入选子状态
            data.action = ACTION_CHOOSE;
            // 设置轮到谁走
            changeTurn();
            // 如果决出胜负
            if (win()) {
                //setTip();
                return true;
            }
        }
        // 中局阶段成三
        else {
            // 设置去子数目
            data.num_NeedRemove = currentRule.removeMore ? n : 1;
            // 进入去子状态
            data.action = ACTION_CAPTURE;
            //setTip();
        }
        //setTip();
        return true;
    }

    return false;
}

bool NineChess::capture(int pos)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (data.phase == GAME_NOTSTARTED || data.phase == GAME_OVER)
        return false;
    // 如非“去子”状态，返回false
    if (data.action != ACTION_CAPTURE)
        return false;
    // 如果去子完成，返回false
    if (data.num_NeedRemove <= 0)
        return false;
    // 对手
    char opponent = data.turn == PLAYER1 ? 0x20 : 0x10;
    // 判断去子是不是对手棋
    if (!(opponent & board_[pos]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (isInMills(pos) && !isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (currentRule.hasForbidden && data.phase == GAME_OPENING)
        board_[pos] = '\x0f';
    else // 去子
        board_[pos] = '\x00';
    if (data.turn == PLAYER1)
        data.player2_Remain--;
    else if (data.turn == PLAYER2)
        data.player1_Remain--;
    move_ = -pos;
    currentPos = 0;
    data.num_NeedRemove--;
    //step++;
    // 去子完成

    // 如果决出胜负
    if (win()) {
        //setTip();
        return true;
    }
    // 还有其余的子要去吗
    if (data.num_NeedRemove > 0) {
        // 继续去子
        return true;
    }
    // 所有去子都完成了
    else {
        // 开局阶段
        if (data.phase == GAME_OPENING) {
            // 如果双方都无未放置的棋子
            if (data.player1_InHand == 0 && data.player2_InHand == 0) {
                // 进入中局阶段
                data.phase = GAME_MID;
                // 进入选子状态
                data.action = ACTION_CHOOSE;
                // 清除禁点
                cleanForbidden();
                // 设置轮到谁走
                if (currentRule.isDefensiveMoveFirst) {
                    data.turn = PLAYER2;
                } else {
                    data.turn = PLAYER1;
                }
                // 再决胜负
                if (win()) {
                    //setTip();
                    return true;
                }
            }
            // 如果双方还有子
            else {
                // 进入落子状态
                data.action = ACTION_PLACE;
                // 设置轮到谁走
                changeTurn();
                // 如果决出胜负
                if (win()) {
                    //setTip();
                    return true;
                }
            }
        }
        // 中局阶段
        else {
            // 进入选子状态
            data.action = ACTION_CHOOSE;
            // 设置轮到谁走
            changeTurn();
            // 如果决出胜负
            if (win()) {
                //setTip();
                return true;
            }
        }
    }
    //setTip();
    return true;
}

bool NineChess::choose(int pos)
{
    // 如果局面不是"中局”，返回false
    if (data.phase != GAME_MID)
        return false;
    // 如非“选子”或“落子”状态，返回false
    if (data.action != ACTION_CHOOSE && data.action != ACTION_PLACE)
        return false;
    char t = data.turn == PLAYER1 ? 0x10 : 0x20;
    // 判断选子是否可选
    if (board_[pos] & t) {
        // 判断pos处的棋子是否被“闷”
        if (isSurrounded(pos)) {
            return false;
        }
        // 选子
        currentPos = pos;
        // 选子完成，进入落子状态
        data.action = ACTION_PLACE;
        return true;
    }
    return false;
}

// hash函数，对应可重复去子的规则
uint64_t NineChess::chessHash()
{
    /* hash各数据位详解（名为hash，但实际并无冲突，是算法用到的棋局数据的完全表示）
    57-64位：空白不用，全为0
    56位：轮流标识，0为先手，1为后手
    55位：动作标识，落子（选子移动）为0，1为去子
    7-54位（共48位）：从棋盘第一个位置点到最后一个位置点的棋子，每个点用2个二进制位表示，共24个位置点，即48位。
           0b00表示空白，0b01表示先手棋子，0b10表示后手棋子，0b11表示禁点
    5-6位（共2位）：待去子数，最大为3，用2个二进制位表示即可
    1-4位：player1的手棋数，不需要player2的（可计算出）
    */
    uint64_t hash = 0ull;
    for (int i = SEAT; i < (RING + 1) * SEAT; i++) {
        hash |= board_[i] & 0x30;
        hash <<= 2;
    }
    if (data.turn == PLAYER2)
        hash |= 1ull << 55;
    if (data.action == ACTION_CAPTURE)
        hash |= 1ull << 54;
    hash |= (uint64_t)data.num_NeedRemove << 4;
    hash |= data.player1_InHand;
    return hash;
}

bool NineChess::giveup(Players loser)
{
    if (data.phase == GAME_MID || data.phase == GAME_OPENING) {
        if (loser == PLAYER1) {
            data.phase = GAME_OVER;
            winner = PLAYER2;
            tip = "玩家1投子认负，恭喜玩家2获胜！";
            sprintf(cmdline, "Player1 give up!");
            cmdlist.push_back(string(cmdline));
            return true;
        } else if (loser == PLAYER2) {
            data.phase = GAME_OVER;
            winner = PLAYER1;
            tip = "玩家2投子认负，恭喜玩家1获胜！";
            sprintf(cmdline, "Player2 give up!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
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
        return capture(c1, p1, tm);
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

    // 认输
    args = sscanf(cmd, "Players%1u give up!", &t);
    if (args == 1) {
        if (t == 1) {
            return giveup(PLAYER1);
        } else if (t == 2) {
            return giveup(PLAYER2);
        }
    }

    return false;
}

bool NineChess::command(int move)
{
    if (move < 0) {
        return capture(-move);
    } else if (move & 0x1f00) {
        if (choose(move >> 8))
            return place(move & 0x00ff);
    } else {
        return place(move & 0x00ff);
    }
    return false;
}

inline long NineChess::update(long time_p /*= -1*/)
{
    long ret = -1;
    long *player_ms = (data.turn == PLAYER1 ? &player1_MS : &player2_MS);
    long playerNext_ms = (data.turn == PLAYER1 ? player2_MS : player1_MS);

    // 根据局面调整计时器
    switch (data.phase) {
    case NineChess::GAME_OPENING:
    case NineChess::GAME_MID:
        ftime(&currentTimeb);
        // 更新时间
        if (time_p >= *player_ms) {
            *player_ms = ret = time_p;
            long t = player1_MS + player2_MS;
            if (t % 1000 <= currentTimeb.millitm) {
                startTimeb.time = currentTimeb.time - (t / 1000);
                startTimeb.millitm = currentTimeb.millitm - (t % 1000);
            } else {
                startTimeb.time = currentTimeb.time - (t / 1000) - 1;
                startTimeb.millitm = currentTimeb.millitm + 1000 - (t % 1000);
            }
        } else {
            *player_ms = ret = (long)(currentTimeb.time - startTimeb.time) * 1000
                + (currentTimeb.millitm - startTimeb.millitm) - playerNext_ms;
        }
        // 有限时要求则判断胜负
        if (currentRule.maxTime > 0)
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
    if (data.phase == GAME_OVER)
        return true;
    if (data.phase == GAME_NOTSTARTED)
        return false;

    // 如果有时间限定
    if (currentRule.maxTime > 0) {
        // 这里不能update更新时间，否则会形成循环嵌套
        // 如果玩家1超时
        if (player1_MS > currentRule.maxTime * 60000) {
            player1_MS = currentRule.maxTime * 60000;
            winner = PLAYER2;
            data.phase = GAME_OVER;
            tip = "玩家1超时，恭喜玩家2获胜！";
            sprintf(cmdline, "Time over. Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
        // 如果玩家2超时
        else if (player2_MS > currentRule.maxTime * 60000) {
            player2_MS = currentRule.maxTime * 60000;
            winner = PLAYER1;
            data.phase = GAME_OVER;
            tip = "玩家2超时，恭喜玩家1获胜！";
            sprintf(cmdline, "Time over. Player1 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果有步数限定
    if (currentRule.maxSteps > 0) {
        if (currentStep > currentRule.maxSteps) {
            winner = DRAW;
            data.phase = GAME_OVER;
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果玩家1子数小于赛点，则玩家2获胜
    if (data.player1_Remain + data.player1_InHand < currentRule.numAtLest) {
        winner = PLAYER2;
        data.phase = GAME_OVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
    // 如果玩家2子数小于赛点，则玩家1获胜
    else if (data.player2_Remain + data.player2_InHand < currentRule.numAtLest) {
        winner = PLAYER1;
        data.phase = GAME_OVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
    // 如果摆满了，根据规则判断胜负
    else if (data.player1_Remain + data.player2_Remain >= SEAT * RING) {
        if (currentRule.isFullLose) {
            winner = PLAYER2;
            data.phase = GAME_OVER;
            sprintf(cmdline, "Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        } else {
            winner = DRAW;
            data.phase = GAME_OVER;
            sprintf(cmdline, "Full. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }
    // 如果中局被“闷”
    else if (data.phase == GAME_MID && data.action == ACTION_CHOOSE && isAllSurrounded(data.turn)) {
        // 规则要求被“闷”判负，则对手获胜
        if (currentRule.isNoWayLose) {
            if (data.turn == PLAYER1) {
                tip = "玩家1无子可走，恭喜玩家2获胜！";
                winner = PLAYER2;
                data.phase = GAME_OVER;
                sprintf(cmdline, "Player1 no way to go. Player2 win!");
                cmdlist.push_back(string(cmdline));
                return true;
            } else {
                tip = "玩家2无子可走，恭喜玩家1获胜！";
                winner = PLAYER1;
                data.phase = GAME_OVER;
                sprintf(cmdline, "Player2 no way to go. Player1 win!");
                cmdlist.push_back(string(cmdline));
                return true;
            }
        }
        // 否则让棋，由对手走
        else {
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
    char m = board_[pos] & '\x30';
    for (int i = 0; i < 3; i++) {
        pos1 = millTable[pos][i][0];
        pos2 = millTable[pos][i][1];
        if (m & board_[pos1] & board_[pos2])
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
    uint64_t mill = 0;
    int n = 0;
    int p[3], min, temp;
    char m = board_[pos] & '\x30';
    for (int i = 0; i < 3; i++) {
        p[0] = pos;
        p[1] = millTable[pos][i][0];
        p[2] = millTable[pos][i][1];
        // 如果成三
        if (m & board_[p[1]] & board_[p[2]]) {
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
            mill = (((uint64_t)board_[p[0]]) << 40)
                + (((uint64_t)p[0]) << 32)
                + (((uint64_t)board_[p[1]]) << 24)
                + (((uint64_t)p[1]) << 16)
                + (((uint64_t)board_[p[2]]) << 8)
                + (uint64_t)p[2];

            // 如果允许相同三连反复去子
            if (currentRule.canRepeated) {
                n++;
            }
            // 如果不允许相同三连反复去子
            else {
                // 迭代器
                list<uint64_t>::iterator itor;
                // 遍历
                for (itor = data.millList.begin(); itor != data.millList.end(); itor++) {
                    if (mill == *itor)
                        break;
                }
                // 如果没找到历史项
                if (itor == data.millList.end()) {
                    n++;
                    data.millList.push_back(mill);
                }
            }
        }
    }
    return n;
}

bool NineChess::isAllInMills(char ch)
{
    for (int i = SEAT; i < SEAT * (RING + 1); i++)
        if (board_[i] & ch) {
            if (!isInMills(i)) {
                return false;
            }
        }
    return true;
}

bool NineChess::isAllInMills(enum Players player)
{
    char ch = '\x00';
    if (player == PLAYER1)
        ch = '\x10';
    else if (player == PLAYER2)
        ch = '\x20';
    else
        return true;
    return isAllInMills(ch);
}

// 判断玩家的棋子是否被围
bool NineChess::isSurrounded(int pos)
{
    // 判断pos处的棋子是否被“闷”
    if ((data.turn == PLAYER1 && (data.player1_Remain > currentRule.numAtLest || !currentRule.canFly)) ||
        (data.turn == PLAYER2 && (data.player2_Remain > currentRule.numAtLest || !currentRule.canFly))) {
        int i, movePos;
        for (i = 0; i < 4; i++) {
            movePos = moveTable[pos][i];
            if (movePos && !board_[movePos])
                break;
        }
        // 被围住
        if (i == 4)
            return true;
    }
    // 没被围住
    return false;
}

bool NineChess::isAllSurrounded(char ch)
{
    // 如果摆满
    if (data.player1_Remain + data.player2_Remain >= SEAT * RING)
        return true;
    // 判断是否可以飞子
    if ((data.turn == PLAYER1 && (data.player1_Remain <= currentRule.numAtLest && currentRule.canFly)) ||
        (data.turn == PLAYER2 && (data.player2_Remain <= currentRule.numAtLest && currentRule.canFly))) {
        return false;
    }
    // 查询整个棋盘
    int movePos;
    for (int i = 1; i < SEAT * (RING + 1); i++) {
        if (ch & board_[i]) {
            for (int k = 0; k < 4; k++) {
                movePos = moveTable[i][k];
                if (movePos && !board_[movePos])
                    return false;
            }
        }
    }
    return true;
}

// 判断玩家的棋子是否全部被围
bool NineChess::isAllSurrounded(enum Players ply)
{
    char t = '\x30';
    if (ply == PLAYER1)
        t &= '\x10';
    else if (ply == PLAYER2)
        t &= '\x20';
    return isAllSurrounded(t);
}

void NineChess::cleanForbidden()
{
    for (int i = 1; i <= RING; i++)
        for (int j = 0; j < SEAT; j++) {
            if (board_[i * SEAT + j] == '\x0f')
                board_[i * SEAT + j] = '\x00';
        }
}

enum NineChess::Players NineChess::changeTurn()
{
    // 设置轮到谁走
    data.turn = (data.turn == PLAYER1) ? PLAYER2 : PLAYER1;
    return data.turn;
}

void NineChess::setTip()
{
    switch (data.phase) {
    case NineChess::GAME_NOTSTARTED:
        tip = "轮到玩家1落子，剩余" + std::to_string(data.player1_InHand) + "子";
        break;
    case NineChess::GAME_OPENING:
        if (data.action == ACTION_PLACE) {
            if (data.turn == PLAYER1) {
                tip = "轮到玩家1落子，剩余" + std::to_string(data.player1_InHand) + "子";
            } else if (data.turn == PLAYER2) {
                tip = "轮到玩家2落子，剩余" + std::to_string(data.player2_InHand) + "子";
            }
        } else if (data.action == ACTION_CAPTURE) {
            if (data.turn == PLAYER1) {
                tip = "轮到玩家1去子，需去" + std::to_string(data.num_NeedRemove) + "子";
            } else if (data.turn == PLAYER2) {
                tip = "轮到玩家2去子，需去" + std::to_string(data.num_NeedRemove) + "子";
            }
        }
        break;
    case NineChess::GAME_MID:
        if (data.action == ACTION_PLACE || data.action == ACTION_CHOOSE) {
            if (data.turn == PLAYER1) {
                tip = "轮到玩家1选子移动";
            } else if (data.turn == PLAYER2) {
                tip = "轮到玩家2选子移动";
            }
        } else if (data.action == ACTION_CAPTURE) {
            if (data.turn == PLAYER1) {
                tip = "轮到玩家1去子，需去" + std::to_string(data.num_NeedRemove) + "子";
            } else if (data.turn == PLAYER2) {
                tip = "轮到玩家2去子，需去" + std::to_string(data.num_NeedRemove) + "子";
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
        } else if (winner == PLAYER2) {
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

enum NineChess::Players NineChess::getWhosPiece(int c, int p)
{
    int pos = cp2pos(c, p);
    if (board_[pos] & '\x10')
        return PLAYER1;
    else if (board_[pos] & '\x20')
        return PLAYER2;
    return NOBODY;
}

void NineChess::getPlayer_TimeMS(int &p1_ms, int &p2_ms)
{
    update();
    p1_ms = player1_MS;
    p2_ms = player2_MS;
}

void NineChess::mirror(bool cmdChange /*= true*/)
{
    int ch;
    int i, j;

    for (i = 1; i <= RING; i++) {
        for (j = 1; j < SEAT / 2; j++) {
            ch = board_[i * SEAT + j];
            board_[i * SEAT + j] = board_[(i + 1) * SEAT - j];
            board_[(i + 1) * SEAT - j] = ch;
        }
    }

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / SEAT;
        j = (-move_) % SEAT;
        j = (SEAT - j) % SEAT;
        move_ = -(i * SEAT + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / SEAT;
        j = (int)llp1 % SEAT;
        j = (SEAT - j) % SEAT;
        llp1 = i * SEAT + j;

        i = (int)llp2 / SEAT;
        j = (int)llp2 % SEAT;
        j = (SEAT - j) % SEAT;
        llp2 = i * SEAT + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / SEAT;
        j = currentPos % SEAT;
        j = (SEAT - j) % SEAT;
        currentPos = i * SEAT + j;
    }

    if (currentRule.canRepeated) {
        for (auto mill = data.millList.begin(); mill != data.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / SEAT;
            j = (int)llp1 % SEAT;
            j = (SEAT - j) % SEAT;
            llp1 = i * SEAT + j;

            i = (int)llp2 / SEAT;
            j = (int)llp2 % SEAT;
            j = (SEAT - j) % SEAT;
            llp2 = i * SEAT + j;

            i = (int)llp3 / SEAT;
            j = (int)llp3 % SEAT;
            j = (SEAT - j) % SEAT;
            llp3 = i * SEAT + j;

            *mill &= 0xffffff00ff00ff00;
            *mill |= (llp1 << 32) | (llp2 << 16) | llp3;
        }
    }

    // 命令行解析
    if (cmdChange) {
        int c1, p1, c2, p2;
        int args = 0;
        int mm = 0, ss = 0, mss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
        if (args >= 4) {
            p1 = (SEAT - p1 + 1) % SEAT;
            p2 = (SEAT - p2 + 1) % SEAT;
            cmdline[3] = '1' + (char)p1;
            cmdline[10] = '1' + (char)p2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                p1 = (SEAT - p1 + 1) % SEAT;
                cmdline[4] = '1' + (char)p1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (SEAT - p1 + 1) % SEAT;
                    cmdline[3] = '1' + (char)p1;
                }
            }
        }

        for (auto itor = cmdlist.begin(); itor != cmdlist.end(); itor++) {
            args = sscanf((*itor).c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
            if (args >= 4) {
                p1 = (SEAT - p1 + 1) % SEAT;
                p2 = (SEAT - p2 + 1) % SEAT;
                (*itor)[3] = '1' + (char)p1;
                (*itor)[10] = '1' + (char)p2;
            } else {
                args = sscanf((*itor).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (SEAT - p1 + 1) % SEAT;
                    (*itor)[4] = '1' + (char)p1;
                } else {
                    args = sscanf((*itor).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        p1 = (SEAT - p1 + 1) % SEAT;
                        (*itor)[3] = '1' + (char)p1;
                    }
                }
            }
        }
    }
}

void NineChess::turn(bool cmdChange /*= true*/)
{
    int ch;
    int i, j;

    for (i = 0; i < SEAT; i++) {
        ch = board_[SEAT + i];
        board_[SEAT + i] = board_[SEAT * RING + i];
        board_[SEAT * RING + i] = ch;
    }

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / SEAT;
        j = (-move_) % SEAT;
        if (i == 1)
            i = RING;
        else if (i == RING)
            i = 1;
        move_ = -(i * SEAT + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / SEAT;
        j = (int)llp1 % SEAT;
        if (i == 1)
            i = RING;
        else if (i == RING)
            i = 1;
        llp1 = i * SEAT + j;
        i = (int)llp2 / SEAT;
        j = (int)llp2 % SEAT;
        if (i == 1)
            i = RING;
        else if (i == RING)
            i = 1;
        llp2 = i * SEAT + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / SEAT;
        j = currentPos % SEAT;
        if (i == 1)
            i = RING;
        else if (i == RING)
            i = 1;
        currentPos = i * SEAT + j;
    }

    if (currentRule.canRepeated) {
        for (auto mill = data.millList.begin(); mill != data.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / SEAT;
            j = (int)llp1 % SEAT;
            if (i == 1)
                i = RING;
            else if (i == RING)
                i = 1;
            llp1 = i * SEAT + j;

            i = (int)llp2 / SEAT;
            j = (int)llp2 % SEAT;
            if (i == 1)
                i = RING;
            else if (i == RING)
                i = 1;
            llp2 = i * SEAT + j;

            i = (int)llp3 / SEAT;
            j = (int)llp3 % SEAT;
            if (i == 1)
                i = RING;
            else if (i == RING)
                i = 1;
            llp3 = i * SEAT + j;

            *mill &= 0xffffff00ff00ff00;
            *mill |= (llp1 << 32) | (llp2 << 16) | llp3;
        }
    }

    // 命令行解析
    if (cmdChange) {
        int c1, p1, c2, p2;
        int args = 0;
        int mm = 0, ss = 0, mss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
        if (args >= 4) {
            if (c1 == 1)
                c1 = RING;
            else if (c1 == RING)
                c1 = 1;
            if (c2 == 1)
                c2 = RING;
            else if (c2 == RING)
                c2 = 1;
            cmdline[1] = '0' + (char)c1;
            cmdline[8] = '0' + (char)c2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                if (c1 == 1)
                    c1 = RING;
                else if (c1 == RING)
                    c1 = 1;
                cmdline[2] = '0' + (char)c1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    if (c1 == 1)
                        c1 = RING;
                    else if (c1 == RING)
                        c1 = 1;
                    cmdline[1] = '0' + (char)c1;
                }
            }
        }

        for (auto itor = cmdlist.begin(); itor != cmdlist.end(); itor++) {
            args = sscanf((*itor).c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
            if (args >= 4) {
                if (c1 == 1)
                    c1 = RING;
                else if (c1 == RING)
                    c1 = 1;
                if (c2 == 1)
                    c2 = RING;
                else if (c2 == RING)
                    c2 = 1;
                (*itor)[1] = '0' + (char)c1;
                (*itor)[8] = '0' + (char)c2;
            } else {
                args = sscanf((*itor).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    if (c1 == 1)
                        c1 = RING;
                    else if (c1 == RING)
                        c1 = 1;
                    (*itor)[2] = '0' + (char)c1;
                } else {
                    args = sscanf((*itor).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        if (c1 == 1)
                            c1 = RING;
                        else if (c1 == RING)
                            c1 = 1;
                        (*itor)[1] = '0' + (char)c1;
                    }
                }
            }
        }
    }
}

void NineChess::rotate(int degrees, bool cmdChange /*= true*/)
{
    // 将degrees转化为0~359之间的数
    degrees = degrees % 360;
    if (degrees < 0)
        degrees += 360;

    if (degrees == 0 || degrees % 90)
        return;
    else
        degrees /= 45;

    int ch1, ch2;
    int i, j;

    if (degrees == 2) {
        for (i = 1; i <= RING; i++) {
            ch1 = board_[i * SEAT];
            ch2 = board_[i * SEAT + 1];
            for (j = 0; j < SEAT - 2; j++) {
                board_[i * SEAT + j] = board_[i * SEAT + j + 2];
            }
            board_[i * SEAT + 6] = ch1;
            board_[i * SEAT + 7] = ch2;
        }
    } else if (degrees == 6) {
        for (i = 1; i <= RING; i++) {
            ch1 = board_[i * SEAT + 7];
            ch2 = board_[i * SEAT + 6];
            for (j = SEAT - 1; j >= 2; j--) {
                board_[i * SEAT + j] = board_[i * SEAT + j - 2];
            }
            board_[i * SEAT + 1] = ch1;
            board_[i * SEAT] = ch2;
        }
    } else if (degrees == 4) {
        for (i = 1; i <= RING; i++) {
            for (j = 0; j < SEAT / 2; j++) {
                ch1 = board_[i * SEAT + j];
                board_[i * SEAT + j] = board_[i * SEAT + j + 4];
                board_[i * SEAT + j + 4] = ch1;
            }
        }
    } else
        return;

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / SEAT;
        j = (-move_) % SEAT;
        j = (j + SEAT - degrees) % SEAT;
        move_ = -(i * SEAT + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / SEAT;
        j = (int)llp1 % SEAT;
        j = (j + SEAT - degrees) % SEAT;
        llp1 = i * SEAT + j;
        i = (int)llp2 / SEAT;
        j = (int)llp2 % SEAT;
        j = (j + SEAT - degrees) % SEAT;
        llp2 = i * SEAT + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / SEAT;
        j = currentPos % SEAT;
        j = (j + SEAT - degrees) % SEAT;
        currentPos = i * SEAT + j;
    }

    if (currentRule.canRepeated) {
        for (auto mill = data.millList.begin(); mill != data.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / SEAT;
            j = (int)llp1 % SEAT;
            j = (j + SEAT - degrees) % SEAT;
            llp1 = i * SEAT + j;

            i = (int)llp2 / SEAT;
            j = (int)llp2 % SEAT;
            j = (j + SEAT - degrees) % SEAT;
            llp2 = i * SEAT + j;

            i = (int)llp3 / SEAT;
            j = (int)llp3 % SEAT;
            j = (j + SEAT - degrees) % SEAT;
            llp3 = i * SEAT + j;

            *mill &= 0xffffff00ff00ff00;
            *mill |= (llp1 << 32) | (llp2 << 16) | llp3;
        }
    }

    // 命令行解析
    if (cmdChange) {
        int c1, p1, c2, p2;
        int args = 0;
        int mm = 0, ss = 0, mss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
        if (args >= 4) {
            p1 = (p1 - 1 + SEAT - degrees) % SEAT;
            p2 = (p2 - 1 + SEAT - degrees) % SEAT;
            cmdline[3] = '1' + (char)p1;
            cmdline[10] = '1' + (char)p2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                p1 = (p1 - 1 + SEAT - degrees) % SEAT;
                cmdline[4] = '1' + (char)p1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (p1 - 1 + SEAT - degrees) % SEAT;
                    cmdline[3] = '1' + (char)p1;
                }
            }
        }

        for (auto itor = cmdlist.begin(); itor != cmdlist.end(); itor++) {
            args = sscanf((*itor).c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
            if (args >= 4) {
                p1 = (p1 - 1 + SEAT - degrees) % SEAT;
                p2 = (p2 - 1 + SEAT - degrees) % SEAT;
                (*itor)[3] = '1' + (char)p1;
                (*itor)[10] = '1' + (char)p2;
            } else {
                args = sscanf((*itor).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (p1 - 1 + SEAT - degrees) % SEAT;
                    (*itor)[4] = '1' + (char)p1;
                } else {
                    args = sscanf((*itor).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        p1 = (p1 - 1 + SEAT - degrees) % SEAT;
                        (*itor)[3] = '1' + (char)p1;
                    }
                }
            }
        }
    }
}
