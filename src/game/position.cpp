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
#include <climits>
#include "position.h"
#include "search.h"
#include "movegen.h"
#include "player.h"
#include "option.h"
#include "zobrist.h"
#include "bitboard.h"

// 当前棋局的字符提示
string tips;

StateInfo::StateInfo()
{
    if (position != nullptr) {
        delete position;
    }

    position = new Position();
    //memset(position, 0, sizeof(Position));
}

Position::Position()
{
    // 创建哈希数据
    constructHash();

    // 默认规则
    setPosition(&RULES[DEFAULT_RULE_NUMBER]);

    // 比分归零
    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;

    //tips.reserve(1024);
    cmdlist.reserve(256);
}

StateInfo::~StateInfo()
{
}

Position::~Position()
{
    cmdlist.clear();
}

StateInfo::StateInfo(const StateInfo &state)
{  
    if (position != nullptr) {
        delete position;
        position = nullptr;
    }
    
    position = new Position();

    *this = state;
}

Position::Position(const Position &pos)
{  
    *this = pos;
}

StateInfo::StateInfo(StateInfo &state)
{
    if (position != nullptr) {
        delete position;
        position = nullptr;
    }

    position = new Position();

    *this = state;
}

Position::Position(Position &pos)
{  
    *this = pos;
}

StateInfo &StateInfo::operator= (const StateInfo &state)
{
    memcpy(position, state.position, sizeof(Position));
    return *this;
}

Position &Position::operator= (const Position &pos)
{
    currentStep = pos.currentStep;
    moveStep = pos.moveStep;
    memcpy(board.locations, pos.board.locations, sizeof(board.locations));
    memcpy(board.byTypeBB, pos.board.byTypeBB, sizeof(board.byTypeBB));
    currentSquare = pos.currentSquare;
    winner = pos.winner;
    startTime = pos.startTime;
    currentTime = pos.currentTime;
    elapsedSeconds[BLACK] = pos.elapsedSeconds[BLACK];
    elapsedSeconds[WHITE] = pos.elapsedSeconds[WHITE];
    move = pos.move;
    memcpy(cmdline, pos.cmdline, sizeof(cmdline));
    cmdlist = pos.cmdlist;
    //tips = pos.tips;

    return *this;
}

StateInfo &StateInfo::operator= (StateInfo &state)
{
    memcpy(position, state.position, sizeof(Position));
    return *this;
}

Position &Position::operator= (Position &pos)
{
    currentStep = pos.currentStep;
    moveStep = pos.moveStep;
    memcpy(board.locations, pos.board.locations, sizeof(board.locations));
    memcpy(board.byTypeBB, pos.board.byTypeBB, sizeof(board.byTypeBB));
    currentSquare = pos.currentSquare;
    winner = pos.winner;
    startTime = pos.startTime;
    currentTime = pos.currentTime;
    elapsedSeconds[BLACK] = pos.elapsedSeconds[BLACK];
    elapsedSeconds[WHITE] = pos.elapsedSeconds[WHITE];
    move = pos.move;
    memcpy(cmdline, pos.cmdline, sizeof(cmdline));
    cmdlist = pos.cmdlist;
    //tips = pos.tips;

    return *this;
}


int Position::countPiecesOnBoard()
{
    nPiecesOnBoard[BLACK] = nPiecesOnBoard[WHITE] = 0;

    for (int r = 1; r < Board::N_RINGS + 2; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            square_t square = static_cast<square_t>(r * Board::N_SEATS + s);
            if (board.locations[square] & PIECE_BLACK) {
                nPiecesOnBoard[BLACK]++;
            } else if (board.locations[square] & PIECE_WHITE) {
                nPiecesOnBoard[WHITE]++;
            }
#if 0
            else if (board.locations[square] & PIECE_FORBIDDEN) {
                // 不计算盘面子数
            }
#endif
        }
    }

    // 设置玩家盘面剩余子数和未放置子数
    if (nPiecesOnBoard[BLACK] > rule.nTotalPiecesEachSide ||
        nPiecesOnBoard[WHITE] > rule.nTotalPiecesEachSide) {
        return -1;
    }

    return nPiecesOnBoard[BLACK] + nPiecesOnBoard[WHITE];
}

