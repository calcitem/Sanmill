// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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
    board->setDiagonal(false);
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
    p = board->getNearestPoint(p);
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

QPointF GameScene::polarCoordinateToPoint(File f, Rank r) const
{
    return board->polarCoordinateToPoint(f, r);
}

bool GameScene::pointToPolarCoordinate(QPointF pos, File &f, Rank &r) const
{
    return board->pointToPolarCoordinate(pos, f, r);
}

void GameScene::setDiagonal(bool arg) const
{
    if (board) {
        board->setDiagonal(arg);
    }
}
