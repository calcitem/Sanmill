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

void Game::invertPieceColor(bool arg)
{
    isInverted = arg;

    // For all pieces
    for (PieceItem *pieceItem : pieceList) {
        if (pieceItem) {
            // White -> Black
            if (pieceItem->getModel() == PieceItem::Models::whitePiece)
                pieceItem->setModel(PieceItem::Models::blackPiece);

            // Black -> White
            else if (pieceItem->getModel() == PieceItem::Models::blackPiece)
                pieceItem->setModel(PieceItem::Models::whitePiece);

            // Refresh board display
            pieceItem->update();
        }
    }
}


void Game::executeTransform(
    std::function<void(Position &, std::vector<std::string> &)> transform)
{
    stopAndWaitAiThreads();

    transform(position, moveHistory);

    // Update move history
    int row = 0;
    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }

    // Update display
    if (currentRow == row - 1) {
        updateScene();
    } else {
        phaseChange(currentRow, true);
    }

    threadsSetAi(&position);
    startAiThreads();
}

void Game::flip()
{
    executeTransform(
        [](Position &position, std::vector<std::string> &moveHistory) {
            position.mirror(moveHistory);
            position.rotate(moveHistory, 180);
        });
}

void Game::mirror()
{
    executeTransform(
        [](Position &position, std::vector<std::string> &moveHistory) {
            position.mirror(moveHistory);
        });
}

void Game::turnRight()
{
    executeTransform(
        [](Position &position, std::vector<std::string> &moveHistory) {
            position.rotate(moveHistory, -90);
        });
}

void Game::turnLeft()
{
    executeTransform(
        [](Position &position, std::vector<std::string> &moveHistory) {
            position.rotate(moveHistory, 90);
        });
}
