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

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

#include <algorithm>
#include "ninechess.h"
#include "ninechessai_ab.h"
#include <QDebug>

// 对静态常量数组的定义要放在类外，不要放在头文件
// 预定义的4套规则
const struct NineChess::Rule NineChess::RULES[N_RULES] = {
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
    false,      // 不能提对手的“三连”子，除非无子可提；
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
    true,       // 可以提对手的“三连”子
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    true,       // 走棋阶段不能行动（被“闷”）算负
    false,      // 剩三子时不可以飞棋
    50,          // 不计步数
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
    false,      // 不能提对手的“三连”子，除非无子可提；
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
    false,      // 不能提对手的“三连”子，除非无子可提；
    true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
    true,       // 走棋阶段不能行动（被“闷”）算负
    true,       // 剩三子时可以飞棋
    0,          // 不计步数
    0           // 不计时
}
};

// 名义上是个数组，实际上相当于一个判断是否在棋盘上的函数
const int NineChess::onBoard[(N_RINGS + 2) * N_SEATS] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// 着法表
int NineChess::moveTable[N_POINTS][N_MOVE_DIRECTIONS] = { 0 };

// 成三表
int NineChess::millTable[N_POINTS][N_DIRECTIONS][N_RINGS - 1] = { 0 };

NineChess::NineChess()
{
    // 单独提出 board 等数据，免得每次都写 context.board;
    board_ = context.board;

 #if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
    //hash_ = &context.hash;
    //zobrist_ = &context.zobrist;

    // 创建哈希数据
    constructHash();
#endif

#ifdef BOOK_LEARNING
    // TODO: 开局库文件被加载了多次
    NineChessAi_ab::loadOpeningBookFileToHashMap();
#endif

    // 默认选择第1号规则，即“打三棋”
    setContext(&RULES[1]);

    // 比分归零
    score_1 = score_2 = score_draw = 0;
}

NineChess::NineChess(const NineChess &chess)
{
    currentRule = chess.currentRule;
    context = chess.context;
    currentStep = chess.currentStep;
    moveStep = chess.moveStep;
    board_ = context.board;
    currentPos = chess.currentPos;
    winner = chess.winner;
    startTimeb = chess.startTimeb;
    currentTimeb = chess.currentTimeb;
    elapsedMS_1 = chess.elapsedMS_1;
    elapsedMS_2 = chess.elapsedMS_2;
    move_ = chess.move_;
    memcpy(cmdline, chess.cmdline, sizeof(cmdline));
    cmdlist = chess.cmdlist;
    tips = chess.tips;
}

const NineChess &NineChess::operator=(const NineChess &chess)
{
    if (this == &chess)
        return *this;

    currentRule = chess.currentRule;
    context = chess.context;
    currentStep = chess.currentStep;
    moveStep = chess.moveStep;
    board_ = context.board;
    currentPos = chess.currentPos;
    winner = chess.winner;
    startTimeb = chess.startTimeb;
    currentTimeb = chess.currentTimeb;
    elapsedMS_1 = chess.elapsedMS_1;
    elapsedMS_2 = chess.elapsedMS_2;
    move_ = chess.move_;
    memcpy(cmdline, chess.cmdline, sizeof(cmdline));
    cmdlist = chess.cmdlist;
    tips = chess.tips;
    return *this;
}


NineChess::~NineChess()
{
}

NineChess::Player NineChess::getOpponent(NineChess::Player player)
{
    switch (player)
    {
    case PLAYER1:
        return PLAYER2;
        break;
    case PLAYER2:
        return PLAYER1;
        break;
    default:
        return NOBODY;
        break;
    }

    return NOBODY;
}

void NineChess::createMoveTable()
{
    for (int r = 1; r <= N_RINGS; r++) {
        for (int s = 0; s < N_SEATS; s++) {
            // 顺时针走一步的位置
            moveTable[r * N_SEATS + s][MOVE_DIRECTION_CLOCKWISE] = r * N_SEATS + (s + 1) % N_SEATS;

            // 逆时针走一步的位置
            moveTable[r * N_SEATS + s][MOVE_DIRECTION_ANTICLOCKWISE] = r * N_SEATS + (s + N_SEATS - 1) % N_SEATS;

            // 如果是 0、2、4、6位（偶数位）或是有斜线
            if (!(s & 1) || this->currentRule.hasObliqueLines) {
                if (r > 1) {
                    // 向内走一步的位置
                    moveTable[r * N_SEATS + s][MOVE_DIRECTION_INWARD] = (r - 1) * N_SEATS + s;
                }

                if (r < N_RINGS) {
                    // 向外走一步的位置
                    moveTable[r * N_SEATS + s][MOVE_DIRECTION_OUTWARD] = (r + 1) * N_SEATS + s;
                }
            }
#if 0
            // 对于无斜线情况下的1、3、5、7位（奇数位），则都设为棋盘外点（默认'\x00'）
            else {
                // 向内走一步的位置设为随便棋盘外一点
                moveTable[i * SEAT + j][2] = '\x00';
                // 向外走一步的位置设为随便棋盘外一点
                moveTable[i * SEAT + j][3] = '\x00';
            }
#endif
        }
    }
}

void NineChess::createMillTable()
{
    for (int i = 0; i < N_SEATS; i++) {
        // 内外方向的“成三”
        // 如果是0、2、4、6位（偶数位）或是有斜线
        if (!(i & 1) || this->currentRule.hasObliqueLines) {
            millTable[1 * N_SEATS + i][0][0] = 2 * N_SEATS + i;
            millTable[1 * N_SEATS + i][0][1] = 3 * N_SEATS + i;

            millTable[2 * N_SEATS + i][0][0] = 1 * N_SEATS + i;
            millTable[2 * N_SEATS + i][0][1] = 3 * N_SEATS + i;

            millTable[3 * N_SEATS + i][0][0] = 1 * N_SEATS + i;
            millTable[3 * N_SEATS + i][0][1] = 2 * N_SEATS + i;
        }
        // 对于无斜线情况下的1、3、5、7位（奇数位）
        else {
            // 置空该组“成三”
            millTable[1 * N_SEATS + i][0][0] = 0;
            millTable[1 * N_SEATS + i][0][1] = 0;

            millTable[2 * N_SEATS + i][0][0] = 0;
            millTable[2 * N_SEATS + i][0][1] = 0;

            millTable[3 * N_SEATS + i][0][0] = 0;
            millTable[3 * N_SEATS + i][0][1] = 0;
        }

        // 当前圈上的“成三”
        // 如果是0、2、4、6位
        if (!(i & 1)) {
            millTable[1 * N_SEATS + i][1][0] = 1 * N_SEATS + (i + 1) % N_SEATS;
            millTable[1 * N_SEATS + i][1][1] = 1 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;

            millTable[2 * N_SEATS + i][1][0] = 2 * N_SEATS + (i + 1) % N_SEATS;
            millTable[2 * N_SEATS + i][1][1] = 2 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;

            millTable[3 * N_SEATS + i][1][0] = 3 * N_SEATS + (i + 1) % N_SEATS;
            millTable[3 * N_SEATS + i][1][1] = 3 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;
            // 置空另一组“成三”
            millTable[1 * N_SEATS + i][2][0] = 0;
            millTable[1 * N_SEATS + i][2][1] = 0;

            millTable[2 * N_SEATS + i][2][0] = 0;
            millTable[2 * N_SEATS + i][2][1] = 0;

            millTable[3 * N_SEATS + i][2][0] = 0;
            millTable[3 * N_SEATS + i][2][1] = 0;
        }
        // 对于1、3、5、7位（奇数位）
        else {
            // 当前圈上逆时针的“成三”
            millTable[1 * N_SEATS + i][1][0] = 1 * N_SEATS + (i + N_SEATS - 2) % N_SEATS;
            millTable[1 * N_SEATS + i][1][1] = 1 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;

            millTable[2 * N_SEATS + i][1][0] = 2 * N_SEATS + (i + N_SEATS - 2) % N_SEATS;
            millTable[2 * N_SEATS + i][1][1] = 2 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;

            millTable[3 * N_SEATS + i][1][0] = 3 * N_SEATS + (i + N_SEATS - 2) % N_SEATS;
            millTable[3 * N_SEATS + i][1][1] = 3 * N_SEATS + (i + N_SEATS - 1) % N_SEATS;

            // 当前圈上顺时针的“成三”
            millTable[1 * N_SEATS + i][2][0] = 1 * N_SEATS + (i + 1) % N_SEATS;
            millTable[1 * N_SEATS + i][2][1] = 1 * N_SEATS + (i + 2) % N_SEATS;

            millTable[2 * N_SEATS + i][2][0] = 2 * N_SEATS + (i + 1) % N_SEATS;
            millTable[2 * N_SEATS + i][2][1] = 2 * N_SEATS + (i + 2) % N_SEATS;

            millTable[3 * N_SEATS + i][2][0] = 3 * N_SEATS + (i + 1) % N_SEATS;
            millTable[3 * N_SEATS + i][2][1] = 3 * N_SEATS + (i + 2) % N_SEATS;
        }
    }
}

