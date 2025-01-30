// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// gameview.cpp

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
    case TransformType::rotateBoardCounterclockwise:
        newTransform = QTransform(0, -1, 1, 0, 0, 0);
        break;
    }

    setTransform(transform() * newTransform);
}

void GameView::flipBoardVertically()
{
    applyTransform(TransformType::FlipVertically);
}

void GameView::flipBoardHorizontally()
{
    applyTransform(TransformType::FlipHorizontally);
}

void GameView::rotateBoardClockwise()
{
    applyTransform(TransformType::RotateClockwise);
}

void GameView::rotateBoardCounterclockwise()
{
    applyTransform(TransformType::rotateBoardCounterclockwise);
}

void GameView::resizeEvent(QResizeEvent *event)
{
    QGraphicsView::resizeEvent(event);
    fitInView(sceneRect(), Qt::KeepAspectRatio);
}
