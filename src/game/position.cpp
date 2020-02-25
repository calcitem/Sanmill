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

#include <algorithm>
#include "position.h"
#include "search.h"
#include "movegen.h"
#include "player.h"
#include "option.h"
#include "zobrist.h"

Game::Game()
{
    if (position != nullptr) {
        delete position;
    }

    position = new Position();
    //memset(position, 0, sizeof(Position));

    // 单独提出 boardLocations 等数据，免得每次都写 boardLocations;
    boardLocations = position->board.locations;

    // 创建哈希数据
    constructHash();

    // 默认规则
    setPosition(&RULES[DEFAULT_RULE_NUMBER]);

    // 比分归零
    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;

    //tips.reserve(1024);
    cmdlist.reserve(256);
}

Game::~Game()
{
    if (position != nullptr) {
        delete position;
        position = nullptr;
    }

    cmdlist.clear();
}

Game::Game(const Game &game)
{  
    if (position != nullptr) {
        delete position;
        position = nullptr;
    }
    
    position = new Position();

    *this = game;
}

Game::Game(Game &game)
{
    if (position != nullptr) {
        delete position;
        position = nullptr;
    }

    position = new Position();

    *this = game;
}

Game &Game::operator= (const Game &game)
{
    memcpy(position, game.position, sizeof(Position));
    currentStep = game.currentStep;
    moveStep = game.moveStep;
    boardLocations = position->board.locations;
    currentSquare = game.currentSquare;
    winner = game.winner;
    startTime = game.startTime;
    currentTime = game.currentTime;
    elapsedSeconds[BLACK] = game.elapsedSeconds[BLACK];
    elapsedSeconds[WHITE] = game.elapsedSeconds[WHITE];
    move = game.move;
    memcpy(cmdline, game.cmdline, sizeof(cmdline));
    cmdlist = game.cmdlist;
    tips = game.tips;

    return *this;
}

Game &Game::operator= (Game &game)
{
    memcpy(position, game.position, sizeof(Position));
    currentStep = game.currentStep;
    moveStep = game.moveStep;
    boardLocations = position->board.locations;
    currentSquare = game.currentSquare;
    winner = game.winner;
    startTime = game.startTime;
    currentTime = game.currentTime;
    elapsedSeconds[BLACK] = game.elapsedSeconds[BLACK];
    elapsedSeconds[WHITE] = game.elapsedSeconds[WHITE];
    move = game.move;
    memcpy(cmdline, game.cmdline, sizeof(cmdline));
    cmdlist = game.cmdlist;
    tips = game.tips;

    return *this;
}

int Game::countPiecesOnBoard()
{
    position->nPiecesOnBoard[BLACK] = position->nPiecesOnBoard[WHITE] = 0;

    for (int r = 1; r < Board::N_RINGS + 2; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            square_t square = static_cast<square_t>(r * Board::N_SEATS + s);
            if (boardLocations[square] & PIECE_BLACK) {
                position->nPiecesOnBoard[BLACK]++;
            } else if (boardLocations[square] & PIECE_WHITE) {
                position->nPiecesOnBoard[WHITE]++;
            }
#if 0
            else if (boardLocations[square] & PIECE_FORBIDDEN) {
                // 不计算盘面子数
            }
#endif
        }
    }

    // 设置玩家盘面剩余子数和未放置子数
    if (position->nPiecesOnBoard[BLACK] > rule.nTotalPiecesEachSide ||
        position->nPiecesOnBoard[WHITE] > rule.nTotalPiecesEachSide) {
        return -1;
    }

    return position->nPiecesOnBoard[BLACK] + position->nPiecesOnBoard[WHITE];
}

int Game::countPiecesInHand()
{
    position->nPiecesInHand[BLACK] = rule.nTotalPiecesEachSide - position->nPiecesOnBoard[BLACK];
    position->nPiecesInHand[WHITE] = rule.nTotalPiecesEachSide - position->nPiecesOnBoard[WHITE];

    return position->nPiecesInHand[BLACK] + position->nPiecesInHand[WHITE];
}

