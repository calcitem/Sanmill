// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// boarditem.cpp

#include <QPainter>

#include "boarditem.h"
#include "graphicsconst.h"
#include "types.h"

BoardItem::BoardItem(const QGraphicsItem *parent)
    : boardSideLength(BOARD_SIDE_LENGTH)
{
    Q_UNUSED(parent)

    // Put center of the board in the center of the scene
    setPos(0, 0);

    initializePoints();
}

BoardItem::~BoardItem() = default;

/**
 * @brief Get the bounding rectangle of the board item.
 *
 * This function returns a QRectF that represents the bounding box
 * around the board item. The bounding box is calculated based on
 * the dimensions of the board and includes extra space for the shadow.
 *
 * @return QRectF - Bounding rectangle with dimensions adjusted for shadow.
 */
QRectF BoardItem::boundingRect() const
{
    // See drawAdvantageBar() for the origin of the magic numbers
    qreal left = std::min(-boardSideLength / 2, -boardSideLength / 2 - 15);
    qreal top = std::min(-boardSideLength / 2,
                         -static_cast<int>(boardSideLength * 0.8) / 2);
    qreal right = boardSideLength / 2 + boardShadowSize;
    qreal bottom = boardSideLength / 2 + boardShadowSize;

    return QRectF(left, top, right - left, bottom - top);
}

void BoardItem::drawAdvantageBar(QPainter *painter)
{
    int barHeight = static_cast<int>(boardSideLength * 0.8);
    int barWidth = 6;
    int origin_x = -boardSideLength / 2 - 15; // Board left
    int origin_y = -barHeight / 2;

    // Draw the gray background of the bar
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(200, 200, 200));
    painter->drawRect(origin_x, origin_y, barWidth, barHeight);

    // Draw the green fill of the bar
    painter->setBrush(QColor(0, 128, 0)); // Green
    int fillHeight = static_cast<int>(barHeight *
                                      (advantageBarLength / 2 + 0.5));

    painter->drawRect(origin_x, origin_y + barHeight - fillHeight, barWidth,
                      fillHeight); // Green at the bottom
}

/**
 * @brief Get the shape of the board item for interaction.
 *
 * This function returns a QPainterPath that represents the interactive
 * shape of the board item. The shape is used for interactive features.
 *
 * In the current implementation, the shape is the same as the bounding
 * rectangle.
 *
 * @return QPainterPath - Shape of the board item.
 */
QPainterPath BoardItem::shape() const
{
    QPainterPath path;
    path.addRect(boundingRect());

    return path;
}

void BoardItem::paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
                      QWidget *widget)
{
    Q_UNUSED(option)
    Q_UNUSED(widget)

    drawBoardBackground(painter);
    drawBoardLines(painter);
    drawAdvantageBar(painter);
    drawCoordinateLabels(painter);
#ifdef DRAW_POLAR_COORDINATES
    drawPolarLabels(painter);
#endif
}

void BoardItem::setDiagonalLineEnabled(bool enableDiagonal)
{
    hasDiagonalLine = enableDiagonal;
    update(boundingRect());
}

void BoardItem::initializePoints()
{
    // Initialize 24 points
    for (int f = 0; f < FILE_NB; f++) {
        // The first point corresponds to the 12 o'clock position on the inner
        // ring, followed by points arranged in a clockwise direction. This
        // pattern is replicated for the middle and outer rings as well.
        const int radius = (f + 1) * LINE_INTERVAL;
        const int clockwiseRingCoordinates[][2] = {
            {0, -radius}, {radius, -radius}, {radius, 0},  {radius, radius},
            {0, radius},  {-radius, radius}, {-radius, 0}, {-radius, -radius}};
        for (int r = 0; r < RANK_NB; r++) {
            points[f * RANK_NB + r].rx() = clockwiseRingCoordinates[r][0];
            points[f * RANK_NB + r].ry() = clockwiseRingCoordinates[r][1];
        }
    }
}

void BoardItem::updateAdvantageValue(qreal newAdvantage)
{
    int barHeight = static_cast<int>(boardSideLength * 0.8);
    int barWidth = 10;
    int origin_x = -boardSideLength / 2 - 20; // Board left
    int origin_y = -barHeight / 2;

    this->advantageBarLength = newAdvantage;
    QRect indicatorBarRect(origin_x, origin_y, barWidth, barHeight);
    update(indicatorBarRect);
}

void BoardItem::drawBoardBackground(QPainter *painter)
{
#ifndef QT_MOBILE_APP_UI
    QColor shadowColor(128, 42, 42);
    shadowColor.setAlphaF(0.3f);
    painter->fillRect(boundingRect(), QBrush(shadowColor));
#endif /* ! QT_MOBILE_APP_UI */

    // Fill in picture
#ifdef QT_MOBILE_APP_UI
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(239, 239, 239));
    painter->drawRect(-boardSideLength / 2, -boardSideLength / 2,
                      boardSideLength, boardSideLength);
#else
    painter->drawPixmap(-boardSideLength / 2, -boardSideLength / 2,
                        boardSideLength, boardSideLength,
                        QPixmap(":/image/resources/image/board.png"));
#endif /* QT_MOBILE_APP_UI */
}

