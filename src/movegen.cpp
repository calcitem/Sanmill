/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#include <cassert>
#include <random>
#include <array>
#include <cstring>

#include "movegen.h"
#include "position.h"
#include "misc.h"
#include "option.h"

/// generate<LEGAL> generates all the legal moves in the given position

template<>
ExtMove *generate<LEGAL>(/* const */ Position &pos, ExtMove *moveList)
{
    Square s;

    Color us = pos.side_to_move();
    Color them = ~us;

    const int MOVE_PRIORITY_TABLE_SIZE = FILE_NB * RANK_NB;

    ExtMove *cur = moveList;

    switch (pos.get_action()) {
    case ACTION_SELECT:
    case ACTION_PLACE:
        if (pos.get_phase() & (PHASE_PLACING | PHASE_READY)) {
            for (auto i : MoveList<LEGAL>::movePriorityTable) {
                if (pos.get_board()[i]) {
                    continue;
                }

#ifdef FIRST_MOVE_STAR_PREFERRED
                if (Position::is_star_square(s)) {
                    moves.push_back((Move)s);
                }
#else
                *cur++ = (Move)i;
#endif

            }
            break;
        }

        if (pos.get_phase() & PHASE_MOVING) {
            Square newSquare, oldSquare;

            // move piece that location weak first
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                oldSquare = MoveList<LEGAL>::movePriorityTable[i];

                if (!pos.select_piece(oldSquare)) {
                    continue;
                }

                if (pos.pieces_count_on_board(pos.side_to_move()) > rule.nPiecesAtLeast ||
                    !rule.allowFlyWhenRemainThreePieces) {
                    for (int direction = MD_BEGIN; direction < MD_NB; direction++) {
                        newSquare = static_cast<Square>(MoveList<LEGAL>::moveTable[oldSquare][direction]);
                        if (newSquare && !pos.get_board()[newSquare]) {
                            Move m = make_move(oldSquare, newSquare);
                            *cur++ = (Move)m;
                        }
                    }
                } else {
                    // piece count < 3£¬and allow fly, if is empty point, that's ok, do not need in move list
                    for (newSquare = SQ_BEGIN; newSquare < SQ_END; newSquare = static_cast<Square>(newSquare + 1)) {
                        if (!pos.get_board()[newSquare]) {
                            Move m = make_move(oldSquare, newSquare);
                            *cur++ = (Move)m;
                        }
                    }
                }
            }
        }
        break;

    case ACTION_REMOVE:
        if (pos.is_all_in_mills(them)) {
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                s = MoveList<LEGAL>::movePriorityTable[i];
                if (pos.get_board()[s] & make_piece(them)) {
                    *cur++ = (Move)-s;
                }
            }
            break;
        }

        // not is all in mills
        for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
            s = MoveList<LEGAL>::movePriorityTable[i];
            if (pos.get_board()[s] & make_piece(them)) {
                if (rule.allowRemovePieceInMill || !pos.in_how_many_mills(s, NOBODY)) {
                    *cur++ = (Move)-s;
                }
            }
        }
        break;

    default:
#ifdef FLUTTER_UI
        LOGD("generate(): action = %d\n", pos.get_action());
#endif
        assert(0);
        break;
    }

    return cur;
}

///////////////////////////////////////////////////////////////////////////////

template<>
void MoveList<LEGAL>::create()
{
    // Note: Not follow order of MoveDirection array
    const int moveTable_obliqueLine[SQUARE_NB][MD_NB] = {
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

    const int moveTable_noObliqueLine[SQUARE_NB][MD_NB] = {
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

    if (rule.hasObliqueLines) {
        memcpy(moveTable, moveTable_obliqueLine, sizeof(moveTable));
    } else {
        memcpy(moveTable, moveTable_noObliqueLine, sizeof(moveTable));
    }

#ifdef DEBUG_MODE
    int sum = 0;
    for (int i = 0; i < SQUARE_NB; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < MD_NB; j++) {
            if (j == MD_NB - 1)
                loggerDebug("%d", moveTable[i][j]);
            else
                loggerDebug("%d, ", moveTable[i][j]);
            sum += moveTable[i][j];
        }
        loggerDebug("},\n");
    }
    loggerDebug("sum = %d\n", sum);
#endif
}

template<>
void MoveList<LEGAL>::shuffle()
{
    std::array<Square, 4> movePriorityTable0 = { SQ_17, SQ_19, SQ_21, SQ_23 };
    std::array<Square, 8> movePriorityTable1 = { SQ_25, SQ_27, SQ_29, SQ_31, SQ_9, SQ_11, SQ_13, SQ_15 };
    std::array<Square, 4> movePriorityTable2 = { SQ_16, SQ_18, SQ_20, SQ_22 };
    std::array<Square, 8> movePriorityTable3 = { SQ_24, SQ_26, SQ_28, SQ_30, SQ_8, SQ_10, SQ_12, SQ_14 };

    if (rule.nTotalPiecesEachSide == 9)
    {
        movePriorityTable0 = { SQ_16, SQ_18, SQ_20, SQ_22 };
        movePriorityTable1 = { SQ_24, SQ_26, SQ_28, SQ_30, SQ_8, SQ_10, SQ_12, SQ_14 };
        movePriorityTable2 = { SQ_17, SQ_19, SQ_21, SQ_23 };
        movePriorityTable3 = { SQ_25, SQ_27, SQ_29, SQ_31, SQ_9, SQ_11, SQ_13, SQ_15 };
    }


    if (gameOptions.getRandomMoveEnabled()) {
        uint32_t seed = static_cast<uint32_t>(now());

        std::shuffle(movePriorityTable0.begin(), movePriorityTable0.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable1.begin(), movePriorityTable1.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable2.begin(), movePriorityTable2.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable3.begin(), movePriorityTable3.end(), std::default_random_engine(seed));
    }

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 0] = movePriorityTable0[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 4] = movePriorityTable1[i];
    }

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 12] = movePriorityTable2[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 16] = movePriorityTable3[i];
    }
}
