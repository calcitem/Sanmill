// graphicsconst.h

#ifndef GRAPHICSCONST_H_INCLUDED
#define GRAPHICSCONST_H_INCLUDED

#include "config.h"

#ifdef QT_MOBILE_APP_UI
constexpr int16 BOARD_SIDE_LENGTH = 500;
#else
constexpr int16_t BOARD_SIDE_LENGTH = 550;
#endif /* QT_MOBILE_APP_UI */

constexpr int16_t BOARD_SHADOW_SIZE = 5;

// Minimum width and height, i.e. 1 / 4 Size
constexpr int16_t BOARD_MINISIZE = 150;
constexpr int16_t PIECE_SIZE = 56;
constexpr int16_t LINE_INTERVAL = 72;
constexpr int16_t LINE_WEIGHT = 3;

#endif // GRAPHICSCONST_H_INCLUDED
