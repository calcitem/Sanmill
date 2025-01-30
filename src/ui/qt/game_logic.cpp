// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_logic.cpp

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

void Game::handleRemovedPiece(PieceItem *piece, int key,
                              QParallelAnimationGroup *animationGroup,
                              PieceItem *&deletedPiece)
{
    QPointF pos;

    // Judge whether it is a removing seed or an unplaced one
    if (key & W_PIECE) {
        pos = (key - 0x11 < rule.pieceCount - position.count<IN_HAND>(WHITE)) ?
                  scene.pos_p2_g :
                  scene.pos_p1;
    } else {
        pos = (key - 0x21 < rule.pieceCount - position.count<IN_HAND>(BLACK)) ?
                  scene.pos_p1_g :
                  scene.pos_p2;
    }

    if (piece && piece->pos() != pos) {
        // In order to prepare for the selection of the recently removed pieces
        deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        if (position.get_phase() == Phase::moving) {
#endif
            auto *animation = buildPieceAnimation(piece, piece->pos(), pos,
                                                  durationTime);
            if (animation) {
                animationGroup->addAnimation(animation);
            }
#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        }
#endif
    }
}

void Game::processMarkedSquares()
{
    QPointF pos;
    int nTotalPieces = rule.pieceCount * 2;
    const Piece *board = position.get_board();

    // Add marked points in placing phase
    if (rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase::markAndDelayRemovingPieces &&
        position.get_phase() == Phase::placing) {
        for (int sq = SQ_BEGIN; sq < SQ_END; sq++) {
            if (board[sq] == MARKED_PIECE) {
                pos = scene.convertFromPolarCoordinate(
                    static_cast<File>(sq / RANK_NB),
                    static_cast<Rank>(sq % RANK_NB + 1));
                if (nTotalPieces < static_cast<int>(pieceList.size())) {
                    pieceList.at(static_cast<size_t>(nTotalPieces++))
                        ->setPos(pos);
                } else {
                    auto *newP = new PieceItem;
                    newP->setDeleted();
                    newP->setPos(pos);
                    pieceList.push_back(newP);
                    nTotalPieces++;
                    scene.addItem(newP);
                }
            }
        }
    }

    // Clear marked points in moving phase
    if (rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase::markAndDelayRemovingPieces &&
        position.get_phase() != Phase::placing) {
        while (nTotalPieces < static_cast<int>(pieceList.size())) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }
}

void Game::selectActiveAndRemovedPieces(PieceItem *deletedPiece)
{
    const Piece *board = position.get_board();
    int nTotalPieces = rule.pieceCount * 2;

    // Select the current piece
    int ipos = position.current_square();
    int key;
    if (ipos) {
        key = board[position.current_square()];
        ipos = key & W_PIECE ? (key - W_PIECE_1) * 2 :
                               (key - B_PIECE_1) * 2 + 1;
        if (ipos >= 0 && ipos < nTotalPieces) {
            currentPiece = pieceList.at(static_cast<size_t>(ipos));
            currentPiece->setSelected(true);
        }
    }

    // Set the most recently removed pieces to select action
    if (deletedPiece) {
        deletedPiece->setSelected(true);
    }
}

// Key slot function, according to the signal and state of qgraphics scene to
// select, drop or remove sub
bool Game::handleBoardClick(QPointF point)
{
    // Click non drop point, do not execute
    File f;
    Rank r;

    if (!isValidBoardClick(point, f, r))
        return false;

    if (!undoMovesIfReviewing())
        return false;

    initGameIfReady();

    bool result = applyBoardAction(f, r, point);

    updateGameState(result);

    return result;
}

// TODO: Function name
bool Game::undoMovesIfReviewing()
{
    // Activated when the user clicks on the board while reviewing past moves.
    // This action is considered as a request to undo moves.
    if (currentRow != moveListModel.rowCount() - 1) {
#ifndef QT_MOBILE_APP_UI
        // Initialize a new dialog box for user confirmation
        QMessageBox msgBox;
        msgBox.setIcon(QMessageBox::Question);
        msgBox.setMinimumSize(600, 400);
        msgBox.setText(tr("You're reviewing a previous board state."));
        msgBox.setInformativeText(tr("Would you like to undo your recent "
                                     "moves?"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("Yes"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("No"));

        // If the user confirms, execute the following logic
        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !QT_MOBILE_APP_UI */
            // Determine the number of moves to be retracted
            const int rowCount = moveListModel.rowCount();
            const int removeCount = rowCount - currentRow - 1;
            // Remove retracted moves from the model
            moveListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            // Update internal move list
            for (int i = 0; i < removeCount; i++) {
                gameMoveList.pop_back();
            }

            // If no winner has been determined, restart the timer
            if (position.get_winner() == NOBODY) {
                // Restart game timer
                timeID = startTimer(100);
                refreshStatusBar();
#ifndef QT_MOBILE_APP_UI
            }
        } else {
            // If user cancels, exit function and return false
            return false;
#endif /* !QT_MOBILE_APP_UI */
        }
    }
    // If currentRow equals the last row in moveListModel, no action is taken
    return true;
}
