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

#ifndef GAMESCENE_H
#define GAMESCENE_H

#include <QGraphicsScene>

#include "config.h"

class BoardItem;

class GameScene : public QGraphicsScene
{
    Q_OBJECT
public:
    explicit GameScene(QObject *parent = nullptr);
    ~GameScene() override;

    // 将模型的圈、位转化为落子点坐标
    QPointF cp2pos(int c, int p);

    // 将落子点坐标转化为模型用的圈、位
    bool pos2cp(QPointF pos, int &c, int &p);

    // 设置棋盘斜线
    void setDiagonal(bool arg = true);

    // 玩家1的己方棋盒及对方棋盒位置
    const QPointF pos_p1, pos_p1_g;

    // 玩家2的己方棋盒及对方棋盒位置
    const QPointF pos_p2, pos_p2_g;

protected:
    //void keyPressEvent(QKeyEvent *keyEvent);
    void mouseDoubleClickEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

signals:
    void mouseReleased(QPointF);

public slots:

private:
    // 棋盘对象
    BoardItem *board {nullptr};

};

#endif // GAMESCENE_H
