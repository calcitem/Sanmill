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
