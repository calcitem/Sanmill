/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

#ifndef GAMESCENE_H
#define GAMESCENE_H

#include <QGraphicsScene>

#include "config.h"
#include "types.h"

class BoardItem;

class GameScene : public QGraphicsScene
{
    Q_OBJECT
public:
    explicit GameScene(QObject *parent = nullptr);
    ~GameScene() override;

    QPointF polar2pos(File file, Rank rank);

    bool pos2polar(QPointF pos, File &file, Rank &rank);

    void setDiagonal(bool arg = true);

    // Position of player 1's own board and opponent's board
    const QPointF pos_p1, pos_p1_g;

    // Position of player 2's own board and opponent's board
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
    BoardItem *board {nullptr};

};

#endif // GAMESCENE_H
