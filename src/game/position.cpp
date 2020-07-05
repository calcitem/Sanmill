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

string tips;

Position::Position()
{
    constructKey();

    setPosition(&RULES[DEFAULT_RULE_NUMBER]);

    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;

    //tips.reserve(1024);
    cmdlist.reserve(256);
}

Position::~Position()
{
    cmdlist.clear();
}

int Position::countPiecesOnBoard()
{
    nPiecesOnBoard[BLACK] = nPiecesOnBoard[WHITE] = 0;

    for (int r = 1; r < Board::N_FILES + 2; r++) {
        for (int s = 0; s < Board::N_RANKS; s++) {
            Square square = static_cast<Square>(r * Board::N_RANKS + s);
            if (board.locations[square] & B_STONE) {
                nPiecesOnBoard[BLACK]++;
            } else if (board.locations[square] & W_STONE) {
                nPiecesOnBoard[WHITE]++;
            }
#if 0
            else if (board.locations[square] & BAN_STONE) {
            }
#endif
        }
    }

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

bool Position::setPosition(const struct Rule *newRule)
{
    rule = *newRule;

    this->currentStep = 0;
    this->moveStep = 0;

    phase = PHASE_READY;
    setSideToMove(BLACK);
    action = ACTION_PLACE;

    memset(board.locations, 0, sizeof(board.locations));
    key = 0;
    memset(board.byTypeBB, 0, sizeof(board.byTypeBB));

    if (countPiecesOnBoard() == -1) {
        return false;
    }

    countPiecesInHand();
    nPiecesNeedRemove = 0;
    board.millListSize = 0;
    winner = NOBODY;
    MoveList::create();
    board.createMillTable();
    currentSquare = SQ_0;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;
    setTips();
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

    currentStep = 0;
    moveStep = 0;

    phase = PHASE_READY;
    setSideToMove(BLACK);
    action = ACTION_PLACE;

    winner = NOBODY;

    memset(board.locations, 0, sizeof(board.locations));
    key = 0;
    memset(board.byTypeBB, 0, sizeof(board.byTypeBB));

    nPiecesOnBoard[BLACK] = nPiecesOnBoard[WHITE] = 0;
    nPiecesInHand[BLACK] = nPiecesInHand[WHITE] = rule.nTotalPiecesEachSide;
    nPiecesNeedRemove = 0;
    board.millListSize = 0;
    currentSquare = SQ_0;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;
    setTips();
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
    case PHASE_PLACING:
    case PHASE_MOVING:
        return false;
    case PHASE_GAMEOVER:
        reset();
        [[fallthrough]];
    case PHASE_READY:
        startTime = time(nullptr);
        phase = PHASE_PLACING;
        return true;
    default:
        return false;
    }
}

