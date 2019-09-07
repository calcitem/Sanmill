#include "evaluate.h"

Evaluation::value_t Evaluation::getValue(MillGame &chessTemp, MillGame::ChessContext *chessContext, MillGameAi_ab::Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = 0;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

#ifdef DEBUG_AB_TREE
    node->stage = chessContext->stage;
    node->action = chessContext->action;
    node->evaluated = true;
#endif

    switch (chessContext->stage) {
    case MillGame::GAME_NOTSTARTED:
        break;

    case MillGame::GAME_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = chessContext->nPiecesInHand_1 - chessContext->nPiecesInHand_2;
        value += nPiecesInHandDiff * 50;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = chessContext->nPiecesOnBoard_1 - chessContext->nPiecesOnBoard_2;
        value += nPiecesOnBoardDiff * 100;
#ifdef DEBUG_AB_TREE
        node->nPiecesOnBoardDiff = nPiecesOnBoardDiff;
#endif

        switch (chessContext->action) {
            // 选子和落子使用相同的评价方法
        case MillGame::ACTION_CHOOSE:
        case MillGame::ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算100分
        case MillGame::ACTION_CAPTURE:
            nPiecesNeedRemove = (chessContext->turn == MillGame::PLAYER1) ?
                chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
            value += nPiecesNeedRemove * 100;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    case MillGame::GAME_MOVING:
        // 按场上棋子计分
        value += chessContext->nPiecesOnBoard_1 * 100 - chessContext->nPiecesOnBoard_2 * 100;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += chessTemp.getMobilityDiff(false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (chessContext->action) {
            // 选子和落子使用相同的评价方法
        case MillGame::ACTION_CHOOSE:
        case MillGame::ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算128分
        case MillGame::ACTION_CAPTURE:
            nPiecesNeedRemove = (chessContext->turn == MillGame::PLAYER1) ?
                chessContext->nPiecesNeedRemove : -(chessContext->nPiecesNeedRemove);
            value += nPiecesNeedRemove * 128;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

        // 终局评价最简单
    case MillGame::GAME_OVER:
        // 布局阶段闷棋判断
        if (chessContext->nPiecesOnBoard_1 + chessContext->nPiecesOnBoard_2 >=
            MillGame::N_SEATS * MillGame::N_RINGS) {
            if (chessTemp.getRule()->isStartingPlayerLoseWhenBoardFull) {
                // winner = PLAYER2;
                value -= 10000;
#ifdef DEBUG_AB_TREE
                node->result = -3;
#endif
            } else {
                value = 0;
            }
        }

        // 走棋阶段被闷判断
        if (chessContext->action == MillGame::ACTION_CHOOSE &&
            chessTemp.isAllSurrounded(chessContext->turn) &&
            chessTemp.getRule()->isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            if (chessContext->turn == MillGame::PLAYER1) {
                value -= 10000;
#ifdef DEBUG_AB_TREE
                node->result = -2;
#endif
            } else {
                value += 10000;
#ifdef DEBUG_AB_TREE
                node->result = 2;
#endif
            }
        }

        // 剩余棋子个数判断
        if (chessContext->nPiecesOnBoard_1 < chessTemp.getRule()->nPiecesAtLeast) {
            value -= 10000;
#ifdef DEBUG_AB_TREE
            node->result = -1;
#endif
        } else if (chessContext->nPiecesOnBoard_2 < chessTemp.getRule()->nPiecesAtLeast) {
            value += 10000;
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