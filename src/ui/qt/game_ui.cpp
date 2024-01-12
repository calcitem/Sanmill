// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <iomanip>
#include <map>
#include <string>

#include <QAbstractButton>
#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsView>
#include <QKeyEvent>
#include <QMessageBox>
#include <QParallelAnimationGroup>
#include <QPropertyAnimation>
#include <QSoundEffect>
#include <QThread>
#include <QTimer>

#include "boarditem.h"
#include "client.h"
#include "game.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

void Game::setAnimation(bool arg) noexcept
{
    hasAnimation = arg;

    // The default animation time is 500ms
    if (hasAnimation)
        durationTime = 500;
    else
        durationTime = 0;

    settings->setValue("Options/Animation", arg);
}

void Game::updateStatusBar(bool reset)
{
    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    qreal advantage = (double)position.bestvalue /
                      (VALUE_EACH_PIECE *
                       (rule.pieceCount - rule.piecesAtLeastCount));
    if (advantage < -1) {
        advantage = -1;
    }

    if (advantage > 1) {
        advantage = 1;
    }

    if (isAiPlayer[WHITE] && !isAiPlayer[BLACK]) {
        advantage = -advantage;
    }

    if (reset) {
        advantage = 0;
    }

    // TODO: updateStatusBar but also emit advantageChanged
    emit advantageChanged(advantage);
}

void Game::updateLCDDisplays()
{
    emit score1Changed(QString::number(position.score[WHITE], 10));
    emit score2Changed(QString::number(position.score[BLACK], 10));
    emit scoreDrawChanged(QString::number(position.score_draw, 10));

    // Update winning rate LCD display
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 /
                        position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 /
                        position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 /
                           position.gamesPlayedCount;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));
}

void Game::updateLcdDisplay()
{
    // Update LCD display
    emit nGamesPlayedChanged(QString::number(position.gamesPlayedCount, 10));
    emit score1Changed(QString::number(position.score[WHITE], 10));
    emit score2Changed(QString::number(position.score[BLACK], 10));
    emit scoreDrawChanged(QString::number(position.score_draw, 10));

    // Update winning rate LCD display
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;

    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 /
                        position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 /
                        position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 /
                           position.gamesPlayedCount;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));
}

void Game::reinitMoveListModel()
{
    moveListModel.removeRows(0, moveListModel.rowCount());
    moveListModel.insertRow(0);
    moveListModel.setData(moveListModel.index(0), position.get_record());
    currentRow = 0;
}

bool Game::updateScene()
{
    // The deleted pieces are in place
    PieceItem *deletedPiece = nullptr;

    // Animate pieces and find deleted pieces
    // TODO: Rename
    animatePieceMovement(deletedPiece);

    // Handle banned locations
    handleBannedLocations();

    // Select the current and recently deleted pieces
    selectCurrentAndDeletedPieces(deletedPiece);

    // Update LCD displays
    updateLCDDisplays();

    // Update tips
    setTips();

    return true;
}

void Game::animatePieceMovement(PieceItem *&deletedPiece)
{
    int key;
    QPointF pos;
    const Piece *board = position.get_board();
    // Animation group
    auto *animationGroup = new QParallelAnimationGroup;

    // Total number of pieces
    int nTotalPieces = rule.pieceCount * 2;

    for (int i = 0; i < nTotalPieces; i++) {
        const auto piece = pieceList.at(static_cast<size_t>(i));

        piece->setSelected(false);

        // Convert the subscript of pieceList to the code of game
        key = (i % 2) ? (i / 2 + B_PIECE_1) : (i / 2 + W_PIECE_1);

        int j;

        // Traverse the board, find and place the pieces on the board
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.polarCoordinateToPoint(
                    static_cast<File>(j / RANK_NB),
                    static_cast<Rank>(j % RANK_NB + 1));
                if (piece->pos() != pos) {
                    // Let the moving pieces be at the top level
                    piece->setZValue(1);

                    // Pieces movement animation
                    auto *animation = new QPropertyAnimation(piece, "pos");
                    animation->setDuration(durationTime);
                    animation->setStartValue(piece->pos());
                    animation->setEndValue(pos);
                    animation->setEasingCurve(QEasingCurve::InOutQuad);
                    animationGroup->addAnimation(animation);
                } else {
                    // Let the still pieces be at the bottom
                    piece->setZValue(0);
                }
                break;
            }
        }

        // If not, place the pieces outside the board
        if (j == RANK_NB * (FILE_NB + 1)) {
            handleDeletedPiece(piece, key, animationGroup, deletedPiece);
        }

        piece->setSelected(false); // TODO: Need?
    }

    animationGroup->start(QAbstractAnimation::DeleteWhenStopped);
}

inline char Game::colorToChar(Color color)
{
    return static_cast<char>('0' + color);
}

inline std::string Game::charToString(char ch)
{
    if (ch == '1') {
        return "White";
    }

    return "Black";
}

