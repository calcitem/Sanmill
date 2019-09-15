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

#include <algorithm>
#include "position.h"
#include "search.h"
#include "movegen.h"
#include "player.h"
#include "zobrist.h"

Game::Game()
{
    // 单独提出 boardLocations 等数据，免得每次都写 boardLocations;
    boardLocations = position.board.locations;

    // 创建哈希数据
    constructHash();

#ifdef BOOK_LEARNING
    // TODO: 开局库文件被加载了多次
    MillGameAi_ab::loadOpeningBookFileToHashMap();
#endif

    // 默认选择第1号规则，即“打三棋”
    setContext(&RULES[1]);

    // 比分归零
    score[1] = score[2] = score_draw = 0;
}

Game::~Game() = default;

Game::Game(const Game &game)
{  
    *this = game;
}

Game &Game::operator= (const Game &game)
{
    if (this == &game)
        return *this;

    currentRule = game.currentRule;
    position = game.position;
    currentStep = game.currentStep;
    moveStep = game.moveStep;
    isRandomMove = game.isRandomMove;
    giveUpIfMostLose_ = game.giveUpIfMostLose_;
    boardLocations = position.board.locations;
    currentLocation = game.currentLocation;
    winner = game.winner;
    startTime = game.startTime;
    currentTime = game.currentTime;
    elapsedSeconds[1] = game.elapsedSeconds[1];
    elapsedSeconds[2] = game.elapsedSeconds[2];
    move_ = game.move_;
    memcpy(cmdline, game.cmdline, sizeof(cmdline));
    cmdlist = game.cmdlist;
    tips = game.tips;

    return *this;
}

// 设置配置
bool Game::configure(bool giveUpIfMostLose, bool randomMove)
{
    // 设置是否必败时认输
    this->giveUpIfMostLose_ = giveUpIfMostLose;

    // 设置是否随机走子
    this->isRandomMove = randomMove;

    return true;
}

// 设置棋局状态和棋盘数据，用于初始化
bool Game::setContext(const struct Rule *rule, step_t maxStepsLedToDraw, int maxTimeLedToLose,
                          step_t initialStep,
                          phase_t phase, player_t turn, action_t action,
                          const char *locations,
                          int nPiecesInHand_1, int nPiecesInHand_2, int nPiecesNeedRemove)
{
    // 有效性判断
    if (maxTimeLedToLose < 0) {
        return false;
    }

    // 根据规则
    this->currentRule = *rule;
    this->currentRule.maxStepsLedToDraw = maxStepsLedToDraw;
    this->currentRule.maxTimeLedToLose = maxTimeLedToLose;

    // 设置棋局数据

    // 设置步数
    this->currentStep = initialStep;
    this->moveStep = initialStep;

    // 局面阶段标识
    position.phase = phase;

    // 轮流状态标识
    setTurn(turn);

    // 动作状态标识
    position.action = action;

    // 当前棋局（3×8）
    if (locations == nullptr) {
        memset(boardLocations, 0, sizeof(position.board.locations));
        position.hash = 0;
    } else {
        memcpy(boardLocations, locations, sizeof(position.board.locations));
    }

    // 计算盘面子数
    // 棋局，抽象为一个（5×8）的数组，上下两行留空
    /*
        0x00 代表无棋子
        0x0F 代表禁点
        0x11～0x1C 代表先手第 1～12 子
        0x21～0x2C 代表后手第 1～12 子
        判断棋子是先手的用 (locations[i] & 0x10)
        判断棋子是后手的用 (locations[i] & 0x20)
     */
    position.nPiecesOnBoard[1] = position.nPiecesOnBoard[2] = 0;

    for (int r = 1; r < Board::N_RINGS + 2; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            int location = r * Board::N_SEATS + s;
            if (boardLocations[location] & 0x10) {
                position.nPiecesOnBoard[1]++;
            } else if (boardLocations[location] & 0x20) {
                position.nPiecesOnBoard[2]++;
            } else if (boardLocations[location] & 0x0F) {
                // 不计算盘面子数
            }
        }
    }

    // 设置玩家盘面剩余子数和未放置子数
    if (position.nPiecesOnBoard[1] > rule->nTotalPiecesEachSide ||
        position.nPiecesOnBoard[2] > rule->nTotalPiecesEachSide) {
        return false;
    }

    if (nPiecesInHand_1 < 0 || nPiecesInHand_2 < 0) {
        return false;
    }

    position.nPiecesInHand[1] = rule->nTotalPiecesEachSide - position.nPiecesOnBoard[1];
    position.nPiecesInHand[2] = rule->nTotalPiecesEachSide - position.nPiecesOnBoard[2];
    position.nPiecesInHand[1] = std::min(nPiecesInHand_1, position.nPiecesInHand[1]);
    position.nPiecesInHand[2] = std::min(nPiecesInHand_2, position.nPiecesInHand[2]);

    // 设置去子状态时的剩余尚待去除子数
    if (action == ACTION_CAPTURE) {
        if (0 <= nPiecesNeedRemove && nPiecesNeedRemove < 3) {
            position.nPiecesNeedRemove = nPiecesNeedRemove;
        }
    } else {
        position.nPiecesNeedRemove = 0;
    }

    // 清空成三记录
    if (!position.board.millList.empty()) {
        position.board.millList.clear();
    }

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 生成着法表
    MoveList::createMoveTable(*this);

    // 生成成三表
    position.board.createMillTable(currentRule);

    // 不选中棋子
    currentLocation = 0;

    // 用时置零
    elapsedSeconds[1] = elapsedSeconds[2] = 0;

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
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';
    return false;
}

