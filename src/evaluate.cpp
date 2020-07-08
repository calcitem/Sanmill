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

enum Tracing
{
    NO_TRACE, TRACE
};

enum Term
{ // The first 8 entries are reserved for PieceType
    MATERIAL = 8, IMBALANCE, MOBILITY, THREAT, PASSED, SPACE, INITIATIVE, TOTAL, TERM_NB
};

Score scores[TERM_NB][COLOR_NB];

double to_cp(Value v)
{
    return double(v) / StoneValue;
}

void add(int idx, Color c, Score s)
{
    scores[idx][c] = s;
}

void add(int idx, Score w, Score b = 0)
{
    scores[idx][WHITE] = w;
    scores[idx][BLACK] = b;
}

std::ostream &operator<<(std::ostream &os, Score s)
{
    os << std::setw(5) << to_cp(mg_value(s)) << " "
        << std::setw(5) << to_cp(eg_value(s));
    return os;
}

std::ostream &operator<<(std::ostream &os, Term t)
{
#if 0
    if (t == MATERIAL || t == IMBALANCE || t == INITIATIVE || t == TOTAL)
        os << " ----  ----" << " | " << " ----  ----";
    else
        os << scores[t][WHITE] << " | " << scores[t][BLACK];

    os << " | " << scores[t][WHITE] - scores[t][BLACK] << "\n";
#endif
    return os;
}
}

using namespace Trace;

#ifdef ALPHABETA_AI
Value Eval::evaluate(Position *pos)
{
    Value value = VALUE_ZERO;

    int nPiecesInHandDiff;
    int nPiecesOnBoardDiff;
    int nPiecesNeedRemove;

    switch (pos->phase) {
    case PHASE_READY:
        break;

    case PHASE_PLACING:
        nPiecesInHandDiff = pos->nPiecesInHand[BLACK] - pos->nPiecesInHand[WHITE];
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;

        nPiecesOnBoardDiff = pos->nPiecesOnBoard[BLACK] - pos->nPiecesOnBoard[WHITE];
        value += nPiecesOnBoardDiff * VALUE_EACH_PIECE_ONBOARD;

        switch (pos->action) {
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        case ACTION_REMOVE:
            nPiecesNeedRemove = (pos->sideToMove == BLACK) ?
                pos->nPiecesNeedRemove : -(pos->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_PLACING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    case PHASE_MOVING:
        value = pos->nPiecesOnBoard[BLACK] * VALUE_EACH_PIECE_ONBOARD -
                pos->nPiecesOnBoard[WHITE] * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        value += pos->get_mobility_diff(position->turn, position->nPiecesInHand[BLACK], position->nPiecesInHand[WHITE], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (pos->action) {
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        case ACTION_REMOVE:
            nPiecesNeedRemove = (pos->sideToMove == BLACK) ?
                pos->nPiecesNeedRemove : -(pos->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_MOVING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    case PHASE_GAMEOVER:
        if (pos->nPiecesOnBoard[BLACK] + pos->nPiecesOnBoard[WHITE] >=
            RANK_NB * FILE_NB) {
            if (rule.isBlackLosebutNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos->action == ACTION_SELECT &&
            pos->is_all_surrounded() &&
            rule.isLoseButNotChangeTurnWhenNoWay) {
            Value delta = pos->sideToMove == BLACK ? -VALUE_MATE : VALUE_MATE;
            value += delta;
        }

        else if (pos->nPiecesOnBoard[BLACK] < rule.nPiecesAtLeast) {
            value -= VALUE_MATE;
        } else if (pos->nPiecesOnBoard[WHITE] < rule.nPiecesAtLeast) {
            value += VALUE_MATE;
        }

        break;

    default:
        break;
    }

    if (pos->sideToMove == WHITE) {
        value = -value;
    }

    return value;
}
#endif  // ALPHABETA_AI



/// trace() is like evaluate(), but instead of returning a value, it returns
/// a string (suitable for outputting to stdout) that contains the detailed
/// descriptions and values of each evaluation term. Useful for debugging.

std::string Eval::trace(Position *pos)
{
#if 0
    std::memset(scores, 0, sizeof(scores));

    // TODO
    //pos->this_thread()->contempt = 0 // TODO: SCORE_ZERO; // Reset any dynamic contempt

    Value v = Evaluation(pos)->value();

    v = pos->side_to_move() == WHITE ? v : -v; // Trace scores are from white's point of view

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
    return "";
}