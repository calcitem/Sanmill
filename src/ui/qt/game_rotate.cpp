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
 * void Game::executeTransform(const TransformFunc &transform)
 * {
 *     stopAndWaitAiThreads();   // old code
 *     transform();
 *     updateUIComponents();
 *     startAiThreads();         // old code
 * }
 *
 * We replace these calls with the new approach. If you need to forcibly
 * stop tasks prior to transforming, you can call Threads.stop_all().
 * Then, if you want to re-queue AI tasks, you can do so by checking which
 * side is AI and calling submitAiTask(...). But if you do not need that,
 * you can simply call transform() and update your UI.
 */

void Game::executeTransform(const TransformFunc &transform)
{
    transform();
    updateUIComponents();
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
    position.flipHorizontally(gameMoveList);
    position.rotate(gameMoveList, 180);
}

// Define transformation functions
void Game::flipVertically()
{
    executeTransform([this]() { mirrorAndRotate(); });
}
void Game::flipHorizontally()
{
    executeTransform([this]() { applyMirror(); });
}
void Game::rotateClockwise()
{
    executeTransform([this]() { rotateRight(); });
}
void Game::RotateCounterclockwise()
{
    executeTransform([this]() { rotateLeft(); });
}

void Game::applyMirror()
{
    position.flipHorizontally(gameMoveList);
}

void Game::rotateRight()
{
    position.rotate(gameMoveList, -90);
}

void Game::rotateLeft()
{
    position.rotate(gameMoveList, 90);
}
