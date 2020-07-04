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

#include "evaluate.h"

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
            nPiecesNeedRemove = (pos->sideToMove == PLAYER_BLACK) ?
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
        value += pos->getMobilityDiff(position->turn, position->nPiecesInHand[BLACK], position->nPiecesInHand[WHITE], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (pos->action) {
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        case ACTION_REMOVE:
            nPiecesNeedRemove = (pos->sideToMove == PLAYER_BLACK) ?
                pos->nPiecesNeedRemove : -(pos->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_MOVING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    case PHASE_GAMEOVER:
        if (pos->nPiecesOnBoard[BLACK] + pos->nPiecesOnBoard[WHITE] >=
            Board::N_RANKS * Board::N_FILES) {
            if (rule.isBlackLosebutNotDrawWhenBoardFull) {
                value -= VALUE_MATE;
            } else {
                value = VALUE_DRAW;
            }
        } else if (pos->action == ACTION_SELECT &&
            pos->board.isAllSurrounded(pos->sideId, pos->nPiecesOnBoard, pos->sideToMove) &&
            rule.isLoseButNotChangeTurnWhenNoWay) {
            Value delta = pos->sideToMove == PLAYER_BLACK ? -VALUE_MATE : VALUE_MATE;
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

    if (pos->sideToMove == PLAYER_WHITE) {
        value = -value;
    }

    return value;
}
#endif  // ALPHABETA_AI
