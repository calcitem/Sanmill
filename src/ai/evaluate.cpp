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
value_t Eval::evaluate(Position *pos)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = VALUE_ZERO;

    int nPiecesInHandDiff;
    int nPiecesOnBoardDiff;
    int nPiecesNeedRemove;

    switch (pos->phase) {
    case PHASE_READY:
        break;

    case PHASE_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = pos->nPiecesInHand[BLACK] - pos->nPiecesInHand[WHITE];
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;

        // 按场上棋子计分
        nPiecesOnBoardDiff = pos->nPiecesOnBoard[BLACK] - pos->nPiecesOnBoard[WHITE];
        value += nPiecesOnBoardDiff * VALUE_EACH_PIECE_ONBOARD;

        switch (pos->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算100分
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
        // 按场上棋子计分
        value = pos->nPiecesOnBoard[BLACK] * VALUE_EACH_PIECE_ONBOARD -
                pos->nPiecesOnBoard[WHITE] * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += st->position->getMobilityDiff(position->turn, position->nPiecesInHand[BLACK], position->nPiecesInHand[WHITE], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (pos->action) {
        // 选子和落子使用相同的评价方法
        case ACTION_SELECT:
        case ACTION_PLACE:
            break;

        // 如果形成去子状态，每有一个可去的子，算128分
        case ACTION_REMOVE:
            nPiecesNeedRemove = (pos->sideToMove == PLAYER_BLACK) ?
                pos->nPiecesNeedRemove : -(pos->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_MOVING_NEEDREMOVE;
            break;
        default:
            break;
        }

        break;

    // 终局评价最简单
    case PHASE_GAMEOVER:
        // 布局阶段闷棋判断
        if (pos->nPiecesOnBoard[BLACK] + pos->nPiecesOnBoard[WHITE] >=
            Board::N_SEATS * Board::N_RINGS) {
            if (rule.isStartingPlayerLoseWhenBoardFull) {
                value -= VALUE_WIN;
            } else {
                value = VALUE_DRAW;
            }
        }

        // 走棋阶段被闷判断
        else if (pos->action == ACTION_SELECT &&
            pos->board.isAllSurrounded(pos->sideId, pos->nPiecesOnBoard, pos->sideToMove) &&
            rule.isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            value_t delta = pos->sideToMove == PLAYER_BLACK ? -VALUE_WIN : VALUE_WIN;
            value += delta;
        }

        // 剩余棋子个数判断
        else if (pos->nPiecesOnBoard[BLACK] < rule.nPiecesAtLeast) {
            value -= VALUE_WIN;
        } else if (pos->nPiecesOnBoard[WHITE] < rule.nPiecesAtLeast) {
            value += VALUE_WIN;
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