int Position::countPiecesInHand()
{
    nPiecesInHand[BLACK] = rule.nTotalPiecesEachSide - nPiecesOnBoard[BLACK];
    nPiecesInHand[WHITE] = rule.nTotalPiecesEachSide - nPiecesOnBoard[WHITE];

    return nPiecesInHand[BLACK] + nPiecesInHand[WHITE];
}

// 设置棋局状态和棋盘数据，用于初始化
bool Position::setPosition(const struct Rule *newRule)
{
    // 根据规则
    rule = *newRule;

    // 设置棋局数据

    // 设置步数
    this->currentStep = 0;
    this->moveStep = 0;

    // 局面阶段标识
    phase = PHASE_READY;

    // 轮流状态标识
    setSideToMove(PLAYER_BLACK);

    // 动作状态标识
    action = ACTION_PLACE;

    // 当前棋局（3×8）
    memset(board.locations, 0, sizeof(board.locations));
    hash = 0;
    memset(board.byTypeBB, 0, sizeof(board.byTypeBB));

    if (countPiecesOnBoard() == -1) {
        return false;
    }

    countPiecesInHand();

    // 设置去子状态时的剩余尚待去除子数
    nPiecesNeedRemove = 0;

    // 清空成三记录
    board.millListSize = 0;

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 生成着法表
    MoveList::create();

    // 生成成三表
    board.createMillTable();

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

bool Position::reset()
{
    if (phase == PHASE_READY &&
        elapsedSeconds[BLACK] == elapsedSeconds[WHITE] == 0) {
        return true;
    }

    // 步数归零
    currentStep = 0;
    moveStep = 0;

    // 局面阶段标识
    phase = PHASE_READY;

    // 设置轮流状态
    setSideToMove(PLAYER_BLACK);

    // 动作状态标识
    action = ACTION_PLACE;

    // 胜负标识
    winner = PLAYER_NOBODY;

    // 当前棋局（3×8）
    memset(board.locations, 0, sizeof(board.locations));
    hash = 0;
    memset(board.byTypeBB, 0, sizeof(board.byTypeBB));

    // 盘面子数归零
    nPiecesOnBoard[BLACK] = nPiecesOnBoard[WHITE] = 0;

    // 设置玩家盘面剩余子数和未放置子数
    nPiecesInHand[BLACK] = nPiecesInHand[WHITE] = rule.nTotalPiecesEachSide;

    // 设置去子状态时的剩余尚待去除子数
    nPiecesNeedRemove = 0;

    // 清空成三记录
    board.millListSize = 0;

    // 不选中棋子
    currentSquare = SQ_0;

    // 用时置零
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

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

bool Position::start()
{
    switch (phase) {
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
        phase = PHASE_PLACING;
        return true;
    default:
        return false;
    }
}

bool Position::placePiece(square_t square, bool updateCmdlist)
{
    // 如果局面为“结局”，返回false
    if (phase == PHASE_GAMEOVER)
        return false;

    // 如果局面为“未开局”，则开局
    if (phase == PHASE_READY)
        start();

    // 如非“落子”状态，返回false
    if (action != ACTION_PLACE)
        return false;

    // 如果落子位置在棋盘外、已有子点或禁点，返回false
    if (!board.onBoard[square] || board.locations[square])
        return false;

    // 格式转换
    ring_t r;
    seat_t s;
    Board::squareToPolar(square, r, s);

    // 时间的临时变量
    int seconds = -1;

    // 对于开局落子
    int piece = '\x00';
    int n = 0;

    int playerId = Player::toId(sideToMove);

    if (phase == PHASE_PLACING) {
        piece = (0x01 | sideToMove) + rule.nTotalPiecesEachSide - nPiecesInHand[playerId];
        nPiecesInHand[playerId]--;
        nPiecesOnBoard[playerId]++;

        board.locations[square] = piece;

        updateHash(square);

        board.byTypeBB[ALL_PIECES] |= square;
        board.byTypeBB[playerId] |= square;

        move = static_cast<move_t>(square);

        if (updateCmdlist) {
            seconds = update();
            sprintf(cmdline, "(%1u,%1u) %02u:%02u",
                    r, s, seconds / 60, seconds % 60);
            cmdlist.emplace_back(string(cmdline));
            currentStep++;
        }

        currentSquare = square;

        n = board.addMills(currentSquare);

        // 开局阶段未成三
        if (n == 0) {
            assert(nPiecesInHand[BLACK] >= 0 && nPiecesInHand[WHITE] >= 0);
     
            // 如果双方都无未放置的棋子
            if (nPiecesInHand[BLACK] == 0 && nPiecesInHand[WHITE] == 0) {
                // 决胜负
                if (checkGameOverCondition(updateCmdlist)) {
                    goto out;
                }

                // 进入中局阶段
                phase = PHASE_MOVING;

                // 进入选子状态
                action = ACTION_SELECT;

                // 清除禁点
                cleanForbiddenLocations();

                // 设置轮到谁走
                if (rule.isDefenderMoveFirst) {
                    setSideToMove(PLAYER_WHITE);
                } else {
                    setSideToMove(PLAYER_BLACK);
                }

                // 再决胜负
                if (checkGameOverCondition(updateCmdlist)) {
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
            nPiecesNeedRemove = rule.allowRemoveMultiPieces ? n : 1;

            // 进入去子状态
            action = ACTION_REMOVE;
        }

        goto out;
    }

    // 如果决出胜负
    if (checkGameOverCondition(updateCmdlist)) {
        goto out;
    }

    // 对于中局落子 (ontext.phase == GAME_MOVING)

    // 如果落子不合法
    if (nPiecesOnBoard[sideId] > rule.nPiecesAtLeast ||
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
    move = make_move(currentSquare, square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u", currentSquare / Board::N_SEATS, currentSquare % Board::N_SEATS + 1,
                r, s, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep++;
    }

    bitboard_t fromTo = square_bb(currentSquare) | square_bb(square);
    board.byTypeBB[ALL_PIECES] ^= fromTo;
    board.byTypeBB[playerId] ^= fromTo;

    board.locations[square] = board.locations[currentSquare];

    updateHash(square);
    revertHash(currentSquare);

    board.locations[currentSquare] = '\x00';

    currentSquare = square;
    n = board.addMills(currentSquare);

    // 中局阶段未成三
    if (n == 0) {
        // 进入选子状态
        action = ACTION_SELECT;

        // 设置轮到谁走
        changeSideToMove();

        // 如果决出胜负
        if (checkGameOverCondition(updateCmdlist)) {
            goto out;
        }
    }
    // 中局阶段成三
    else {
        // 设置去子数目
        nPiecesNeedRemove = rule.allowRemoveMultiPieces ? n : 1;

        // 进入去子状态
        action = ACTION_REMOVE;
    }

out:
    if (updateCmdlist) {
        setTips();
    }

    return true;
}

bool Position::_placePiece(ring_t r, seat_t s)
{
    // 转换为 square
    square_t square = Board::polarToSquare(r, s);

    return placePiece(square, true);
}

bool Position::_removePiece(ring_t r, seat_t s)
{
    // 转换为 square
    square_t square = Board::polarToSquare(r, s);

    return removePiece(square, 1);
}

bool Position::removePiece(square_t square, bool updateCmdlist)
{
    // 如果局面为"未开局"或“结局”，返回false
    if (phase & PHASE_NOTPLAYING)
        return false;

    // 如非“去子”状态，返回false
    if (action != ACTION_REMOVE)
        return false;

    // 如果去子完成，返回false
    if (nPiecesNeedRemove <= 0)
        return false;

    // 格式转换
    ring_t r;
    seat_t s;
    Board::squareToPolar(square, r, s);

    // 时间的临时变量
    int seconds = -1;

    int oppId = Player::toId(opponent);

    // 判断去子是不是对手棋
    if (!(opponent & board.locations[square]))
        return false;

    // 如果当前子是否处于“三连”之中，且对方还未全部处于“三连”之中
    if (!rule.allowRemoveMill &&
        board.inHowManyMills(square, PLAYER_NOBODY) &&
        !board.isAllInMills(Player::getOpponent(sideToMove))) {
        return false;
    }

    // 去子（设置禁点）
    if (rule.hasForbiddenLocations && phase == PHASE_PLACING) {
        revertHash(square);
        board.locations[square] = '\x0f';
        updateHash(square);

        board.byTypeBB[oppId] ^= square;
        board.byTypeBB[FORBIDDEN_STONE] |= square;
    } else { // 去子
        revertHash(square);
        board.locations[square] = '\x00';

        board.byTypeBB[ALL_PIECES] ^= square;
        board.byTypeBB[opponentId] ^= square;
    }

    nPiecesOnBoard[opponentId]--;

    move = static_cast<move_t>(-square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "-(%1u,%1u)  %02u:%02u", r, s, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep = 0;
    }

    currentSquare = SQ_0;
    nPiecesNeedRemove--;
    //updateHash(square); // TODO: 多余? 若去掉.则评估点的数量和哈希命中数量上升, 未剪枝?

    // 去子完成

    // 如果决出胜负
    if (checkGameOverCondition(updateCmdlist)) {
        goto out;
    }

    // 还有其余的子要去吗
    if (nPiecesNeedRemove > 0) {
        // 继续去子
        return true;
    }

    // 所有去子都完成了

    // 开局阶段
    if (phase == PHASE_PLACING) {
        // 如果双方都无未放置的棋子
        if (nPiecesInHand[BLACK] == 0 && nPiecesInHand[WHITE] == 0) {

            // 进入中局阶段
            phase = PHASE_MOVING;

            // 进入选子状态
            action = ACTION_SELECT;

            // 清除禁点
            cleanForbiddenLocations();

            // 设置轮到谁走
            if (rule.isDefenderMoveFirst) {
                setSideToMove(PLAYER_WHITE);
            } else {
                setSideToMove(PLAYER_BLACK);
            }

            // 再决胜负
            if (checkGameOverCondition(updateCmdlist)) {
                goto out;
            }
        }
        // 如果双方还有子
        else {
            // 进入落子状态
            action = ACTION_PLACE;

            // 设置轮到谁走
            changeSideToMove();

            // 如果决出胜负
            if (checkGameOverCondition(updateCmdlist)) {
                goto out;
            }
        }
    }
    // 中局阶段
    else {
        // 进入选子状态
        action = ACTION_SELECT;

        // 设置轮到谁走
        changeSideToMove();

        // 如果决出胜负
        if (checkGameOverCondition(updateCmdlist)) {
            goto out;
        }
    }

out:
    if (updateCmdlist) {
        setTips();
    }

    return true;
}

bool Position::selectPiece(square_t square)
{
    // 如果局面不是"中局”，返回false
    if (phase != PHASE_MOVING)
        return false;

    // 如非“选子”或“落子”状态，返回false
    if (action != ACTION_SELECT && action != ACTION_PLACE)
        return false;

    // 判断选子是否可选
    if (board.locations[square] & sideToMove) {
        // 选子
        currentSquare = square;

        // 选子完成，进入落子状态
        action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool Position::selectPiece(ring_t r, seat_t s)
{
    return selectPiece(Board::polarToSquare(r, s));
}

bool Position::giveup(player_t loser)
{
    if (phase & PHASE_NOTPLAYING ||
        phase == PHASE_NONE) {
        return false;
    }

    phase = PHASE_GAMEOVER;

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
bool Position::command(const char *cmd)
{
    int r;
    unsigned t;
    step_t s;
    ring_t r1, r2;
    seat_t s1, s2;
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

        if (selectPiece(r1, s1)) {
            return _placePiece(r2, s2);
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
        return _removePiece(r1, s1);
    }

    // 落子
    args = sscanf(cmd, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _placePiece(r1, s1);
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
        phase = PHASE_GAMEOVER;
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

bool Position::doMove(move_t m)
{
    movetype_t mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        return removePiece(static_cast<square_t>(-m));
    case MOVETYPE_MOVE:
        if (selectPiece(from_sq(m))) {
            return placePiece(to_sq(m));
        }
    case MOVETYPE_PLACE:
        return placePiece(to_sq(m));
    default:
        break;
    }

    return false;
}

player_t Position::getWinner() const
{
    return winner;
}

int Position::update()
{
    int ret = -1;
    int timePoint = -1;
    time_t *seconds = &elapsedSeconds[sideId];
    time_t opponentSeconds = elapsedSeconds[opponentId];

    // 根据局面调整计时器

    if (!(phase & PHASE_PLAYING)) {
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
bool Position::checkGameOverCondition(int8_t updateCmdlist)
{
    if (phase & PHASE_NOTPLAYING) {
        return true;
    }

    // 如果有时间限定
    if (rule.maxTimeLedToLose > 0) {
        phase = PHASE_GAMEOVER;

        if (updateCmdlist) {
            // 这里不能update更新时间，否则会形成循环嵌套
            for (int i = 1; i <= 2; i++) {
                if (elapsedSeconds[i] > rule.maxTimeLedToLose * 60) {
                    elapsedSeconds[i] = rule.maxTimeLedToLose * 60;
                    winner = Player::idToPlayer(Player::getOpponentById(i));
                    tips = "玩家" + Player::chToStr(Player::idToCh(i)) + "超时判负。";
                    sprintf(cmdline, "Time over. Player%d win!", Player::getOpponentById(i));
                }
            }

            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    // 如果有步数限定
    if (rule.maxStepsLedToDraw > 0 &&
        moveStep > rule.maxStepsLedToDraw) {
        winner = PLAYER_DRAW;
        phase = PHASE_GAMEOVER;
        if (updateCmdlist) {
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    // 如果玩家子数小于赛点，则对方获胜
    for (int i = 1; i <= 2; i++)
    {
        if (nPiecesOnBoard[i] + nPiecesInHand[i] < rule.nPiecesAtLeast) {
            int o = Player::getOpponentById(i);
            winner = Player::idToPlayer(o);
            phase = PHASE_GAMEOVER;
            if (updateCmdlist) {
                sprintf(cmdline, "Player%d win!", o);
                cmdlist.emplace_back(string(cmdline));
            }

            return true;
        }
    }

#ifdef MCTS_AI
#if 0
    int diff = nPiecesOnBoard[BLACK] - nPiecesOnBoard[WHITE];
    if (diff > 4) {
        winner = PLAYER_BLACK;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    if (diff < -4) {
        winner = PLAYER_WHITE;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }
#endif
#endif

    // 如果摆满了，根据规则判断胜负
    if (nPiecesOnBoard[BLACK] + nPiecesOnBoard[WHITE] >= Board::N_SEATS * Board::N_RINGS) {
        phase = PHASE_GAMEOVER;

        if (rule.isStartingPlayerLoseWhenBoardFull) {
            winner = PLAYER_WHITE;
            if (updateCmdlist) {
                sprintf(cmdline, "Player2 win!");
            }
        } else {
            winner = PLAYER_DRAW; 
            if (updateCmdlist) {
                sprintf(cmdline, "Full. In draw!");
            }
        }

        if (updateCmdlist) {
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    // 如果中局被“闷”
    if (phase == PHASE_MOVING && action == ACTION_SELECT && board.isAllSurrounded(sideId, nPiecesOnBoard, sideToMove)) {
        // 规则要求被“闷”判负，则对手获胜 // TODO: 应该转移到下面的分支中
        phase = PHASE_GAMEOVER;

        if (rule.isLoseWhenNoWay) {
            if (updateCmdlist) {
                tips = "玩家" + Player::chToStr(chSide) + "无子可走被闷";
                winner = Player::getOpponent(sideToMove);
                int winnerId = Player::toId(winner);
                sprintf(cmdline, "Player%d no way to go. Player%d win!", sideId, winnerId);
                cmdlist.emplace_back(string(cmdline));  // TODO: 内存泄漏
            }

            return true;
        }

        // 否则让棋，由对手走
        changeSideToMove();

        return false;
    }

    return false;
}

// 计算玩家1和玩家2的棋子活动能力之差
int Position::getMobilityDiff(player_t turn, int piecesOnBoard[], bool includeFobidden)
{
    // TODO: 处理规则无禁点的情况
    location_t *locations = board.locations;
    int mobilityBlack = 0;
    int mobilityWhite = 0;
    int diff = 0;
    int n = 0;

    for (square_t i = SQ_BEGIN; i < SQ_END; i = static_cast<square_t>(i + 1)) {
        n = board.getSurroundedEmptyLocationCount(turn, piecesOnBoard, i, includeFobidden);

        if (locations[i] & PIECE_BLACK) {
            mobilityBlack += n;
        } else if (locations[i] & PIECE_WHITE) {
            mobilityWhite += n;
        }
    }

    diff = mobilityBlack - mobilityWhite;

    return diff;
}

void Position::cleanForbiddenLocations()
{
    if (!rule.hasForbiddenLocations) {
        return;
    }

    square_t square = SQ_0;

    for (int r = 1; r <= Board::N_RINGS; r++) {
        for (int s = 0; s < Board::N_SEATS; s++) {
            square = static_cast<square_t>(r * Board::N_SEATS + s);

            if (board.locations[square] == '\x0f') {
                revertHash(square);
                board.locations[square] = '\x00';
                board.byTypeBB[ALL_PIECES] ^= square;
                board.byTypeBB[FORBIDDEN_STONE] ^= square;  // TODO: 可能是多余
            }
        }
    }
}

void Position::setSideToMove(player_t player)
{
    // 设置轮到谁走
    sideToMove = player;

    sideId = Player::toId(sideToMove);
    chSide = Player::idToCh(sideId);

    opponent = Player::getOpponent(player);

    opponentId = Player::toId(opponent);
    chOpponent = Player::idToCh(opponentId);
}

player_t Position::getSideToMove()
{
    return sideToMove;
}

void Position::changeSideToMove()
{
    setSideToMove(Player::getOpponent(sideToMove));
}

bool Position::doNullMove()
{
    changeSideToMove();
    return true;
}

bool Position::undoNullMove()
{
    changeSideToMove();
    return true;
}

void Position::setTips()
{
    string winnerStr, t;
    int winnerId;
    string turnStr = Player::chToStr(chSide);

    switch (phase) {
    case PHASE_READY:
        tips = "轮到玩家1落子，剩余" + std::to_string(nPiecesInHand[BLACK]) + "子" +
            "  比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
        break;

    case PHASE_PLACING:
        if (action == ACTION_PLACE) {
            tips = "轮到玩家" + turnStr + "落子，剩余" + std::to_string(nPiecesInHand[sideId]) + "子";
        } else if (action == ACTION_REMOVE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(nPiecesNeedRemove) + "子";
        }
        break;

    case PHASE_MOVING:
        if (action == ACTION_PLACE || action == ACTION_SELECT) {
            tips = "轮到玩家" + turnStr + "选子移动";
        } else if (action == ACTION_REMOVE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(nPiecesNeedRemove) + "子";
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

time_t Position::getElapsedTime(int playerId)
{
    return elapsedSeconds[playerId];
}

void Position::constructHash()
{
    hash = 0;
}

hash_t Position::getPosKey()
{
    // TODO: 每次获取哈希值时更新 hash 值剩余8位，放在此处调用不优雅
    return updateHashMisc();
}

hash_t Position::updateHash(square_t square)
{
    // PieceType is board.locations[square] 

    // 0b00 表示空白，0b01 = 1 表示先手棋子，0b10 = 2 表示后手棋子，0b11 = 3 表示禁点
    int pieceType = Player::toId(board.locationToPlayer(square));
    // TODO: 标准写法应该是如下的写法，但目前这么写也可以工作
    //location_t loc = board.locations[square];
    //int pieceType = loc == 0x0f? 3 : loc >> PLAYER_SHIFT;

    // 清除或者放置棋子
    hash ^= zobrist[square][pieceType];

    return hash;
}

hash_t Position::revertHash(square_t square)
{
    return updateHash(square);
}

hash_t Position::updateHashMisc()
{
    const int HASH_MISC_BIT = 8;

    // 清除标记位
    hash = hash << HASH_MISC_BIT >> HASH_MISC_BIT;
    hash_t hi = 0;

    // 置位

    if (sideToMove == PLAYER_WHITE) {
        hi |= 1U;
    }

    if (action == ACTION_REMOVE) {
        hi |= 1U << 1;
    }

    hi |= static_cast<hash_t>(nPiecesNeedRemove) << 2;
    hi |= static_cast<hash_t>(nPiecesInHand[BLACK]) << 4;     // TODO: 或许换 phase 也可以？

    hash = hash | (hi << (CHAR_BIT * sizeof(hash_t) - HASH_MISC_BIT));

    return hash;
}

hash_t Position::getNextMainHash(move_t m)
{
    hash_t nextMainHash = hash /* << 8 >> 8 */;
    square_t sq = static_cast<square_t>(to_sq(m));;
    movetype_t mt = type_of(m);

    if (mt == MOVETYPE_REMOVE) {
        int pieceType = Player::getOpponentById(Player::toId(sideToMove));
        nextMainHash ^= zobrist[sq][pieceType];

        if (rule.hasForbiddenLocations && phase == PHASE_PLACING) {
            nextMainHash ^= zobrist[sq][FORBIDDEN_STONE];
        }

        return nextMainHash;
    }
    
    int pieceType = Player::toId(sideToMove);
    nextMainHash ^= zobrist[sq][pieceType];

    if (mt == MOVETYPE_MOVE) {
        nextMainHash ^= zobrist[from_sq(m)][pieceType];
    }

    return nextMainHash;
}
