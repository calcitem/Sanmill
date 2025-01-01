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

#include "gameview.h"

GameView::GameView(QWidget *parent)
    : QGraphicsView(parent)
{
    Q_UNUSED(parent)
}

GameView::~GameView() = default;

void GameView::applyTransform(TransformType type)
{
    QTransform newTransform;

    switch (type) {
    case TransformType::FlipVertically:
        newTransform = QTransform(1, 0, 0, -1, 0, 0);
        break;
    case TransformType::FlipHorizontally:
        newTransform = QTransform(-1, 0, 0, 1, 0, 0);
        break;
    case TransformType::RotateClockwise:
        newTransform = QTransform(0, 1, -1, 0, 0, 0);
        break;
    case TransformType::RotateCounterclockwise:
        newTransform = QTransform(0, -1, 1, 0, 0, 0);
        break;
    }

    setTransform(transform() * newTransform);
}

void GameView::flipVertically()
{
    applyTransform(TransformType::FlipVertically);
}

void GameView::flipHorizontally()
{
    applyTransform(TransformType::FlipHorizontally);
}

void GameView::rotateClockwise()
{
    applyTransform(TransformType::RotateClockwise);
}

void GameView::RotateCounterclockwise()
{
    applyTransform(TransformType::RotateCounterclockwise);
}

void GameView::resizeEvent(QResizeEvent *event)
{
    QGraphicsView::resizeEvent(event);
    fitInView(sceneRect(), Qt::KeepAspectRatio);
}
