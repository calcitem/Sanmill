#include <random>

#include "movegen.h"

void MoveList::generateLegalMoves(MillGameAi_ab &ai_ab, MillGame &chessTemp,
                                  MillGameAi_ab::Node *node, MillGameAi_ab::Node *rootNode,
                                  move_t bestMove)
{
    const int MOVE_PRIORITY_TABLE_SIZE = MillGame::N_RINGS * MillGame::N_SEATS;
    int pos = 0;
    size_t newCapacity = 24;

    // 留足余量空间避免多次重新分配，此动作本身也占用 CPU/内存 开销
    switch (chessTemp.getStage()) {
    case MillGame::GAME_PLACING:
        if (chessTemp.getAction() == MillGame::ACTION_CAPTURE) {
            if (chessTemp.whosTurn() == MillGame::PLAYER1)
                newCapacity = static_cast<size_t>(chessTemp.getPiecesOnBoardCount_2());
            else
                newCapacity = static_cast<size_t>(chessTemp.getPiecesOnBoardCount_1());
        } else {
            newCapacity = static_cast<size_t>(chessTemp.getPiecesInHandCount_1() + chessTemp.getPiecesInHandCount_2());
        }
        break;
    case MillGame::GAME_MOVING:
        if (chessTemp.getAction() == MillGame::ACTION_CAPTURE) {
            if (chessTemp.whosTurn() == MillGame::PLAYER1)
                newCapacity = static_cast<size_t>(chessTemp.getPiecesOnBoardCount_2());
            else
                newCapacity = static_cast<size_t>(chessTemp.getPiecesOnBoardCount_1());
        } else {
            newCapacity = 6;
        }
        break;
    case MillGame::GAME_NOTSTARTED:
        newCapacity = 24;
        break;
    default:
        newCapacity = 24;
        break;
    };

    node->children.reserve(newCapacity + 2 /* TODO: 未细调故再多留余量2 */);

    // 如果有子节点，则返回，避免重复建立
    if (!node->children.empty()) {
        return;
    }

    // 对手
    MillGame::Player opponent = MillGame::getOpponent(chessTemp.context.turn);

    // 列出所有合法的下一招
    switch (chessTemp.context.action) {
        // 对于选子和落子动作
    case MillGame::ACTION_CHOOSE:
    case MillGame::ACTION_PLACE:
        // 对于摆子阶段
        if (chessTemp.context.stage & (MillGame::GAME_PLACING | MillGame::GAME_NOTSTARTED)) {
            for (int i : movePriorityTable) {
                pos = i;

                if (chessTemp.board_[pos]) {
                    continue;
                }

                if (chessTemp.context.stage != MillGame::GAME_NOTSTARTED || node != rootNode) {
                    ai_ab.addNode(node, 0, pos, bestMove, chessTemp.context.turn);
                } else {
                    // 若为先手，则抢占星位
                    if (MillGame::isStarPoint(pos)) {
                        ai_ab.addNode(node, MillGameAi_ab::INF_VALUE, pos, bestMove, chessTemp.context.turn);
                    }
                }
            }
            break;
        }

        // 对于移子阶段
        if (chessTemp.context.stage & MillGame::GAME_MOVING) {
            int newPos, oldPos;

            // 尽量走理论上较差的位置的棋子
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                oldPos = movePriorityTable[i];

                if (!chessTemp.choose(oldPos)) {
                    continue;
                }

                if ((chessTemp.context.turn == MillGame::PLAYER1 &&
                    (chessTemp.context.nPiecesOnBoard_1 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces)) ||
                     (chessTemp.context.turn == MillGame::PLAYER2 &&
                    (chessTemp.context.nPiecesOnBoard_2 > chessTemp.currentRule.nPiecesAtLeast || !chessTemp.currentRule.allowFlyWhenRemainThreePieces))) {
                    // 对于棋盘上还有3个子以上，或不允许飞子的情况，要求必须在着法表中
                    for (int moveDirection = MillGame::MOVE_DIRECTION_CLOCKWISE; moveDirection <= MillGame::MOVE_DIRECTION_OUTWARD; moveDirection++) {
                        // 对于原有位置，遍历四个方向的着法，如果棋盘上为空位就加到结点列表中
                        newPos = moveTable[oldPos][moveDirection];
                        if (newPos && !chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            ai_ab.addNode(node, 0, move, bestMove, chessTemp.context.turn); // (12%)
                        }
                    }
                } else {
                    // 对于棋盘上还有不到3个字，但允许飞子的情况，不要求在着法表中，是空位就行
                    for (newPos = MillGame::POS_BEGIN; newPos < MillGame::POS_END; newPos++) {
                        if (!chessTemp.board_[newPos]) {
                            int move = (oldPos << 8) + newPos;
                            ai_ab.addNode(node, 0, move, bestMove, chessTemp.context.turn);
                        }
                    }
                }
            }
        }
        break;

        // 对于吃子动作
    case MillGame::ACTION_CAPTURE:
        if (chessTemp.isAllInMills(opponent)) {
            // 全成三的情况
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                pos = movePriorityTable[i];
                if (chessTemp.board_[pos] & opponent) {
                    ai_ab.addNode(node, 0, -pos, bestMove, chessTemp.context.turn);
                }
            }
            break;
        }

        // 不是全成三的情况
        for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
            pos = movePriorityTable[i];
            if (chessTemp.board_[pos] & opponent) {
                if (chessTemp.getRule()->allowRemoveMill || !chessTemp.isInMills(pos)) {
                    ai_ab.addNode(node, 0, -pos, bestMove, chessTemp.context.turn);
                }
            }
        }
        break;

    default:
        break;
    }
}

