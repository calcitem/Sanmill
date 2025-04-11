// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// gamescene.h

#ifndef GAMESCENE_H_INCLUDED
#define GAMESCENE_H_INCLUDED

#include <memory>

#include <QGraphicsScene>

#include "config.h"
#include "graphicsconst.h"
#include "types.h"

#include "boarditem.h"

class BoardItem;

class GameScene : public QGraphicsScene
{
    Q_OBJECT

public:
    explicit GameScene(QObject *parent = nullptr);

    QPointF convertFromPolarCoordinate(File f, Rank r) const;

    bool convertToPolarCoordinate(QPointF pos, File &f, Rank &r) const;

    void setDiagonalLineEnabled(bool arg = true) const;

    // Position of player 1's own board and opponent's board
    const QPointF pos_p1 {LINE_INTERVAL * 4, LINE_INTERVAL * 6};
    const QPointF pos_p1_g {LINE_INTERVAL * (-4), LINE_INTERVAL * 6};

    // Position of player 2's own board and opponent's board
    const QPointF pos_p2 {LINE_INTERVAL * (-4), LINE_INTERVAL * (-6)};
    const QPointF pos_p2_g {LINE_INTERVAL * 4, LINE_INTERVAL * (-6)};

    std::unique_ptr<BoardItem> board;

protected:
    // void keyPressEvent(QKeyEvent *keyEvent);
    void mouseDoubleClickEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent) override;

signals:
    void mouseReleased(QPointF);

private:
    void handleBoardClick(QGraphicsSceneMouseEvent *mouseEvent);
    void handlePieceClick(const QGraphicsItem *item);
};

#endif // GAMESCENE_H_INCLUDED