bool Game::reset()
{
    if (position.phase == PHASE_NOTSTARTED &&
        elapsedSeconds[1] == elapsedSeconds[2] == 0) {
        return true;
    }

    // 步数归零
    currentStep = 0;
    moveStep = 0;

    // 局面阶段标识
    position.phase = PHASE_NOTSTARTED;

    // 设置轮流状态
    setTurn(PLAYER_1);

    // 动作状态标识
    position.action = ACTION_PLACE;

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 当前棋局（3×8）
    memset(boardLocations, 0, sizeof(position.board));

    // 盘面子数归零
    position.nPiecesOnBoard[1] = position.nPiecesOnBoard[2] = 0;

    // 设置玩家盘面剩余子数和未放置子数
    position.nPiecesInHand[1] = position.nPiecesInHand[2] = currentRule.nTotalPiecesEachSide;

    // 设置去子状态时的剩余尚待去除子数
    position.nPiecesNeedRemove = 0;

    // 清空成三记录
    if (!position.board.millList.empty()) {
        position.board.millList.clear();
    }    

    // 不选中棋子
    currentLocation = 0;

    // 用时置零
    elapsedSeconds[1] = elapsedSeconds[2] = 0;

    // 哈希归零
    position.hash = 0;

    // 提示
    setTips();

    // 计棋谱
    cmdlist.clear();

    int i;

    for (i = 0; i < N_RULES; i++) {
        if (strcmp(this->currentRule.name, RULES[i].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u",
                i + 1, currentRule.maxStepsLedToDraw, currentRule.maxTimeLedToLose) > 0) {
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';

    return false;
}

bool Game::start()
{
    switch (position.phase) {
    // 如果游戏已经开始，则返回false
    case PHASE_PLACING:
    case PHASE_MOVING:
        return false;
    // 如果游戏结束，则重置游戏，进入未开始状态
    case PHASE_GAMEOVER:
        reset();
        [[fallthrough]];
    // 如果游戏处于未开始状态
    case PHASE_NOTSTARTED:
        // 启动计时器
        startTime = time(NULL);
        // 进入开局状态
        position.phase = PHASE_PLACING;
        return true;
    default:
        return false;
    }
}

bool Game::place(int location, int time_p, int8_t rs)
{
    // 如果局面为“结局”，返回false
    if (position.phase == PHASE_GAMEOVER)
        return false;

    // 如果局面为“未开局”，则开局
    if (position.phase == PHASE_NOTSTARTED)
        start();

    // 如非“落子”状态，返回false
    if (position.action != ACTION_PLACE)
        return false;

    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!position.board.onBoard[location] || boardLocations[location])
        return false;

    // 格式转换
    int r = 0;
    int s = 0;
    position.board.locationToPolar(location, r, s);

    // 时间的临时变量
    int player_ms = -1;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;

    if (position.phase == PHASE_PLACING) {
        int playerId = Player::toId(position.turn);
        piece = (0x01 | position.turn) + currentRule.nTotalPiecesEachSide - position.nPiecesInHand[playerId];
        position.nPiecesInHand[playerId]--;
        position.nPiecesOnBoard[playerId]++;

        boardLocations[location] = piece;

        updateHash(location);

        move_ = static_cast<move_t>(location);

        if (rs) {
            player_ms = update(time_p);
            sprintf(cmdline, "(%1u,%1u) %02u:%02u",
                    r, s, player_ms / 60, player_ms % 60);
            cmdlist.emplace_back(string(cmdline));
            currentStep++;
        }

        currentLocation = location;

        n = position.board.addMills(currentRule, currentLocation);

        // 开局阶段未成三
        if (n == 0) {
            // 如果双方都无未放置的棋子
            if (position.nPiecesInHand[1] == 0 && position.nPiecesInHand[2] == 0) {
                // 进入中局阶段
                position.phase = PHASE_MOVING;

                // 进入选子状态
                position.action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenLocations();

                // 设置轮到谁走
                if (currentRule.isDefenderMoveFirst) {
                    setTurn(PLAYER_2);
                } else {
                    setTurn(PLAYER_1);
                }

                // 再决胜负
                if (win()) {
                    goto out;
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
            position.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            position.action = ACTION_CAPTURE;
        }

        goto out;
    }

    // 如果决出胜负
    if (win()) {
        goto out;
    }

    // 对于中局落子 (ontext.phase == GAME_MOVING)

    // 如果落子不合法
    if (position.nPiecesOnBoard[position.turnId] > currentRule.nPiecesAtLeast ||
        !currentRule.allowFlyWhenRemainThreePieces) {
        int i;
        for (i = 0; i < 4; i++) {
            if (location == MoveList::moveTable[currentLocation][i])
                break;
        }

        // 不在着法表中
        if (i == 4) {
            return false;
        }
    }

    // 移子
    move_ = static_cast<move_t>((currentLocation << 8) + location);

    if (rs) {
        player_ms = update(time_p);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u", currentLocation / Board::N_SEATS, currentLocation % Board::N_SEATS + 1,
                r, s, player_ms / 60, player_ms % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep++;
    }

    boardLocations[location] = boardLocations[currentLocation];

    updateHash(location);

    boardLocations[currentLocation] = '\x00';

    revertHash(currentLocation);

    currentLocation = location;
    n = position.board.addMills(currentRule, currentLocation);

    // 中局阶段未成三
    if (n == 0) {
        // 进入选子状态
        position.action = ACTION_CHOOSE;

        // 设置轮到谁走
        changeTurn();

        // 如果决出胜负
        if (win()) {
            goto out;
        }
    }
    // 中局阶段成三
    else {
        // 设置去子数目
        position.nPiecesNeedRemove = currentRule.allowRemoveMultiPieces ? n : 1;

        // 进入去子状态
        position.action = ACTION_CAPTURE;
    }

out:
    if (rs) {
        setTips();
    }

    return true;
}

bool Game::_place(int r, int s, int time_p)
{
    // 转换为 location
    int location = position.board.polarToLocation(r, s);

    return place(location, time_p, true);
}

bool Game::_capture(int r, int s, int time_p)
{
    // 转换为 location
    int location = position.board.polarToLocation(r, s);

    return capture(location, time_p, 1);
}

bool Game::capture(int location, int time_p, int8_t cp)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (position.phase == PHASE_NOTSTARTED || position.phase == PHASE_GAMEOVER)
        return false;

    // 如非“去子”状态，返回false
    if (position.action != ACTION_CAPTURE)
        return false;

    // 如果去子完成，返回false
    if (position.nPiecesNeedRemove <= 0)
        return false;

    // 格式转换
    int r = 0;
    int s = 0;
    position.board.locationToPolar(location, r, s);

    // 时间的临时变量
    int player_ms = -1;

    player_t opponent = Player::getOpponent(position.turn);

    // 判断去子是不是对手棋
    if (!(opponent & boardLocations[location]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (!currentRule.allowRemoveMill &&
        position.board.inHowManyMills(location) &&
        !position.board.isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (currentRule.hasForbiddenLocations && position.phase == PHASE_PLACING) {
        revertHash(location);
        boardLocations[location] = '\x0f';
        updateHash(location);
    } else { // 去子
        revertHash(location);
        boardLocations[location] = '\x00';
    }

    position.nPiecesOnBoard[position.opponentId]--;

    move_ = static_cast<move_t>(-location);

    if (cp) {
        player_ms = update(time_p);
        sprintf(cmdline, "-(%1u,%1u)  %02u:%02u", r, s, player_ms / 60, player_ms % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep = 0;
    }

    currentLocation = 0;
    position.nPiecesNeedRemove--;
    updateHash(location);

    // 去子完成

    // 如果决出胜负
    if (win()) {
        goto out;
    }

    // 还有其余的子要去吗
    if (position.nPiecesNeedRemove > 0) {
        // 继续去子
        return true;
    }

    // 所有去子都完成了

    // 开局阶段
    if (position.phase == PHASE_PLACING) {
        // 如果双方都无未放置的棋子
        if (position.nPiecesInHand[1] == 0 && position.nPiecesInHand[2] == 0) {

            // 进入中局阶段
            position.phase = PHASE_MOVING;

            // 进入选子状态
            position.action = ACTION_CHOOSE;

            // 清除禁点
            cleanForbiddenLocations();

            // 设置轮到谁走
            if (currentRule.isDefenderMoveFirst) {
                setTurn(PLAYER_2);
            } else {
                setTurn(PLAYER_1);
            }

            // 再决胜负
            if (win()) {
                goto out;
            }
        }
        // 如果双方还有子
        else {
            // 进入落子状态
            position.action = ACTION_PLACE;

            // 设置轮到谁走
            changeTurn();

            // 如果决出胜负
            if (win()) {
                goto out;
            }
        }
    }
    // 中局阶段
    else {
        // 进入选子状态
        position.action = ACTION_CHOOSE;

        // 设置轮到谁走
        changeTurn();

        // 如果决出胜负
        if (win()) {
            goto out;
        }
    }

out:
    if (cp) {
        setTips();
    }

    return true;
}

bool Game::choose(int location)
{
    // 如果局面不是"中局”，返回false
    if (position.phase != PHASE_MOVING)
        return false;

    // 如非“选子”或“落子”状态，返回false
    if (position.action != ACTION_CHOOSE && position.action != ACTION_PLACE)
        return false;

    // 判断选子是否可选
    if (boardLocations[location] & position.turn) {
        // 判断location处的棋子是否被“闷”
        if (position.board.isSurrounded(position.turnId, currentRule, position.nPiecesOnBoard, location)) {
            return false;
        }

        // 选子
        currentLocation = location;

        // 选子完成，进入落子状态
        position.action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool Game::choose(int r, int s)
{
    return choose(position.board.polarToLocation(r, s));
}

bool Game::giveup(player_t loser)
{
    if (position.phase == PHASE_NOTSTARTED ||
        position.phase == PHASE_GAMEOVER ||
        position.phase == PHASE_NONE) {
        return false;
    }

    position.phase = PHASE_GAMEOVER;

    int loserId = Player::toId(loser);
    char loserCh = Player::idToCh(loserId);
    string loserStr = Player::chToStr(loserCh);

    winner = Player::getOpponent(loser);
    tips = "玩家" + loserStr + "投子认负";
    sprintf(cmdline, "Player%d give up!", loserId);
    score[Player::toId(winner)]++;

    cmdlist.emplace_back(string(cmdline));

    return true;
}

// 打算用个C++的命令行解析库的，简单的没必要，但中文编码有极小概率出问题
bool Game::command(const char *cmd)
{
    int r;
    unsigned t;
    step_t s;
    int r1, s1, r2, s2;
    int args = 0;
    int mm = 0, ss = 0;
    int tm = -1;

    // 设置规则
    if (sscanf(cmd, "r%1u s%3hd t%2u", &r, &s, &t) == 3) {
        if (r <= 0 || r > N_RULES) {
            return false;
        }

        return setContext(&RULES[r - 1], s, t);
    }

    // 选子移动
    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);

    if (args >= 4) {
        if (args == 7) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }

        if (choose(r1, s1)) {
            return _place(r2, s2, tm);
        }

        return false;
    }

    // 去子
    args = sscanf(cmd, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _capture(r1, s1, tm);
    }

    // 落子
    args = sscanf(cmd, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _place(r1, s1, tm);
    }

    // 认输
    args = sscanf(cmd, "Player%1u give up!", &t);

    if (args == 1) {
        return giveup(Player::idToPlayer(t));
    }

#ifdef THREEFOLD_REPETITION
    if (!strcmp(cmd, "Threefold Repetition. Draw!")) {
        return true;
    }

    if (!strcmp(cmd, "draw")) {
        position.phase = PHASE_GAMEOVER;
        winner = PLAYER_DRAW;
        score_draw++;
        tips = "三次重复局面判和。";
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }
#endif /* THREEFOLD_REPETITION */

    return false;
}

bool Game::command(int move)
{
    if (move < 0) {
        return capture(-move);
    }

    if (move & 0x1f00) {
        if (choose(move >> 8)) {
            return place(move & 0x00ff);
        }
    } else {
        return place(move & 0x00ff);
    }

    return false;
}

inline int Game::update(int time_p /*= -1*/)
{
    int ret = -1;
    time_t *player_ms = &elapsedSeconds[position.turnId];
    time_t playerNext_ms = elapsedSeconds[position.opponentId];

    // 根据局面调整计时器

    if (!(position.phase == PHASE_PLACING || position.phase == PHASE_MOVING)) {
        return -1;
    }

    currentTime = time(NULL);

    // 更新时间
    if (time_p >= *player_ms) {
        *player_ms = ret = time_p;
        startTime = currentTime - (elapsedSeconds[1] + elapsedSeconds[2]);
    } else {
        *player_ms = ret = currentTime - startTime - playerNext_ms;
    }

    // 有限时要求则判断胜负
    if (currentRule.maxTimeLedToLose > 0) {
        win();
    }

    return ret;
}

// 是否分出胜负
bool Game::win()
{
    return win(false);
}

// 是否分出胜负
bool Game::win(bool forceDraw)
{
    if (position.phase == PHASE_GAMEOVER) {
        return true;
    }

    if (position.phase == PHASE_NOTSTARTED) {
        return false;
    }

    // 如果有时间限定
    if (currentRule.maxTimeLedToLose > 0) {
        position.phase = PHASE_GAMEOVER;

        // 这里不能update更新时间，否则会形成循环嵌套
        for (int i = 1; i <= 2; i++)
        {
            if (elapsedSeconds[i] > currentRule.maxTimeLedToLose * 60) {
                elapsedSeconds[i] = currentRule.maxTimeLedToLose * 60;
                winner = Player::idToPlayer(Player::getOpponentById(i));
                tips = "玩家" + Player::chToStr(Player::idToCh(i)) + "超时判负。";
                sprintf(cmdline, "Time over. Player%d win!", Player::getOpponentById(i));
            }
        }

        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    // 如果有步数限定
    if (currentRule.maxStepsLedToDraw > 0 &&
        moveStep > currentRule.maxStepsLedToDraw) {
        winner = PLAYER_DRAW;
        position.phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Steps over. In draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    // 如果玩家子数小于赛点，则对方获胜
    for (int i = 1; i <= 2; i++)
    {
        if (position.nPiecesOnBoard[i] + position.nPiecesInHand[i] < currentRule.nPiecesAtLeast) {
            int o = Player::getOpponentById(i);
            winner = Player::idToPlayer(o);
            position.phase = PHASE_GAMEOVER;
            sprintf(cmdline, "Player%d win!", o);
            cmdlist.emplace_back(string(cmdline));
#ifdef BOOK_LEARNING
            MillGameAi_ab::recordOpeningBookToHashMap();  // TODO: 目前是对"双方"失败都记录到开局库
#endif /* BOOK_LEARNING */

            return true;
        }
    }

    // 如果摆满了，根据规则判断胜负
    if (position.nPiecesOnBoard[1] + position.nPiecesOnBoard[2] >= Board::N_SEATS * Board::N_RINGS) {
        position.phase = PHASE_GAMEOVER;

        if (currentRule.isStartingPlayerLoseWhenBoardFull) {
            winner = PLAYER_2;
            sprintf(cmdline, "Player2 win!");
        } else {
            winner = PLAYER_DRAW;  
            sprintf(cmdline, "Full. In draw!");
        }

        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    // 如果中局被“闷”
    if (position.phase == PHASE_MOVING && position.action == ACTION_CHOOSE && position.board.isAllSurrounded(position.turn, currentRule, position.nPiecesOnBoard, position.turn)) {
        // 规则要求被“闷”判负，则对手获胜
        position.phase = PHASE_GAMEOVER;

        if (currentRule.isLoseWhenNoWay) {
            tips = "玩家" + Player::chToStr(position.turnChar) + "无子可走被闷";
            winner = Player::getOpponent(position.turn);
            int winnerId = Player::toId(winner);
            sprintf(cmdline, "Player%d no way to go. Player%d win!", position.turnId, winnerId);
            cmdlist.emplace_back(string(cmdline));
#ifdef BOOK_LEARNING
            MillGameAi_ab::recordOpeningBookToHashMap();  // TODO: 目前是对所有的失败记录到开局库
#endif /* BOOK_LEARNING */

            return true;
        }

        // 否则让棋，由对手走
        changeTurn();

        return false;
    }

#ifdef THREEFOLD_REPETITION
    if (forceDraw)
    {
        tips = "重复三次局面和棋！";
        winner = PLAYER_DRAW;
        position.phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }
#endif

    return false;
}

// 计算玩家1和玩家2的棋子活动能力之差
int Game::getMobilityDiff(enum player_t turn, const Rule &rule, int nPiecesOnBoard[], bool includeFobidden)
{
    int *locations = boardLocations;
    int mobility1 = 0;
    int mobility2 = 0;
    int diff = 0;
    int n = 0;

    for (int i = Board::LOCATION_BEGIN; i < Board::LOCATION_END; i++) {
        n = position.board.getSurroundedEmptyLocationCount(turn, rule, nPiecesOnBoard, i, includeFobidden);

        if (locations[i] & 0x10) {
            mobility1 += n;
        } else if (locations[i] & 0x20) {
            mobility2 += n;
        }
    }

    diff = mobility1 - mobility2;

    return diff;
}

void Game::cleanForbiddenLocations()
{
    int location = 0;

    for (int r = 1; r <= Board::N_RINGS; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            location = r * Board::N_SEATS + s;

            if (boardLocations[location] == '\x0f') {
                revertHash(location);
                boardLocations[location] = '\x00';
            }
        }
    }
}

void Game::setTurn(player_t player)
{
    // 设置轮到谁走
    position.turn = player;

    position.turnId = Player::toId(position.turn);
    position.turnChar = Player::idToCh(position.turnId);
    //context.turnStr = Player::chToStr(context.turnChar);

    position.opponent = Player::getOpponent(player);

    position.opponentId = Player::toId(position.opponent);
    position.opponentChar = Player::idToCh(position.opponentId);
    //context.opponentStr = Player::chToStr(context.opponentChar);
}

void Game::changeTurn()
{
    setTurn(Player::getOpponent(position.turn));
}

void Game::setTips()
{
    string winnerStr, t;
    int winnerId;
    string turnStr = Player::chToStr(position.turnChar);

    switch (position.phase) {
    case PHASE_NOTSTARTED:
        tips = "轮到玩家1落子，剩余" + std::to_string(position.nPiecesInHand[1]) + "子" +
            "  比分 " + to_string(score[1]) + ":" + to_string(score[2]) + ", 和棋 " + to_string(score_draw);
        break;

    case PHASE_PLACING:
        if (position.action == ACTION_PLACE) {
            tips = "轮到玩家" + turnStr + "落子，剩余" + std::to_string(position.nPiecesInHand[position.turnId]) + "子";
        } else if (position.action == ACTION_CAPTURE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(position.nPiecesNeedRemove) + "子";
        }
        break;

    case PHASE_MOVING:
        if (position.action == ACTION_PLACE || position.action == ACTION_CHOOSE) {
            tips = "轮到玩家" + turnStr + "选子移动";
        } else if (position.action == ACTION_CAPTURE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(position.nPiecesNeedRemove) + "子";
        }
        break;

    case PHASE_GAMEOVER:  
        if (winner == PLAYER_DRAW) {
            score_draw++;
            tips = "双方平局！比分 " + to_string(score[1]) + ":" + to_string(score[2]) + ", 和棋 " + to_string(score_draw); 
            break;
        }

        winnerId = Player::toId(winner);
        winnerStr = Player::chToStr(Player::idToCh(winnerId));

        score[winnerId]++;

        t = "玩家" + winnerStr + "获胜！比分 " + to_string(score[1]) + ":" + to_string(score[2]) + ", 和棋 " + to_string(score_draw);

        if (tips.find("无子可走") != string::npos) {
            tips += t;
        } else {
            tips = t;
        }

        break;

    default:
        break;
    }
}

void Game::getElapsedTime(time_t &p1_ms, time_t &p2_ms)
{
    update();

    p1_ms = elapsedSeconds[1];
    p2_ms = elapsedSeconds[2];
}

/*
 * hash 各数据位详解
 * 8-63位 (共56位): zobrist 值
 * TODO: 低8位浪费了哈希空间，待后续优化
 * 4-7位 (共4位)：player1的手棋数，不需要player2的（可计算出）, 走子阶段置为全1即为全15
 * 2-3位（共2位）：待去子数，最大为3，用2个二进制位表示即可
 * 1位: 动作标识，落子（选子移动）为0，1为去子
 * 0位：轮流标识，0为先手，1为后手
 */

void Game::constructHash()
{
    position.hash = 0;
}

hash_t Game::getHash()
{
    // TODO: 每次获取哈希值时更新 hash 值低8位，放在此处调用不优雅
    updateHashMisc();

    return position.hash;
}

hash_t Game::updateHash(int location)
{
    // PieceType is boardLocations[location] 

    // 0b00 表示空白，0b01 = 1 表示先手棋子，0b10 = 2 表示后手棋子，0b11 = 3 表示禁点
    int pieceType = (boardLocations[location] & 0x30) >> 4;

    // 清除或者放置棋子
    position.hash ^= zobrist[location][pieceType];

    return position.hash;
}

hash_t Game::revertHash(int location)
{
    return updateHash(location);
}

hash_t Game::updateHashMisc()
{
    // 清除标记位
    position.hash &= static_cast<hash_t>(~0xFF);

    // 置位

    if (position.turn == PLAYER_2) {
        position.hash |= 1U;
    }

    if (position.action == ACTION_CAPTURE) {
        position.hash |= 1U << 1;
    }

    position.hash |= static_cast<hash_t>(position.nPiecesNeedRemove) << 2;
    position.hash |= static_cast<hash_t>(position.nPiecesInHand[1]) << 4;     // TODO: 或许换 position.phase 也可以？

    return position.hash;
}
