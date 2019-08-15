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

#include "pieceitem.h"
#include "graphicsconst.h"
#include <QPainter>
#include <QGraphicsSceneMouseEvent>
#include <QStyleOption>

PieceItem::PieceItem(QGraphicsItem *parent) :
    QGraphicsItem(parent),
    num(0),
    deleted_(false),
    showNum(false)
{
    Q_UNUSED(parent)
        // 允许选择和移动
        setFlags(ItemIsSelectable
                 // | ItemIsMovable
        );

    // 设置缓存模式
    setCacheMode(DeviceCoordinateCache);

    // 鼠标放在棋子上时显示为伸开的手形
    setCursor(Qt::OpenHandCursor);

    // 只接受左键事件
    //setAcceptedMouseButtons(Qt::LeftButton);

    // 不接受鼠标事件
    setAcceptedMouseButtons(nullptr);
    //setAcceptHoverEvents(true);

    // 默认模型为没有棋子
    model_ = noPiece;

    // 棋子尺寸
    size = PIECE_SIZE;

    // 选中子标识线宽度
    chooseLineWeight = LINE_WEIGHT;

    // 删除线宽度
    removeLineWeight = LINE_WEIGHT * 5;

    // 选中线为黄色
    chooseLineColor = Qt::darkYellow;

    // 删除线为橘红色
    removeLineColor = QColor(0xff, 0x75, 0);
}

PieceItem::~PieceItem()
{
}

QRectF PieceItem::boundingRect() const
{
    return QRectF(-size / 2, -size / 2, size, size);
}

QPainterPath PieceItem::shape() const
{
    QPainterPath path;
    path.addEllipse(boundingRect());
    return path;
}

void PieceItem::paint(QPainter *painter,
                      const QStyleOptionGraphicsItem *option,
                      QWidget *widget)
{
    Q_UNUSED(option)
        Q_UNUSED(widget)

    // 空模型不画棋子

    switch (model_) {
    case blackPiece:
        // 如果模型为黑色，则画黑色棋子
        painter->drawPixmap(-size / 2, -size / 2, size, size,
            QPixmap(":/image/resources/image/black_piece.png"));
        break;

    case whitePiece:
        // 如果模型为白色，则画白色棋子
        painter->drawPixmap(-size / 2, -size / 2, size, size,
            QPixmap(":/image/resources/image/white_piece.png"));
        break;
    default:
        break;
    }

    // 如果模型要求显示序号
    if (showNum) {
        // 如果模型为黑色，用白色笔画序号
        if (model_ == blackPiece)
            painter->setPen(QColor(255, 255, 255));

        // 如果模型为白色，用白色笔画序号
        if (model_ == whitePiece)
            painter->setPen(QColor(0, 0, 0));

        // 字体
        QFont font;
        font.setFamily("Arial");
        font.setPointSize(size / 3);
        painter->setFont(font);

        // 画序号，默认中间位置偏下，需微调
        painter->drawText(boundingRect().adjusted(0, 0, 0, -size / 12),
                            Qt::AlignCenter, QString::number(num));

    }

    // 如果模型为选中状态，则画上四个小直角
    if (isSelected()) {
        QPen pen(chooseLineColor, chooseLineWeight, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
        painter->setPen(pen);
        int xy = (size - chooseLineWeight) / 2;

        painter->drawLine(-xy, -xy, -xy, -xy / 2);
        painter->drawLine(-xy, -xy, -xy / 2, -xy);
        painter->drawLine(xy, -xy, xy, -xy / 2);
        painter->drawLine(xy, -xy, xy / 2, -xy);
        painter->drawLine(xy, xy, xy, xy / 2);
        painter->drawLine(xy, xy, xy / 2, xy);
        painter->drawLine(-xy, xy, -xy, xy / 2);
        painter->drawLine(-xy, xy, -xy / 2, xy);
    }

    // 如果模型为删除状态，则画上叉号
    if (deleted_) {
        QPen pen(removeLineColor, removeLineWeight, Qt::SolidLine, Qt::SquareCap, Qt::BevelJoin);
        painter->setPen(pen);

        painter->drawLine(-size / 3, -size / 3, size / 3, size / 3);
        painter->drawLine(size / 3, -size / 3, -size / 3, size / 3);
    }
}

void PieceItem::mousePressEvent(QGraphicsSceneMouseEvent *event)
{
    // 鼠标按下时变为握住的手形
    setCursor(Qt::ClosedHandCursor);
    QGraphicsItem::mousePressEvent(event);
}

void PieceItem::mouseMoveEvent(QGraphicsSceneMouseEvent *event)
{
    QGraphicsItem::mouseMoveEvent(event);
}

void PieceItem::mouseReleaseEvent(QGraphicsSceneMouseEvent *event)
{
    // 鼠标松开时变为伸开的手形
    setCursor(Qt::OpenHandCursor);
    QGraphicsItem::mouseReleaseEvent(event);
}
