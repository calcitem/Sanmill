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

#include <algorithm>
#include <cassert>
#include <cstring>   // For std::memset
#include <iomanip>
#include <sstream>

#include "bitboard.h"
#include "evaluate.h"
#include "thread.h"

namespace Trace
{

double to_cp(Value v)
{
    return double(v) / StoneValue;
}

std::ostream &operator<<(std::ostream &os, Score s)
{
    os << std::setw(5) << "" << " "
        << std::setw(5) << "";
    return os;
}
}

using namespace Trace;

namespace
{

class Evaluation
{
public:
    Evaluation() = delete;
    explicit Evaluation(const Position &p) : pos(p)
    {
    }
    Evaluation &operator=(const Evaluation &) = delete;
    Value value();

private:
    const Position &pos;
};

// Evaluation::value() is the main function of the class. It computes the various
// parts of the evaluation and returns the value of the position from the point
// of view of the side to move.

Value Evaluation::value()
{
    Value value = VALUE_ZERO;

    int nPiecesInHandDiff;
    int nPiecesOnBoardDiff;
    int pieceCountNeedRemove;

    switch (pos.phase) {
    case PHASE_READY:
        break;

    case PHASE_PLACING:
        nPiecesInHandDiff = pos.pieceCountInHand[BLACK] - pos.pieceCountInHand[WHITE];
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;

        nPiecesOnBoardDiff = pos.pieceCountOnBoard[BLACK] - pos.pieceCountOnBoard[WHITE];
        value += nPiecesOnBoardDiff * VALUE_EACH_PIECE_ONBOARD;

        switch (pos.action) {
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        case ACTION_REMOVE:
            pieceCountNeedRemove = (pos.sideToMove == BLACK) ?
                pos.pieceCountNeedRemove : -(pos.pieceCountNeedRemove);
            value += pieceCountNeedRemove * VALUE_EACH_PIECE_PLACING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    case PHASE_MOVING:
        value = pos.pieceCountOnBoard[BLACK] * VALUE_EACH_PIECE_ONBOARD -
            pos.pieceCountOnBoard[WHITE] * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        value += pos.get_mobility_diff(position->turn, position->pieceCountInHand[BLACK], position->pieceCountInHand[WHITE], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (pos.action) {
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        case ACTION_REMOVE:
            pieceCountNeedRemove = (pos.sideToMove == BLACK) ?
                pos.pieceCountNeedRemove : -(pos.pieceCountNeedRemove);
            value += pieceCountNeedRemove * VALUE_EACH_PIECE_MOVING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    case PHASE_GAMEOVER:
        if (pos.pieceCountOnBoard[BLACK] + pos.pieceCountOnBoard[WHITE] >=
            RANK_NB * FILE_NB) {
            if (rule.isBlackLosebutNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos.action == ACTION_SELECT &&
                   pos.is_all_surrounded() &&
                   rule.isLoseButNotChangeSideWhenNoWay) {
            Value delta = pos.sideToMove == BLACK ? -VALUE_MATE : VALUE_MATE;
            value += delta;
        }

        else if (pos.pieceCountOnBoard[BLACK] < rule.nPiecesAtLeast) {
            value -= VALUE_MATE;
        } else if (pos.pieceCountOnBoard[WHITE] < rule.nPiecesAtLeast) {
            value += VALUE_MATE;
        }

        break;

    default:
        break;
    }

    if (pos.sideToMove == WHITE) {
        value = -value;
    }

    return value;
}

} // namespace


/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(const Position &pos)
{
#ifdef ALPHABETA_AI
    return Evaluation(pos).value();
#endif  // ALPHABETA_AI
}

/// trace() is like evaluate(), but instead of returning a value, it returns
/// a string (suitable for outputting to stdout) that contains the detailed
/// descriptions and values of each evaluation term. Useful for debugging.

std::string Eval::trace(const Position &pos)
{
#if 0
    std::memset(scores, 0, sizeof(scores));

    // TODO
    //pos.this_thread()->contempt = 0 // TODO: SCORE_ZERO; // Reset any dynamic contempt

    Value v = Evaluation(pos)->value();

    v = pos.side_to_move() == WHITE ? v : -v; // Trace scores are from white's point of view

    std::stringstream ss;
    ss << std::showpoint << std::noshowpos << std::fixed << std::setprecision(2)
        << "     Term    |    White    |    Black    |    Total   \n"
        << "             |   MG    EG  |   MG    EG  |   MG    EG \n"
        << " ------------+-------------+-------------+------------\n"
        << "    Material | " << Term(MATERIAL)
        << "   Imbalance | " << Term(IMBALANCE)
        << "    Mobility | " << Term(MOBILITY)
        << "     Threats | " << Term(THREAT)
        << "      Passed | " << Term(PASSED)
        << "       Space | " << Term(SPACE)
        << "  Initiative | " << Term(INITIATIVE)
        << " ------------+-------------+-------------+------------\n"
        << "       Total | " << Term(TOTAL);

    ss << "\nTotal evaluation: " << to_cp(v) << " (white side)\n";

    return ss.str();
#endif
    //pos = pos;
    return "";
}