// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_ui.cpp

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

// Set the piece animation
QPropertyAnimation *Game::buildPieceAnimation(PieceItem *piece,
                                              const QPointF &startPos,
                                              const QPointF &endPos,
                                              int duration)
{
    if (!piece) {
        qDebug() << "piece is nullptr in buildPieceAnimation";
        return nullptr;
    }

    auto *animation = new QPropertyAnimation(piece, "pos");
    animation->setDuration(duration);
    animation->setStartValue(startPos);
    animation->setEndValue(endPos);
    animation->setEasingCurve(QEasingCurve::InOutQuad);
    return animation;
}

void Game::refreshStatusBar(bool reset)
{
    QString thinkingMessage = "";

    if (hasActiveAiTasks()) {
        Color side = position.side_to_move();
        if (isAiPlayer[side]) {
            QString sideName = (side == WHITE ? "White" : "Black");
            thinkingMessage = QString("%1 is thinking...").arg(sideName);
        }
    }

    // Signal update status bar
    // refreshScene();
    message = QString::fromStdString(getTips()) + " " + thinkingMessage;
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

    // TODO: refreshStatusBar but also emit advantageChanged
    emit advantageChanged(advantage);
}

void Game::refreshLcdDisplay()
{
    switch (position.winner) {
    case WHITE:
        score[WHITE]++;
        break;
    case BLACK:
        score[BLACK]++;
        break;
    case DRAW:
        score[DRAW]++;
        break;
    case COLOR_NB:
    case NOBODY:
        break;
    }

    // Update LCD display
    emit nGamesPlayedChanged(QString::number(gamesPlayedCount, 10));
    emit score1Changed(QString::number(score[WHITE], 10));
    emit score2Changed(QString::number(score[BLACK], 10));
    emit scoreDrawChanged(QString::number(score[DRAW], 10));

    // Update winning rate LCD display
    gamesPlayedCount = score[WHITE] + score[BLACK] + score[DRAW];
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;

    if (gamesPlayedCount != 0) {
        winningRate_1 = score[WHITE] * 10000 / gamesPlayedCount;
        winningRate_2 = score[BLACK] * 10000 / gamesPlayedCount;
        winningRate_draw = score[DRAW] * 10000 / gamesPlayedCount;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));
}

void Game::resetMoveListModel()
{
    moveListModel.removeRows(0, moveListModel.rowCount());
    moveListModel.insertRow(0);
    moveListModel.setData(moveListModel.index(0), position.get_record());
    currentRow = 0;
}

bool Game::refreshScene()
{
    // The deleted pieces are in place
    PieceItem *deletedPiece = nullptr;

    // Animate pieces and find deleted pieces
    // TODO: Rename
    animatePieces(deletedPiece);

    // Handle marked locations
    processMarkedSquares();

    // Select the current and recently deleted pieces
    selectActiveAndRemovedPieces(deletedPiece);

    // Update LCD displays
    // refreshLcdDisplay();

    // Update tips
    updateTips();

    return true;
}

void Game::animatePieces(PieceItem *&deletedPiece)
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
        assert(piece != nullptr);

        piece->setSelected(false);

        // Convert the subscript of pieceList to the code of game
        key = (i % 2) ? (i / 2 + B_PIECE_1) : (i / 2 + W_PIECE_1);

        int j;

        // Traverse the board, find and place the pieces on the board
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.convertFromPolarCoordinate(
                    static_cast<File>(j / RANK_NB),
                    static_cast<Rank>(j % RANK_NB + 1));
                if (piece && piece->pos() != pos) {
                    // Let the moving pieces be at the top level
                    piece->setZValue(1);

                    // Pieces movement animation
                    auto *animation = buildPieceAnimation(piece, piece->pos(),
                                                          pos, durationTime);
                    if (animation) {
                        animationGroup->addAnimation(animation);
                    }
                } else {
                    // Let the still pieces be at the bottom
                    piece->setZValue(0);
                }
                break;
            }
        }

        // If not, place the pieces outside the board
        if (j == RANK_NB * (FILE_NB + 1)) {
            handleRemovedPiece(piece, key, animationGroup, deletedPiece);
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

void Game::updateTips()
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
        } else if (rule.mayMoveInPlacingPhase &&
                   (p.action == Action::select || p.action == Action::place)) {
            tips = turnStr + " to place or move a piece. " +
                   std::to_string(p.pieceInHandCount[p.sideToMove]) +
                   " pieces remain unplaced.";
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
        recordGameOverReason();

        scoreStr = "Score " + to_string(score[WHITE]) + " : " +
                   to_string(score[BLACK]) + ", Draw " + to_string(score[DRAW]);

        switch (p.winner) {
        case WHITE:
        case BLACK:
            winnerStr = charToString(colorToChar(p.winner));
            resultStr = winnerStr + " won! ";
            break;
        case DRAW:
            resultStr = "Draw! ";
            break;
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

void Game::resetUiComponents()
{
    // Clear pieces
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // Redraw pieces
    scene.setDiagonalLineEnabled(rule.hasDiagonalLines);

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

void Game::displayTestWindow() const
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

void Game::updateMisc()
{
    // Sound effects play
    // playGameSound(":/sound/resources/sound/newgame.wav");
}

void Game::setEditingModeEnabled(bool arg) noexcept
{
    isEditing = arg;
}
