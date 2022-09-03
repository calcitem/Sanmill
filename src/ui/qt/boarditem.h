// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

    // Use UserType + 1 to represent mill pieces, and determines whether it is
    // an object of the boarditem class Another way is to put the class name in
    // the 0key position of data, SetData(0, "BoardItem"), and then use data(0)
    // to judge
    enum { Type = UserType + 1 };

    [[nodiscard]] int type() const noexcept override { return Type; }

    // Set with or without diagonal
    void setDiagonal(bool arg = true);

    // Return to the nearest placing point
    QPointF nearestPosition(QPointF pos);

    // The circle and position of the model are transformed into the point
    // coordinates
    [[nodiscard]] QPointF polar2pos(File file, Rank rank) const;

    // The coordinates of the falling point are transformed into circles and
    // positions for the model
    [[nodiscard]] bool pos2polar(QPointF pos, File &f, Rank &r) const;

private:
    int size; // board size
    int sizeShadow {5};
    QPointF position[SQUARE_NB]; // 24 points
    bool hasDiagonalLine {false};
};

#endif // BOARDITEM_H_INCLUDED
