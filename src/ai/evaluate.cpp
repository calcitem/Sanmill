#include "evaluate.h"

value_t Evaluation::getValue(MillGame &gameTemp, GameContext *gameContext, MillGameAi_ab::Node *node)
{
    // 初始评估值为0，对先手有利则增大，对后手有利则减小
    value_t value = 0;

    int nPiecesInHandDiff = INT_MAX;
    int nPiecesOnBoardDiff = INT_MAX;
    int nPiecesNeedRemove = 0;

#ifdef DEBUG_AB_TREE
    node->stage = gameContext->stage;
    node->action = gameContext->action;
    node->evaluated = true;
#endif

    switch (gameContext->stage) {
    case GAME_NOTSTARTED:
        break;

    case GAME_PLACING:
        // 按手中的棋子计分，不要break;
        nPiecesInHandDiff = gameContext->nPiecesInHand_1 - gameContext->nPiecesInHand_2;
        value += nPiecesInHandDiff * 50;
#ifdef DEBUG_AB_TREE
        node->nPiecesInHandDiff = nPiecesInHandDiff;
#endif

        // 按场上棋子计分
        nPiecesOnBoardDiff = gameContext->nPiecesOnBoard_1 - gameContext->nPiecesOnBoard_2;
        value += nPiecesOnBoardDiff * 100;
#ifdef DEBUG_AB_TREE
        node->nPiecesOnBoardDiff = nPiecesOnBoardDiff;
#endif

        switch (gameContext->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算100分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (gameContext->turn == PLAYER1) ?
                gameContext->nPiecesNeedRemove : -(gameContext->nPiecesNeedRemove);
            value += nPiecesNeedRemove * 100;
#ifdef DEBUG_AB_TREE
            node->nPiecesNeedRemove = nPiecesNeedRemove;
#endif
            break;
        default:
            break;
        }

        break;

    case GAME_MOVING:
        // 按场上棋子计分
        value += gameContext->nPiecesOnBoard_1 * 100 - gameContext->nPiecesOnBoard_2 * 100;

#ifdef EVALUATE_MOBILITY
        // 按棋子活动能力计分
        value += gameTemp.getMobilityDiff(gameContext->turn, gameTemp.currentRule, gameContext->nPiecesInHand_1, gameContext->nPiecesInHand_2, false) * 10;
#endif  /* EVALUATE_MOBILITY */

        switch (gameContext->action) {
            // 选子和落子使用相同的评价方法
        case ACTION_CHOOSE:
        case ACTION_PLACE:
            break;

            // 如果形成去子状态，每有一个可去的子，算128分
        case ACTION_CAPTURE:
            nPiecesNeedRemove = (gameContext->turn == PLAYER1) ?
                gameContext->nPiecesNeedRemove : -(gameContext->nPiecesNeedRemove);
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
    case GAME_OVER:
        // 布局阶段闷棋判断
        if (gameContext->nPiecesOnBoard_1 + gameContext->nPiecesOnBoard_2 >=
            Board::N_SEATS * Board::N_RINGS) {
            if (gameTemp.getRule()->isStartingPlayerLoseWhenBoardFull) {
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
        if (gameContext->action == ACTION_CHOOSE &&
            gameTemp.context.board.isAllSurrounded(gameContext->turn, gameTemp.currentRule, gameContext->nPiecesOnBoard_1, gameContext->nPiecesOnBoard_2, gameContext->turn) &&
            gameTemp.getRule()->isLoseWhenNoWay) {
            // 规则要求被“闷”判负，则对手获胜  
            if (gameContext->turn == PLAYER1) {
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
        if (gameContext->nPiecesOnBoard_1 < gameTemp.getRule()->nPiecesAtLeast) {
            value -= 10000;
#ifdef DEBUG_AB_TREE
            node->result = -1;
#endif
        } else if (gameContext->nPiecesOnBoard_2 < gameTemp.getRule()->nPiecesAtLeast) {
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