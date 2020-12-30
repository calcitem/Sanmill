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
#include <random>
#include "bitboard.h"
#include "rule.h"
#include "movegen.h"
#include "mills.h"
#include "misc.h"
#include "option.h"

namespace Mills
{

// Morris boards have concentric square rings joined by edges and an empty middle.
// Morris games are typically played on the vertices not the cells.

/*
    31 ----- 24 ----- 25
    | \       |      / |
    |  23 -- 16 -- 17  |
    |  | \    |   / |  |
    |  |  15 08 09  |  |
    30-22-14    10-18-26
    |  |  13 12 11  |  |
    |  | /    |   \ |  |
    |  21 -- 20 -- 19  |
    | /       |     \  |
    29 ----- 28 ----- 27
*/

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

#define S2(a, b)        (square_bb(SQ_##a) | square_bb(SQ_##b))
#define S3(a, b, c)     (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c))
#define S4(a, b, c, d)  (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c) | square_bb(SQ_##d))

    const Bitboard adjacentSquaresBB12[SQUARE_NB] = {
        /*  0 */ 0,
        /*  1 */ 0,
        /*  2 */ 0,
        /*  3 */ 0,
        /*  4 */ 0,
        /*  5 */ 0,
        /*  6 */ 0,
        /*  7 */ 0,

        /*  8 */ S3(9, 15, 16),
        /*  9 */ S3(17, 8, 10),
        /* 10 */ S3(9, 11, 18),
        /* 11 */ S3(19, 10, 12),
        /* 12 */ S3(11, 13, 20),
        /* 13 */ S3(21, 12, 14),
        /* 14 */ S3(13, 15, 22),
        /* 15 */ S3(23, 8, 14),

        /* 16 */ S4(17, 23, 8, 24),
        /* 17 */ S4(9, 25, 16, 18),
        /* 18 */ S4(17, 19, 10, 26),
        /* 19 */ S4(11, 27, 18, 20),
        /* 20 */ S4(19, 21, 12, 28),
        /* 21 */ S4(13, 29, 20, 22),
        /* 22 */ S4(21, 23, 14, 30),
        /* 23 */ S4(15, 31, 16, 22),

        /* 24 */ S3(25, 31, 16),
        /* 25 */ S3(17, 24, 26),
        /* 26 */ S3(25, 27, 18),
        /* 27 */ S3(19, 26, 28),
        /* 28 */ S3(27, 29, 20),
        /* 29 */ S3(21, 28, 30),
        /* 30 */ S3(29, 31, 22),
        /* 31 */ S3(23, 24, 30),

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

        /*  8 */ S3(16, 9, 15),
        /*  9 */ S2(10, 8),
        /* 10 */ S3(18, 11, 9),
        /* 11 */ S2(12, 10),
        /* 12 */ S3(20, 13, 11),
        /* 13 */ S2(14, 12),
        /* 14 */ S3(22, 15, 13),
        /* 15 */ S2(8, 14),

        /* 16 */ S4(8, 24, 17, 23),
        /* 17 */ S2(18, 16),
        /* 18 */ S4(10, 26, 19, 17),
        /* 19 */ S2(20, 18),
        /* 20 */ S4(12, 28, 21, 19),
        /* 21 */ S2(22, 20),
        /* 22 */ S4(14, 30, 23, 21),
        /* 23 */ S2(16, 22),

        /* 24 */ S3(16, 25, 31),
        /* 25 */ S2(26, 24),
        /* 26 */ S3(18, 27, 25),
        /* 27 */ S2(28, 26),
        /* 28 */ S3(20, 29, 27),
        /* 29 */ S2(30, 28),
        /* 30 */ S3(22, 31, 29),
        /* 31 */ S2(24, 30),

        /* 32 */ 0,
        /* 33 */ 0,
        /* 34 */ 0,
        /* 35 */ 0,
        /* 36 */ 0,
        /* 37 */ 0,
        /* 38 */ 0,
        /* 39 */ 0,
    };

#undef S2
#undef S3
#undef S4

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

void move_priority_list_shuffle()
{
    std::array<Square, 4> movePriorityList0;
    std::array<Square, 8> movePriorityList1;
    std::array<Square, 4> movePriorityList2;
    std::array<Square, 8> movePriorityList3;

    if (rule.nTotalPiecesEachSide == 9) {
        movePriorityList0 = { SQ_16, SQ_18, SQ_20, SQ_22 };
        movePriorityList1 = { SQ_24, SQ_26, SQ_28, SQ_30, SQ_8, SQ_10, SQ_12, SQ_14 };
        movePriorityList2 = { SQ_17, SQ_19, SQ_21, SQ_23 };
        movePriorityList3 = { SQ_25, SQ_27, SQ_29, SQ_31, SQ_9, SQ_11, SQ_13, SQ_15 };
    } else if (rule.nTotalPiecesEachSide == 12) {
        movePriorityList0 = { SQ_17, SQ_19, SQ_21, SQ_23 };
        movePriorityList1 = { SQ_25, SQ_27, SQ_29, SQ_31, SQ_9, SQ_11, SQ_13, SQ_15 };
        movePriorityList2 = { SQ_16, SQ_18, SQ_20, SQ_22 };
        movePriorityList3 = { SQ_24, SQ_26, SQ_28, SQ_30, SQ_8, SQ_10, SQ_12, SQ_14 };
    }

    if (gameOptions.getShufflingEnabled()) {
        uint32_t seed = static_cast<uint32_t>(now());

        std::shuffle(movePriorityList0.begin(), movePriorityList0.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityList1.begin(), movePriorityList1.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityList2.begin(), movePriorityList2.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityList3.begin(), movePriorityList3.end(), std::default_random_engine(seed));
    }

    for (size_t i = 0; i < 4; i++) {
        MoveList<LEGAL>::movePriorityList[i + 0] = movePriorityList0[i];
    }

    for (size_t i = 0; i < 8; i++) {
        MoveList<LEGAL>::movePriorityList[i + 4] = movePriorityList1[i];
    }

    for (size_t i = 0; i < 4; i++) {
        MoveList<LEGAL>::movePriorityList[i + 12] = movePriorityList2[i];
    }

    for (size_t i = 0; i < 8; i++) {
        MoveList<LEGAL>::movePriorityList[i + 16] = movePriorityList3[i];
    }
}

}