// 设置棋局状态和棋盘数据，用于初始化
bool NineChess::setContext(const struct Rule *rule, int maxStepsLedToDraw, int maxTimeLedToLose,
                        int initialStep, int flags, const char *board,
                        int nPiecesInHand_1, int nPiecesInHand_2, int nPiecesNeedRemove)
{
    // 有效性判断
    if (maxStepsLedToDraw < 0 || maxTimeLedToLose < 0 || initialStep < 0 ||
        nPiecesInHand_1 < 0 || nPiecesInHand_2 < 0 || nPiecesNeedRemove < 0) {
        return false;
    }

    // 根据规则
    this->currentRule = *rule;
    this->currentRule.maxStepsLedToDraw = maxStepsLedToDraw;
    this->currentRule.maxTimeLedToLose = maxTimeLedToLose;

    // 设置棋局数据
    {
        // 设置步数
        this->currentStep = initialStep;
        this->moveStep = initialStep;

        // 局面阶段标识
        if (flags & GAME_NOTSTARTED) {
            context.stage = GAME_NOTSTARTED;
        }
        else if (flags & GAME_PLACING) {
            context.stage = GAME_PLACING;
        }
        else if (flags & GAME_MOVING) {
            context.stage = GAME_MOVING;
            //context.hash ^=  // TODO
        }
        else if (flags & GAME_OVER) {
            context.stage = GAME_OVER;
        }
        else {
            return false;
        }

        // 轮流状态标识
        if (flags & PLAYER1) {
//             if (context.turn == PLAYER2) {
//                 context.hash ^= player2sTurnHash;
//             }
            context.turn = PLAYER1;
        }
        else if (flags & PLAYER2) {
//             if (context.turn == PLAYER1) {
//                 context.hash ^= player2sTurnHash;
//             }
            context.turn = PLAYER2;
        }
        else {
            return false;
        }

        // 动作状态标识
        if (flags & ACTION_CHOOSE)
            context.action = ACTION_CHOOSE;
        else if (flags & ACTION_PLACE)
            context.action = ACTION_PLACE;
        else if (flags & ACTION_CAPTURE)
            context.action = ACTION_CAPTURE;
        else
            return false;

        // 当前棋局（3×8）
        if (board == nullptr) {
            memset(context.board, 0, sizeof(context.board));
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
            context.hash = 0ull;
#endif
        } else {
            memcpy(context.board, board, sizeof(context.board));
        }

        // 计算盘面子数
        // 棋局，抽象为一个（5×8）的数组，上下两行留空
        /*
            0x00 代表无棋子
            0x0F 代表禁点
            0x11～0x1C 代表先手第 1～12 子
            0x21～0x2C 代表后手第 1～12 子
            判断棋子是先手的用 (board[i] & 0x10)
            判断棋子是后手的用 (board[i] & 0x20)
         */
        context.nPiecesOnBoard_1 = context.nPiecesOnBoard_2 = 0;
        for (int r = 1; r < N_RINGS + 2; r++) {
            for (int s = 0; s < N_SEATS; s++) {
                int pos = r * N_SEATS + s;
                if (context.board[pos] & '\x10') {
                    context.nPiecesOnBoard_1++;
                }
                else if (context.board[pos] & '\x20') {
                    context.nPiecesOnBoard_2++;
                }
                else if (context.board[pos] & '\x0F') {
                    // 不计算盘面子数
                }

                //updateHash(pos);
            }
        }

        // 设置玩家盘面剩余子数和未放置子数
        if (context.nPiecesOnBoard_1 > rule->nTotalPiecesEachSide ||
            context.nPiecesOnBoard_2 > rule->nTotalPiecesEachSide) {
            return false;
        }

        if (nPiecesInHand_1 < 0 || nPiecesInHand_2 < 0) {
            return false;
        }

        context.nPiecesInHand_1 = rule->nTotalPiecesEachSide - context.nPiecesOnBoard_1;
        context.nPiecesInHand_2 = rule->nTotalPiecesEachSide - context.nPiecesOnBoard_2;
        context.nPiecesInHand_1 = std::min(nPiecesInHand_1, context.nPiecesInHand_1);
        context.nPiecesInHand_2 = std::min(nPiecesInHand_2, context.nPiecesInHand_2);

        // 设置去子状态时的剩余尚待去除子数
        if (flags & ACTION_CAPTURE) {
            if (0 <= nPiecesNeedRemove && nPiecesNeedRemove < 3)
                context.nPiecesNeedRemove = nPiecesNeedRemove;
        } else {
            context.nPiecesNeedRemove = 0;
        }

        // 清空成三记录
        context.millList.clear();
    }

    // 胜负标识
    winner = NOBODY;

    // 生成着法表
    createMoveTable();

    // 生成成三表
    createMillTable();

    // 不选中棋子
    currentPos = 0;

    // 用时置零
    elapsedMS_1 = elapsedMS_2 = 0;

    // 提示
    setTips();

    // 计棋谱
    cmdlist.clear();

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(this->currentRule.name, RULES[r].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u", r + 1, maxStepsLedToDraw, maxTimeLedToLose) > 0) {
        cmdlist.push_back(string(cmdline));
        return true;
    } else {
        cmdline[0] = '\0';
        return false;
    }

    //return true;
}