void BoardItem::drawBoardLines(QPainter *painter)
{
    // Solid line brush
#ifdef QT_MOBILE_APP_UI
    QPen pen(QBrush(QColor(241, 156, 159)), LINE_WEIGHT, Qt::SolidLine,
             Qt::SquareCap, Qt::BevelJoin);
#else
    const QPen pen(QBrush(QColor(178, 34, 34)), LINE_WEIGHT, Qt::SolidLine,
                   Qt::SquareCap, Qt::BevelJoin);
#endif
    painter->setPen(pen);

    // No brush
    painter->setBrush(Qt::NoBrush);

    for (uint8_t f = 0; f < FILE_NB; f++) {
        // Draw three boxes
        painter->drawPolygon(f * RANK_NB + points, RANK_NB);
    }

    // Draw 4 vertical and horizontal lines
    for (int r = 0; r < RANK_NB; r += 2) {
        painter->drawLine(points[r], points[(FILE_NB - 1) * RANK_NB + r]);
    }

    if (hasDiagonalLine) {
        // Draw 4 diagonal lines
        for (int r = 1; r < RANK_NB; r += 2) {
            painter->drawLine(points[r], points[(FILE_NB - 1) * RANK_NB + r]);
        }
    }
}

void BoardItem::drawCoordinateLabels(QPainter *painter)
{
    // Calculate font size based on board size for consistent appearance across
    // different DPI settings Use approximately 2.2% of board side length as
    // base font size
    const int FONT_SIZE_PIXELS = boardSideLength / 45; // Approximately 12
                                                       // pixels for default
                                                       // 550px board

    int offset_x = LINE_WEIGHT + FONT_SIZE_PIXELS / 4;
    int offset_y = LINE_WEIGHT + FONT_SIZE_PIXELS / 4;

    const int extra_offset_x = 4;
    const int extra_offset_y = 1;

    QPen fontPen(QBrush(Qt::darkRed), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap,
                 Qt::BevelJoin);
    painter->setPen(fontPen);

    QFont font;
    // Use pixel size instead of point size for consistent scaling across
    // different DPI
    font.setPixelSize(FONT_SIZE_PIXELS);
    painter->setFont(font);

    QFontMetrics fm(font);
    int textWidth = fm.horizontalAdvance("A");

    int origin_x = -boardSideLength / 2 + (boardSideLength / 8) - offset_x;
    int origin_y = boardSideLength / 2 - (boardSideLength / 8) + offset_y;

    int interval = boardSideLength / 8;

    for (int i = 0; i < 7; ++i) {
        QString text = QString(QChar('A' + i));
        painter->drawText(origin_x + interval * i - textWidth / 2 +
                              2 * extra_offset_x,
                          origin_y + 20 + extra_offset_x, text);
    }

    for (int i = 0; i < 7; ++i) {
        QString text = QString::number(i + 1);
        painter->drawText(origin_x - 20 - extra_offset_y,
                          origin_y - interval * i, text);
    }
}

/**
 * @brief Draw polar coordinates on the board.
 *
 * This function sets up the pen and font, and then iteratively draws
 * polar coordinates at specified points on the board. The coordinates
 * are positioned in a manner similar to clock face numbers.
 *
 * @param painter Pointer to the QPainter object for drawing.
 */
void BoardItem::drawPolarLabels(QPainter *painter)
{
    QPen fontPen(QBrush(Qt::white), LINE_WEIGHT, Qt::SolidLine, Qt::SquareCap,
                 Qt::BevelJoin);
    painter->setPen(fontPen);
    QFont font;
    // Calculate polar label font size based on board size for consistent
    // appearance Use a smaller size relative to coordinate labels
    // (approximately 1/3 of coordinate font size)
    const int POLAR_FONT_SIZE_PIXELS = boardSideLength / 135; // Approximately 4
                                                              // pixels for
                                                              // default 550px
                                                              // board
    font.setPixelSize(POLAR_FONT_SIZE_PIXELS);
    font.setFamily("Arial");
    font.setLetterSpacing(QFont::AbsoluteSpacing, 0);
    painter->setFont(font);

    for (int r = 0; r < RANK_NB; r++) {
        QString text(QChar('1' + r));
        painter->drawText(points[(FILE_NB - 1) * RANK_NB + r], text);
    }
}

/**
 * @brief Find the point closest to the provided target point among the board's
 * predefined points.
 *
 * This function iterates through an array of predefined points (represented by
 * the member variable 'points'). It returns the point that is closest to the
 * provided target point, based on a set distance threshold (PIECE_SIZE / 2).
 *
 * @param targetPoint The point to which we are finding the closest point from
 * the array 'points'.
 * @return Returns the point closest to targetPoint based on the distance
 * threshold.
 */
QPointF BoardItem::findNearestPoint(const QPointF targetPoint)
{
    // Initialize nearestPoint to the origin (0,0) as a starting point for
    // comparison
    auto nearestPoint = QPointF(0, 0);

    // Iterate through the array of predefined points to find the nearest one to
    // targetPoint
    for (auto pt : points) {
        // Check if the distance between targetPoint and the current point (pt)
        // is within the radius of a piece (PIECE_SIZE / 2)
        if (QLineF(targetPoint, pt).length() < PIECE_SIZE / 2) {
            nearestPoint = pt;
            break;
        }
    }

    return nearestPoint;
}

QPointF BoardItem::convertFromPolarCoordinate(File f, Rank r) const
{
    return points[(static_cast<int>(f) - 1) * RANK_NB + static_cast<int>(r) - 1];
}

bool BoardItem::convertToPolarCoordinate(QPointF point, File &f, Rank &r) const
{
    // Iterate through all the points to find the closest one to the target
    // point.
    for (int sq = 0; sq < SQUARE_NB; sq++) {
        // If the target point is sufficiently close to one of the predefined
        // points.
        if (QLineF(point, points[sq]).length() < (qreal)PIECE_SIZE / 6) {
            // Calculate the corresponding File and Rank based on the closest
            // point's index.
            f = static_cast<File>(sq / RANK_NB + 1);
            r = static_cast<Rank>(sq % RANK_NB + 1);
            return true;
        }
    }

    return false;
}
