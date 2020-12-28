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

#include <cstring>
#include "bitboard.h"
#include "rule.h"
#include "movegen.h"
#include "mills.h"

namespace Mills
{

void adjacent_squares_init()
{
    // Note: Not follow order of MoveDirection array
    const int adjacentSquares12[SQUARE_NB][MD_NB] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {9, 15, 16, 0},
        /*  9 */ {17, 8, 10, 0},
        /* 10 */ {9, 11, 18, 0},
        /* 11 */ {19, 10, 12, 0},
        /* 12 */ {11, 13, 20, 0},
        /* 13 */ {21, 12, 14, 0},
        /* 14 */ {13, 15, 22, 0},
        /* 15 */ {23, 8, 14, 0},

        /* 16 */ {17, 23, 8, 24},
        /* 17 */ {9, 25, 16, 18},
        /* 18 */ {17, 19, 10, 26},
        /* 19 */ {11, 27, 18, 20},
        /* 20 */ {19, 21, 12, 28},
        /* 21 */ {13, 29, 20, 22},
        /* 22 */ {21, 23, 14, 30},
        /* 23 */ {15, 31, 16, 22},

        /* 24 */ {25, 31, 16, 0},
        /* 25 */ {17, 24, 26, 0},
        /* 26 */ {25, 27, 18, 0},
        /* 27 */ {19, 26, 28, 0},
        /* 28 */ {27, 29, 20, 0},
        /* 29 */ {21, 28, 30, 0},
        /* 30 */ {29, 31, 22, 0},
        /* 31 */ {23, 24, 30, 0},

        /* 32 */ {0, 0, 0, 0},
        /* 33 */ {0, 0, 0, 0},
        /* 34 */ {0, 0, 0, 0},
        /* 35 */ {0, 0, 0, 0},
        /* 36 */ {0, 0, 0, 0},
        /* 37 */ {0, 0, 0, 0},
        /* 38 */ {0, 0, 0, 0},
        /* 39 */ {0, 0, 0, 0},
    };

    const int adjacentSquares9[SQUARE_NB][MD_NB] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {16, 9, 15, 0},
        /*  9 */ {10, 8, 0, 0},
        /* 10 */ {18, 11, 9, 0},
        /* 11 */ {12, 10, 0, 0},
        /* 12 */ {20, 13, 11, 0},
        /* 13 */ {14, 12, 0, 0},
        /* 14 */ {22, 15, 13, 0},
        /* 15 */ {8, 14, 0, 0},

        /* 16 */ {8, 24, 17, 23},
        /* 17 */ {18, 16, 0, 0},
        /* 18 */ {10, 26, 19, 17},
        /* 19 */ {20, 18, 0, 0},
        /* 20 */ {12, 28, 21, 19},
        /* 21 */ {22, 20, 0, 0},
        /* 22 */ {14, 30, 23, 21},
        /* 23 */ {16, 22, 0, 0},

        /* 24 */ {16, 25, 31, 0},
        /* 25 */ {26, 24, 0, 0},
        /* 26 */ {18, 27, 25, 0},
        /* 27 */ {28, 26, 0, 0},
        /* 28 */ {20, 29, 27, 0},
        /* 29 */ {30, 28, 0, 0},
        /* 30 */ {22, 31, 29, 0},
        /* 31 */ {24, 30, 0, 0},

