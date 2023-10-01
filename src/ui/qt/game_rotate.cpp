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
    transform();

    // Update UI components
    updateUIComponents();

    // Restart AI threads after transformation
    startAiThreads();
}

// Update UI components like move list and scene
void Game::updateUIComponents()
{
    int row = 0;
    for (const auto &str : *getMoveList()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }
    syncScene(row - 1);
}

// Synchronize the current scene based on move list
void Game::syncScene(int row)
{
    if (currentRow == row) {
        updateScene();
    } else {
        updateBoardState(currentRow, true);
    }
}

// Transformation function implementations
void Game::mirrorAndRotate()
{
    position.mirror(gameMoveList);
    position.rotate(gameMoveList, 180);
}


// Define transformation functions
void Game::flip()
{
    executeTransform([this]() { mirrorAndRotate(); });
}
void Game::mirror()
{
    executeTransform([this]() { applyMirror(); });
}
void Game::turnRight()
{
    executeTransform([this]() { rotateRight(); });
}
void Game::turnLeft()
{
    executeTransform([this]() { rotateLeft(); });
}

void Game::applyMirror()
{
    position.mirror(gameMoveList);
}

void Game::rotateRight()
{
    position.rotate(gameMoveList, -90);
}

void Game::rotateLeft()
{
    position.rotate(gameMoveList, 90);
}