bool Position::placePiece(Square square, bool updateCmdlist)
{
    File file;
    Rank rank;
    int i;
    int seconds = -1;

    int piece = '\x00';
    int n = 0;

    int playerId = sideToMove;

    Bitboard fromTo;

    if (phase == PHASE_GAMEOVER)
        return false;

    if (phase == PHASE_READY)
        start();

    if (action != ACTION_PLACE)
        return false;

    if (!board.onBoard[square] || board.locations[square])
        return false;

    Board::squareToPolar(square, file, rank);

    if (phase == PHASE_PLACING) {
        piece = (0x01 | (sideToMove << PLAYER_SHIFT)) + rule.nTotalPiecesEachSide - nPiecesInHand[playerId];
        nPiecesInHand[playerId]--;
        nPiecesOnBoard[playerId]++;

        board.locations[square] = piece;

        updateKey(square);

        board.byTypeBB[ALL_PIECES] |= square;
        board.byTypeBB[playerId] |= square;

        move = static_cast<Move>(square);

        if (updateCmdlist) {
            seconds = update();
            sprintf(cmdline, "(%1u,%1u) %02u:%02u",
                    file, rank, seconds / 60, seconds % 60);
            cmdlist.emplace_back(string(cmdline));
            currentStep++;
        }

        currentSquare = square;

        n = board.addMills(currentSquare);

        if (n == 0) {
            assert(nPiecesInHand[BLACK] >= 0 && nPiecesInHand[WHITE] >= 0);     

            if (nPiecesInHand[BLACK] == 0 && nPiecesInHand[WHITE] == 0) {
                if (checkGameOverCondition(updateCmdlist)) {
                    goto out;
                }

                phase = PHASE_MOVING;
                action = ACTION_SELECT;
                cleanBannedLocations();

                if (rule.isDefenderMoveFirst) {
                    setSideToMove(WHITE);
                } else {
                    setSideToMove(BLACK);
                }

                if (checkGameOverCondition(updateCmdlist)) {
                    goto out;
                }
            } else {
                changeSideToMove();
            }
        } else {
            nPiecesNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            action = ACTION_REMOVE;
        }

        goto out;
    }

    if (checkGameOverCondition(updateCmdlist)) {
        goto out;
    }

    // When hase == GAME_MOVING

    // if illegal
    if (nPiecesOnBoard[sideToMove] > rule.nPiecesAtLeast ||
        !rule.allowFlyWhenRemainThreePieces) {
        for (i = 0; i < 4; i++) {
            if (square == MoveList::moveTable[currentSquare][i])
                break;
        }

        // not in moveTable
        if (i == 4) {
            return false;
        }
    }

    move = make_move(currentSquare, square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u", currentSquare / Board::N_RANKS, currentSquare % Board::N_RANKS + 1,
                file, rank, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep++;
    }

    fromTo = square_bb(currentSquare) | square_bb(square);
    board.byTypeBB[ALL_PIECES] ^= fromTo;
    board.byTypeBB[playerId] ^= fromTo;

    board.locations[square] = board.locations[currentSquare];

    updateKey(square);
    revertKey(currentSquare);

    board.locations[currentSquare] = '\x00';

    currentSquare = square;
    n = board.addMills(currentSquare);

    // midgame
    if (n == 0) {
        action = ACTION_SELECT;
        changeSideToMove();

        if (checkGameOverCondition(updateCmdlist)) {
            goto out;
        }
    } else {
        nPiecesNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
        action = ACTION_REMOVE;
    }

out:
    if (updateCmdlist) {
        setTips();
    }

    return true;
}

bool Position::_placePiece(File file, Rank rank)
{
    Square square = Board::polarToSquare(file, rank);

    return placePiece(square, true);
}

bool Position::_removePiece(File file, Rank rank)
{
    Square square = Board::polarToSquare(file, rank);

    return removePiece(square, 1);
}

