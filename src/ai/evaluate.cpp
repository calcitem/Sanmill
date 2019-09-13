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

value_t Evaluation::getValue(Position &dummyPosition, PositionContext *positionContext, MillGameAi_ab::Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = VALUE_ZERO;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

#ifdef DEBUG_AB_TREE
    node->phase = positionContext->phase;
    node->action = positionContext->action;
    node->evaluated = true;
#endif

    switch (positionContext->phase) {
    case PHASE_NOTSTARTED:
        break;

    case PHASE_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = positionContext->nPiecesInHand_1 - positionContext->nPiecesInHand_2;
        value += nPiecesInHandDiff * VALUE_EACH_PIECE_INHAND;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = positionContext->nPiecesOnBoard_1 - positionContext->nPiecesOnBoard_2;
        value += nPiecesOnBoardDiff * VALUE_EACH_PIECE_ONBOARD;
#ifdef DEBUG_AB_TREE
        node->nPiecesOnBoardDiff = nPiecesOnBoardDiff;
#endif

        switch (positionContext->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算100分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (positionContext->turn == PLAYER1) ?
                positionContext->nPiecesNeedRemove : -(positionContext->nPiecesNeedRemove);
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
        value = positionContext->nPiecesOnBoard_1 * VALUE_EACH_PIECE_ONBOARD -
                positionContext->nPiecesOnBoard_2 * VALUE_EACH_PIECE_ONBOARD;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += dummyPosition.getMobilityDiff(positionContext->turn, dummyPosition.currentRule, positionContext->nPiecesInHand_1, positionContext->nPiecesInHand_2, false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (positionContext->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算128分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (positionContext->turn == PLAYER1) ?
                positionContext->nPiecesNeedRemove : -(positionContext->nPiecesNeedRemove);
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
        if (positionContext->nPiecesOnBoard_1 + positionContext->nPiecesOnBoard_2 >=
            Board::N_SEATS * Board::N_RINGS) {
            if (dummyPosition.getRule()->isStartingPlayerLoseWhenBoardFull) {
                // winner = PLAYER2;
                value -= VALUE_WIN;
#ifdef DEBUG_AB_TREE
                node->result = -3;
#endif
            } else {
                value = VALUE_DRAW;
            }
        }

        // 走棋阶段被闷判断
        if (positionContext->action == ACTION_CHOOSE &&
            dummyPosition.context.board.isAllSurrounded(positionContext->turn, dummyPosition.currentRule, positionContext->nPiecesOnBoard_1, positionContext->nPiecesOnBoard_2, positionContext->turn) &&
            dummyPosition.getRule()->isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            if (positionContext->turn == PLAYER1) {
                value -= VALUE_WIN;
#ifdef DEBUG_AB_TREE
                node->result = -2;
#endif
            } else {
                value += VALUE_WIN;
#ifdef DEBUG_AB_TREE
                node->result = 2;
#endif
            }
        }

        // 剩余棋子个数判断
        if (positionContext->nPiecesOnBoard_1 < dummyPosition.getRule()->nPiecesAtLeast) {
            value -= VALUE_WIN;
#ifdef DEBUG_AB_TREE
            node->result = -1;
#endif
        } else if (positionContext->nPiecesOnBoard_2 < dummyPosition.getRule()->nPiecesAtLeast) {
            value += VALUE_WIN;
#ifdef DEBUG_AB_TREE
            node->result = 1;
#endif
        }

        break;

    default:
        break;
    }

    // 赋值返回
    node->value = value;
    return value;
}