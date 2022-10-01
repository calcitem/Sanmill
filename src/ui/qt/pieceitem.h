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

#ifndef PIECE_ITEM_H_INCLUDED
#define PIECE_ITEM_H_INCLUDED

#include <QGraphicsItem>
#include <QObject>

#include "config.h"

class PieceItem : public QObject, public QGraphicsItem
{
    Q_OBJECT
    Q_INTERFACES(QGraphicsItem)
    Q_PROPERTY(QPointF pos READ pos WRITE setPos)

public:
    explicit PieceItem(QGraphicsItem *parent = nullptr);

    ~PieceItem() override;

    [[nodiscard]] QRectF boundingRect() const override;

    [[nodiscard]] QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // Use UserType + 2 to represent pieces,
    // and use qgraphicsitems_cast() determines whether it is an object of the
    // pieceitem class Another way is to put the class name in the 0key position
    // of data, setData(0, "pieceitem"), and then use data(0) to judge
    enum { Type = UserType + 2 };

    [[nodiscard]] int type() const noexcept override { return Type; }

    enum class Models {
        noPiece = 0x1,
        whitePiece = 0x2,
        blackPiece = 0x4,
    };

    [[nodiscard]] Models getModel() const noexcept { return model; }

    void setModel(Models m) noexcept { this->model = m; }

    [[nodiscard]] int getNum() const noexcept { return num; }

    void setNum(int n) noexcept { num = n; }

    [[nodiscard]] bool isDeleted() const noexcept { return deleted; }

    void setDeleted(bool del = true)
    {
        deleted = del;

        if (deleted)
            this->model = Models::noPiece;

        update(boundingRect());
    }

    void setShowNum(bool show = true) noexcept { this->showNum = show; }

protected:
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

private:
    Models model;

    // Piece number
    int num {0};

    int size {0};

    // Is there a delete line
    bool deleted {false};

    bool showNum {false};

    int selectLineWeight {0};

    int removeLineWeight {0};

    QColor selectLineColor;

    QColor removeLineColor;
};

#endif // PIECE_ITEM_H_INCLUDED
