/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef CHESSITEM_H
#define CHESSITEM_H

#include <QObject>
#include <QGraphicsItem>

#include "config.h"

class PieceItem : public QObject, public QGraphicsItem
{
    Q_OBJECT
        Q_INTERFACES(QGraphicsItem)

        // 位置属性
        Q_PROPERTY(QPointF pos READ pos WRITE setPos)

public:
    explicit PieceItem(QGraphicsItem *parent = nullptr);

    ~PieceItem() override;

    QRectF boundingRect() const override;

    QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // 用UserType+2表示棋子，用qgraphicsitem_cast()判断是否为PieceItem类的对象
    // 还有一个方式是把类名放在Data的0key位置setData(0, "PieceItem")，然后用data(0)来判断
    enum
    {
        Type = UserType + 2
    };

    int type() const override
    {
        return Type;
    }

    // 模型状态枚举，用位运算标明
    enum Models
    {
        noPiece = 0x1,      // 空棋子
        blackPiece = 0x2,   // 黑色棋子
        whitePiece = 0x4,   // 白色棋子
    };

    enum Models getModel()
    {
        return model_;
    }

    void setModel(enum Models model)
    {
        this->model_ = model;
    }

    int getNum()
    {
        return num;
    }

    void setNum(int n)
    {
        num = n;
    }

    bool isDeleted()
    {
        return deleted_;
    }

    void setDeleted(bool deleted = true)
    {
        this->deleted_ = deleted;

        if (deleted)
            this->model_ = noPiece;

        update(boundingRect());
    }

    void setShowNum(bool show = true)
    {
        this->showNum = show;
    }

protected:
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

private:
    // 棋子本质
    enum Models model_;

    // 棋子序号，黑白都从1开始
    int num = 1;

    // 棋子尺寸
    int size;

    // 有无删除线
    bool deleted_ {false};

    // 显示序号
    bool showNum {false};

    // 选中子标识线宽度
    int chooseLineWeight;

    // 删除线宽度
    int removeLineWeight;

    // 选中线颜色
    QColor chooseLineColor;

    // 删除线颜色
    QColor removeLineColor;
};

#endif // CHESSITEM_H
