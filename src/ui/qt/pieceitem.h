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

#ifndef GAMEITEM_H
#define GAMEITEM_H

#include <QObject>
#include <QGraphicsItem>

#include "config.h"

class PieceItem : public QObject, public QGraphicsItem
{
    Q_OBJECT
        Q_INTERFACES(QGraphicsItem)
        Q_PROPERTY(QPointF pos READ pos WRITE setPos)

public:
    explicit PieceItem(QGraphicsItem *parent = nullptr);

    ~PieceItem() override;

    QRectF boundingRect() const override;

    QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // Use UserType + 2 to represent pieces, 
    // and use qgraphicsitems_cast() determines whether it is an object of the pieceitem class
    // Another way is to put the class name in the 0key position of data, 
    // setData(0, "pieceitem"), and then use data(0) to judge
    enum
    {
        Type = UserType + 2
    };

    int type() const noexcept override
    {
        return Type;
    }

    enum class Models
    {
        noPiece = 0x1,
        whitePiece = 0x2,
        blackPiece = 0x4,
    };

    enum Models getModel() noexcept
    {
        return model;
    }

    void setModel(enum Models m) noexcept
    {
        this->model = m;
    }

    int getNum() noexcept
    {
        return num;
    }

    void setNum(int n) noexcept
    {
        num = n;
    }

    bool isDeleted() noexcept
    {
        return deleted;
    }

    void setDeleted(bool del = true)
    {
        deleted = del;

        if (deleted)
            this->model = Models::noPiece;

        update(boundingRect());
    }

    void setShowNum(bool show = true) noexcept
    {
        this->showNum = show;
    }

protected:
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

private:
    enum Models model;

    // Piece number, white and black all start from 1
    int num  {1};

    int size {0};

    // Is there a delete line
    bool deleted {false};

    bool showNum {false};

    int selectLineWeight {0};

    int removeLineWeight {0};

    QColor selectLineColor;

    QColor removeLineColor;
};

#endif // GAMEITEM_H
