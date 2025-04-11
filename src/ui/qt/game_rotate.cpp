// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_rotate.cpp

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
#include "thread_pool.h" // If you want to optionally stop/restart tasks
#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

// Toggle piece color
void Game::togglePieceColors()
{
    isInverted = !isInverted;
    updatePieceColors();
}

// Update piece color based on the value of 'isInverted'
void Game::updatePieceColors()
{
    // Iterate through all pieces
    for (PieceItem *pieceItem : pieceList) {
        if (pieceItem) {
            swapPieceColor(pieceItem);
        }
    }
}

// Swap the color of a single piece
void Game::swapPieceColor(PieceItem *pieceItem)
{
    auto model = pieceItem->getModel();
    if (model == PieceItem::Models::whitePiece) {
        pieceItem->setModel(PieceItem::Models::blackPiece);
    } else if (model == PieceItem::Models::blackPiece) {
        pieceItem->setModel(PieceItem::Models::whitePiece);
    }

    // Update display
    pieceItem->update();
}

/*
 * Old code:
 * void Game::applyTransform(const TransformFunc &transform)
 * {
 *     stopAndWaitAiThreads();   // old code
 *     transform();
 *     refreshUIComponents();
 *     startAiThreads();         // old code
 * }
 *
 * We replace these calls with the new approach. If you need to forcibly
 * stop tasks prior to transforming, you can call Threads.stop_all().
 * Then, if you want to re-queue AI tasks, you can do so by checking which
 * side is AI and calling submitAiSearch(...). But if you do not need that,
 * you can simply call transform() and update your UI.
 */

void Game::applyTransform(const TransformFunc &transform)
{
    transform();
    refreshUIComponents();
}

// Update UI components like move list and scene
void Game::refreshUIComponents()
{
    int row = 0;
    for (const auto &str : *getMoveList()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }
    syncSceneWithRow(row - 1);
}

// Synchronize the current scene based on move list
void Game::syncSceneWithRow(int row)
{
    if (currentRow == row) {
        refreshScene();
    } else {
        refreshBoardState(currentRow, true);
    }
}

// Transformation function implementations
void Game::flipAndRotateBoard()
{
    position.flipBoardHorizontally(gameMoveList);
    position.rotate(gameMoveList, 180);
}

// Define transformation functions
void Game::flipBoardVertically()
{
    applyTransform([this]() { flipAndRotateBoard(); });
}
void Game::flipBoardHorizontally()
{
    applyTransform([this]() { applyHorizontalFlip(); });
}
void Game::rotateBoardClockwise()
{
    applyTransform([this]() { rotateBoardRight(); });
}
void Game::rotateBoardCounterclockwise()
{
    applyTransform([this]() { rotateBoardLeft(); });
}

void Game::applyHorizontalFlip()
{
    position.flipBoardHorizontally(gameMoveList);
}

void Game::rotateBoardRight()
{
    position.rotate(gameMoveList, -90);
}

void Game::rotateBoardLeft()
{
    position.rotate(gameMoveList, 90);
}
