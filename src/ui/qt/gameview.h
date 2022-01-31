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

#ifndef GAME_VIEW_H_INCLUDED
#define GAME_VIEW_H_INCLUDED

#include "config.h"

#include <QGraphicsView>

// This class is mainly derived to make the view adapt to the scene size and
// image rotation mirror operation
class GameView : public QGraphicsView
{
    Q_OBJECT

public:
    explicit GameView(QWidget *parent);
    ~GameView() override;

public slots:
    void flip();
    void mirror();
    void turnRight();
    void turnLeft();

protected:
    void resizeEvent(QResizeEvent *event) override;
};

#endif // GAME_VIEW_H_INCLUDED
