// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// gamescene.cpp

#include <QGraphicsItem>
#include <QGraphicsScene>
#include <QGraphicsSceneMouseEvent>
#include <QKeyEvent>

#include "boarditem.h"
#include "gamescene.h"
#include "graphicsconst.h"
#include "pieceitem.h"
#include "types.h"

GameScene::GameScene(QObject *parent)
    : QGraphicsScene(parent)
    , board(std::make_unique<BoardItem>())
{
    board->setDiagonalLineEnabled(false);
    addItem(board.get());
}

void GameScene::mouseDoubleClickEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    // Block double click events
    mouseEvent->accept();
}

void GameScene::mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    // Screen mouse down events
    mouseEvent->accept();
}

void GameScene::mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    // Only handle left click events
    if (mouseEvent->button() != Qt::LeftButton) {
        mouseEvent->accept();
        return;
    }

    // If it's a board
    const QGraphicsItem *item = itemAt(mouseEvent->scenePos(), QTransform());

    if (!item || item->type() == BoardItem::Type) {
        handleBoardClick(mouseEvent);
    } else if (item->type() == PieceItem::Type) {
        handlePieceClick(item);
    }

    mouseEvent->accept();
}

void GameScene::handleBoardClick(QGraphicsSceneMouseEvent *mouseEvent)
{
    QPointF p = mouseEvent->scenePos();
    p = board->findNearestPoint(p);
    if (p != QPointF(0, 0)) {
        // Send the nearest drop point of the mouse point
        emit mouseReleased(p);
    }
}

void GameScene::handlePieceClick(const QGraphicsItem *item)
{
    // If it's a piece
    // Send out the position of the current piece in the scene
    emit mouseReleased(item->scenePos());
}

QPointF GameScene::convertFromPolarCoordinate(File f, Rank r) const
{
    return board->convertFromPolarCoordinate(f, r);
}

bool GameScene::convertToPolarCoordinate(QPointF pos, File &f, Rank &r) const
{
    return board->convertToPolarCoordinate(pos, f, r);
}

void GameScene::setDiagonalLineEnabled(bool arg) const
{
    if (board) {
        board->setDiagonalLineEnabled(arg);
    }
}
