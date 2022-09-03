// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

#ifndef GAMESCENE_H_INCLUDED
#define GAMESCENE_H_INCLUDED

#include <QGraphicsScene>

#include "config.h"
#include "graphicsconst.h"
#include "types.h"

class BoardItem;

class GameScene : public QGraphicsScene
{
    Q_OBJECT

public:
    explicit GameScene(QObject *parent = nullptr);
    ~GameScene() override;

    [[nodiscard]] QPointF polar2pos(File f, Rank r) const;

    [[nodiscard]] bool pos2polar(QPointF pos, File &f, Rank &r) const;

    void setDiagonal(bool arg = true) const;

    // Position of player 1's own board and opponent's board
    const QPointF pos_p1 {LINE_INTERVAL * 4, LINE_INTERVAL * 6};
    const QPointF pos_p1_g {LINE_INTERVAL * (-4), LINE_INTERVAL * 6};

    // Position of player 2's own board and opponent's board
    const QPointF pos_p2 {LINE_INTERVAL * (-4), LINE_INTERVAL *(-6)};
    const QPointF pos_p2_g {LINE_INTERVAL * 4, LINE_INTERVAL *(-6)};

protected:
    // void keyPressEvent(QKeyEvent *keyEvent);
    void mouseDoubleClickEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

signals:
    void mouseReleased(QPointF);

private:
    BoardItem *board {nullptr};
};

#endif // GAMESCENE_H_INCLUDED
