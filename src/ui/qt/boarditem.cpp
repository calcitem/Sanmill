/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <QPainter>

#include "boarditem.h"
#include "graphicsconst.h"
#include "types.h"

BoardItem::BoardItem(QGraphicsItem* parent)
    : size(BOARD_SIZE)
{
    Q_UNUSED(parent)

    // Put center of the board in the center of the scene
    setPos(0, 0);

    // Initialize 24 points
    for (int r = 0; r < FILE_NB; r++) {
        // The first position is the 12 o'clock direction of the inner ring, which is sorted clockwise
        // Then there is the middle ring and the outer ring
        int a = (r + 1) * LINE_INTERVAL;

        position[r * RANK_NB + 0].rx() = 0;
        position[r * RANK_NB + 0].ry() = -a;

        position[r * RANK_NB + 1].rx() = a;
        position[r * RANK_NB + 1].ry() = -a;

        position[r * RANK_NB + 2].rx() = a;
        position[r * RANK_NB + 2].ry() = 0;

        position[r * RANK_NB + 3].rx() = a;
        position[r * RANK_NB + 3].ry() = a;

        position[r * RANK_NB + 4].rx() = 0;
        position[r * RANK_NB + 4].ry() = a;

        position[r * RANK_NB + 5].rx() = -a;
        position[r * RANK_NB + 5].ry() = a;

        position[r * RANK_NB + 6].rx() = -a;
        position[r * RANK_NB + 6].ry() = 0;

        position[r * RANK_NB + 7].rx() = -a;
        position[r * RANK_NB + 7].ry() = -a;
    }
}

BoardItem::~BoardItem() = default;

QRectF BoardItem::boundingRect() const
{
    return QRectF(-size / 2, -size / 2, size + sizeShadow, size + sizeShadow);
}

QPainterPath BoardItem::shape() const
{
    QPainterPath path;
    path.addRect(boundingRect());

    return path;
}

void BoardItem::setDiagonal(bool arg)
{
    hasDiagonalLine = arg;
    update(boundingRect());
}

void BoardItem::paint(QPainter* painter,
    const QStyleOptionGraphicsItem* option,
    QWidget* widget)
{
    Q_UNUSED(option)
    Q_UNUSED(widget)

    // Fill shadow
#ifndef QT_MOBILE_APP_UI
    QColor shadowColor(128, 42, 42);
    shadowColor.setAlphaF(0.3);
    painter->fillRect(boundingRect(), QBrush(shadowColor));
#endif /* ! QT_MOBILE_APP_UI */

    // Fill in picture
#ifdef QT_MOBILE_APP_UI
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(239, 239, 239));
    painter->drawRect(-size / 2, -size / 2, size, size);
#else
    painter->drawPixmap(-size / 2, -size / 2, size, size,
        QPixmap(":/image/resources/image/board.png"));
#endif /* QT_MOBILE_APP_UI */

    // Solid line brush
#ifdef QT_MOBILE_APP_UI
    QPen pen(QBrush(QColor(241, 156, 159)), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
#else
    QPen pen(QBrush(QColor(178, 34, 34)), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
#endif
    painter->setPen(pen);

    // No brush
    painter->setBrush(Qt::NoBrush);

    for (uint8_t i = 0; i < FILE_NB; i++) {
        // Draw three boxes
        painter->drawPolygon(position + i * RANK_NB, RANK_NB);
    }

    // Draw 4 vertical and horizontal lines
    for (int i = 0; i < RANK_NB; i += 2) {
        painter->drawLine(position[i], position[(FILE_NB - 1) * RANK_NB + i]);
    }

    if (hasDiagonalLine) {
        // Draw 4 diagonal lines
        for (int i = 1; i < RANK_NB; i += 2) {
            painter->drawLine(position[i], position[(FILE_NB - 1) * RANK_NB + i]);
        }
    }

#ifdef PLAYER_DRAW_SEAT_NUMBER
    // Draw the seat number
    QPen fontPen(QBrush(Qt::white), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
    painter->setPen(fontPen);
    QFont font;
    font.setPointSize(4);
    font.setFamily("Arial");
    font.setLetterSpacing(QFont::AbsoluteSpacing, 0);
    painter->setFont(font);

    for (int i = 0; i < RANK_NB; i++) {
        char cSeat = '1' + i;
        QString strSeat(cSeat);
        painter->drawText(position[(FILE_NB - 1) * RANK_NB + i], strSeat);
    }
#endif // PLAYER_DRAW_SEAT_NUMBER
}

QPointF BoardItem::nearestPosition(QPointF const pos)
{
    // The initial closest point is set to (0,0) point
    QPointF nearestPos = QPointF(0, 0);

    // Look for the nearest spot
    for (auto i : position) {
        // If the distance between the mouse point and the falling point is within the radius of the piece
        if (QLineF(pos, i).length() < PIECE_SIZE / 2) {
            nearestPos = i;
            break;
        }
    }

    return nearestPos;
}

QPointF BoardItem::polar2pos(File file, Rank rank)
{
    return position[((int)file - 1) * RANK_NB + (int)rank - 1];
}

bool BoardItem::pos2polar(QPointF pos, File& file, Rank& rank)
{
    // Look for the nearest spot
    for (int i = 0; i < EFFECTIVE_SQUARE_NB; i++) {
        // If the pos point is near the placing point
        if (QLineF(pos, position[i]).length() < PIECE_SIZE / 6) {
            file = File(i / RANK_NB + 1);
            rank = Rank(i % RANK_NB + 1);
            return true;
        }
    }

    return false;
}
