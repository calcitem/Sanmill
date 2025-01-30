// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// pieceitem.h

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

    QRectF boundingRect() const override;

    QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // Use UserType + 2 to represent pieces,
    // and use qgraphicsitems_cast() determines whether it is an object of the
    // pieceitem class Another way is to put the class name in the 0key position
    // of data, setData(0, "pieceitem"), and then use data(0) to judge
    enum { Type = UserType + 2 };

    int type() const noexcept override { return Type; }

    enum class Models {
        noPiece = 0x1,
        whitePiece = 0x2,
        blackPiece = 0x4,
    };

    Models getModel() const noexcept { return model; }

    void setModel(Models m) noexcept { this->model = m; }

    int getNum() const noexcept { return num; }

    void setNum(int n) noexcept { num = n; }

    bool isDeleted() const noexcept { return deleted; }

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
