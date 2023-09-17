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

// Toggle piece color
void Game::togglePieceColor()
{
    isInverted = !isInverted;
    updatePieceColor();
}

// Update piece color based on the value of 'isInverted'
void Game::updatePieceColor()
{
    // Iterate through all pieces
    for (PieceItem *pieceItem : pieceList) {
        if (pieceItem) {
            swapColor(pieceItem);
        }
    }
}

// Swap the color of a single piece
void Game::swapColor(PieceItem *pieceItem)
{
    auto model = pieceItem->getModel();
    if (model == PieceItem::Models::whitePiece)
        pieceItem->setModel(PieceItem::Models::blackPiece);
    else if (model == PieceItem::Models::blackPiece)
        pieceItem->setModel(PieceItem::Models::whitePiece);

    // Update display
    pieceItem->update();
}

// Execute a transformation on the board
void Game::executeTransform(const TransformFunc &transform)
{
    // Stop AI threads before transformation
    stopAndWaitAiThreads();

    // Apply transformation
    transform(position, moveHistory);

    // Update UI components
    updateUIComponents();

    // Restart AI threads after transformation
    startAiThreads();
}

// Update UI components like move history and scene
void Game::updateUIComponents()
{
    int row = 0;
    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }
    syncScene(row - 1);
}

// Synchronize the current scene based on move history
void Game::syncScene(int row)
{
    if (currentRow == row) {
        updateScene();
    } else {
        phaseChange(currentRow, true);
    }
}

// Transformation function implementations
void Game::mirrorAndRotate(Position &position,
                           std::vector<std::string> &moveHistory)
{
    position.mirror(moveHistory);
    position.rotate(moveHistory, 180);
}


// Define transformation functions
void Game::flip()
{
    executeTransform(mirrorAndRotate);
}
void Game::mirror()
{
    executeTransform(applyMirror);
}
void Game::turnRight()
{
    executeTransform(rotateRight);
}
void Game::turnLeft()
{
    executeTransform(rotateLeft);
}

void Game::applyMirror(Position &position,
                       std::vector<std::string> &moveHistory)
{
    position.mirror(moveHistory);
}

void Game::rotateRight(Position &position,
                       std::vector<std::string> &moveHistory)
{
    position.rotate(moveHistory, -90);
}

void Game::rotateLeft(Position &position, std::vector<std::string> &moveHistory)
{
    position.rotate(moveHistory, 90);
}
