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

#include "boarditem.h"
#include "graphicsconst.h"
#include <QPainter>

BoardItem::BoardItem(QGraphicsItem *parent) :
    size(BOARD_SIZE)
{
    Q_UNUSED(parent)

        // 棋盘中心放在场景中心
        setPos(0, 0);

    // 初始化24个落子点
    for (int r = 0; r < N_RINGS; r++) {
        // 内圈的12点钟方向为第一个位置，按顺时针方向排序
        // 然后是中圈和外圈
        int a = (r + 1) * LINE_INTERVAL;

        position[r * N_SEATS + 0].rx() = 0;
        position[r * N_SEATS + 0].ry() = -a;

        position[r * N_SEATS + 1].rx() = a;
        position[r * N_SEATS + 1].ry() = -a;

        position[r * N_SEATS + 2].rx() = a;
        position[r * N_SEATS + 2].ry() = 0;

        position[r * N_SEATS + 3].rx() = a;
        position[r * N_SEATS + 3].ry() = a;

        position[r * N_SEATS + 4].rx() = 0;
        position[r * N_SEATS + 4].ry() = a;

        position[r * N_SEATS + 5].rx() = -a;
        position[r * N_SEATS + 5].ry() = a;

        position[r * N_SEATS + 6].rx() = -a;
        position[r * N_SEATS + 6].ry() = 0;

        position[r * N_SEATS + 7].rx() = -a;
        position[r * N_SEATS + 7].ry() = -a;
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
    hasObliqueLine = arg;
    update(boundingRect());
}

void BoardItem::paint(QPainter *painter,
                      const QStyleOptionGraphicsItem *option,
                      QWidget *widget)
{
    Q_UNUSED(option)
    Q_UNUSED(widget)

    // 填充阴影
    painter->fillRect(boundingRect(), QBrush(QColor(64, 64, 64)));

    // 填充图片
    painter->drawPixmap(-size / 2, -size / 2, size, size,
                        QPixmap(":/image/resources/image/board.png"));

    // 黑色实线画笔
    QPen pen(QBrush(Qt::black), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
    painter->setPen(pen);

    // 空画刷
    painter->setBrush(Qt::NoBrush);

    for (uint8_t i = 0; i < N_RINGS; i++) {
        // 画3个方框
        painter->drawPolygon(position + i * N_SEATS, N_SEATS);
    }

    // 画4条纵横线
    for (int i = 0; i  < N_SEATS; i += 2) {
        painter->drawLine(position[i], position[(N_RINGS - 1) * N_SEATS + i]);
    }

    if (hasObliqueLine) {
        // 画4条斜线
        for (int i = 1; i  < N_SEATS; i += 2) {
            painter->drawLine(position[i], position[(N_RINGS - 1) * N_SEATS + i]);
        }
    }

#ifdef DRAW_SEAT_NUMBER
    // 画 Seat 编号
    QPen fontPen(QBrush(Qt::white), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
    painter->setPen(fontPen);
    QFont font;
    font.setPointSize(4);
    font.setFamily("Arial");
    font.setLetterSpacing(QFont::AbsoluteSpacing, 0);
    painter->setFont(font);

    for (int i = 0; i < N_SEATS; i++) {
        char cSeat = '1' + i;
        QString strSeat(cSeat);
        painter->drawText(position[(N_RINGS - 1) * N_SEATS + i], strSeat);
    }
#endif // DRAW_SEAT_NUMBER
}

QPointF BoardItem::nearestPosition(QPointF const pos)
{
    // 初始最近点设为(0,0)点
    QPointF nearestPos = QPointF(0, 0);

    // 寻找最近的落子点
    for (auto i : position) {
        // 如果鼠标点距离落子点在棋子半径内
        if (QLineF(pos, i).length() < PIECE_SIZE / 2) {
            nearestPos = i;
            break;
        }
    }

    return nearestPos;
}

QPointF BoardItem::cp2pos(int c, int p)
{
    return position[(c - 1) * N_SEATS + p - 1];
}

bool BoardItem::pos2cp(QPointF pos, int &c, int &p)
{
    // 寻找最近的落子点
    for (int i = 0; i < N_RINGS * N_SEATS; i++) {
        // 如果pos点在落子点附近
        if (QLineF(pos, position[i]).length() < PIECE_SIZE / 6) {
            c = i / N_SEATS + 1;
            p = i % N_SEATS + 1;
            return true;
        }
    }

    return false;
}