void MoveList::createMoveTable(MillGame &chess)
{
#ifdef CONST_MOVE_TABLE
#if 1
    const int moveTable_obliqueLine[MillGame::N_POINTS][MillGame::N_MOVE_DIRECTIONS] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {9, 15, 16, 0},
        /*  9 */ {17, 8, 10, 0},
        /* 10 */ {9, 11, 18, 0},
        /* 11 */ {19, 10, 12, 0},
        /* 12 */ {11, 13, 20, 0},
        /* 13 */ {21, 12, 14, 0},
        /* 14 */ {13, 15, 22, 0},
        /* 15 */ {23, 8, 14, 0},

        /* 16 */ {17, 23, 8, 24},
        /* 17 */ {9, 25, 16, 18},
        /* 18 */ {17, 19, 10, 26},
        /* 19 */ {11, 27, 18, 20},
        /* 20 */ {19, 21, 12, 28},
        /* 21 */ {13, 29, 20, 22},
        /* 22 */ {21, 23, 14, 30},
        /* 23 */ {15, 31, 16, 22},

        /* 24 */ {25, 31, 16, 0},
        /* 25 */ {17, 24, 26, 0},
        /* 26 */ {25, 27, 18, 0},
        /* 27 */ {19, 26, 28, 0},
        /* 28 */ {27, 29, 20, 0},
        /* 29 */ {21, 28, 30, 0},
        /* 30 */ {29, 31, 22, 0},
        /* 31 */ {23, 24, 30, 0},

        /* 32 */ {0, 0, 0, 0},
        /* 33 */ {0, 0, 0, 0},
        /* 34 */ {0, 0, 0, 0},
        /* 35 */ {0, 0, 0, 0},
        /* 36 */ {0, 0, 0, 0},
        /* 37 */ {0, 0, 0, 0},
        /* 38 */ {0, 0, 0, 0},
        /* 39 */ {0, 0, 0, 0},
    };

    const int moveTable_noObliqueLine[MillGame::N_POINTS][MillGame::N_MOVE_DIRECTIONS] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {16, 9, 15, 0},
        /*  9 */ {10, 8, 0, 0},
        /* 10 */ {18, 11, 9, 0},
        /* 11 */ {12, 10, 0, 0},
        /* 12 */ {20, 13, 11, 0},
        /* 13 */ {14, 12, 0, 0},
        /* 14 */ {22, 15, 13, 0},
        /* 15 */ {8, 14, 0, 0},

        /* 16 */ {8, 24, 17, 23},
        /* 17 */ {18, 16, 0, 0},
        /* 18 */ {10, 26, 19, 17},
        /* 19 */ {20, 18, 0, 0},
        /* 20 */ {12, 28, 21, 19},
        /* 21 */ {22, 20, 0, 0},
        /* 22 */ {14, 30, 23, 21},
        /* 23 */ {16, 22, 0, 0},

        /* 24 */ {16, 25, 31, 0},
        /* 25 */ {26, 24, 0, 0},
        /* 26 */ {18, 27, 25, 0},
        /* 27 */ {28, 26, 0, 0},
        /* 28 */ {20, 29, 27, 0},
        /* 29 */ {30, 28, 0, 0},
        /* 30 */ {22, 31, 29, 0},
        /* 31 */ {24, 30, 0, 0},

        /* 32 */ {0, 0, 0, 0},
        /* 33 */ {0, 0, 0, 0},
        /* 34 */ {0, 0, 0, 0},
        /* 35 */ {0, 0, 0, 0},
        /* 36 */ {0, 0, 0, 0},
        /* 37 */ {0, 0, 0, 0},
        /* 38 */ {0, 0, 0, 0},
        /* 39 */ {0, 0, 0, 0},
    };
