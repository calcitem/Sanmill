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

#include <random>

#include "movegen.h"
#include "player.h"
#include "misc.h"
#include "option.h"
#include "types.h"
#include "search.h"
#include "position.h"

void MoveList::create()
{
    // Note: Not follow order of MoveDirection array
#if 1
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
#else
    const int moveTable_obliqueLine[Board::N_LOCATIONS][MD_NB] = {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},

        {9, 15, 0, 16},
        {10, 8, 0, 17},
        {11, 9, 0, 18},
        {12, 10, 0, 19},
        {13, 11, 0, 20},
        {14, 12, 0, 21},
        {15, 13, 0, 22},
        {8, 14, 0, 23},

        {17, 23, 8, 24},
        {18, 16, 9, 25},
        {19, 17, 10, 26},
        {20, 18, 11, 27},
        {21, 19, 12, 28},
        {22, 20, 13, 29},
        {23, 21, 14, 30},
        {16, 22, 15, 31},

        {25, 31, 16, 0},
        {26, 24, 17, 0},
        {27, 25, 18, 0},
        {28, 26, 19, 0},
        {29, 27, 20, 0},
        {30, 28, 21, 0},
        {31, 29, 22, 0},
        {24, 30, 23, 0},

        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0}
    };

    const int moveTable_noObliqueLine[Board::N_LOCATIONS][MD_NB] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {9, 15, 0, 16},
        /*  9 */ {10, 8, 0, 0},
        /* 10 */ {11, 9, 0, 18},
        /* 11 */ {12, 10, 0, 0},
        /* 12 */ {13, 11, 0, 20},
        /* 13 */ {14, 12, 0, 0},
        /* 14 */ {15, 13, 0, 22},
        /* 15 */ {8, 14, 0, 0},

        /* 16 */ {17, 23, 8, 24},
        /* 17 */ {18, 16, 0, 0},
        /* 18 */ {19, 17, 10, 26},
        /* 19 */ {20, 18, 0, 0},
        /* 20 */ {21, 19, 12, 28},
        /* 21 */ {22, 20, 0, 0},
        /* 22 */ {23, 21, 14, 30},
        /* 23 */ {16, 22, 0, 0},

        /* 24 */ {25, 31, 16, 0},
        /* 25 */ {26, 24, 0, 0},
        /* 26 */ {27, 25, 18, 0},
        /* 27 */ {28, 26, 0, 0},
        /* 28 */ {29, 27, 20, 0},
        /* 29 */ {30, 28, 0, 0},
        /* 30 */ {31, 29, 22, 0},
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
#endif

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

void MoveList::shuffle()
{
    array<Move, 4> movePriorityTable0 = { (Move)17, (Move)19, (Move)21, (Move)23 };
    array<Move, 8> movePriorityTable1 = { (Move)25, (Move)27, (Move)29, (Move)31, (Move)9, (Move)11, (Move)13, (Move)15 };
    array<Move, 4> movePriorityTable2 = { (Move)16, (Move)18, (Move)20, (Move)22 };
    array<Move, 8> movePriorityTable3 = { (Move)24, (Move)26, (Move)28, (Move)30, (Move)8, (Move)10, (Move)12, (Move)14 };

    if (rule.nTotalPiecesEachSide == 9)
    {
        movePriorityTable0 = { (Move)16, (Move)18, (Move)20, (Move)22 };
        movePriorityTable1 = { (Move)24, (Move)26, (Move)28, (Move)30, (Move)8, (Move)10, (Move)12, (Move)14 };
        movePriorityTable2 = { (Move)17, (Move)19, (Move)21, (Move)23 };
        movePriorityTable3 = { (Move)25, (Move)27, (Move)29, (Move)31, (Move)9, (Move)11, (Move)13, (Move)15 };
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



/// generate<LEGAL> generates all the legal moves in the given position

//template<>
ExtMove *generateMoves(/* TODO: const */ Position *position, ExtMove *moveList)
{
    Square square;
    Color opponent;

    //moves.clear();
    ExtMove *cur = moveList;

    switch (position->action) {
    case ACTION_SELECT:
    case ACTION_PLACE:
        // 对于摆子阶段
        if (position->phase & (PHASE_PLACING | PHASE_READY)) {
            for (Move i : MoveList::movePriorityTable) {
                square = static_cast<Square>(i);

                if (position->board.locations[square]) {
                    continue;
                }

#ifdef MCTS_AI
                moves.push_back((Move)square);
#else // MCTS_AI
                if (position->phase != PHASE_READY) {
                    *cur++ = ((Move)square);
                } else {
#ifdef FIRST_MOVE_STAR_PREFERRED
                    if (Board::isStar(square)) {
                        moves.push_back((Move)square);
                    }
#else
                    *cur++ = ((Move)square);
#endif
                }
#endif // MCTS_AI
            }
            break;
        }

        if (position->phase & PHASE_MOVING) {
            Square newSquare, oldSquare;

            // move piece that location weak first
            for (int i = Board::MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                oldSquare = static_cast<Square>(MoveList::movePriorityTable[i]);

                if (!position->selectPiece(oldSquare)) {
                    continue;
                }

                if (position->nPiecesOnBoard[position->sideToMove] > rule.nPiecesAtLeast ||
                    !rule.allowFlyWhenRemainThreePieces) {
                    for (int direction = MD_BEGIN; direction < MD_NB; direction++) {
                        newSquare = static_cast<Square>(MoveList::moveTable[oldSquare][direction]);
                        if (newSquare && !position->board.locations[newSquare]) {
                            Move m = make_move(oldSquare, newSquare);
                            *cur++ = ((Move)m);
                        }
                    }
                } else {
                    // piece count < 3，and allow fly, if is empty point, that's ok, do not need in move list
                    for (newSquare = SQ_BEGIN; newSquare < SQ_END; newSquare = static_cast<Square>(newSquare + 1)) {
                        if (!position->board.locations[newSquare]) {
                            Move m = make_move(oldSquare, newSquare);
                            *cur++ = ((Move)m);
                        }
                    }
                }
            }
        }
        break;

    case ACTION_REMOVE:
        opponent = Player::getOpponent(position->sideToMove);

        if (position->board.isAllInMills(opponent)) {
            for (int i = Board::MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                square = static_cast<Square>(MoveList::movePriorityTable[i]);
                if (position->board.locations[square] & (opponent << PLAYER_SHIFT)) {
                    *cur++ = ((Move)-square);
                }
            }
            break;
        }

        // not is all in mills
        for (int i = Board::MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
            square = static_cast<Square>(MoveList::movePriorityTable[i]);
            if (position->board.locations[square] & (opponent << PLAYER_SHIFT)) {
                if (rule.allowRemovePieceInMill || !position->board.inHowManyMills(square, NOBODY)) {
                    *cur++ = ((Move)-square);
                }
            }
        }
        break;

    default:
        assert(0);
        break;
    }

    return cur;
}