        /* 32 */ {0, 0, 0, 0},
        /* 33 */ {0, 0, 0, 0},
        /* 34 */ {0, 0, 0, 0},
        /* 35 */ {0, 0, 0, 0},
        /* 36 */ {0, 0, 0, 0},
        /* 37 */ {0, 0, 0, 0},
        /* 38 */ {0, 0, 0, 0},
        /* 39 */ {0, 0, 0, 0},
    };

    const Bitboard adjacentSquaresBB12[SQUARE_NB] = {
        /*  0 */ 0,
        /*  1 */ 0,
        /*  2 */ 0,
        /*  3 */ 0,
        /*  4 */ 0,
        /*  5 */ 0,
        /*  6 */ 0,
        /*  7 */ 0,

        /*  8 */ square_bb(SQ_9) | square_bb(SQ_15) | square_bb(SQ_16),
        /*  9 */ square_bb(SQ_17) | square_bb(SQ_8) | square_bb(SQ_10),
        /* 10 */ square_bb(SQ_9) | square_bb(SQ_11) | square_bb(SQ_18),
        /* 11 */ square_bb(SQ_19) | square_bb(SQ_10) | square_bb(SQ_12),
        /* 12 */ square_bb(SQ_11) | square_bb(SQ_13) | square_bb(SQ_20),
        /* 13 */ square_bb(SQ_21) | square_bb(SQ_12) | square_bb(SQ_14),
        /* 14 */ square_bb(SQ_13) | square_bb(SQ_15) | square_bb(SQ_22),
        /* 15 */ square_bb(SQ_23) | square_bb(SQ_8) | square_bb(SQ_14),

        /* 16 */ square_bb(SQ_17) | square_bb(SQ_23) | square_bb(SQ_8) | square_bb(SQ_24),
        /* 17 */ square_bb(SQ_9) | square_bb(SQ_25) | square_bb(SQ_16) | square_bb(SQ_18),
        /* 18 */ square_bb(SQ_17) | square_bb(SQ_19) | square_bb(SQ_10) | square_bb(SQ_26),
        /* 19 */ square_bb(SQ_11) | square_bb(SQ_27) | square_bb(SQ_18) | square_bb(SQ_20),
        /* 20 */ square_bb(SQ_19) | square_bb(SQ_21) | square_bb(SQ_12) | square_bb(SQ_28),
        /* 21 */ square_bb(SQ_13) | square_bb(SQ_29) | square_bb(SQ_20) | square_bb(SQ_22),
        /* 22 */ square_bb(SQ_21) | square_bb(SQ_23) | square_bb(SQ_14) | square_bb(SQ_30),
        /* 23 */ square_bb(SQ_15) | square_bb(SQ_31) | square_bb(SQ_16) | square_bb(SQ_22),

        /* 24 */ square_bb(SQ_25) | square_bb(SQ_31) | square_bb(SQ_16),
        /* 25 */ square_bb(SQ_17) | square_bb(SQ_24) | square_bb(SQ_26),
        /* 26 */ square_bb(SQ_25) | square_bb(SQ_27) | square_bb(SQ_18),
        /* 27 */ square_bb(SQ_19) | square_bb(SQ_26) | square_bb(SQ_28),
        /* 28 */ square_bb(SQ_27) | square_bb(SQ_29) | square_bb(SQ_20),
        /* 29 */ square_bb(SQ_21) | square_bb(SQ_28) | square_bb(SQ_30),
        /* 30 */ square_bb(SQ_29) | square_bb(SQ_31) | square_bb(SQ_22),
        /* 31 */ square_bb(SQ_23) | square_bb(SQ_24) | square_bb(SQ_30),

        /* 32 */ 0,
        /* 33 */ 0,
        /* 34 */ 0,
        /* 35 */ 0,
        /* 36 */ 0,
        /* 37 */ 0,
        /* 38 */ 0,
        /* 39 */ 0,
    };

    const Bitboard adjacentSquaresBB9[SQUARE_NB] = {
        /*  0 */ 0,
        /*  1 */ 0,
        /*  2 */ 0,
        /*  3 */ 0,
        /*  4 */ 0,
        /*  5 */ 0,
        /*  6 */ 0,
        /*  7 */ 0,

        /*  8 */ square_bb(SQ_16) | square_bb(SQ_9) | square_bb(SQ_15),
        /*  9 */ square_bb(SQ_10) | square_bb(SQ_8),
        /* 10 */ square_bb(SQ_18) | square_bb(SQ_11) | square_bb(SQ_9),
        /* 11 */ square_bb(SQ_12) | square_bb(SQ_10),
        /* 12 */ square_bb(SQ_20) | square_bb(SQ_13) | square_bb(SQ_11),
        /* 13 */ square_bb(SQ_14) | square_bb(SQ_12),
        /* 14 */ square_bb(SQ_22) | square_bb(SQ_15) | square_bb(SQ_13),
        /* 15 */ square_bb(SQ_8) | square_bb(SQ_14),

        /* 16 */ square_bb(SQ_8) | square_bb(SQ_24) | square_bb(SQ_17) | square_bb(SQ_23),
        /* 17 */ square_bb(SQ_18) | square_bb(SQ_16),
        /* 18 */ square_bb(SQ_10) | square_bb(SQ_26) | square_bb(SQ_19) | square_bb(SQ_17),
        /* 19 */ square_bb(SQ_20) | square_bb(SQ_18),
        /* 20 */ square_bb(SQ_12) | square_bb(SQ_28) | square_bb(SQ_21) | square_bb(SQ_19),
        /* 21 */ square_bb(SQ_22) | square_bb(SQ_20),
        /* 22 */ square_bb(SQ_14) | square_bb(SQ_30) | square_bb(SQ_23) | square_bb(SQ_21),
        /* 23 */ square_bb(SQ_16) | square_bb(SQ_22),

        /* 24 */ square_bb(SQ_16) | square_bb(SQ_25) | square_bb(SQ_31),
        /* 25 */ square_bb(SQ_26) | square_bb(SQ_24),
        /* 26 */ square_bb(SQ_18) | square_bb(SQ_27) | square_bb(SQ_25),
        /* 27 */ square_bb(SQ_28) | square_bb(SQ_26),
        /* 28 */ square_bb(SQ_20) | square_bb(SQ_29) | square_bb(SQ_27),
        /* 29 */ square_bb(SQ_30) | square_bb(SQ_28),
        /* 30 */ square_bb(SQ_22) | square_bb(SQ_31) | square_bb(SQ_29),
        /* 31 */ square_bb(SQ_24) | square_bb(SQ_30),

        /* 32 */ 0,
        /* 33 */ 0,
        /* 34 */ 0,
        /* 35 */ 0,
        /* 36 */ 0,
        /* 37 */ 0,
        /* 38 */ 0,
        /* 39 */ 0,
    };


    if (rule.hasObliqueLines) {
        memcpy(MoveList<LEGAL>::adjacentSquares, adjacentSquares12, sizeof(MoveList<LEGAL>::adjacentSquares));
        memcpy(MoveList<LEGAL>::adjacentSquaresBB, adjacentSquaresBB12, sizeof(MoveList<LEGAL>::adjacentSquaresBB));
    } else {
        memcpy(MoveList<LEGAL>::adjacentSquares, adjacentSquares9, sizeof(MoveList<LEGAL>::adjacentSquares));
        memcpy(MoveList<LEGAL>::adjacentSquaresBB, adjacentSquaresBB9, sizeof(MoveList<LEGAL>::adjacentSquaresBB));
    }

#ifdef DEBUG_MODE
    int sum = 0;
    for (int i = 0; i < SQUARE_NB; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < MD_NB; j++) {
            if (j == MD_NB - 1)
                loggerDebug("%d", adjacentSquares[i][j]);
            else
                loggerDebug("%d, ", adjacentSquares[i][j]);
            sum += adjacentSquares[i][j];
        }
        loggerDebug("},\n");
    }
    loggerDebug("sum = %d\n", sum);
#endif

}

}