#else
    const int moveTable_obliqueLine[MillGame::N_POINTS][MillGame::N_MOVE_DIRECTIONS] = {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},

        {9, 15, 0, 16},
        {10, 8, 0, 17},
        {11, 9, 0, 18},
        {12, 10, 0, 19},
        {13, 11, 0, 20},
        {14, 12, 0, 21},
        {15, 13, 0, 22},
        {8, 14, 0, 23},

        {17, 23, 8, 24},
        {18, 16, 9, 25},
        {19, 17, 10, 26},
        {20, 18, 11, 27},
        {21, 19, 12, 28},
        {22, 20, 13, 29},
        {23, 21, 14, 30},
        {16, 22, 15, 31},

        {25, 31, 16, 0},
        {26, 24, 17, 0},
        {27, 25, 18, 0},
        {28, 26, 19, 0},
        {29, 27, 20, 0},
        {30, 28, 21, 0},
        {31, 29, 22, 0},
        {24, 30, 23, 0},

        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0}
    };

    const int moveTable_noObliqueLine[MillGame::N_POINTS][MillGame::N_MOVE_DIRECTIONS] = {
        /*  0 */ {0, 0, 0, 0},
        /*  1 */ {0, 0, 0, 0},
        /*  2 */ {0, 0, 0, 0},
        /*  3 */ {0, 0, 0, 0},
        /*  4 */ {0, 0, 0, 0},
        /*  5 */ {0, 0, 0, 0},
        /*  6 */ {0, 0, 0, 0},
        /*  7 */ {0, 0, 0, 0},

        /*  8 */ {9, 15, 0, 16},
        /*  9 */ {10, 8, 0, 0},
        /* 10 */ {11, 9, 0, 18},
        /* 11 */ {12, 10, 0, 0},
        /* 12 */ {13, 11, 0, 20},
        /* 13 */ {14, 12, 0, 0},
        /* 14 */ {15, 13, 0, 22},
        /* 15 */ {8, 14, 0, 0},

        /* 16 */ {17, 23, 8, 24},
        /* 17 */ {18, 16, 0, 0},
        /* 18 */ {19, 17, 10, 26},
        /* 19 */ {20, 18, 0, 0},
        /* 20 */ {21, 19, 12, 28},
        /* 21 */ {22, 20, 0, 0},
        /* 22 */ {23, 21, 14, 30},
        /* 23 */ {16, 22, 0, 0},

        /* 24 */ {25, 31, 16, 0},
        /* 25 */ {26, 24, 0, 0},
        /* 26 */ {27, 25, 18, 0},
        /* 27 */ {28, 26, 0, 0},
        /* 28 */ {29, 27, 20, 0},
        /* 29 */ {30, 28, 0, 0},
        /* 30 */ {31, 29, 22, 0},
        /* 31 */ {24, 30, 0, 0},

        /* 32 */ {0, 0, 0, 0},
        /* 33 */ {0, 0, 0, 0},
        /* 34 */ {0, 0, 0, 0},
        /* 35 */ {0, 0, 0, 0},
        /* 36 */ {0, 0, 0, 0},
        /* 37 */ {0, 0, 0, 0},
        /* 38 */ {0, 0, 0, 0},
        /* 39 */ {0, 0, 0, 0},
    };