bool Position::removePiece(Square square, bool updateCmdlist)
{
    if (phase & PHASE_NOTPLAYING)
        return false;

    if (action != ACTION_REMOVE)
        return false;

    if (nPiecesNeedRemove <= 0)
        return false;

    File file;
    Rank rank;
    Board::squareToPolar(square, file, rank);

    int seconds = -1;

    int oppId = them;

    // if piece is not their
    if (!((them << PLAYER_SHIFT) & board.locations[square]))
        return false;

    if (!rule.allowRemovePieceInMill &&
        board.inHowManyMills(square, NOBODY) &&
        !board.isAllInMills(~sideToMove)) {
        return false;
    }

    if (rule.hasBannedLocations && phase == PHASE_PLACING) {
        revertKey(square);
        board.locations[square] = '\x0f';
        updateKey(square);

        board.byTypeBB[oppId] ^= square;
        board.byTypeBB[BAN] |= square;
    } else { // Remove
        revertKey(square);
        board.locations[square] = '\x00';

        board.byTypeBB[ALL_PIECES] ^= square;
        board.byTypeBB[them] ^= square;
    }

    nPiecesOnBoard[them]--;

    move = static_cast<Move>(-square);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "-(%1u,%1u)  %02u:%02u", file, rank, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep = 0;
    }

    currentSquare = SQ_0;
    nPiecesNeedRemove--;

    // Remove piece completed

    if (checkGameOverCondition(updateCmdlist)) {
        goto out;
    }

    if (nPiecesNeedRemove > 0) {
        return true;
    }

    if (phase == PHASE_PLACING) {
        if (nPiecesInHand[BLACK] == 0 && nPiecesInHand[WHITE] == 0) {

            phase = PHASE_MOVING;
            action = ACTION_SELECT;
            cleanBannedLocations();

            if (rule.isDefenderMoveFirst) {
                setSideToMove(WHITE);
            } else {
                setSideToMove(BLACK);
            }

            if (checkGameOverCondition(updateCmdlist)) {
                goto out;
            }
        } else {
            action = ACTION_PLACE;
            changeSideToMove();

            if (checkGameOverCondition(updateCmdlist)) {
                goto out;
            }
        }
    } else {
        action = ACTION_SELECT;
        changeSideToMove();

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

bool Position::selectPiece(Square square)
{
    if (phase != PHASE_MOVING)
        return false;

    if (action != ACTION_SELECT && action != ACTION_PLACE)
        return false;

    if (board.locations[square] & (sideToMove << PLAYER_SHIFT)) {
        currentSquare = square;
        action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool Position::selectPiece(File file, Rank rank)
{
    return selectPiece(Board::polarToSquare(file, rank));
}

bool Position::giveup(Color loser)
{
    if (phase & PHASE_NOTPLAYING ||
        phase == PHASE_NONE) {
        return false;
    }

    phase = PHASE_GAMEOVER;

    Color loserColor = loser;
    char loserCh = Player::colorToCh(loserColor);
    string loserStr = Player::chToStr(loserCh);

    winner = ~loser;
    tips = "玩家" + loserStr + "投子认负";
    sprintf(cmdline, "Player%d give up!", loserColor);
    score[winner]++;

    cmdlist.emplace_back(string(cmdline));

    return true;
}

bool Position::command(const char *cmd)
{
    int ruleIndex;
    unsigned t;
    Step step;
    File file1, file2;
    Rank rank1, rank2;
    int args = 0;
    int mm = 0, ss = 0;

    if (sscanf(cmd, "r%1u s%3hd t%2u", &ruleIndex, &step, &t) == 3) {
        if (ruleIndex <= 0 || ruleIndex > N_RULES) {
            return false;
        }

        return setPosition(&RULES[ruleIndex - 1]);
    }

    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &file1, &rank1, &file2, &rank2, &mm, &ss);

    if (args >= 4) {
        if (args == 7) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }

        if (selectPiece(file1, rank1)) {
            return _placePiece(file2, rank2);
        }

        return false;
    }

    args = sscanf(cmd, "-(%1u,%1u) %2u:%2u", &file1, &rank1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _removePiece(file1, rank1);
    }

    args = sscanf(cmd, "(%1u,%1u) %2u:%2u", &file1, &rank1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return _placePiece(file1, rank1);
    }

    args = sscanf(cmd, "Player%1u give up!", &t);

    if (args == 1) {
        return giveup((Color)t);
    }

#ifdef THREEFOLD_REPETITION
    if (!strcmp(cmd, "Threefold Repetition. Draw!")) {
        return true;
    }

    if (!strcmp(cmd, "draw")) {
        phase = PHASE_GAMEOVER;
        winner = DRAW;
        score_draw++;
        tips = "三次重复局面判和。";
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }
#endif /* THREEFOLD_REPETITION */

    return false;
}

bool Position::doMove(Move m)
{
    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        return removePiece(static_cast<Square>(-m));
    case MOVETYPE_MOVE:
        if (selectPiece(from_sq(m))) {
            return placePiece(to_sq(m));
        }
        break;
    case MOVETYPE_PLACE:
        return placePiece(to_sq(m));
    default:
        break;
    }

    return false;
}

Color Position::getWinner() const
{
    return winner;
}

