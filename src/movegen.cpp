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

#include <cassert>
#include <random>
#include <array>
#include <cstring>

#include "movegen.h"
#include "position.h"
#include "misc.h"
#include "bitboard.h"
#include "option.h"
#include "mills.h"

/// generate<PLACE> generates all places.
/// Returns a pointer to the end of the move list.
template<>
ExtMove *generate<PLACE>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    for (auto i : MoveList<LEGAL>::movePriorityTable) {
        if (pos.get_board()[i]) {
            continue;
        }

        *cur++ = (Move)i;
    }

    return cur;
}

/// generate<PLACE> generates all places.
/// Returns a pointer to the end of the move moves.
template<>
ExtMove *generate<MOVE>(Position &pos, ExtMove *moveList)
{
    Square newSquare, oldSquare;
    ExtMove *cur = moveList;

    // move piece that location weak first
    for (int i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
        oldSquare = MoveList<LEGAL>::movePriorityTable[i];

        if (!pos.select_piece(oldSquare)) {
            continue;
        }

        if (pos.pieces_count_on_board(pos.side_to_move()) > rule.nPiecesAtLeast ||
            !rule.allowFlyWhenRemainThreePieces) {
            for (int direction = MD_BEGIN; direction < MD_NB; direction++) {
                newSquare = static_cast<Square>(MoveList<LEGAL>::adjacentSquares[oldSquare][direction]);
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

    return cur;
}

/// generate<PLACE> generates all removes.
/// Returns a pointer to the end of the move moves.
template<>
ExtMove *generate<REMOVE>(Position &pos, ExtMove *moveList)
{
    Square s;

    Color us = pos.side_to_move();
    Color them = ~us;

    ExtMove *cur = moveList;

    if (pos.is_all_in_mills(them)) {
        for (int i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
            s = MoveList<LEGAL>::movePriorityTable[i];
            if (pos.get_board()[s] & make_piece(them)) {
                *cur++ = (Move)-s;
            }
        }
        return cur;
    }

    // not is all in mills
    for (int i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
        s = MoveList<LEGAL>::movePriorityTable[i];
        if (pos.get_board()[s] & make_piece(them)) {
            if (rule.allowRemovePieceInMill || !pos.in_how_many_mills(s, NOBODY)) {
                *cur++ = (Move)-s;
            }
        }
    }

    return cur;
}

/// generate<LEGAL> generates all the legal moves in the given position

template<>
ExtMove *generate<LEGAL>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    switch (pos.get_action()) {
    case ACTION_SELECT:
    case ACTION_PLACE:
        if (pos.get_phase() & (PHASE_PLACING | PHASE_READY)) {
            return generate<PLACE>(pos, moveList);
        }

        if (pos.get_phase() & PHASE_MOVING) {
            return generate<MOVE>(pos, moveList);
        }

        break;

    case ACTION_REMOVE:
        return generate<REMOVE>(pos, moveList);

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
    Mills::adjacent_squares_init();
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
