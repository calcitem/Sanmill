/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
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

#ifndef BOARDITEM_H
#define BOARDITEM_H

#include <QGraphicsItem>

#include "config.h"

class BoardItem : public QGraphicsItem
{
public:
    explicit BoardItem(QGraphicsItem *parent = nullptr);
    ~BoardItem();

    QRectF boundingRect() const;

    QPainterPath shape() const;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr);

    // 用UserType+1表示棋子，用qgraphicsitem_cast()判断是否为BoardItem类的对象
    // 还有一个方式是把类名放在Data的0key位置setData(0, "BoardItem")，然后用data(0)来判断
    enum
    {
        Type = UserType + 1
    };

    int type() const
    {
        return Type;
    }

    // 设置有无斜线
    void setDiagonal(bool arg = true);

    // 返回最近的落子点
    QPointF nearestPosition(QPointF const pos);

    // 将模型的圈、位转化为落子点坐标
    QPointF cp2pos(int c, int p);

    // 将落子点坐标转化为模型用的圈、位
    bool pos2cp(QPointF pos, int &c, int &p);

    // 3圈，禁止修改！
    static const uint8_t N_RINGS = 3;

    // 8位，禁止修改！
    static const uint8_t N_SEATS = 8;

private:
    // 棋盘尺寸
    int size;

    // 影子尺寸
    int sizeShadow;

    // 24个落子点
    QPointF position[N_RINGS * N_SEATS];

    // 是否有斜线
    bool hasObliqueLine;
};

#endif // BOARDITEM_H
