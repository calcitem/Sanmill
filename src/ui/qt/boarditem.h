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

#include "types.h"
#include <QGraphicsItem>

class BoardItem : public QGraphicsItem
{
public:
    explicit BoardItem(const QGraphicsItem *parent = nullptr);
    ~BoardItem() override;

    QRectF boundingRect() const override;
    QPainterPath shape() const override;
    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    int type() const noexcept override;
    void setDiagonal(bool arg = true);

    QPointF nearestPosition(const QPointF &pos);
    QPointF polar2pos(File file, Rank rank) const;
    bool pos2polar(const QPointF &pos, File &f, Rank &r) const;

private:
    int size; // board size
    int sizeShadow {5};
    QPointF position[SQUARE_NB]; // 24 points
    bool hasDiagonalLine {false};

    static constexpr int BoardItemType = UserType + 1;
};

#endif // BOARDITEM_H_INCLUDED