int Position::update()
{
    int ret = -1;
    int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    time_t theirSeconds = elapsedSeconds[them];

    if (!(phase & PHASE_PLAYING)) {
        return -1;
    }

    currentTime = time(NULL);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = ret = timePoint;
        startTime = currentTime - (elapsedSeconds[BLACK] + elapsedSeconds[WHITE]);
    } else {
        *ourSeconds = ret = currentTime - startTime - theirSeconds;
    }

    if (rule.maxTimeLedToLose > 0) {
        checkGameOverCondition();
    }

    return ret;
}

bool Position::checkGameOverCondition(int8_t updateCmdlist)
{
    if (phase & PHASE_NOTPLAYING) {
        return true;
    }

    if (rule.maxTimeLedToLose > 0) {
        phase = PHASE_GAMEOVER;

        if (updateCmdlist) {
            for (int i = 1; i <= 2; i++) {
                if (elapsedSeconds[i] > rule.maxTimeLedToLose * 60) {
                    elapsedSeconds[i] = rule.maxTimeLedToLose * 60;
                    winner = ~Color(i);
                    tips = "玩家" + Player::chToStr(Player::colorToCh(Color(i))) + "超时判负。";
                    sprintf(cmdline, "Time over. Player%d win!", ~Color(i));
                }
            }

            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    if (rule.maxStepsLedToDraw > 0 &&
        moveStep > rule.maxStepsLedToDraw) {
        winner = DRAW;
        phase = PHASE_GAMEOVER;
        if (updateCmdlist) {
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    for (int i = 1; i <= 2; i++)
    {
        if (nPiecesOnBoard[i] + nPiecesInHand[i] < rule.nPiecesAtLeast) {
            winner = ~Color(i);
            phase = PHASE_GAMEOVER;

            if (updateCmdlist) {
                sprintf(cmdline, "Player%d win!", winner);
                cmdlist.emplace_back(string(cmdline));
            }

            return true;
        }
    }

#ifdef MCTS_AI
#if 0
    int diff = nPiecesOnBoard[BLACK] - nPiecesOnBoard[WHITE];
    if (diff > 4) {
        winner = BLACK;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    if (diff < -4) {
        winner = WHITE;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }
#endif
#endif

    if (nPiecesOnBoard[BLACK] + nPiecesOnBoard[WHITE] >= Board::N_RANKS * Board::N_FILES) {
        phase = PHASE_GAMEOVER;

        if (rule.isBlackLosebutNotDrawWhenBoardFull) {
            winner = WHITE;
            if (updateCmdlist) {
                sprintf(cmdline, "Player2 win!");
            }
        } else {
            winner = DRAW; 
            if (updateCmdlist) {
                sprintf(cmdline, "Full. In draw!");
            }
        }

        if (updateCmdlist) {
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    if (phase == PHASE_MOVING && action == ACTION_SELECT && board.isAllSurrounded(sideToMove, nPiecesOnBoard)) {
        // TODO: move to next branch
        phase = PHASE_GAMEOVER;

        if (rule.isLoseButNotChangeTurnWhenNoWay) {
            if (updateCmdlist) {
                tips = "玩家" + Player::chToStr(Player::colorToCh(sideToMove)) + "无子可走被闷";
                winner = ~sideToMove;
                sprintf(cmdline, "Player%d no way to go. Player%d win!", sideToMove, winner);
                cmdlist.emplace_back(string(cmdline));  // TODO: memleak
            }

            return true;
        }

        changeSideToMove();

        return false;
    }

    return false;
}

int Position::getMobilityDiff(Color turn, int piecesOnBoard[], bool includeFobidden)
{
    // TODO: Deal with rule is no ban location
    Location *locations = board.locations;
    int mobilityBlack = 0;
    int mobilityWhite = 0;
    int diff = 0;
    int n = 0;

    for (Square i = SQ_BEGIN; i < SQ_END; i = static_cast<Square>(i + 1)) {
        n = board.getSurroundedEmptyLocationCount(turn, piecesOnBoard, i, includeFobidden);

        if (locations[i] & B_STONE) {
            mobilityBlack += n;
        } else if (locations[i] & W_STONE) {
            mobilityWhite += n;
        }
    }

    diff = mobilityBlack - mobilityWhite;

    return diff;
}

void Position::cleanBannedLocations()
{
    if (!rule.hasBannedLocations) {
        return;
    }

    Square square = SQ_0;

    for (int r = 1; r <= Board::N_FILES; r++) {
        for (int s = 0; s < Board::N_RANKS; s++) {
            square = static_cast<Square>(r * Board::N_RANKS + s);

            if (board.locations[square] == '\x0f') {
                revertKey(square);
                board.locations[square] = '\x00';
                board.byTypeBB[ALL_PIECES] ^= square;   // Need to remove?
            }
        }
    }
}

void Position::setSideToMove(Color c)
{
    sideToMove = c;
    them = ~sideToMove;
}

Color Position::getSideToMove()
{
    return sideToMove;
}

void Position::changeSideToMove()
{
    setSideToMove(~sideToMove);
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
    string turnStr = Player::chToStr(Player::colorToCh(sideToMove));

    switch (phase) {
    case PHASE_READY:
        tips = "轮到玩家1落子，剩余" + std::to_string(nPiecesInHand[BLACK]) + "子" +
            "  比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
        break;

    case PHASE_PLACING:
        if (action == ACTION_PLACE) {
            tips = "轮到玩家" + turnStr + "落子，剩余" + std::to_string(nPiecesInHand[sideToMove]) + "子";
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
        if (winner == DRAW) {
            score_draw++;
            tips = "双方平局！比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
            break;
        }

        winnerStr = Player::chToStr(Player::colorToCh(winner));

        score[winner]++;

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

void Position::constructKey()
{
    key = 0;
}

Key Position::getPosKey()
{
    // TODO: Move to suitable function
    return updateKeyMisc();
}

Key Position::updateKey(Square square)
{
    // PieceType is board.locations[square] 

    // 0b00 - no piece，0b01 = 1 black，0b10 = 2 white，0b11 = 3 ban
    int pieceType = board.locationToColor(square);
    // TODO: this is std, but current code can work
    //Location loc = board.locations[square];
    //int pieceType = loc == 0x0f? 3 : loc >> PLAYER_SHIFT;

    key ^= zobrist[square][pieceType];

    return key;
}

Key Position::revertKey(Square square)
{
    return updateKey(square);
}

Key Position::updateKeyMisc()
{
    const int KEY_MISC_BIT = 8;

    key = key << KEY_MISC_BIT >> KEY_MISC_BIT;
    Key hi = 0;

    if (sideToMove == WHITE) {
        hi |= 1U;
    }

    if (action == ACTION_REMOVE) {
        hi |= 1U << 1;
    }

    hi |= static_cast<Key>(nPiecesNeedRemove) << 2;
    hi |= static_cast<Key>(nPiecesInHand[BLACK]) << 4;     // TODO: may use phase is also OK?

    key = key | (hi << (CHAR_BIT * sizeof(Key) - KEY_MISC_BIT));

    return key;
}

Key Position::getNextPrimaryKey(Move m)
{
    Key npKey = key /* << 8 >> 8 */;
    Square sq = static_cast<Square>(to_sq(m));;
    MoveType mt = type_of(m);

    if (mt == MOVETYPE_REMOVE) {
        int pieceType = ~sideToMove;
        npKey ^= zobrist[sq][pieceType];

        if (rule.hasBannedLocations && phase == PHASE_PLACING) {
            npKey ^= zobrist[sq][BAN];
        }

        return npKey;
    }
    
    int pieceType = sideToMove;
    npKey ^= zobrist[sq][pieceType];

    if (mt == MOVETYPE_MOVE) {
        npKey ^= zobrist[from_sq(m)][pieceType];
    }

    return npKey;
}
