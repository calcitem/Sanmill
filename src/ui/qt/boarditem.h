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

#ifndef BOARDITEM_H_INCLUDED
#define BOARDITEM_H_INCLUDED

#include <QGraphicsItem>

#include "graphicsconst.h"
#include "config.h"
#include "types.h"

class BoardItem : public QGraphicsItem
{
public:
    explicit BoardItem(const QGraphicsItem *parent = nullptr);
    ~BoardItem() override;

    [[nodiscard]] QRectF boundingRect() const override;

    [[nodiscard]] QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // Utilize UserType + 1 as a unique identifier for instances of the
    // BoardItem class. An alternative approach would be to store the class name
    // using setData(0, "BoardItem") and subsequently use data(0) for object
    // identification.
    enum { Type = UserType + 1 };

    [[nodiscard]] int type() const noexcept override { return Type; }

     // Enable or disable diagonal lines on the board
    void setDiagonal(bool enableDiagonal = true);

    // Get the nearest point on the board to the given point
    QPointF getNearestPoint(QPointF targetPoint);

    // Convert polar coordinates (File and Rank) to Cartesian point
    [[nodiscard]] QPointF polarCoordinateToPoint(File f, Rank r) const;

    // Convert Cartesian point to polar coordinates (File and Rank)
    [[nodiscard]] bool pointToPolarCoordinate(QPointF point, File &f, Rank &r) const;

private:
    void initPoints();
    void drawBoard(QPainter *painter);
    void drawLines(QPainter *painter);
    void drawCoordinates(QPainter *painter);
    void drawPolarCoordinates(QPainter *painter);

    // Side length of the square board
    int boardSideLength {BOARD_SIDE_LENGTH};

    // Size of the board's shadow
    int boardShadowSize {BOARD_SHADOW_SIZE};

    // Points representing board positions
    QPointF points[SQUARE_NB]; // 24 points

    // Flag to indicate if diagonal lines are enabled
    bool hasDiagonalLine {false};
};

#endif // BOARDITEM_H_INCLUDED
