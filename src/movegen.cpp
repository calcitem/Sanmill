// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "movegen.h"
#include "mills.h"
#include "position.h"

/// generate<MOVE> generates all moves.
/// Returns a pointer to the end of the move moves.
template <>
ExtMove *generate<MOVE>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    if (pos.phase == Phase::placing && !rule.mayMoveInPlacingPhase) {
        return cur;
    }

    const int pieceOnBoardCount = pos.piece_on_board_count(pos.side_to_move());
    Piece *board = pos.get_board();

    // Iterate over all squares in reverse priority order
    // Move piece that location weak first
    for (auto i = SQUARE_NB - 1; i >= 0; --i) {
        const Square from = MoveList<LEGAL>::movePriorityList[i];

        // Skip if no piece of the current side to move
        if (!(pos.board[from] & make_piece(pos.sideToMove))) {
            continue;
        }

        // Special condition to generate "fly" moves
        if (rule.mayFly && pieceOnBoardCount <= rule.flyPieceCount &&
            pos.pieceInHandCount[pos.side_to_move()] == 0) {
            for (Square to = SQ_BEGIN; to < SQ_END; ++to) {
                if (!board[to]) {
                    *cur++ = make_move(from, to);
                }
            }
        } else {
            // Generate standard moves based on direction vectors
            for (auto direction = MD_BEGIN; direction < MD_NB; ++direction) {
                const Square to =
                    MoveList<LEGAL>::adjacentSquares[from][direction];
                if (to && !board[to]) {
                    *cur++ = make_move(from, to);
                }
            }
        }
    }

    return cur;
}

/// generate<PLACE> generates all places.
/// Returns a pointer to the end of the move list.
template <>
ExtMove *generate<PLACE>(Position &pos, ExtMove *moveList)
{
    const Color us = pos.side_to_move();
    ExtMove *cur = moveList;

    if (pos.piece_in_hand_count(us) == 0) {
        return cur;
    }

    for (auto s : MoveList<LEGAL>::movePriorityList) {
        if (!pos.get_board()[s]) {
            *cur++ = static_cast<Move>(s);
        }
    }

    return cur;
}

/// generate<REMOVE> generates all removes.
/// Returns a pointer to the end of the move moves.
template <>
ExtMove *generate<REMOVE>(Position &pos, ExtMove *moveList)
{
    const Color us = pos.side_to_move();
    const Color them = ~us;

    ExtMove *cur = moveList;

    if (pos.is_stalemate_removal()) {
        for (auto i = SQUARE_NB - 1; i >= 0; i--) {
            Square s = MoveList<LEGAL>::movePriorityList[i];
            if (pos.get_board()[s] & make_piece(them)) {
                if (pos.is_adjacent_to(s, us) == true) {
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }

        return cur;
    }

    if (pos.is_all_in_mills(them)) {
        for (auto i = SQUARE_NB - 1; i >= 0; i--) {
            Square s = MoveList<LEGAL>::movePriorityList[i];
            if (pos.get_board()[s] & make_piece(them)) {
                *cur++ = static_cast<Move>(-s);
            }
        }
        return cur;
    }

    // not is all in mills
    for (auto i = SQUARE_NB - 1; i >= 0; i--) {
        const Square s = MoveList<LEGAL>::movePriorityList[i];
        if (pos.get_board()[s] & make_piece(them)) {
            if (rule.mayRemoveFromMillsAlways ||
                !pos.potential_mills_count(s, NOBODY)) {
                *cur++ = static_cast<Move>(-s);
            }
        }
    }

    return cur;
}

/// generate<LEGAL> generates all the legal moves in the given position

template <>
ExtMove *generate<LEGAL>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    switch (pos.get_action()) {
    case Action::select:
    case Action::place:
        // Generate both PLACE and MOVE actions if the phase is placing
        if (pos.get_phase() == Phase::placing ||
            pos.get_phase() == Phase::ready) {
            cur = generate<PLACE>(pos, moveList);
            return generate<MOVE>(pos, cur);
        }

        // Generate MOVE actions if the phase is moving
        if (pos.get_phase() == Phase::moving) {
            return generate<MOVE>(pos, moveList);
        }

        break;

    case Action::remove:
        return generate<REMOVE>(pos, moveList);

    case Action::none:
#ifdef FLUTTER_UI
        LOGD("generate(): action = %hu\n", pos.get_action());
#endif
        break;
    }

    return cur;
}

template <>
void MoveList<LEGAL>::create()
{
    Mills::adjacent_squares_init();
}

template <>
void MoveList<LEGAL>::shuffle()
{
    Mills::move_priority_list_shuffle();
}
