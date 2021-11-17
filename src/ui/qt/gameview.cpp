// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
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

#include <QTransform>

#include "gameview.h"

GameView::GameView(QWidget* parent)
    : QGraphicsView(parent)
{
    Q_UNUSED(parent)
}

GameView::~GameView() = default;

void GameView::flip()
{
    // Flip view up and down
    /* The following uses a lot of knowledge about graphic transformation matrix
     * Do not use the scale method, QT graphics transformation is for the
     * coordinate system Scale matrix to sx  0  0 S = 0 sy  0 0  0  1 The up and
     * down flip should be multiplied by the following matrix on the basis of
     * the original transformation matrix: 1  0  0 0 -1  0 0  0  1
     */

    // Method 1: directly multiply the original transformation matrix by the
    // above matrix QMatrix only assigns values to the first two columns of the
    // transformation matrix
    setTransform(transform() * QTransform(1, 0, 0, -1, 0, 0));

    /* Method 2: manually calculate the new transformation matrix and then
    assign a value to the scene
     * The efficiency of this method is not necessarily high, and manual
    calculation is needed QMatrix mt = matrix(); mt.setMatrix(-mt.m11(),
    mt.m12(), -mt.m21(), mt.m22(), -mt.dx(), mt.dy()); setMatrix(mt);
     */
}

void GameView::mirror()
{
    // Left and right mirror of view
    /* The left and right mirror images shall be multiplied by the following
     matrix on the basis of the original transformation matrix:
     * -1  0  0
     *  0  1  0
     *  0  0  1
     */
    setTransform(transform() * QTransform(-1, 0, 0, 1, 0, 0));
}

void GameView::turnRight()
{
    // The view must be rotated 90 degree clockwise
    /*  Don't use the scale method.
        After the view is mirrored or flipped, its steering will be reversed
     *  The rotation matrix is
     *     cos(a)  sin(a)  0
     * R = sin(a)  cos(a)  0
     *       0       0     1
     * The view must be rotated 90 degree clockwise and multiplied by
     * the following matrix on the basis of the original transformation matrix:
     *  0  1  0
     * -1  0  0
     *  0  0  1
     */
    setTransform(transform() * QTransform(0, 1, -1, 0, 0, 0));
}

void GameView::turnLeft()
{
    // View rotated 90 degree counterclockwise
    /* When the view is rotated 90 degree counterclockwise,
     * it should be multiplied by the following matrix
     * on the basis of the original transformation matrix:
     * 0 -1  0
     * 1  0  0
     * 0  0  1
     */
    setTransform(transform() * QTransform(0, -1, 1, 0, 0, 0));
}

void GameView::resizeEvent(QResizeEvent* event)
{
    QGraphicsView::resizeEvent(event);
    fitInView(sceneRect(), Qt::KeepAspectRatio);
}
