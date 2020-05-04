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
value_t Evaluation::getValue(Position *position, Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = VALUE_ZERO;

    int nPiecesInHandDiff;
    int nPiecesOnBoardDiff;
    int nPiecesNeedRemove;

#ifdef DEBUG_AB_TREE
    node->phase = position->phase;
    node->action = position->action;
    node->evaluated = true;
#endif

    switch (position->phase) {
    case PHASE_READY:
        break;

    case PHASE_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = position->nPiecesInHand[BLACK] - position->nPiecesInHand[WHITE];
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = position->nPiecesOnBoard[BLACK] - position->nPiecesOnBoard[WHITE];
        value += nPiecesOnBoardDiff * VALUE_EACH_PIECE_ONBOARD;
#ifdef DEBUG_AB_TREE
        node->nPiecesOnBoardDiff = nPiecesOnBoardDiff;
#endif

        switch (position->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算100分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (position->sideToMove == PLAYER_BLACK) ?
                position->nPiecesNeedRemove : -(position->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_PLACING_NEEDREMOVE;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    case PHASE_MOVING:
        // 按场上棋子计分
        value = position->nPiecesOnBoard[BLACK] * VALUE_EACH_PIECE_ONBOARD -
                position->nPiecesOnBoard[WHITE] * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += st->position->getMobilityDiff(position->turn, position->nPiecesInHand[BLACK], position->nPiecesInHand[WHITE], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (position->action) {
        // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

        // 如果形成去子状态，每有一个可去的子，算128分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (position->sideToMove == PLAYER_BLACK) ?
                position->nPiecesNeedRemove : -(position->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_MOVING_NEEDREMOVE;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    // 终局评价最简单
    case PHASE_GAMEOVER:
        // 布局阶段闷棋判断
        if (position->nPiecesOnBoard[BLACK] + position->nPiecesOnBoard[WHITE] >=
            Board::N_SEATS * Board::N_RINGS) {
            if (rule.isStartingPlayerLoseWhenBoardFull) {
                value -= VALUE_WIN;
            } else {
                value = VALUE_DRAW;
            }
        }

        // 走棋阶段被闷判断
        else if (position->action == ACTION_CHOOSE &&
            position->board.isAllSurrounded(position->sideId, position->nPiecesOnBoard, position->sideToMove) &&
            rule.isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            value_t delta = position->sideToMove == PLAYER_BLACK ? -VALUE_WIN : VALUE_WIN;
            value += delta;
        }

        // 剩余棋子个数判断
        else if (position->nPiecesOnBoard[BLACK] < rule.nPiecesAtLeast) {
            value -= VALUE_WIN;
        } else if (position->nPiecesOnBoard[WHITE] < rule.nPiecesAtLeast) {
            value += VALUE_WIN;
        }

        break;

    default:
        break;
    }

    if (position->sideToMove == PLAYER_WHITE) {
        value = -value;
    }

    // 赋值返回
    node->value = value;
    return value;
}
#endif  // ALPHABETA_AI
