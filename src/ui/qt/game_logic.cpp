// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

void Game::handleDeletedPiece(const Position &p, PieceItem *piece, int key,
                              QParallelAnimationGroup *animationGroup,
                              PieceItem *&deletedPiece)
{
    QPointF pos;

    // Judge whether it is a removing seed or an unplaced one
    if (key & W_PIECE) {
        pos = (key - 0x11 < rule.pieceCount - p.count<IN_HAND>(WHITE)) ?
                  scene.pos_p2_g :
                  scene.pos_p1;
    } else {
        pos = (key - 0x21 < rule.pieceCount - p.count<IN_HAND>(BLACK)) ?
                  scene.pos_p1_g :
                  scene.pos_p2;
    }

    if (piece->pos() != pos) {
        // In order to prepare for the selection of the recently removed
        // pieces
        deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        if (position.get_phase() == Phase::moving) {
#endif
            auto *animation = new QPropertyAnimation(piece, "pos");
            animation->setDuration(durationTime);
            animation->setStartValue(piece->pos());
            animation->setEndValue(pos);
            animation->setEasingCurve(QEasingCurve::InOutQuad);
            animationGroup->addAnimation(animation);
#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        }
#endif
    }
}

void Game::handleBannedLocations(const Position &p, const Piece *board,
                                 int &nTotalPieces)
{
    QPointF pos;

    // Add banned points in placing phase
    if (rule.hasBannedLocations && p.get_phase() == Phase::placing) {
        for (int sq = SQ_BEGIN; sq < SQ_END; sq++) {
            if (board[sq] == BAN_PIECE) {
                pos = scene.polarCoordinateToPoint(static_cast<File>(sq / RANK_NB),
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

    // Clear banned points in moving phase
    if (rule.hasBannedLocations && p.get_phase() != Phase::placing) {
        while (nTotalPieces < static_cast<int>(pieceList.size())) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }
}

void Game::selectCurrentAndDeletedPieces(const Piece *board, const Position &p,
                                         int nTotalPieces,
                                         PieceItem *deletedPiece)
{
    // Select the current piece
    int ipos = p.current_square();
    int key;
    if (ipos) {
        key = board[p.current_square()];
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
bool Game::actionPiece(QPointF p)
{
    // Click non drop point, do not execute
    File f;
    Rank r;

    if (!validateClick(p, f, r))
        return false;

    if (!isRepentancePhase())
        return false;

    initiateGameIfReady();

    bool result = performAction(f, r, p);

    updateState(result);

    return result;
}

// TODO: Function name
bool Game::isRepentancePhase()
{
    // When you click the board while browsing the history, it is considered
    // repentance
    if (currentRow != moveListModel.rowCount() - 1) {
#ifndef QT_MOBILE_APP_UI
        // Define new dialog box
        QMessageBox msgBox;
        msgBox.setIcon(QMessageBox::Question);
        msgBox.setMinimumSize(600, 400);
        msgBox.setText(tr("You are looking back at an old position."));
        msgBox.setInformativeText(tr("Do you want to retract your moves?"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("Yes"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("No"));

        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !QT_MOBILE_APP_UI */
            const int rowCount = moveListModel.rowCount();
            const int removeCount = rowCount - currentRow - 1;
            moveListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            for (int i = 0; i < removeCount; i++) {
                gameMoveList.pop_back();
            }

            // If you regret the game, restart the timing
            if (position.get_winner() == NOBODY) {
                // Restart timing
                timeID = startTimer(100);

                // Signal update status bar
                updateScene();
                message = QString::fromStdString(getTips());
                emit statusBarChanged(message);
#ifndef QT_MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !QT_MOBILE_APP_UI */
        }
    }
    return true;
}
