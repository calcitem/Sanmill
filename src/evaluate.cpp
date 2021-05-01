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

#include "bitboard.h"
#include "evaluate.h"
#include "thread.h"

namespace
{

class Evaluation
{
public:
    Evaluation() = delete;
    explicit Evaluation(Position &p) noexcept : pos(p)
    {
    }
    Evaluation &operator=(const Evaluation &) = delete;
    Value value();

private:
    Position &pos;
};


// Evaluation::value() is the main function of the class. It computes the various
// parts of the evaluation and returns the value of the position from the point
// of view of the side to move.

Value Evaluation::value()
{
    Value value = VALUE_ZERO;

    int pieceInHandDiffCount;
    int pieceOnBoardDiffCount;
    int pieceToRemoveCount;

    switch (pos.get_phase()) {
    case Phase::ready:
        break;

    case Phase::placing:
        pieceInHandDiffCount = pos.piece_in_hand_count(BLACK) - pos.piece_in_hand_count(WHITE);
        value += VALUE_EACH_PIECE_INHAND * pieceInHandDiffCount;

        pieceOnBoardDiffCount = pos.piece_on_board_count(BLACK) - pos.piece_on_board_count(WHITE);
        value += VALUE_EACH_PIECE_ONBOARD * pieceOnBoardDiffCount;

        switch (pos.get_action()) {
        case Action::select:
        case Action::place:
            break;

        case Action::remove:
            pieceToRemoveCount = (pos.side_to_move() == BLACK) ?
                pos.piece_to_remove_count() : -pos.piece_to_remove_count();
            value += VALUE_EACH_PIECE_PLACING_NEEDREMOVE * pieceToRemoveCount;
            break;
        default:
            break;
        }

        break;

    case Phase::moving:
        value = (pos.piece_on_board_count(BLACK) - pos.piece_on_board_count(WHITE)) * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        value += pos.get_mobility_diff() / 5;
#endif  /* EVALUATE_MOBILITY */

        switch (pos.get_action()) {
        case Action::select:
        case Action::place:
            break;

        case Action::remove:
            pieceToRemoveCount = (pos.side_to_move() == BLACK) ?
                pos.piece_to_remove_count() : -(pos.piece_to_remove_count());
            value += VALUE_EACH_PIECE_MOVING_NEEDREMOVE * pieceToRemoveCount;
            break;
        default:
            break;
        }

        break;

    case Phase::gameOver:
        if (pos.piece_on_board_count(BLACK) + pos.piece_on_board_count(WHITE) >= EFFECTIVE_SQUARE_NB) {
            if (rule.isBlackLoseButNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos.get_action() == Action::select &&
                   pos.is_all_surrounded(pos.side_to_move()) &&
                   rule.isLoseButNotChangeSideWhenNoWay) {
            const Value delta = pos.side_to_move() == BLACK ? -VALUE_MATE : VALUE_MATE;
            value += delta;
        }
        else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            value -= VALUE_MATE;
        } else if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            value += VALUE_MATE;
        }

        break;

    default:
        break;
    }

    if (pos.side_to_move() == WHITE) {
        value = -value;
    }

    return value;
}

} // namespace


/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(Position &pos)
{
    return Evaluation(pos).value();
}