// 设置棋局状态和棋盘数据，用于初始化
bool Game::setPosition(const struct Rule *newRule,
                       step_t initialStep,
                       phase_t phase, player_t side, action_t action,
                       const char *locations,
                       int nPiecesNeedRemove)
{
    // 根据规则
    rule = *newRule;

    // 设置棋局数据

    // 设置步数
    this->currentStep = initialStep;
    this->moveStep = initialStep;

    // 局面阶段标识
    position->phase = phase;

    // 轮流状态标识
    setSideToMove(side);

    // 动作状态标识
    position->action = action;

    // 当前棋局（3×8）
    if (locations == nullptr) {
        memset(boardLocations, 0, sizeof(position->board.locations));
        position->hash = 0;
    } else {
        memcpy(boardLocations, locations, sizeof(position->board.locations));
    }

    if (countPiecesOnBoard() == -1) {
        return false;
    }

    countPiecesInHand();

    // 设置去子状态时的剩余尚待去除子数
    if (action == ACTION_CAPTURE) {
        if (0 <= nPiecesNeedRemove && nPiecesNeedRemove < 3) {
            position->nPiecesNeedRemove = nPiecesNeedRemove;
        }
    } else {
        position->nPiecesNeedRemove = 0;
    }

    // 清空成三记录
    position->board.millListSize = 0;

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 生成着法表
    MoveList::create();

    // 生成成三表
    position->board.createMillTable();

    // 不选中棋子
    currentSquare = SQ_0;

    // 用时置零
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

    // 提示
    setTips();

    // 计棋谱
    cmdlist.clear();

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(rule.name, RULES[r].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u", r + 1, rule.maxStepsLedToDraw, rule.maxTimeLedToLose) > 0) {
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';
    return false;
}

bool Game::reset()
{
    if (position->phase == PHASE_READY &&
        elapsedSeconds[BLACK] == elapsedSeconds[WHITE] == 0) {
        return true;
    }

    // 步数归零
    currentStep = 0;
    moveStep = 0;

    // 局面阶段标识
    position->phase = PHASE_READY;

    // 设置轮流状态
    setSideToMove(PLAYER_BLACK);

    // 动作状态标识
    position->action = ACTION_PLACE;

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 当前棋局（3×8）
    memset(boardLocations, 0, sizeof(position->board));

    // 盘面子数归零
    position->nPiecesOnBoard[BLACK] = position->nPiecesOnBoard[WHITE] = 0;

    // 设置玩家盘面剩余子数和未放置子数
    position->nPiecesInHand[BLACK] = position->nPiecesInHand[WHITE] = rule.nTotalPiecesEachSide;

    // 设置去子状态时的剩余尚待去除子数
    position->nPiecesNeedRemove = 0;

    // 清空成三记录
    position->board.millListSize = 0;

    // 不选中棋子
    currentSquare = SQ_0;

    // 用时置零
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

    // 哈希归零
    position->hash = 0;

    // 提示
    setTips();

    // 计棋谱
    cmdlist.clear();

#ifdef ENDGAME_LEARNING
    if (gameOptions.getLearnEndgameEnabled() && nPlayed != 0 && nPlayed % 256 == 0) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    int i;

    for (i = 0; i < N_RULES; i++) {
        if (strcmp(rule.name, RULES[i].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u",
                i + 1, rule.maxStepsLedToDraw, rule.maxTimeLedToLose) > 0) {
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';

    return false;
}

bool Game::start()
{
    switch (position->phase) {
    // 如果游戏已经开始，则返回false
    case PHASE_PLACING:
    case PHASE_MOVING:
        return false;
    // 如果游戏结束，则重置游戏，进入未开始状态
    case PHASE_GAMEOVER:
        reset();
        [[fallthrough]];
    // 如果游戏处于未开始状态
    case PHASE_READY:
        // 启动计时器
        startTime = time(NULL);
        // 进入开局状态
        position->phase = PHASE_PLACING;
        return true;
    default:
        return false;
    }
}

bool Game::place(square_t square, int8_t updateCmdlist)
{
    // 如果局面为“结局”，返回false
    if (position->phase == PHASE_GAMEOVER)
        return false;

    // 如果局面为“未开局”，则开局
    if (position->phase == PHASE_READY)
        start();

    // 如非“落子”状态，返回false
    if (position->action != ACTION_PLACE)
        return false;

    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!position->board.onBoard[square] || boardLocations[square])
        return false;

    // 格式转换
    int r = 0;
    int s = 0;
    Board::squareToPolar(square, r, s);

    // 时间的临时变量
    int seconds = -1;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;

    if (position->phase == PHASE_PLACING) {
        int playerId = Player::toId(position->sideToMove);
        piece = (0x01 | position->sideToMove) + rule.nTotalPiecesEachSide - position->nPiecesInHand[playerId];
        position->nPiecesInHand[playerId]--;
        position->nPiecesOnBoard[playerId]++;

        boardLocations[square] = piece;

        updateHash(square);

        move = static_cast<move_t>(square);

        if (updateCmdlist) {
            seconds = update();
            sprintf(cmdline, "(%1u,%1u) %02u:%02u",
                    r, s, seconds / 60, seconds % 60);
            cmdlist.emplace_back(string(cmdline));
            currentStep++;
        }

        currentSquare = square;

        n = position->board.addMills(currentSquare);

        // 开局阶段未成三
        if (n == 0) {
            assert(position->nPiecesInHand[BLACK] >= 0 && position->nPiecesInHand[WHITE] >= 0);
     
            // 如果双方都无未放置的棋子
            if (position->nPiecesInHand[BLACK] == 0 && position->nPiecesInHand[WHITE] == 0) {
                // 决胜负
                if (checkGameOverCondition()) {
                    goto out;
                }

                // 进入中局阶段
                position->phase = PHASE_MOVING;

                // 进入选子状态
                position->action = ACTION_CHOOSE;

                // 清除禁点
                cleanForbiddenLocations();

                // 设置轮到谁走
                if (rule.isDefenderMoveFirst) {
                    setSideToMove(PLAYER_WHITE);
                } else {
                    setSideToMove(PLAYER_BLACK);
                }

                // 再决胜负
                if (checkGameOverCondition()) {
                    goto out;
                }
            }
            // 如果双方还有子
            else {
                // 设置轮到谁走
                changeSideToMove();
            }
        }
        // 如果成三
        else {
            // 设置去子数目
            position->nPiecesNeedRemove = rule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            position->action = ACTION_CAPTURE;
        }

        goto out;
    }

    // 如果决出胜负
    if (checkGameOverCondition()) {
        goto out;
    }

    // 对于中局落子 (ontext.phase == GAME_MOVING)

    // 如果落子不合法
    if (position->nPiecesOnBoard[position->sideId] > rule.nPiecesAtLeast ||
        !rule.allowFlyWhenRemainThreePieces) {
        int i;
        for (i = 0; i < 4; i++) {
            if (square == MoveList::moveTable[currentSquare][i])
                break;
        }

        // 不在着法表中
        if (i == 4) {
            return false;
        }
    }

    // 移子
    move = static_cast<move_t>((currentSquare << 8) + square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u", currentSquare / Board::N_SEATS, currentSquare % Board::N_SEATS + 1,
                r, s, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep++;
    }

    boardLocations[square] = boardLocations[currentSquare];

    updateHash(square);

    boardLocations[currentSquare] = '\x00';

    revertHash(currentSquare);

    currentSquare = square;
    n = position->board.addMills(currentSquare);

    // 中局阶段未成三
    if (n == 0) {
        // 进入选子状态
        position->action = ACTION_CHOOSE;

        // 设置轮到谁走
        changeSideToMove();

        // 如果决出胜负
        if (checkGameOverCondition()) {
            goto out;
        }
    }
    // 中局阶段成三
    else {
        // 设置去子数目
        position->nPiecesNeedRemove = rule.allowRemoveMultiPieces ? n : 1;

        // 进入去子状态
        position->action = ACTION_CAPTURE;
    }

out:
    if (updateCmdlist) {
        setTips();
    }

    return true;
}

bool Game::_place(int r, int s)
{
    // 转换为 square
    square_t square = Board::polarToSquare(r, s);

    return place(square, true);
}

bool Game::_capture(int r, int s)
{
    // 转换为 square
    square_t square = Board::polarToSquare(r, s);

    return capture(square, 1);
}

bool Game::capture(square_t square, int8_t updateCmdlist)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (position->phase & PHASE_NOTPLAYING)
        return false;

    // 如非“去子”状态，返回false
    if (position->action != ACTION_CAPTURE)
        return false;

    // 如果去子完成，返回false
    if (position->nPiecesNeedRemove <= 0)
        return false;

    // 格式转换
    int r = 0;
    int s = 0;
    Board::squareToPolar(square, r, s);

    // 时间的临时变量
    int seconds = -1;

    player_t opponent = Player::getOpponent(position->sideToMove);

    // 判断去子是不是对手棋
    if (!(opponent & boardLocations[square]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (!rule.allowRemoveMill &&
        position->board.inHowManyMills(square) &&
        !position->board.isAllInMills(opponent)) {
        return false;
    }

    // 去子（设置禁点）
    if (rule.hasForbiddenLocations && position->phase == PHASE_PLACING) {
        revertHash(square);
        boardLocations[square] = '\x0f';
        updateHash(square);
    } else { // 去子
        revertHash(square);
        boardLocations[square] = '\x00';
    }

    position->nPiecesOnBoard[position->opponentId]--;

    move = static_cast<move_t>(-square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "-(%1u,%1u)  %02u:%02u", r, s, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep = 0;
    }

    currentSquare = SQ_0;
    position->nPiecesNeedRemove--;
    updateHash(square); // TODO: 多余? 若去掉.则评估点的数量和哈希命中数量上升, 未剪枝?

    // 去子完成

    // 如果决出胜负
    if (checkGameOverCondition()) {
        goto out;
    }

    // 还有其余的子要去吗
    if (position->nPiecesNeedRemove > 0) {
        // 继续去子
        return true;
    }

    // 所有去子都完成了

    // 开局阶段
    if (position->phase == PHASE_PLACING) {
        // 如果双方都无未放置的棋子
        if (position->nPiecesInHand[BLACK] == 0 && position->nPiecesInHand[WHITE] == 0) {

            // 进入中局阶段
            position->phase = PHASE_MOVING;

            // 进入选子状态
            position->action = ACTION_CHOOSE;

            // 清除禁点
            cleanForbiddenLocations();

            // 设置轮到谁走
            if (rule.isDefenderMoveFirst) {
                setSideToMove(PLAYER_WHITE);
            } else {
                setSideToMove(PLAYER_BLACK);
            }

            // 再决胜负
            if (checkGameOverCondition()) {
                goto out;
            }
        }
        // 如果双方还有子
        else {
            // 进入落子状态
            position->action = ACTION_PLACE;

            // 设置轮到谁走
            changeSideToMove();

            // 如果决出胜负
            if (checkGameOverCondition()) {
                goto out;
            }
        }
    }
    // 中局阶段
    else {
        // 进入选子状态
        position->action = ACTION_CHOOSE;

        // 设置轮到谁走
        changeSideToMove();

        // 如果决出胜负
        if (checkGameOverCondition()) {
            goto out;
        }
    }

out:
    if (updateCmdlist) {
        setTips();
    }

    return true;
}

bool Game::choose(square_t square)
{
    // 如果局面不是"中局”，返回false
    if (position->phase != PHASE_MOVING)
        return false;

    // 如非“选子”或“落子”状态，返回false
    if (position->action != ACTION_CHOOSE && position->action != ACTION_PLACE)
        return false;

    // 判断选子是否可选
    if (boardLocations[square] & position->sideToMove) {
        // 判断location处的棋子是否被“闷”
        if (position->board.isSurrounded(position->sideId, position->nPiecesOnBoard, square)) {
            return false;
        }

        // 选子
        currentSquare = square;

        // 选子完成，进入落子状态
        position->action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool Game::choose(int r, int s)
{
    return choose(Board::polarToSquare(r, s));
}

bool Game::giveup(player_t loser)
{
    if (position->phase & PHASE_NOTPLAYING ||
        position->phase == PHASE_NONE) {
        return false;
    }

    position->phase = PHASE_GAMEOVER;

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

    // 设置规则
    if (sscanf(cmd, "r%1u s%3hd t%2u", &r, &s, &t) == 3) {
        if (r <= 0 || r > N_RULES) {
            return false;
        }

        return setPosition(&RULES[r - 1]);
    }

    // 选子移动
    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);

    if (args >= 4) {
        if (args == 7) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }

        if (choose(r1, s1)) {
            return _place(r2, s2);
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
        return _capture(r1, s1);
    }

    // 落子
    args = sscanf(cmd, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _place(r1, s1);
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
        position->phase = PHASE_GAMEOVER;
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

bool Game::doMove(move_t m)
{
    if (m < 0) {
        return capture(static_cast<square_t>(-m));
    }

    if (m & 0x1f00) {
        if (choose(static_cast<square_t>(m >> 8))) {
            return place(static_cast<square_t>(m & 0x00ff));
        }
    } else {
        return place(static_cast<square_t>(m & 0x00ff));
    }

    return false;
}

int Game::update()
{
    int ret = -1;
    int timePoint = -1;
    time_t *seconds = &elapsedSeconds[position->sideId];
    time_t opponentSeconds = elapsedSeconds[position->opponentId];

    // 根据局面调整计时器

    if (!(position->phase & PHASE_PLAYING)) {
        return -1;
    }

    currentTime = time(NULL);

    // 更新时间
    if (timePoint >= *seconds) {
        *seconds = ret = timePoint;
        startTime = currentTime - (elapsedSeconds[BLACK] + elapsedSeconds[WHITE]);
    } else {
        *seconds = ret = currentTime - startTime - opponentSeconds;
    }

    // 有限时要求则判断胜负
    if (rule.maxTimeLedToLose > 0) {
        checkGameOverCondition();
    }

    return ret;
}

// 是否分出胜负
bool Game::checkGameOverCondition()
{
    if (position->phase & PHASE_NOTPLAYING) {
        return true;
    }

    // 如果有时间限定
    if (rule.maxTimeLedToLose > 0) {
        position->phase = PHASE_GAMEOVER;

        // 这里不能update更新时间，否则会形成循环嵌套
        for (int i = 1; i <= 2; i++)
        {
            if (elapsedSeconds[i] > rule.maxTimeLedToLose * 60) {
                elapsedSeconds[i] = rule.maxTimeLedToLose * 60;
                winner = Player::idToPlayer(Player::getOpponentById(i));
                tips = "玩家" + Player::chToStr(Player::idToCh(i)) + "超时判负。";
                sprintf(cmdline, "Time over. Player%d win!", Player::getOpponentById(i));
            }
        }

        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    // 如果有步数限定
    if (rule.maxStepsLedToDraw > 0 &&
        moveStep > rule.maxStepsLedToDraw) {
        winner = PLAYER_DRAW;
        position->phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Steps over. In draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    // 如果玩家子数小于赛点，则对方获胜
    for (int i = 1; i <= 2; i++)
    {
        if (position->nPiecesOnBoard[i] + position->nPiecesInHand[i] < rule.nPiecesAtLeast) {
            int o = Player::getOpponentById(i);
            winner = Player::idToPlayer(o);
            position->phase = PHASE_GAMEOVER;
            sprintf(cmdline, "Player%d win!", o);
            cmdlist.emplace_back(string(cmdline));

            return true;
        }
    }

    // 如果摆满了，根据规则判断胜负
    if (position->nPiecesOnBoard[BLACK] + position->nPiecesOnBoard[WHITE] >= Board::N_SEATS * Board::N_RINGS) {
        position->phase = PHASE_GAMEOVER;

        if (rule.isStartingPlayerLoseWhenBoardFull) {
            winner = PLAYER_WHITE;
            sprintf(cmdline, "Player2 win!");
        } else {
            winner = PLAYER_DRAW;  
            sprintf(cmdline, "Full. In draw!");
        }

        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    // 如果中局被“闷”
    if (position->phase == PHASE_MOVING && position->action == ACTION_CHOOSE && position->board.isAllSurrounded(position->sideId, position->nPiecesOnBoard, position->sideToMove)) {
        // 规则要求被“闷”判负，则对手获胜 // TODO: 应该转移到下面的分支中
        position->phase = PHASE_GAMEOVER;

        if (rule.isLoseWhenNoWay) {
            tips = "玩家" + Player::chToStr(position->chSide) + "无子可走被闷";
            winner = Player::getOpponent(position->sideToMove);
            int winnerId = Player::toId(winner);
            sprintf(cmdline, "Player%d no way to go. Player%d win!", position->sideId, winnerId);
            cmdlist.emplace_back(string(cmdline));

            return true;
        }

        // 否则让棋，由对手走
        changeSideToMove();

        return false;
    }

    return false;
}

// 计算玩家1和玩家2的棋子活动能力之差
int Game::getMobilityDiff(player_t turn, int nPiecesOnBoard[], bool includeFobidden)
{
    // TODO: 处理规则无禁点的情况
    location_t *locations = boardLocations;
    int mobilityBlack = 0;
    int mobilityWhite = 0;
    int diff = 0;
    int n = 0;

    for (square_t i = SQ_BEGIN; i < SQ_END; i = static_cast<square_t>(i + 1)) {
        n = position->board.getSurroundedEmptyLocationCount(turn, nPiecesOnBoard, i, includeFobidden);

        if (locations[i] & PIECE_BLACK) {
            mobilityBlack += n;
        } else if (locations[i] & PIECE_WHITE) {
            mobilityWhite += n;
        }
    }

    diff = mobilityBlack - mobilityWhite;

    return diff;
}

void Game::cleanForbiddenLocations()
{
    if (!rule.hasForbiddenLocations) {
        return;
    }

    square_t square = SQ_0;

    for (int r = 1; r <= Board::N_RINGS; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            square = static_cast<square_t>(r * Board::N_SEATS + s);

            if (boardLocations[square] == '\x0f') {
                revertHash(square);
                boardLocations[square] = '\x00';
            }
        }
    }
}

void Game::setSideToMove(player_t player)
{
    // 设置轮到谁走
    position->sideToMove = player;

    position->sideId = Player::toId(position->sideToMove);
    position->chSide = Player::idToCh(position->sideId);

    position->opponent = Player::getOpponent(player);

    position->opponentId = Player::toId(position->opponent);
    position->chOpponent = Player::idToCh(position->opponentId);
}

void Game::changeSideToMove()
{
    setSideToMove(Player::getOpponent(position->sideToMove));
}

void Game::setTips()
{
    string winnerStr, t;
    int winnerId;
    string turnStr = Player::chToStr(position->chSide);

    switch (position->phase) {
    case PHASE_READY:
        tips = "轮到玩家1落子，剩余" + std::to_string(position->nPiecesInHand[BLACK]) + "子" +
            "  比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
        break;

    case PHASE_PLACING:
        if (position->action == ACTION_PLACE) {
            tips = "轮到玩家" + turnStr + "落子，剩余" + std::to_string(position->nPiecesInHand[position->sideId]) + "子";
        } else if (position->action == ACTION_CAPTURE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(position->nPiecesNeedRemove) + "子";
        }
        break;

    case PHASE_MOVING:
        if (position->action == ACTION_PLACE || position->action == ACTION_CHOOSE) {
            tips = "轮到玩家" + turnStr + "选子移动";
        } else if (position->action == ACTION_CAPTURE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(position->nPiecesNeedRemove) + "子";
        }
        break;

    case PHASE_GAMEOVER:  
        if (winner == PLAYER_DRAW) {
            score_draw++;
            tips = "双方平局！比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
            break;
        }

        winnerId = Player::toId(winner);
        winnerStr = Player::chToStr(Player::idToCh(winnerId));

        score[winnerId]++;

        t = "玩家" + winnerStr + "获胜！比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);

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

time_t Game::getElapsedTime(int playerId)
{
    return elapsedSeconds[playerId];
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
    position->hash = 0;
}

hash_t Game::getHash()
{
    // TODO: 每次获取哈希值时更新 hash 值低8位，放在此处调用不优雅
    return updateHashMisc();
}

hash_t Game::updateHash(square_t square)
{
    // PieceType is boardLocations[square] 

    // 0b00 表示空白，0b01 = 1 表示先手棋子，0b10 = 2 表示后手棋子，0b11 = 3 表示禁点
    int pieceType = (boardLocations[square] & 0x30) >> 4;

    // 清除或者放置棋子
    position->hash ^= zobrist[square][pieceType];

    return position->hash;
}

hash_t Game::revertHash(square_t square)
{
    return updateHash(square);
}

hash_t Game::updateHashMisc()
{
    // 清除标记位
    position->hash &= static_cast<hash_t>(~0xFF);

    // 置位

    if (position->sideToMove == PLAYER_WHITE) {
        position->hash |= 1U;
    }

    if (position->action == ACTION_CAPTURE) {
        position->hash |= 1U << 1;
    }

    position->hash |= static_cast<hash_t>(position->nPiecesNeedRemove) << 2;
    position->hash |= static_cast<hash_t>(position->nPiecesInHand[BLACK]) << 4;     // TODO: 或许换 position->phase 也可以？

    return position->hash;
}
