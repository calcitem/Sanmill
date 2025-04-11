// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// pieceitem.cpp

#include "pieceitem.h"
#include "graphicsconst.h"
#include <QGraphicsSceneMouseEvent>
#include <QPainter>
#include <QStyleOption>

PieceItem::PieceItem(QGraphicsItem *parent)
    : QGraphicsItem(parent)
{
    Q_UNUSED(parent)
    setFlags(ItemIsSelectable
             // | ItemIsMovable
    );

    setCacheMode(DeviceCoordinateCache);

    setCursor(Qt::OpenHandCursor);

    // setAcceptedMouseButtons(Qt::LeftButton);

    setAcceptedMouseButtons(Qt::MouseButtons());
    // setAcceptHoverEvents(true);

    model = Models::noPiece;

    size = PIECE_SIZE;

    selectLineWeight = LINE_WEIGHT;

    removeLineWeight = LINE_WEIGHT * 5;

#ifdef QT_MOBILE_APP_UI
    selectLineColor = Qt::gray;
#else
    selectLineColor = Qt::darkYellow;
#endif /* QT_MOBILE_APP_UI */

    removeLineColor = QColor(227, 23, 13);
    removeLineColor.setAlphaF(0.9f);
}

PieceItem::~PieceItem() = default;

QRectF PieceItem::boundingRect() const
{
    return QRectF(-size / 2, -size / 2, size, size);
}

QPainterPath PieceItem::shape() const
{
    QPainterPath path;
    path.addEllipse(boundingRect());
    return path;
}

void PieceItem::paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
                      QWidget *widget)
{
    Q_UNUSED(option)
    Q_UNUSED(widget)

    // Empty models don't draw pieces

    switch (model) {
    case Models::whitePiece:
        // If the model is white, draw white pieces
#ifdef QT_MOBILE_APP_UI
        painter->setPen(Qt::NoPen);
        painter->setBrush(QColor(0, 93, 172));
        painter->drawEllipse(-size / 2, -size / 2, size, size);
#else
        painter->drawPixmap(-size / 2, -size / 2, size, size,
                            QPixmap(":/image/resources/image/white_piece.png"));
#endif /* QT_MOBILE_APP_UI */
        break;

    case Models::blackPiece:
        // If the model is black, draw black pieces
#ifdef QT_MOBILE_APP_UI
        painter->setPen(Qt::NoPen);
        painter->setBrush(QColor(231, 36, 46));
        painter->drawEllipse(-size / 2, -size / 2, size, size);
#else
        painter->drawPixmap(-size / 2, -size / 2, size, size,
                            QPixmap(":/image/resources/image/black_piece.png"));
#endif /* QT_MOBILE_APP_UI */
        break;
    case Models::noPiece:
        break;
    }

    // If the model requires the serial number to be displayed
    if (showNum) {
        if (model == Models::whitePiece)
            painter->setPen(QColor(255, 255, 255));

        if (model == Models::blackPiece)
            painter->setPen(QColor(0, 0, 0));

        QFont font;
        font.setFamily("Arial");
        font.setPointSize(size / 3);
        painter->setFont(font);

        painter->drawText(boundingRect().adjusted(0, 0, 0, -size / 12),
                          Qt::AlignCenter, QString::number(num));
    }

    // If the model is selected, draw four small right angles
    if (isSelected()) {
        const QPen pen(selectLineColor, selectLineWeight, Qt::SolidLine,
                       Qt::SquareCap, Qt::BevelJoin);
        painter->setPen(pen);
        const int xy = (size - selectLineWeight) / 2;

        painter->drawLine(-xy, -xy, -xy, -xy / 2);
        painter->drawLine(-xy, -xy, -xy / 2, -xy);
        painter->drawLine(xy, -xy, xy, -xy / 2);
        painter->drawLine(xy, -xy, xy / 2, -xy);
        painter->drawLine(xy, xy, xy, xy / 2);
        painter->drawLine(xy, xy, xy / 2, xy);
        painter->drawLine(-xy, xy, -xy, xy / 2);
        painter->drawLine(-xy, xy, -xy / 2, xy);
    }

    // If the model is deleted, cross it
    if (deleted) {
        const QPen pen(removeLineColor, removeLineWeight, Qt::SolidLine,
                       Qt::SquareCap, Qt::BevelJoin);
        painter->setPen(pen);

        painter->drawLine(-size / 3, -size / 3, size / 3, size / 3);
        painter->drawLine(size / 3, -size / 3, -size / 3, size / 3);
    }
}

void PieceItem::mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    // When the mouse is pressed, it becomes the shape of the hand it holds
    setCursor(Qt::ClosedHandCursor);
    QGraphicsItem::mousePressEvent(mouseEvent);
}

void PieceItem::mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    QGraphicsItem::mouseMoveEvent(mouseEvent);
}

void PieceItem::mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    // When the mouse is released, it becomes an extended hand
    setCursor(Qt::OpenHandCursor);
    QGraphicsItem::mouseReleaseEvent(mouseEvent);
}