#endif

    if (chess.currentRule.hasObliqueLines) {
        memcpy(moveTable, moveTable_obliqueLine, sizeof(moveTable));
    } else {
        memcpy(moveTable, moveTable_noObliqueLine, sizeof(moveTable));
    }

#else /* CONST_MOVE_TABLE */

    for (int r = 1; r <= N_RINGS; r++) {
        for (int s = 0; s < N_SEATS; s++) {
            int p = r * N_SEATS + s;

            // 顺时针走一步的位置
            moveTable[p][MOVE_DIRECTION_CLOCKWISE] = r * N_SEATS + (s + 1) % N_SEATS;

            // 逆时针走一步的位置
            moveTable[p][MOVE_DIRECTION_ANTICLOCKWISE] = r * N_SEATS + (s + N_SEATS - 1) % N_SEATS;

            // 如果是 0、2、4、6位（偶数位）或是有斜线
            if (!(s & 1) || this->currentRule.hasObliqueLines) {
                if (r > 1) {
                    // 向内走一步的位置
                    moveTable[p][MOVE_DIRECTION_INWARD] = (r - 1) * N_SEATS + s;
                }

                if (r < N_RINGS) {
                    // 向外走一步的位置
                    moveTable[p][MOVE_DIRECTION_OUTWARD] = (r + 1) * N_SEATS + s;
                }
            }
#if 0
            // 对于无斜线情况下的1、3、5、7位（奇数位），则都设为棋盘外点（默认'\x00'）
            else {
                // 向内走一步的位置设为随便棋盘外一点
                moveTable[i * SEAT + j][2] = '\x00';
                // 向外走一步的位置设为随便棋盘外一点
                moveTable[i * SEAT + j][3] = '\x00';
            }
#endif
        }
    }
#endif /* CONST_MOVE_TABLE */

#if 0
    int sum = 0;
    for (int i = 0; i < N_POINTS; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < N_MOVE_DIRECTIONS; j++) {
            if (j == N_MOVE_DIRECTIONS - 1)
                loggerDebug("%d", moveTable[i][j]);
            else
                loggerDebug("%d, ", moveTable[i][j]);
            sum += moveTable[i][j];
        }
        loggerDebug("},\n");
    }
    loggerDebug("sum = %d\n");
#endif
}

void MoveList::shuffleMovePriorityTable(MillGame & chess)
{
    array<int, 4> movePriorityTable0 = { 17, 19, 21, 23 }; // 中圈四个顶点 (星位)
    array<int, 8> movePriorityTable1 = { 25, 27, 29, 31, 9, 11, 13, 15 }; // 外圈和内圈四个顶点
    array<int, 4> movePriorityTable2 = { 16, 18, 20, 22 }; // 中圈十字架
    array<int, 8> movePriorityTable3 = { 24, 26, 28, 30, 8, 10, 12, 14 }; // 外内圈十字架

    if (chess.getRandomMove() == true) {
        uint32_t seed = static_cast<uint32_t>(std::chrono::system_clock::now().time_since_epoch().count());

        std::shuffle(movePriorityTable0.begin(), movePriorityTable0.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable1.begin(), movePriorityTable1.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable2.begin(), movePriorityTable2.end(), std::default_random_engine(seed));
        std::shuffle(movePriorityTable3.begin(), movePriorityTable3.end(), std::default_random_engine(seed));
    }

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 0] = movePriorityTable0[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 4] = movePriorityTable1[i];
    }

    for (size_t i = 0; i < 4; i++) {
        movePriorityTable[i + 12] = movePriorityTable2[i];
    }

    for (size_t i = 0; i < 8; i++) {
        movePriorityTable[i + 16] = movePriorityTable3[i];
    }
}