void NineChess::getContext(struct Rule &rule, int &step, int &flags,
                           int *&board, int &nPiecesInHand_1, int &nPiecesInHand_2, int &num_NeedRemove)
{
    rule = this->currentRule;
    step = this->currentStep;
    flags = context.stage | context.turn | context.action;
    this->board_ = board;
    nPiecesInHand_1 = context.nPiecesInHand_1;
    nPiecesInHand_2 = context.nPiecesInHand_2;
    num_NeedRemove = context.nPiecesNeedRemove;
}

bool NineChess::reset()
{
    if (context.stage == GAME_NOTSTARTED && elapsedMS_1 == elapsedMS_2 == 0)
        return true;

    // 步数归零
    currentStep = 0;
    moveStep = 0;

    // 局面阶段标识
    context.stage = GAME_NOTSTARTED;

    // 轮流状态标识
    context.turn = PLAYER1;

    // 动作状态标识
    context.action = ACTION_PLACE;

    // 胜负标识
    winner = NOBODY;

    // 当前棋局（3×8）
    memset(board_, 0, sizeof(context.board));

    // 盘面子数归零
    context.nPiecesOnBoard_1 = context.nPiecesOnBoard_2 = 0;

    // 设置玩家盘面剩余子数和未放置子数
    context.nPiecesInHand_1 = context.nPiecesInHand_2 = currentRule.nTotalPiecesEachSide;

    // 设置去子状态时的剩余尚待去除子数
    context.nPiecesNeedRemove = 0;

    // 清空成三记录
    context.millList.clear();

    // 不选中棋子
    currentPos = 0;

    // 用时置零
    elapsedMS_1 = elapsedMS_2 = 0;

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
    // 哈希归零
    context.hash = 0;
#endif

    // 提示
    setTips();

    // 计棋谱
    cmdlist.clear();

    int i;

    for (i = 0; i < N_RULES; i++) {
        if (strcmp(this->currentRule.name, RULES[i].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u", i + 1, currentRule.maxStepsLedToDraw, currentRule.maxTimeLedToLose) > 0) {
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
    switch (context.stage) {
    // 如果游戏已经开始，则返回false
    case GAME_PLACING:
    case GAME_MOVING:
        return false;
    // 如果游戏结束，则重置游戏，进入未开始状态
    case GAME_OVER:
        reset();   // 这里不要break;
    // 如果游戏处于未开始状态
    case GAME_NOTSTARTED:
        // 启动计时器
        ftime(&startTimeb);
        // 进入开局状态
        context.stage = GAME_PLACING;
        return true;
    default:
        return false;
    }
}

bool NineChess::getPieceCP(const Player &player, const int &number, int &c, int &p)
{
    int piece;

    if (player == PLAYER1)
        piece = 0x10;
    else if (player == PLAYER2)
        piece = 0x20;
    else
        return false;

    if (number > 0 && number <= currentRule.nTotalPiecesEachSide)
        piece &= number;
    else
        return false;

    for (int i = POS_BEGIN; i < POS_END; i++) {
        if (board_[i] == piece) {
            pos2cp(i, c, p);
            return true;
        }
    }

    return false;
}

// 获取当前棋子
bool NineChess::getCurrentPiece(Player &player, int &number)
{
    if (!onBoard[currentPos])
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
    if (pos < POS_BEGIN || POS_END <= pos)
        return false;

    c = pos / N_SEATS;
    p = pos % N_SEATS + 1;

    return true;
}

int NineChess::cp2pos(int c, int p)
{
    if (c < 1 || c > N_RINGS || p < 1 || p > N_SEATS)
        return 0;

    return c * N_SEATS + p - 1;
}

bool NineChess::place(int c, int p, long time_p /* = -1*/)
{
    // 如果局面为“结局”，返回false
    if (context.stage == GAME_OVER)
        return false;

    // 如果局面为“未开局”，则开局
    if (context.stage == GAME_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (context.action != ACTION_PLACE)
        return false;

    // 转换为 pos
    int pos = cp2pos(c, p);

    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!onBoard[pos] || board_[pos])
        return false;

    // 时间的临时变量
    long player_ms = -1;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;

    if (context.stage == GAME_PLACING) {
        // 先手下
        if (context.turn == PLAYER1) {
            piece = '\x11' + currentRule.nTotalPiecesEachSide - context.nPiecesInHand_1;
            context.nPiecesInHand_1--;
            context.nPiecesOnBoard_1++;
        }
        // 后手下
        else {
            piece = '\x21' + currentRule.nTotalPiecesEachSide - context.nPiecesInHand_2;
            context.nPiecesInHand_2--;
            context.nPiecesOnBoard_2++;
        }

        board_[pos] = piece;

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        updateHash(pos);
#endif
        move_ = pos;
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u) %02u:%02u.%03u",
                c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        currentPos = pos;
        currentStep++;

        // 如果决出胜负
        if (win()) {
            setTips();
            return true;
        }

        n = addMills(currentPos);

        // 开局阶段未成三
        if (n == 0) {
            // 如果双方都无未放置的棋子
            if (context.nPiecesInHand_1 == 0 && context.nPiecesInHand_2 == 0) {
                // 进入中局阶段
                context.stage = GAME_MOVING;

                // 进入选子状态
                context.action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenPoints();

                // 设置轮到谁走
                if (currentRule.isDefenderMoveFirst) {
                    context.turn = PLAYER2;
                } else {
                    context.turn = PLAYER1;
                }

                // 再决胜负
                if (win()) {
                    setTips();
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
            context.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            context.action = ACTION_CAPTURE;
        }

        setTips();

        return true;
    }

    // 对于中局落子
    else if (context.stage == GAME_MOVING) {
        // 如果落子不合法
        if ((context.turn == PLAYER1 &&
            (context.nPiecesOnBoard_1 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces)) ||
            (context.turn == PLAYER2 &&
            (context.nPiecesOnBoard_2 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces))) {

            int i;
            for (i = 0; i < 4; i++) {
                if (pos == moveTable[currentPos][i])
                    break;
            }

            // 不在着法表中
            if (i == 4)
                return false;
        }

        // 移子
        move_ = (currentPos << 8) + pos;
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u.%03u", currentPos / N_SEATS, currentPos % N_SEATS + 1,
                c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
        cmdlist.push_back(string(cmdline));
        board_[pos] = board_[currentPos];
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING))
        updateHash(pos);
#endif
        board_[currentPos] = '\x00';
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        revertHash(currentPos);
#endif
        currentPos = pos;
        currentStep++;
        moveStep++;
        n = addMills(currentPos);

        // 中局阶段未成三
        if (n == 0) {
            // 进入选子状态
            context.action = ACTION_CHOOSE;

            // 设置轮到谁走
            changeTurn();

            // 如果决出胜负
            if (win()) {
                setTips();
                return true;
            }
        }
        // 中局阶段成三
        else {
            // 设置去子数目
            context.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            context.action = ACTION_CAPTURE;
            setTips();
        }

        setTips();

        return true;
    }

    return false;
}

bool NineChess::capture(int c, int p, long time_p /* = -1*/)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (context.stage == GAME_NOTSTARTED || context.stage == GAME_OVER)
        return false;

    // 如非“去子”状态，返回false
    if (context.action != ACTION_CAPTURE)
        return false;

    // 如果去子完成，返回false
    if (context.nPiecesNeedRemove <= 0)
        return false;

    // 时间的临时变量
    long player_ms = -1;
    int pos = cp2pos(c, p);

    // 对手
    char opponent = context.turn == PLAYER1 ? 0x20 : 0x10;

    // 判断去子是不是对手棋
    if (!(opponent & board_[pos]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (currentRule.allowRemoveMill == false &&
        isInMills(pos) && !isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (currentRule.hasForbiddenPoint && context.stage == GAME_PLACING) {
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING))
        revertHash(pos);
#endif
        board_[pos] = '\x0f';
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        updateHash(pos);
#endif
    } else { // 去子
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        revertHash(pos);
#endif
        board_[pos] = '\x00';
    }

    if (context.turn == PLAYER1)
        context.nPiecesOnBoard_2--;
    else if (context.turn == PLAYER2)
        context.nPiecesOnBoard_1--;

    move_ = -pos;
    player_ms = update(time_p);
    sprintf(cmdline, "-(%1u,%1u)  %02u:%02u.%03u", c, p, player_ms / 60000, (player_ms % 60000) / 1000, player_ms % 1000);
    cmdlist.push_back(string(cmdline));
    currentPos = 0;
    context.nPiecesNeedRemove--;
    currentStep++;
    moveStep = 0;
    // 去子完成

    // 如果决出胜负
    if (win()) {
        setTips();
        return true;
    }

    // 还有其余的子要去吗
    if (context.nPiecesNeedRemove > 0) {
        // 继续去子
        return true;
    }
    // 所有去子都完成了
    else {
        // 开局阶段
        if (context.stage == GAME_PLACING) {
            // 如果双方都无未放置的棋子
            if (context.nPiecesInHand_1 == 0 && context.nPiecesInHand_2 == 0) {

                // 进入中局阶段
                context.stage = GAME_MOVING;

                // 进入选子状态
                context.action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenPoints();

                // 设置轮到谁走
                if (currentRule.isDefenderMoveFirst) {
                    context.turn = PLAYER2;
                } else {
                    context.turn = PLAYER1;
                }

                // 再决胜负
                if (win()) {
                    setTips();
                    return true;
                }
            }
            // 如果双方还有子
            else {
                // 进入落子状态
                context.action = ACTION_PLACE;
                // 设置轮到谁走
                changeTurn();
                // 如果决出胜负
                if (win()) {
                    setTips();
                    return true;
                }
            }
        }
        // 中局阶段
        else {
            // 进入选子状态
            context.action = ACTION_CHOOSE;
            // 设置轮到谁走
            changeTurn();
            // 如果决出胜负
            if (win()) {
                setTips();
                return true;
            }
        }
    }

    setTips();

    return true;
}

bool NineChess::choose(int c, int p)
{
    // 如果局面不是"中局”，返回false
    if (context.stage != GAME_MOVING)
        return false;

    // 如非“选子”或“落子”状态，返回false
    if (context.action != ACTION_CHOOSE && context.action != ACTION_PLACE)
        return false;

    int pos = cp2pos(c, p);

    // 根据先后手，判断可选子
    char t = '\0';

    if (context.turn == PLAYER1)
        t = '\x10';
    else if (context.turn == PLAYER2)
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
        context.action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool NineChess::place(int pos)
{
    // 如果局面为“结局”，返回false
    if (context.stage == GAME_OVER)
        return false;

    // 如果局面为“未开局”，则开局
    if (context.stage == GAME_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (context.action != ACTION_PLACE)
        return false;

    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!onBoard[pos] || board_[pos])
        return false;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;
    if (context.stage == GAME_PLACING) {
        // 先手下
        if (context.turn == PLAYER1) {
            piece = '\x11' + currentRule.nTotalPiecesEachSide - context.nPiecesInHand_1;
            context.nPiecesInHand_1--;
            context.nPiecesOnBoard_1++;
        }
        // 后手下
        else {
            piece = '\x21' + currentRule.nTotalPiecesEachSide - context.nPiecesInHand_2;
            context.nPiecesInHand_2--;
            context.nPiecesOnBoard_2++;
        }

        board_[pos] = piece;

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        updateHash(pos);
#endif
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
            if (context.nPiecesInHand_1 == 0 && context.nPiecesInHand_2 == 0) {

                // 进入中局阶段
                context.stage = GAME_MOVING;

                // 进入选子状态
                context.action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenPoints();

                // 设置轮到谁走
                if (currentRule.isDefenderMoveFirst) {
                    context.turn = PLAYER2;
                } else {
                    context.turn = PLAYER1;
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
            context.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;
            // 进入去子状态
            context.action = ACTION_CAPTURE;
        }
        //setTips(); // 非常影响性能
        return true;
    }

    // 对于中局落子
    else if (context.stage == GAME_MOVING) {
        // 如果落子不合法
        if ((context.turn == PLAYER1 &&
            (context.nPiecesOnBoard_1 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces)) ||
            (context.turn == PLAYER2 &&
            (context.nPiecesOnBoard_2 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces))) {
            int i;
            for (i = 0; i < 4; i++) {
                if (pos == moveTable[currentPos][i])
                    break;
            }
            // 不在着法表中
            if (i == 4)
                return false;
        }
        // 移子
        move_ = (currentPos << 8) + pos;
        board_[pos] = board_[currentPos];
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        updateHash(pos);
#endif
        board_[currentPos] = '\x00';
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        revertHash(currentPos);
#endif
        currentPos = pos;
        //step++;
        n = addMills(currentPos);

        // 中局阶段未成三
        if (n == 0) {
            // 进入选子状态
            context.action = ACTION_CHOOSE;

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
            context.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            context.action = ACTION_CAPTURE;
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
    if (context.stage == GAME_NOTSTARTED || context.stage == GAME_OVER)
        return false;

    // 如非“去子”状态，返回false
    if (context.action != ACTION_CAPTURE)
        return false;

    // 如果去子完成，返回false
    if (context.nPiecesNeedRemove <= 0)
        return false;

    // 对手
    char opponent = context.turn == PLAYER1 ? 0x20 : 0x10;

    // 判断去子是不是对手棋
    if (!(opponent & board_[pos]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (currentRule.allowRemoveMill == false &&
        isInMills(pos) && !isAllInMills(opponent)) {
        return false;
    }

    if (currentRule.hasForbiddenPoint && context.stage == GAME_PLACING) {
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        revertHash(pos);
#endif
        board_[pos] = '\x0f';
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        updateHash(pos);
#endif
    } else { // 去子
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
        revertHash(pos);
#endif
        board_[pos] = '\x00';
    }

    if (context.turn == PLAYER1)
        context.nPiecesOnBoard_2--;
    else if (context.turn == PLAYER2)
        context.nPiecesOnBoard_1--;

    move_ = -pos;
    currentPos = 0;
    context.nPiecesNeedRemove--;
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
    updateHash(pos);
#endif
    //step++;
    // 去子完成

    // 如果决出胜负
    if (win()) {
        //setTip();
        return true;
    }

    // 还有其余的子要去吗
    if (context.nPiecesNeedRemove > 0) {
        // 继续去子
        return true;
    }
    // 所有去子都完成了
    else {
        // 开局阶段
        if (context.stage == GAME_PLACING) {
            // 如果双方都无未放置的棋子
            if (context.nPiecesInHand_1 == 0 && context.nPiecesInHand_2 == 0) {
                // 进入中局阶段
                context.stage = GAME_MOVING;

                // 进入选子状态
                context.action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenPoints();

                // 设置轮到谁走
                if (currentRule.isDefenderMoveFirst) {
                    context.turn = PLAYER2;
                } else {
                    context.turn = PLAYER1;
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
                context.action = ACTION_PLACE;
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
            context.action = ACTION_CHOOSE;
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
    if (context.stage != GAME_MOVING)
        return false;

    // 如非“选子”或“落子”状态，返回false
    if (context.action != ACTION_CHOOSE && context.action != ACTION_PLACE)
        return false;

    char t = context.turn == PLAYER1 ? 0x10 : 0x20;

    // 判断选子是否可选
    if (board_[pos] & t) {
        // 判断pos处的棋子是否被“闷”
        if (isSurrounded(pos)) {
            return false;
        }

        // 选子
        currentPos = pos;

        // 选子完成，进入落子状态
        context.action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool NineChess::giveup(Player loser)
{
    if (context.stage == GAME_MOVING || context.stage == GAME_PLACING) {
        if (loser == PLAYER1) {
            context.stage = GAME_OVER;
            winner = PLAYER2;
            tips = "玩家1投子认负。";
            sprintf(cmdline, "Player1 give up!");
            cmdlist.push_back(string(cmdline));
            return true;
        } else if (loser == PLAYER2) {
            context.stage = GAME_OVER;
            winner = PLAYER1;
            tips = "玩家2投子认负。";
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
        if (r <= 0 || r > N_RULES)
            return false;
        return setContext(&NineChess::RULES[r - 1], s, t);
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

#ifdef THREEFOLD_REPETITION
    if (!strcmp(cmd, "Threefold Repetition. Draw!")) {
        return true;
    }
    if (!strcmp(cmd, "draw")) {
        context.stage = GAME_OVER;
        winner = DRAW;
        score_draw++;
        tips = "三次重复局面判和。";
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
#endif

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
    long *player_ms = (context.turn == PLAYER1 ? &elapsedMS_1 : &elapsedMS_2);
    long playerNext_ms = (context.turn == PLAYER1 ? elapsedMS_2 : elapsedMS_1);

    // 根据局面调整计时器
    switch (context.stage) {
    case NineChess::GAME_PLACING:
    case NineChess::GAME_MOVING:
        ftime(&currentTimeb);

        // 更新时间
        if (time_p >= *player_ms) {
            *player_ms = ret = time_p;
            long t = elapsedMS_1 + elapsedMS_2;
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
        if (currentRule.maxTimeLedToLose > 0)
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
    return win(false);
}

// 是否分出胜负
bool NineChess::win(bool forceDraw)
{
    if (context.stage == GAME_OVER)
        return true;
    if (context.stage == GAME_NOTSTARTED)
        return false;

    // 如果有时间限定
    if (currentRule.maxTimeLedToLose > 0) {
        // 这里不能update更新时间，否则会形成循环嵌套
        // 如果玩家1超时
        if (elapsedMS_1 > currentRule.maxTimeLedToLose * 60000) {
            elapsedMS_1 = currentRule.maxTimeLedToLose * 60000;
            winner = PLAYER2;
            context.stage = GAME_OVER;
            tips = "玩家1超时判负。";
            sprintf(cmdline, "Time over. Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
        // 如果玩家2超时
        else if (elapsedMS_2 > currentRule.maxTimeLedToLose * 60000) {
            elapsedMS_2 = currentRule.maxTimeLedToLose * 60000;
            winner = PLAYER1;
            context.stage = GAME_OVER;
            tips = "玩家2超时判负。";
            sprintf(cmdline, "Time over. Player1 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果有步数限定
    if (currentRule.maxStepsLedToDraw > 0) {
        if (moveStep > currentRule.maxStepsLedToDraw) {
            winner = DRAW;
            context.stage = GAME_OVER;
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }

    // 如果玩家1子数小于赛点，则玩家2获胜
    if (context.nPiecesOnBoard_1 + context.nPiecesInHand_1 < currentRule.nPiecesAtLeast) {
        winner = PLAYER2;
        context.stage = GAME_OVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
    // 如果玩家2子数小于赛点，则玩家1获胜
    else if (context.nPiecesOnBoard_2 + context.nPiecesInHand_2 < currentRule.nPiecesAtLeast) {
        winner = PLAYER1;
        context.stage = GAME_OVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.push_back(string(cmdline));
#ifdef BOOK_LEARNING
        NineChessAi_ab::recordOpeningBookToHashMap();  // 暂时只对后手的失败记录到开局库
#endif /* BOOK_LEARNING */
        return true;
    }
    // 如果摆满了，根据规则判断胜负
    else if (context.nPiecesOnBoard_1 + context.nPiecesOnBoard_2 >= N_SEATS * N_RINGS) {
        if (currentRule.isStartingPlayerLoseWhenBoardFull) {
            winner = PLAYER2;
            context.stage = GAME_OVER;
            sprintf(cmdline, "Player2 win!");
            cmdlist.push_back(string(cmdline));
            return true;
        } else {
            winner = DRAW;
            context.stage = GAME_OVER;
            sprintf(cmdline, "Full. In draw!");
            cmdlist.push_back(string(cmdline));
            return true;
        }
    }
    // 如果中局被“闷”
    else if (context.stage == GAME_MOVING && context.action == ACTION_CHOOSE && isAllSurrounded(context.turn)) {
        // 规则要求被“闷”判负，则对手获胜
        if (currentRule.isLoseWhenNoWay) {
            if (context.turn == PLAYER1) {
                tips = "玩家1无子可走被闷。";
                winner = PLAYER2;
                context.stage = GAME_OVER;
                sprintf(cmdline, "Player1 no way to go. Player2 win!");
                cmdlist.push_back(string(cmdline));
                return true;
            } else {
                tips = "玩家2无子可走被闷。";
                winner = PLAYER1;
                context.stage = GAME_OVER;
                sprintf(cmdline, "Player2 no way to go. Player1 win!");
                cmdlist.push_back(string(cmdline));
#ifdef BOOK_LEARNING
                NineChessAi_ab::recordOpeningBookToHashMap();  // 暂时只对后手的失败记录到开局库
#endif /* BOOK_LEARNING */
                return true;
            }
        }
        else {  // 否则让棋，由对手走            
            changeTurn();
            return false;           
        }
    }

#ifdef THREEFOLD_REPETITION
    if (forceDraw)
    {
        tips = "重复三次局面和棋！";
        winner = DRAW;
        context.stage = GAME_OVER;
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.push_back(string(cmdline));
        return true;
    }
#endif

    return false;
}

int NineChess::isInMills(int pos, bool test)
{
    int n = 0;
    int pos1, pos2;
    char m = test? INT32_MAX : board_[pos] & '\x30';
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
    // 成三用一个64位整数了，规则如下
    // 0x   00     00     00    00    00    00    00    00
    //    unused unused piece1 pos1 piece2 pos2 piece3 pos3
    // piece1、piece2、piece3按照序号从小到大顺序排放
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
            if (currentRule.allowRemovePiecesRepeatedly) {
                n++;
            }

            // 如果不允许相同三连反复去子
            else {
                // 迭代器
                list<uint64_t>::iterator iter;

                // 遍历
                for (iter = context.millList.begin(); iter != context.millList.end(); iter++) {
                    if (mill == *iter)
                        break;
                }

                // 如果没找到历史项
                if (iter == context.millList.end()) {
                    n++;
                    context.millList.push_back(mill);
                }
            }
        }
    }

    return n;
}

bool NineChess::isAllInMills(char ch)
{
    for (int i = POS_BEGIN; i < POS_END; i++) {
        if (board_[i] & ch) {
            if (!isInMills(i)) {
                return false;
            }
        }
    }

    return true;
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

    return isAllInMills(ch);
}

// 判断玩家的棋子是否被围
bool NineChess::isSurrounded(int pos)
{
    // 判断pos处的棋子是否被“闷”
    if ((context.turn == PLAYER1 &&
        (context.nPiecesOnBoard_1 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces)) ||
        (context.turn == PLAYER2 &&
        (context.nPiecesOnBoard_2 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces))) {
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
    if (context.nPiecesOnBoard_1 + context.nPiecesOnBoard_2 >= N_SEATS * N_RINGS)
        return true;

    // 判断是否可以飞子
    if ((context.turn == PLAYER1 &&
        (context.nPiecesOnBoard_1 <= currentRule.nPiecesAtLeast && currentRule.allowFlyWhenRemainThreePieces)) ||
        (context.turn == PLAYER2 &&
        (context.nPiecesOnBoard_2 <= currentRule.nPiecesAtLeast && currentRule.allowFlyWhenRemainThreePieces))) {
        return false;
    }

    // 查询整个棋盘
    int movePos;
    for (int i = 1; i < N_SEATS * (N_RINGS + 1); i++) {
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
bool NineChess::isAllSurrounded(enum Player ply)
{
    char t = '\x30';

    if (ply == PLAYER1)
        t &= '\x10';
    else if (ply == PLAYER2)
        t &= '\x20';

    return isAllSurrounded(t);
}

void NineChess::cleanForbiddenPoints()
{
    int pos = 0;

    for (int i = 1; i <= N_RINGS; i++) {
        for (int j = 0; j < N_SEATS; j++) {
            pos = i * N_SEATS + j;
            if (board_[pos] == '\x0f') {
#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))
                revertHash(pos);
#endif
                board_[pos] = '\x00';
            }
        }
    }
}

enum NineChess::Player NineChess::changeTurn()
{
    // 设置轮到谁走
    context.turn = (context.turn == PLAYER1) ? PLAYER2 : PLAYER1;
    return context.turn;
}

void NineChess::setTips()
{
    switch (context.stage) {
    case NineChess::GAME_NOTSTARTED:
        tips = "轮到玩家1落子，剩余" + std::to_string(context.nPiecesInHand_1) + "子" +
            "  比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);
        break;

    case NineChess::GAME_PLACING:
        if (context.action == ACTION_PLACE) {
            if (context.turn == PLAYER1) {
                tips = "轮到玩家1落子，剩余" + std::to_string(context.nPiecesInHand_1) + "子";
            } else if (context.turn == PLAYER2) {
                tips = "轮到玩家2落子，剩余" + std::to_string(context.nPiecesInHand_2) + "子";
            }
        } else if (context.action == ACTION_CAPTURE) {
            if (context.turn == PLAYER1) {
                tips = "成三！轮到玩家1去子，需去" + std::to_string(context.nPiecesNeedRemove) + "子";
            } else if (context.turn == PLAYER2) {
                tips = "成三！轮到玩家2去子，需去" + std::to_string(context.nPiecesNeedRemove) + "子";
            }
        }
        break;

    case NineChess::GAME_MOVING:
        if (context.action == ACTION_PLACE || context.action == ACTION_CHOOSE) {
            if (context.turn == PLAYER1) {
                tips = "轮到玩家1选子移动";
            } else if (context.turn == PLAYER2) {
                tips = "轮到玩家2选子移动";
            }
        } else if (context.action == ACTION_CAPTURE) {
            if (context.turn == PLAYER1) {
                tips = "成三！轮到玩家1去子，需去" + std::to_string(context.nPiecesNeedRemove) + "子";
            } else if (context.turn == PLAYER2) {
                tips = "成三！轮到玩家2去子，需去" + std::to_string(context.nPiecesNeedRemove) + "子";
            }
        }
        break;

    case NineChess::GAME_OVER:
        if (winner == DRAW) {
            score_draw++;
            tips = "双方平局！比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);            
        }            
        else if (winner == PLAYER1) {
            score_1++;
            if (tips.find("无子可走") != tips.npos)
                tips += "玩家1获胜！比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);
            else
                tips = "玩家1获胜！比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);
        } else if (winner == PLAYER2) {
            score_2++;
            if (tips.find("无子可走") != tips.npos)
                tips += "玩家2获胜！比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);
            else
                tips = "玩家2获胜！比分 " + to_string(score_1) + ":" + to_string(score_2) + ", 和棋 " + to_string(score_draw);
        }
        break;

    default:
        break;
    }
}

enum NineChess::Player NineChess::getWhosPiece(int c, int p)
{
    int pos = cp2pos(c, p);
    if (board_[pos] & '\x10')
        return PLAYER1;
    else if (board_[pos] & '\x20')
        return PLAYER2;
    return NOBODY;
}

void NineChess::getElapsedTimeMS(int &p1_ms, int &p2_ms)
{
    update();
    p1_ms = elapsedMS_1;
    p2_ms = elapsedMS_2;
}

void NineChess::mirror(bool cmdChange /*= true*/)
{
    int ch;
    int i, j;

    for (i = 1; i <= N_RINGS; i++) {
        for (j = 1; j < N_SEATS / 2; j++) {
            ch = board_[i * N_SEATS + j];
            board_[i * N_SEATS + j] = board_[(i + 1) * N_SEATS - j];
            //updateHash(i * N_SEATS + j);
            board_[(i + 1) * N_SEATS - j] = ch;
            //updateHash((i + 1) * N_SEATS - j);
        }
    }

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / N_SEATS;
        j = (-move_) % N_SEATS;
        j = (N_SEATS - j) % N_SEATS;
        move_ = -(i * N_SEATS + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / N_SEATS;
        j = (int)llp1 % N_SEATS;
        j = (N_SEATS - j) % N_SEATS;
        llp1 = i * N_SEATS + j;

        i = (int)llp2 / N_SEATS;
        j = (int)llp2 % N_SEATS;
        j = (N_SEATS - j) % N_SEATS;
        llp2 = i * N_SEATS + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / N_SEATS;
        j = currentPos % N_SEATS;
        j = (N_SEATS - j) % N_SEATS;
        currentPos = i * N_SEATS + j;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto mill = context.millList.begin(); mill != context.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / N_SEATS;
            j = (int)llp1 % N_SEATS;
            j = (N_SEATS - j) % N_SEATS;
            llp1 = i * N_SEATS + j;

            i = (int)llp2 / N_SEATS;
            j = (int)llp2 % N_SEATS;
            j = (N_SEATS - j) % N_SEATS;
            llp2 = i * N_SEATS + j;

            i = (int)llp3 / N_SEATS;
            j = (int)llp3 % N_SEATS;
            j = (N_SEATS - j) % N_SEATS;
            llp3 = i * N_SEATS + j;

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
            p1 = (N_SEATS - p1 + 1) % N_SEATS;
            p2 = (N_SEATS - p2 + 1) % N_SEATS;
            cmdline[3] = '1' + (char)p1;
            cmdline[10] = '1' + (char)p2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                p1 = (N_SEATS - p1 + 1) % N_SEATS;
                cmdline[4] = '1' + (char)p1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (N_SEATS - p1 + 1) % N_SEATS;
                    cmdline[3] = '1' + (char)p1;
                }
            }
        }

        for (auto iter = cmdlist.begin(); iter != cmdlist.end(); iter++) {
            args = sscanf((*iter).c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
            if (args >= 4) {
                p1 = (N_SEATS - p1 + 1) % N_SEATS;
                p2 = (N_SEATS - p2 + 1) % N_SEATS;
                (*iter)[3] = '1' + (char)p1;
                (*iter)[10] = '1' + (char)p2;
            } else {
                args = sscanf((*iter).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (N_SEATS - p1 + 1) % N_SEATS;
                    (*iter)[4] = '1' + (char)p1;
                } else {
                    args = sscanf((*iter).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        p1 = (N_SEATS - p1 + 1) % N_SEATS;
                        (*iter)[3] = '1' + (char)p1;
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

    for (i = 0; i < N_SEATS; i++) {
        ch = board_[N_SEATS + i];
        board_[N_SEATS + i] = board_[N_SEATS * N_RINGS + i];
        //updateHash(N_SEATS + i);
        board_[N_SEATS * N_RINGS + i] = ch;
        //updateHash(N_SEATS * N_RINGS + i);
    }

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / N_SEATS;
        j = (-move_) % N_SEATS;

        if (i == 1)
            i = N_RINGS;
        else if (i == N_RINGS)
            i = 1;

        move_ = -(i * N_SEATS + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / N_SEATS;
        j = (int)llp1 % N_SEATS;

        if (i == 1)
            i = N_RINGS;
        else if (i == N_RINGS)
            i = 1;

        llp1 = i * N_SEATS + j;
        i = (int)llp2 / N_SEATS;
        j = (int)llp2 % N_SEATS;

        if (i == 1)
            i = N_RINGS;
        else if (i == N_RINGS)
            i = 1;

        llp2 = i * N_SEATS + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / N_SEATS;
        j = currentPos % N_SEATS;
        if (i == 1)
            i = N_RINGS;
        else if (i == N_RINGS)
            i = 1;
        currentPos = i * N_SEATS + j;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto mill = context.millList.begin(); mill != context.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / N_SEATS;
            j = (int)llp1 % N_SEATS;
            if (i == 1)
                i = N_RINGS;
            else if (i == N_RINGS)
                i = 1;
            llp1 = i * N_SEATS + j;

            i = (int)llp2 / N_SEATS;
            j = (int)llp2 % N_SEATS;

            if (i == 1)
                i = N_RINGS;
            else if (i == N_RINGS)
                i = 1;

            llp2 = i * N_SEATS + j;

            i = (int)llp3 / N_SEATS;
            j = (int)llp3 % N_SEATS;

            if (i == 1)
                i = N_RINGS;
            else if (i == N_RINGS)
                i = 1;

            llp3 = i * N_SEATS + j;

            *mill &= 0xffffff00ff00ff00;
            *mill |= (llp1 << 32) | (llp2 << 16) | llp3;
        }
    }

    // 命令行解析
    if (cmdChange) {
        int c1, p1, c2, p2;
        int args = 0;
        int mm = 0, ss = 0, mss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u",
                        &c1, &p1, &c2, &p2, &mm, &ss, &mss);

        if (args >= 4) {
            if (c1 == 1)
                c1 = N_RINGS;
            else if (c1 == N_RINGS)
                c1 = 1;
            if (c2 == 1)
                c2 = N_RINGS;
            else if (c2 == N_RINGS)
                c2 = 1;
            cmdline[1] = '0' + (char)c1;
            cmdline[8] = '0' + (char)c2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                if (c1 == 1)
                    c1 = N_RINGS;
                else if (c1 == N_RINGS)
                    c1 = 1;
                cmdline[2] = '0' + (char)c1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    if (c1 == 1)
                        c1 = N_RINGS;
                    else if (c1 == N_RINGS)
                        c1 = 1;
                    cmdline[1] = '0' + (char)c1;
                }
            }
        }

        for (auto iter = cmdlist.begin(); iter != cmdlist.end(); iter++) {
            args = sscanf((*iter).c_str(),
                            "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u",
                            &c1, &p1, &c2, &p2, &mm, &ss, &mss);

            if (args >= 4) {
                if (c1 == 1)
                    c1 = N_RINGS;
                else if (c1 == N_RINGS)
                    c1 = 1;
                if (c2 == 1)
                    c2 = N_RINGS;
                else if (c2 == N_RINGS)
                    c2 = 1;
                (*iter)[1] = '0' + (char)c1;
                (*iter)[8] = '0' + (char)c2;
            } else {
                args = sscanf((*iter).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    if (c1 == 1)
                        c1 = N_RINGS;
                    else if (c1 == N_RINGS)
                        c1 = 1;
                    (*iter)[2] = '0' + (char)c1;
                } else {
                    args = sscanf((*iter).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        if (c1 == 1)
                            c1 = N_RINGS;
                        else if (c1 == N_RINGS)
                            c1 = 1;
                        (*iter)[1] = '0' + (char)c1;
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
        for (i = 1; i <= N_RINGS; i++) {
            ch1 = board_[i * N_SEATS];
            ch2 = board_[i * N_SEATS + 1];
            for (j = 0; j < N_SEATS - 2; j++) {
                board_[i * N_SEATS + j] = board_[i * N_SEATS + j + 2];
                //updateHash(i * N_SEATS + j);
            }
            board_[i * N_SEATS + 6] = ch1;
            //updateHash(i * N_SEATS + 6);
            board_[i * N_SEATS + 7] = ch2;
            //updateHash(i * N_SEATS + 7);
        }
    } else if (degrees == 6) {
        for (i = 1; i <= N_RINGS; i++) {
            ch1 = board_[i * N_SEATS + 7];
            ch2 = board_[i * N_SEATS + 6];
            for (j = N_SEATS - 1; j >= 2; j--) {
                board_[i * N_SEATS + j] = board_[i * N_SEATS + j - 2];
                //updateHash(i * N_SEATS + j);
            }
            board_[i * N_SEATS + 1] = ch1;
            //updateHash(i * N_SEATS + 1);
            board_[i * N_SEATS] = ch2;
            //updateHash(i * N_SEATS);
        }
    } else if (degrees == 4) {
        for (i = 1; i <= N_RINGS; i++) {
            for (j = 0; j < N_SEATS / 2; j++) {
                ch1 = board_[i * N_SEATS + j];
                board_[i * N_SEATS + j] = board_[i * N_SEATS + j + 4];
                //updateHash(i * N_SEATS + j);
                board_[i * N_SEATS + j + 4] = ch1;
                //updateHash(i * N_SEATS + j + 4);
            }
        }
    } else
        return;

    uint64_t llp1, llp2, llp3;

    if (move_ < 0) {
        i = (-move_) / N_SEATS;
        j = (-move_) % N_SEATS;
        j = (j + N_SEATS - degrees) % N_SEATS;
        move_ = -(i * N_SEATS + j);
    } else {
        llp1 = move_ >> 8;
        llp2 = move_ & 0x00ff;
        i = (int)llp1 / N_SEATS;
        j = (int)llp1 % N_SEATS;
        j = (j + N_SEATS - degrees) % N_SEATS;
        llp1 = i * N_SEATS + j;
        i = (int)llp2 / N_SEATS;
        j = (int)llp2 % N_SEATS;
        j = (j + N_SEATS - degrees) % N_SEATS;
        llp2 = i * N_SEATS + j;
        move_ = (int16_t)((llp1 << 8) | llp2);
    }

    if (currentPos != 0) {
        i = currentPos / N_SEATS;
        j = currentPos % N_SEATS;
        j = (j + N_SEATS - degrees) % N_SEATS;
        currentPos = i * N_SEATS + j;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto mill = context.millList.begin(); mill != context.millList.end(); mill++) {
            llp1 = (*mill & 0x000000ff00000000) >> 32;
            llp2 = (*mill & 0x0000000000ff0000) >> 16;
            llp3 = (*mill & 0x00000000000000ff);

            i = (int)llp1 / N_SEATS;
            j = (int)llp1 % N_SEATS;
            j = (j + N_SEATS - degrees) % N_SEATS;
            llp1 = i * N_SEATS + j;

            i = (int)llp2 / N_SEATS;
            j = (int)llp2 % N_SEATS;
            j = (j + N_SEATS - degrees) % N_SEATS;
            llp2 = i * N_SEATS + j;

            i = (int)llp3 / N_SEATS;
            j = (int)llp3 % N_SEATS;
            j = (j + N_SEATS - degrees) % N_SEATS;
            llp3 = i * N_SEATS + j;

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
            p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
            p2 = (p2 - 1 + N_SEATS - degrees) % N_SEATS;
            cmdline[3] = '1' + (char)p1;
            cmdline[10] = '1' + (char)p2;
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
            if (args >= 2) {
                p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
                cmdline[4] = '1' + (char)p1;
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
                    cmdline[3] = '1' + (char)p1;
                }
            }
        }

        for (auto iter = cmdlist.begin(); iter != cmdlist.end(); iter++) {
            args = sscanf((*iter).c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &c2, &p2, &mm, &ss, &mss);
            if (args >= 4) {
                p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
                p2 = (p2 - 1 + N_SEATS - degrees) % N_SEATS;
                (*iter)[3] = '1' + (char)p1;
                (*iter)[10] = '1' + (char)p2;
            } else {
                args = sscanf((*iter).c_str(), "-(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                if (args >= 2) {
                    p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
                    (*iter)[4] = '1' + (char)p1;
                } else {
                    args = sscanf((*iter).c_str(), "(%1u,%1u) %2u:%2u.%3u", &c1, &p1, &mm, &ss, &mss);
                    if (args >= 2) {
                        p1 = (p1 - 1 + N_SEATS - degrees) % N_SEATS;
                        (*iter)[3] = '1' + (char)p1;
                    }
                }
            }
        }
    }
}

#if ((defined HASH_MAP_ENABLE) || (defined BOOK_LEARNING) || (defined THREEFOLD_REPETITION))

#if 0
/*
 * 原始版本 hash 各数据位详解（名为 hash 但实际并无冲突，是算法用到的棋局数据的完全表示）[因效率问题废弃]
 * 56-63位：空白不用，全为0
 * 55位：轮流标识，0为先手，1为后手
 * 54位：动作标识，落子（选子移动）为0，1为去子
 * 6-53位（共48位）：从棋盘第一个位置点到最后一个位置点的棋子，每个点用2个二进制位表示，共24个位置点，即48位。
 *        0b00表示空白，0b01表示先手棋子，0b10表示后手棋子，0b11表示禁点
 * 4-5位（共2位）：待去子数，最大为3，用2个二进制位表示即可
 * 0-3位：player1的手棋数，不需要player2的（可计算出）
 */
#endif

/*
 * 新版本 hash 各数据位详解
 * 8-63位 (共56位): zobrist 值
 * TODO: 低8位浪费了哈希空间，待后续优化
 * 4-7位 (共4位)：player1的手棋数，不需要player2的（可计算出）, 走子阶段置为全1即为全15
 * 2-3位（共2位）：待去子数，最大为3，用2个二进制位表示即可
 * 1位: 动作标识，落子（选子移动）为0，1为去子
 * 0位：轮流标识，0为先手，1为后手
 */

void NineChess::constructHash()
{
    context.hash = 0ull;

#include "zobrist.h"
    memcpy(context.zobrist, zobrist0, sizeof(uint64_t) * NineChess::N_POINTS * NineChess::POINT_TYPE_COUNT);

#if 0
    // 预留末8位后续填充局面特征标志
    for (int p = 0; p < N_POINTS; p++) {
        //qDebug("{\n");
        for (int t = NineChess::POINT_TYPE_EMPTY; t <= NineChess::POINT_TYPE_FORBIDDEN; t++) {
            context.zobrist[p][t] = rand56();
            //qDebug("%llX, ", context.zobrist[p][t]);
        }
        //qDebug("},\n");
    }      
#endif
}

uint64_t NineChess::getHash()
{
    // TODO: 每次获取哈希值时更新 hash 值低8位，放在此处调用不优雅
    updateHashMisc();

    return context.hash;
}

uint64_t NineChess::updateHash(int pos)
{
    // PieceType is board_[pos]

    // 0b00 表示空白，0b01 = 1 表示先手棋子，0b10 = 2 表示后手棋子，0b11 = 3 表示禁点
    int pointType = (board_[pos] & 0x30) >> 4;

    // 清除或者放置棋子
    context.hash ^= context.zobrist[pos][pointType];

    return context.hash;
}

uint64_t NineChess::revertHash(int pos)
{
    return updateHash(pos);
}

uint64_t NineChess::updateHashMisc()
{
    // 清除标记位
    context.hash &= ~0xFF;

    // 置位

    if (context.turn == PLAYER2) {
        context.hash |= 1ULL;
    }

    if (context.action == ACTION_CAPTURE) {
        context.hash |= 1ULL << 1;
    }

    context.hash |= (uint64_t)context.nPiecesNeedRemove << 2;
    context.hash |= (uint64_t)context.nPiecesInHand_1 << 4;     // TODO: 或许换 game.stage 也可以？

    return context.hash;
}
#endif /* HASH_MAP_ENABLE etc. */

