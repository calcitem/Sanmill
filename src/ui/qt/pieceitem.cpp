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

#include "pieceitem.h"
#include "graphicsconst.h"
#include <QGraphicsSceneMouseEvent>
#include <QPainter>
#include <QStyleOption>

PieceItem::PieceItem(QGraphicsItem *parent)
    : QGraphicsItem(parent)
{
    Q_UNUSED(parent)
    configurePieceItem();
}

PieceItem::~PieceItem() = default;

void PieceItem::configurePieceItem()
{
    setFlags(ItemIsSelectable);
    setCacheMode(DeviceCoordinateCache);
    setCursor(Qt::OpenHandCursor);
    setAcceptedMouseButtons(Qt::MouseButtons());

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
    removeLineColor.setAlphaF(0.9);
}

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
    drawPiece(painter);
    drawNum(painter);
    drawSelected(painter);
    drawDeleted(painter);
}

void PieceItem::mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    setCursor(Qt::ClosedHandCursor);
    QGraphicsItem::mousePressEvent(mouseEvent);
}

void PieceItem::mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    QGraphicsItem::mouseMoveEvent(mouseEvent);
}

void PieceItem::mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent)
{
    setCursor(Qt::OpenHandCursor);
    QGraphicsItem::mouseReleaseEvent(mouseEvent);
}

void PieceItem::drawPiece(QPainter *painter)
{
    switch (model) {
    case Models::whitePiece:
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
}

void PieceItem::drawNum(QPainter *painter)
{
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
}

void PieceItem::drawSelected(QPainter *painter)
{
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
}

void PieceItem::drawDeleted(QPainter *painter)
{
    if (deleted) {
        const QPen pen(removeLineColor, removeLineWeight, Qt::SolidLine,
                       Qt::SquareCap, Qt::BevelJoin);
        painter->setPen(pen);

        painter->drawLine(-size / 3, -size / 3, size / 3, size / 3);
        painter->drawLine(size / 3, -size / 3, -size / 3, size / 3);
    }
}
