// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mills.cpp

#include <cstring>
#include <random>

#include "bitboard.h"
#include "mills.h"
#include "misc.h"
#include "movegen.h"
#include "option.h"
#include "position.h"

namespace Mills {

// Morris boards have concentric square rings joined by edges and an empty
// middle. Morris games are typically played on the vertices not the cells.

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

void adjacent_squares_init() noexcept
{
    constexpr int adjacentSquares[SQUARE_EXT_NB][MD_NB] = {
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

    constexpr int adjacentSquares_diagonal[SQUARE_EXT_NB][MD_NB] = {
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

    const Bitboard adjacentSquaresBB[SQUARE_EXT_NB] = {
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

    const Bitboard adjacentSquaresBB_diagonal[SQUARE_EXT_NB] = {
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

    if (rule.hasDiagonalLines) {
        memcpy(MoveList<LEGAL>::adjacentSquares, adjacentSquares_diagonal,
               sizeof(MoveList<LEGAL>::adjacentSquares));
        memcpy(MoveList<LEGAL>::adjacentSquaresBB, adjacentSquaresBB_diagonal,
               sizeof(MoveList<LEGAL>::adjacentSquaresBB));
    } else {
        memcpy(MoveList<LEGAL>::adjacentSquares, adjacentSquares,
               sizeof(MoveList<LEGAL>::adjacentSquares));
        memcpy(MoveList<LEGAL>::adjacentSquaresBB, adjacentSquaresBB,
               sizeof(MoveList<LEGAL>::adjacentSquaresBB));
    }

#ifdef DEBUG_MODE
#if 0
    int sum = 0;
    for (int i = 0; i < SQUARE_EXT_NB; i++) {
        debugPrintf("/* %d */ {", i);
        for (int j = 0; j < MD_NB; j++) {
            if (j == MD_NB - 1)
                debugPrintf("%d", adjacentSquares[i][j]);
            else
                debugPrintf("%d, ", adjacentSquares[i][j]);
            sum += adjacentSquares[i][j];
        }
        debugPrintf("},\n");
    }
    debugPrintf("sum = %d\n", sum);
#endif
#endif
}

void mill_table_init()
{
    const Bitboard millTableBB[SQUARE_EXT_NB][LD_NB] = {
        /* 0 */ {0, 0, 0},
        /* 1 */ {0, 0, 0},
        /* 2 */ {0, 0, 0},
        /* 3 */ {0, 0, 0},
        /* 4 */ {0, 0, 0},
        /* 5 */ {0, 0, 0},
        /* 6 */ {0, 0, 0},
        /* 7 */ {0, 0, 0},

        /*  8 */ {S2(16, 24), S2(9, 15), ~0U},
        /*  9 */ {~0U, S2(15, 8), S2(10, 11)},
        /* 10 */ {S2(18, 26), S2(11, 9), ~0U},
        /* 11 */ {~0U, S2(9, 10), S2(12, 13)},
        /* 12 */ {S2(20, 28), S2(13, 11), ~0U},
        /* 13 */ {~0U, S2(11, 12), S2(14, 15)},
        /* 14 */ {S2(22, 30), S2(15, 13), ~0U},
        /* 15 */ {~0U, S2(13, 14), S2(8, 9)},

        /* 16 */ {S2(8, 24), S2(17, 23), ~0U},
        /* 17 */ {~0U, S2(23, 16), S2(18, 19)},
        /* 18 */ {S2(10, 26), S2(19, 17), ~0U},
        /* 19 */ {~0U, S2(17, 18), S2(20, 21)},
        /* 20 */ {S2(12, 28), S2(21, 19), ~0U},
        /* 21 */ {~0U, S2(19, 20), S2(22, 23)},
        /* 22 */ {S2(14, 30), S2(23, 21), ~0U},
        /* 23 */ {~0U, S2(21, 22), S2(16, 17)},

        /* 24 */ {S2(8, 16), S2(25, 31), ~0U},
        /* 25 */ {~0U, S2(31, 24), S2(26, 27)},
        /* 26 */ {S2(10, 18), S2(27, 25), ~0U},
        /* 27 */ {~0U, S2(25, 26), S2(28, 29)},
        /* 28 */ {S2(12, 20), S2(29, 27), ~0U},
        /* 29 */ {~0U, S2(27, 28), S2(30, 31)},
        /* 30 */ {S2(14, 22), S2(31, 29), ~0U},
        /* 31 */ {~0U, S2(29, 30), S2(24, 25)},

        /* 32 */ {0, 0, 0},
        /* 33 */ {0, 0, 0},
        /* 34 */ {0, 0, 0},
        /* 35 */ {0, 0, 0},
        /* 36 */ {0, 0, 0},
        /* 37 */ {0, 0, 0},
        /* 38 */ {0, 0, 0},
        /* 39 */ {0, 0, 0},
    };

    const Bitboard millTableBB_diagonal[SQUARE_EXT_NB][LD_NB] = {
        /* 0 */ {0, 0, 0},
        /* 1 */ {0, 0, 0},
        /* 2 */ {0, 0, 0},
        /* 3 */ {0, 0, 0},
        /* 4 */ {0, 0, 0},
        /* 5 */ {0, 0, 0},
        /* 6 */ {0, 0, 0},
        /* 7 */ {0, 0, 0},

        /* 8 */ {S2(16, 24), S2(9, 15), ~0U},
        /* 9 */ {S2(17, 25), S2(15, 8), S2(10, 11)},
        /* 10 */ {S2(18, 26), S2(11, 9), ~0U},
        /* 11 */ {S2(19, 27), S2(9, 10), S2(12, 13)},
        /* 12 */ {S2(20, 28), S2(13, 11), ~0U},
        /* 13 */ {S2(21, 29), S2(11, 12), S2(14, 15)},
        /* 14 */ {S2(22, 30), S2(15, 13), ~0U},
        /* 15 */ {S2(23, 31), S2(13, 14), S2(8, 9)},

        /* 16 */ {S2(8, 24), S2(17, 23), ~0U},
        /* 17 */ {S2(9, 25), S2(23, 16), S2(18, 19)},
        /* 18 */ {S2(10, 26), S2(19, 17), ~0U},
        /* 19 */ {S2(11, 27), S2(17, 18), S2(20, 21)},
        /* 20 */ {S2(12, 28), S2(21, 19), ~0U},
        /* 21 */ {S2(13, 29), S2(19, 20), S2(22, 23)},
        /* 22 */ {S2(14, 30), S2(23, 21), ~0U},
        /* 23 */ {S2(15, 31), S2(21, 22), S2(16, 17)},

        /* 24 */ {S2(8, 16), S2(25, 31), ~0U},
        /* 25 */ {S2(9, 17), S2(31, 24), S2(26, 27)},
        /* 26 */ {S2(10, 18), S2(27, 25), ~0U},
        /* 27 */ {S2(11, 19), S2(25, 26), S2(28, 29)},
        /* 28 */ {S2(12, 20), S2(29, 27), ~0U},
        /* 29 */ {S2(13, 21), S2(27, 28), S2(30, 31)},
        /* 30 */ {S2(14, 22), S2(31, 29), ~0U},
        /* 31 */ {S2(15, 23), S2(29, 30), S2(24, 25)},

        /* 32 */ {0, 0, 0},
        /* 33 */ {0, 0, 0},
        /* 34 */ {0, 0, 0},
        /* 35 */ {0, 0, 0},
        /* 36 */ {0, 0, 0},
        /* 37 */ {0, 0, 0},
        /* 38 */ {0, 0, 0},
        /* 39 */ {0, 0, 0},
    };

    if (rule.hasDiagonalLines) {
        memcpy(Position::millTableBB, millTableBB_diagonal,
               sizeof(Position::millTableBB));
    } else {
        memcpy(Position::millTableBB, millTableBB,
               sizeof(Position::millTableBB));
    }
}

void move_priority_list_shuffle()
{
    if (gameOptions.getSkillLevel() == 1) {
        // TODO(calcitem): 8 is SQ_BEGIN & 32 is SQ_END
        for (auto i = 8; i < 32; i++) {
            MoveList<LEGAL>::movePriorityList[i - static_cast<int>(SQ_BEGIN)] =
                static_cast<Square>(i);
        }
        if (gameOptions.getShufflingEnabled()) {
            const auto seed = static_cast<uint32_t>(now());

            std::shuffle(MoveList<LEGAL>::movePriorityList.begin(),
                         MoveList<LEGAL>::movePriorityList.end(),
                         std::default_random_engine(seed));
        }
        return;
    }

    std::array<Square, 4> movePriorityList0 {};
    std::array<Square, 8> movePriorityList1 {};
    std::array<Square, 4> movePriorityList2 {};
    std::array<Square, 8> movePriorityList3 {};

    if (!rule.hasDiagonalLines) {
        movePriorityList0 = {SQ_16, SQ_18, SQ_20, SQ_22};
        movePriorityList1 = {SQ_24, SQ_26, SQ_28, SQ_30,
                             SQ_8,  SQ_10, SQ_12, SQ_14};
        movePriorityList2 = {SQ_17, SQ_19, SQ_21, SQ_23};
        movePriorityList3 = {SQ_25, SQ_27, SQ_29, SQ_31,
                             SQ_9,  SQ_11, SQ_13, SQ_15};
    } else {
        movePriorityList0 = {SQ_17, SQ_19, SQ_21, SQ_23};
        movePriorityList1 = {SQ_25, SQ_27, SQ_29, SQ_31,
                             SQ_9,  SQ_11, SQ_13, SQ_15};
        movePriorityList2 = {SQ_16, SQ_18, SQ_20, SQ_22};
        movePriorityList3 = {SQ_24, SQ_26, SQ_28, SQ_30,
                             SQ_8,  SQ_10, SQ_12, SQ_14};
    }

    if (gameOptions.getShufflingEnabled()) {
        const auto seed = static_cast<uint32_t>(now());

        std::shuffle(movePriorityList0.begin(), movePriorityList0.end(),
                     std::default_random_engine(seed));
        std::shuffle(movePriorityList1.begin(), movePriorityList1.end(),
                     std::default_random_engine(seed));
        std::shuffle(movePriorityList2.begin(), movePriorityList2.end(),
                     std::default_random_engine(seed));
        std::shuffle(movePriorityList3.begin(), movePriorityList3.end(),
                     std::default_random_engine(seed));
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
#if 0
    if (!rule.hasDiagonalLines && gameOptions.getShufflingEnabled()) {
        const uint32_t seed = static_cast<uint32_t>(now());
        std::shuffle(MoveList<LEGAL>::movePriorityList.begin(),
                     MoveList<LEGAL>::movePriorityList.end(),
                     std::default_random_engine(seed));
    }
#endif
}

bool is_star_squares_full(Position *pos)
{
    bool ret;

    if (rule.hasDiagonalLines) {
        ret = pos->get_board()[SQ_17] && pos->get_board()[SQ_19] &&
              pos->get_board()[SQ_21] && pos->get_board()[SQ_23];
    } else {
        ret = pos->get_board()[SQ_16] && pos->get_board()[SQ_18] &&
              pos->get_board()[SQ_20] && pos->get_board()[SQ_22];
    }

    return ret;
}

// TODO: For Lasker Morris
Depth get_search_depth(const Position *pos)
{
    Depth d = 0;

    const int level = gameOptions.getSkillLevel();

    const int pw = pos->count<ON_BOARD>(WHITE);
    const int pb = pos->count<ON_BOARD>(BLACK);

    const int pieces = pw + pb;

    if (!gameOptions.getDeveloperMode()) {
        if (pos->phase == Phase::placing) {
            // TODO: Lasker Morris
            if (!gameOptions.getDrawOnHumanExperience() ||
                rule.mayMoveInPlacingPhase) {
                return static_cast<Depth>(level);
            }

            constexpr Depth placingDepthTable9[25] = {
                +1,  1, +1,  1,  /* 0 ~ 3 */
                +3,  3, +3,  15, /* 4 ~ 7 */
                +15, 5, +18, 0,  /* 8 ~ 11 */
                +0,  0, +0,  0,  /* 12 ~ 15 */
                +0,  0, +0,  0,  /* 16 ~ 19 */
                +0,  0, +0,  0,  /* 20 ~ 23 */
                +0               /* 24 */
            };

            constexpr Depth placingDepthTable12[25] = {
                +1,  2,  +2,  4,  /* 0 ~ 3 */
                +4,  12, +12, 18, /* 4 ~ 7 */
                +12, 0,  +0,  0,  /* 8 ~ 11 */
                +0,  0,  +0,  0,  /* 12 ~ 15 */
                +0,  0,  +0,  0,  /* 16 ~ 19 */
                +0,  0,  +0,  0,  /* 20 ~ 23 */
                +0                /* 24 */
            };

            const int index = rule.pieceCount * 2 - pos->count<IN_HAND>(WHITE) -
                              pos->count<IN_HAND>(BLACK);

            if (rule.hasDiagonalLines) {
                d = placingDepthTable12[index];
            } else {
                d = placingDepthTable9[index];
            }

#if 0
            if (gameOptions.getDrawOnHumanExperience()) {
                if (index == 4 &&
                    is_star_squares_full(const_cast<Position *>(pos))) {
                    d = 3;  // In order to use Mobility
                }
            }
#endif

            if (d == 0) {
                return static_cast<Depth>(level);
            }
            if (level > d) {
                return d;
            }
            return static_cast<Depth>(level);
        }
        if (pos->phase == Phase::moving) {
            return static_cast<Depth>(level);
        }
    }

#ifdef _DEBUG
    constexpr Depth reduce = 0;
#else
    constexpr Depth reduce = 0;
#endif

    constexpr Depth placingDepthTable_12[25] = {
        +1,  2,  +2,  4,  /* 0 ~ 3 */
        +4,  12, +12, 18, /* 4 ~ 7 */
        +12, 16, +16, 16, /* 8 ~ 11 */
        +16, 16, +16, 17, /* 12 ~ 15 */
        +17, 16, +16, 15, /* 16 ~ 19 */
        +15, 14, +14, 14, /* 20 ~ 23 */
        +14               /* 24 */
    };

    constexpr Depth placingDepthTable_12_special[25] = {
        +1,  2,  +2,  4,  /* 0 ~ 3 */
        +4,  12, +12, 12, /* 4 ~ 7 */
        +12, 13, +13, 13, /* 8 ~ 11 */
        +13, 13, +13, 13, /* 12 ~ 15 */
        +13, 13, +13, 13, /* 16 ~ 19 */
        +13, 13, +13, 13, /* 20 ~ 23 */
        +13               /* 24 */
    };

    constexpr Depth placingDepthTable_9[20] = {
        +1,  7,  +7,  10, /* 0 ~ 3 */
        +10, 12, +12, 14, /* 4 ~ 7 */
        +14, 14, +14, 14, /* 8 ~ 11 */
        +14, 14, +14, 14, /* 12 ~ 15 */
        +14, 14, +14,     /* 16 ~ 18 */
        +14               /* 19 */
    };

    constexpr Depth movingDepthTable[24] = {
        1,  1,  1,  1,  /* 0 ~ 3 */
        1,  1,  11, 11, /* 4 ~ 7 */
        11, 11, 11, 11, /* 8 ~ 11 */
        11, 11, 11, 11, /* 12 ~ 15 */
        11, 11, 12, 12, /* 16 ~ 19 */
        12, 12, 13, 14, /* 20 ~ 23 */
    };

#ifdef ENDGAME_LEARNING
    const Depth movingDiffDepthTable[13] = {
        0, 0, 0,       /* 0 ~ 2 */
        0, 0, 0, 0, 0, /* 3 ~ 7 */
        0, 0, 0, 0, 0  /* 8 ~ 12 */
    };
#else
    const Depth movingDiffDepthTable[13] = {
        0,  0,  0,        /* 0 ~ 2 */
        11, 11, 10, 9, 8, /* 3 ~ 7 */
        7,  6,  5,  4, 3  /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    constexpr Depth flyingDepth = 9;

    if (pos->phase == Phase::placing) {
        const int index = rule.pieceCount * 2 - pos->count<IN_HAND>(WHITE) -
                          pos->count<IN_HAND>(BLACK);

        if (rule.pieceCount == 9) {
            assert(0 <= index && index <= 19);
            d = placingDepthTable_9[index];
        } else {
            assert(0 <= index && index <= rule.pieceCount * 2);
            if (rule.millFormationActionInPlacingPhase !=
                    MillFormationActionInPlacingPhase::markAndDelayRemovingPieces &&
                !rule.hasDiagonalLines) {
                d = placingDepthTable_12_special[index];
            } else {
                d = placingDepthTable_12[index];
            }
        }
    }

    if (pos->phase == Phase::moving) {
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }

        // Can fly
        if (rule.mayFly) {
            if (pb <= rule.flyPieceCount || pw <= rule.flyPieceCount) {
                d = flyingDepth;
            }

            if (pb <= rule.flyPieceCount && pw <= rule.flyPieceCount) {
                d = flyingDepth / 2;
            }
        }
    }

    // For debugging
    if (unlikely(d > reduce)) {
        d -= reduce;
    }

    assert(d <= 32);

    // Make sure opening is OK
    if (d != 0 && d <= 4) {
        return d;
    }

#if 0
    // Adjust depth for Skill Level
    Depth depthLimit = (Depth)gameOptions.getSkillLevel();

    if (d > depthLimit) {
        d = depthLimit;
    }

    // Do not too weak
    if (depthLimit == 30 && d <= 4) {   // TODO(calcitem)
        d = 4;
    }
#endif

    // WAR: Limit depth if continue to move when stalemate
    if (rule.stalemateAction != StalemateAction::endWithStalemateLoss &&
        rule.stalemateAction != StalemateAction::endWithStalemateDraw) {
        if (d > 9) {
            d = 9;
        }
    }

    d += DEPTH_ADJUST;

    d = d >= 1 ? d : 1;

    assert(d <= 32);

#ifdef FLUTTER_UI
    LOGD("Search depth: %d\n", d);
#endif // FLUTTER_UI

    return d;
}

} // namespace Mills
