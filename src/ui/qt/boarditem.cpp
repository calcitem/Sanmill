/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#include "boarditem.h"
#include "graphicsconst.h"
#include <QPainter>
#include "types.h"

BoardItem::BoardItem(QGraphicsItem *parent) :
    size(BOARD_SIZE)
{
    Q_UNUSED(parent)

        // 棋盘中心放在场景中心
        setPos(0, 0);

    // 初始化24个落子点
    for (int r = 0; r < FILE_NB; r++) {
        // 内圈的12点钟方向为第一个位置，按顺时针方向排序
        // 然后是中圈和外圈
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
#ifndef MOBILE_APP_UI
    QColor shadowColor(128, 42, 42);
    shadowColor.setAlphaF(0.3);
    painter->fillRect(boundingRect(), QBrush(shadowColor));
#endif /* ! MOBILE_APP_UI */

    // 填充图片
#ifdef MOBILE_APP_UI
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(239, 239, 239));
    painter->drawRect(-size / 2, -size / 2, size, size);
#else
    painter->drawPixmap(-size / 2, -size / 2, size, size,
                        QPixmap(":/image/resources/image/board.png"));
#endif /* MOBILE_APP_UI */

    // 实线画笔
#ifdef  MOBILE_APP_UI
    QPen pen(QBrush(QColor(241, 156, 159)), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
#else
    QPen pen(QBrush(QColor(178, 34, 34)), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
#endif
    painter->setPen(pen);

    // 空画刷
    painter->setBrush(Qt::NoBrush);

    for (uint8_t i = 0; i < FILE_NB; i++) {
        // 画3个方框
        painter->drawPolygon(position + i * RANK_NB, RANK_NB);
    }

    // 画4条纵横线
    for (int i = 0; i  < RANK_NB; i += 2) {
        painter->drawLine(position[i], position[(FILE_NB - 1) * RANK_NB + i]);
    }

    if (hasObliqueLine) {
        // 画4条斜线
        for (int i = 1; i  < RANK_NB; i += 2) {
            painter->drawLine(position[i], position[(FILE_NB - 1) * RANK_NB + i]);
        }
    }

#ifdef PLAYER_DRAW_SEAT_NUMBER
    // 画 Seat 编号
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

QPointF BoardItem::polar2pos(File file, Rank rank)
{
    return position[((int)file - 1) * RANK_NB + (int)rank - 1]; // TODO: 为什么是 r - 1 和算法部分不一样?
}

bool BoardItem::pos2polar(QPointF pos, File &file, Rank &rank)
{
    // 寻找最近的落子点
    for (int i = 0; i < FILE_NB * RANK_NB; i++) {
        // 如果pos点在落子点附近
        if (QLineF(pos, position[i]).length() < PIECE_SIZE / 6) {
            file = File(i / RANK_NB + 1);
            rank = Rank(i % RANK_NB + 1);
            return true;
        }
    }

    return false;
}