void Game::setTips()
{
    Position &p = position;

    string winnerStr, reasonStr, resultStr, scoreStr;
    string turnStr;

    if (isInverted) {
        turnStr = charToString(colorToChar(~p.sideToMove));
    } else {
        turnStr = charToString(colorToChar(p.sideToMove));
    }

#ifdef NNUE_GENERATE_TRAINING_DATA
    if (p.winner == WHITE) {
        nnueTrainingDataGameResult = "1-0";
    } else if (p.winner == BLACK) {
        nnueTrainingDataGameResult = "0-1";
    } else if (p.winner == DRAW) {
        nnueTrainingDataGameResult = "1/2-1/2";
    } else {
    }
#endif /* NNUE_GENERATE_TRAINING_DATA */

    switch (p.phase) {
    case Phase::ready:
        // TODO: Uncaught fun_call_w_exception:
        // Called function throws an exception of type
        // std::bad_array_new_length.
        tips = turnStr + " to place a piece. " +
               std::to_string(p.pieceInHandCount[WHITE]) +
               " pieces remain unplaced. Score: " + to_string(p.score[WHITE]) +
               ":" + to_string(p.score[BLACK]) +
               ", Draws: " + to_string(p.score_draw);
        break;

    case Phase::placing:
        if (p.action == Action::place) {
            tips = turnStr + " to place a piece. " +
                   std::to_string(p.pieceInHandCount[p.sideToMove]) +
                   " pieces remain unplaced.";
        } else if (p.action == Action::remove) {
            tips = turnStr + " to remove a piece. " +
                   std::to_string(p.pieceToRemoveCount[p.sideToMove]) +
                   " pieces can be removed.";
        } else if (p.action == Action::select) {
            tips = turnStr + " to select a piece.";
        }
        break;

    case Phase::moving:
        if (p.action == Action::place || p.action == Action::select) {
            tips = turnStr + " to make a move.";
        } else if (p.action == Action::remove) {
            tips = turnStr + " to remove a piece. " +
                   std::to_string(p.pieceToRemoveCount[p.sideToMove]) +
                   " pieces can be removed.";
        }
        break;

    case Phase::gameOver:
        appendGameOverReasonToMoveList();

        scoreStr = "Score " + to_string(p.score[WHITE]) + " : " +
                   to_string(p.score[BLACK]) + ", Draw " +
                   to_string(p.score_draw);

        switch (p.winner) {
        case WHITE:
        case BLACK:
            winnerStr = charToString(colorToChar(p.winner));
            resultStr = winnerStr + " won! ";
            break;
        case DRAW:
            resultStr = "Draw! ";
            break;
        case NOCOLOR:
        case COLOR_NB:
        case NOBODY:
            break;
        }

        switch (p.gameOverReason) {
        case GameOverReason::loseFewerThanThree:
            break;
        case GameOverReason::loseNoLegalMoves:
            reasonStr = turnStr + " has no valid moves.";
            break;
        case GameOverReason::loseFullBoard:
            reasonStr = turnStr + " loses; board is full.";
            break;
        case GameOverReason::loseResign:
            reasonStr = turnStr + " has resigned.";
            break;
        case GameOverReason::loseTimeout:
            reasonStr = "Time is up; " + turnStr + " loses.";
            break;
        case GameOverReason::drawThreefoldRepetition:
            reasonStr = "Draw due to threefold repetition.";
            break;
        case GameOverReason::drawFiftyMove:
            reasonStr = "Draw under the 50-move rule.";
            break;
        case GameOverReason::drawEndgameFiftyMove:
            reasonStr = "Draw under the endgame 50-move rule.";
            break;
        case GameOverReason::drawFullBoard:
            reasonStr = "Draw; board is full.";
            break;
        case GameOverReason::drawStalemateCondition:
            reasonStr = "Stalemate; game is a draw.";
            break;
        case GameOverReason::None:
            break;
        }

        tips = reasonStr + " " + resultStr + scoreStr;
        break;

    case Phase::none:
        break;
    }

    tips = to_string(position.bestvalue) + " | " + tips;
}

void Game::resetUIElements()
{
    // Clear pieces
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // Redraw pieces
    scene.setDiagonal(rule.hasDiagonalLines);

    // Draw all the pieces and put them in the starting position
    // 0: the first piece in the first hand; 1: the first piece in the second
    // hand 2: the first second piece; 3: the second piece
    // ......

    for (int i = 0; i < rule.pieceCount; i++) {
        // The first piece
        PieceItem::Models md = isInverted ? PieceItem::Models::blackPiece :
                                            PieceItem::Models::whitePiece;
        auto newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p1);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);

        // Backhand piece
        md = isInverted ? PieceItem::Models::whitePiece :
                          PieceItem::Models::blackPiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p2);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);
    }
}

void Game::showTestWindow() const
{
    gameTest->show();
}

void Game::showDatabaseDialog() const
{
    databaseDialog->show();
}

#ifdef NET_FIGHT_SUPPORT
void Game::showNetworkWindow()
{
    getServer()->show();
    getClient()->show();
}
#endif

void Game::updateMiscellaneous()
{
    // Sound effects play
    // playSound(":/sound/resources/sound/newgame.wav");
}

void Game::setEditing(bool arg) noexcept
{
    isEditing = arg;
}
