// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// boarditem.h

#ifndef BOARDITEM_H_INCLUDED
#define BOARDITEM_H_INCLUDED

#include <QGraphicsItem>
#include <QPaintEvent>

#include "graphicsconst.h"
#include "config.h"
#include "types.h"

class BoardItem : public QGraphicsItem
{
public:
    explicit BoardItem(const QGraphicsItem *parent = nullptr);
    ~BoardItem() override;

    QRectF boundingRect() const override;

    QPainterPath shape() const override;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr) override;

    // Utilize UserType + 1 as a unique identifier for instances of the
    // BoardItem class. An alternative approach would be to store the class name
    // using setData(0, "BoardItem") and subsequently use data(0) for object
    // identification.
    enum { Type = UserType + 1 };

    int type() const noexcept override { return Type; }

    // Enable or disable diagonal lines on the board
    void setDiagonalLineEnabled(bool enableDiagonal = true);

    // Get the nearest point on the board to the given point
    QPointF findNearestPoint(QPointF targetPoint);

    // Convert polar coordinates (File and Rank) to Cartesian point
    QPointF convertFromPolarCoordinate(File f, Rank r) const;

    // Convert Cartesian point to polar coordinates (File and Rank)
    bool convertToPolarCoordinate(QPointF point, File &f, Rank &r) const;

    void updateAdvantageValue(qreal newAdvantage);

private:
    void initializePoints();
    void drawBoardBackground(QPainter *painter);
    void drawBoardLines(QPainter *painter);
    void drawCoordinateLabels(QPainter *painter);
    void drawPolarLabels(QPainter *painter);
    void drawAdvantageBar(QPainter *painter);

    // Side length of the square board
    int boardSideLength {BOARD_SIDE_LENGTH};

    // Size of the board's shadow
    int boardShadowSize {BOARD_SHADOW_SIZE};

    // Points representing board positions
    QPointF points[SQUARE_NB]; // 24 points

    // Flag to indicate if diagonal lines are enabled
    bool hasDiagonalLine {false};

    qreal advantageBarLength = 0; /* -1 ~ +1 */
};

#endif // BOARDITEM_H_INCLUDED
