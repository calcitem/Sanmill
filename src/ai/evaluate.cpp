/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "evaluate.h"

value_t Evaluation::getValue(Game &tempGame, Position *position, AIAlgorithm::Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = VALUE_ZERO;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

#ifdef DEBUG_AB_TREE
    node->phase = position->phase;
    node->action = position->action;
    node->evaluated = true;
#endif

    switch (position->phase) {
    case PHASE_NOTSTARTED:
        break;

    case PHASE_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = position->nPiecesInHand[1] - position->nPiecesInHand[2];
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = position->nPiecesOnBoard[1] - position->nPiecesOnBoard[2];
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
            nPiecesNeedRemove = (position->turn == PLAYER_1) ?
                position->nPiecesNeedRemove : -(position->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_NEEDREMOVE;
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
        value = position->nPiecesOnBoard[1] * VALUE_EACH_PIECE_ONBOARD -
                position->nPiecesOnBoard[2] * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += tempGame.getMobilityDiff(position->turn, tempGame.currentRule, position->nPiecesInHand[1], position->nPiecesInHand[2], false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (position->action) {
        // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

        // 如果形成去子状态，每有一个可去的子，算128分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (position->turn == PLAYER_1) ?
                position->nPiecesNeedRemove : -(position->nPiecesNeedRemove);
            value += nPiecesNeedRemove * VALUE_EACH_PIECE_NEEDREMOVE_2;
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
        if (position->nPiecesOnBoard[1] + position->nPiecesOnBoard[2] >=
            Board::N_SEATS * Board::N_RINGS) {
            if (tempGame.getRule()->isStartingPlayerLoseWhenBoardFull) {
                value -= VALUE_WIN;
            } else {
                value = VALUE_DRAW;
            }
        }

        // 走棋阶段被闷判断
        if (position->action == ACTION_CHOOSE &&
            tempGame.position.board.isAllSurrounded(position->turn, tempGame.currentRule, position->nPiecesOnBoard, position->turn) &&
            tempGame.getRule()->isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            value_t delta = position->turn == PLAYER_1 ? -VALUE_WIN : VALUE_WIN;
            value += delta;
        }

        // 剩余棋子个数判断
        if (position->nPiecesOnBoard[1] < tempGame.getRule()->nPiecesAtLeast) {
            value -= VALUE_WIN;
        } else if (position->nPiecesOnBoard[2] < tempGame.getRule()->nPiecesAtLeast) {
            value += VALUE_WIN;
        }

        break;

    default:
        break;
    }

    // 赋值返回
    node->value = value;
    return value;
}