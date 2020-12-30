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

    for (auto s : MoveList<LEGAL>::movePriorityList) {
        if (!pos.get_board()[s]) {
            *cur++ = (Move)s;
        }        
    }

    return cur;
}

/// generate<PLACE> generates all places.
/// Returns a pointer to the end of the move moves.
template<>
ExtMove *generate<MOVE>(Position &pos, ExtMove *moveList)
{
    Square from, to;
    ExtMove *cur = moveList;

    // move piece that location weak first
    for (auto i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
        from = MoveList<LEGAL>::movePriorityList[i];

        if (!pos.select_piece(from)) {
            continue;
        }

        if (pos.n_pieces_on_board(pos.side_to_move()) > rule.nPiecesAtLeast ||
            !rule.flyingAllowed) {
            for (auto direction = MD_BEGIN; direction < MD_NB; ++direction) {
                to = static_cast<Square>(MoveList<LEGAL>::adjacentSquares[from][direction]);
                if (to && !pos.get_board()[to]) {
                    *cur++ = make_move(from, to);
                }
            }
        } else {
            // piece count < 3 and allow fly, if is empty point, that's ok, do not need in move list
            for (to = SQ_BEGIN; to < SQ_END; ++to) {
                if (!pos.get_board()[to]) {
                    *cur++ = make_move(from, to);
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
        for (auto i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
            s = MoveList<LEGAL>::movePriorityList[i];
            if (pos.get_board()[s] & make_piece(them)) {
                *cur++ = (Move)-s;
            }
        }
        return cur;
    }

    // not is all in mills
    for (auto i = EFFECTIVE_SQUARE_NB - 1; i >= 0; i--) {
        s = MoveList<LEGAL>::movePriorityList[i];
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
    case Action::select:
    case Action::place:
        if (pos.get_phase() == Phase::placing || pos.get_phase() == Phase::ready) {
            return generate<PLACE>(pos, moveList);
        }

        if (pos.get_phase() == Phase::moving) {
            return generate<MOVE>(pos, moveList);
        }

        break;

    case Action::remove:
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


template<>
void MoveList<LEGAL>::create()
{
    Mills::adjacent_squares_init();
}

template<>
void MoveList<LEGAL>::shuffle()
{
    Mills::move_priority_list_shuffle();
}
