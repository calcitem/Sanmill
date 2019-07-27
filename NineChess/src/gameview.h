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

// 派生这个类主要是为了让视图适应场景大小及图像旋转镜像操作
#ifndef GRAPHICSVIEW_H
#define GRAPHICSVIEW_H

#include <QGraphicsView>

#include "config.h"

class GameView : public QGraphicsView
{
    Q_OBJECT

public:
    explicit GameView(QWidget *parent);
    ~GameView();

public slots:
    void flip();
    void mirror();
    void turnRight();
    void turnLeft();

protected:
    void resizeEvent(QResizeEvent *event);

private:
    // 缩放因子，代码更新后不使用了
    // qreal sx, sy;
};

#endif // GRAPHICSVIEW_H
