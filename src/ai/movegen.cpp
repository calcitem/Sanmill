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

#include <random>

#include "movegen.h"
#include "misc.h"

void MoveList::generateLegalMoves(MillGameAi_ab &ai_ab, Position &dummyPosition,
                                  MillGameAi_ab::Node *node, MillGameAi_ab::Node *rootNode,
                                  move_t bestMove)
{
    const int MOVE_PRIORITY_TABLE_SIZE = Board::N_RINGS * Board::N_SEATS;
    int location = 0;
    size_t newCapacity = 24;

    // 留足余量空间避免多次重新分配，此动作本身也占用 CPU/内存 开销
    switch (dummyPosition.getPhase()) {
    case PHASE_PLACING:
        if (dummyPosition.getAction() == ACTION_CAPTURE) {
            if (dummyPosition.whosTurn() == PLAYER_1)
                newCapacity = static_cast<size_t>(dummyPosition.getPiecesOnBoardCount_2());
            else
                newCapacity = static_cast<size_t>(dummyPosition.getPiecesOnBoardCount_1());
        } else {
            newCapacity = static_cast<size_t>(dummyPosition.getPiecesInHandCount_1() + dummyPosition.getPiecesInHandCount_2());
        }
        break;
    case PHASE_MOVING:
        if (dummyPosition.getAction() == ACTION_CAPTURE) {
            if (dummyPosition.whosTurn() == PLAYER_1)
                newCapacity = static_cast<size_t>(dummyPosition.getPiecesOnBoardCount_2());
            else
                newCapacity = static_cast<size_t>(dummyPosition.getPiecesOnBoardCount_1());
        } else {
            newCapacity = 6;
        }
        break;
    case PHASE_NOTSTARTED:
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
    player_t opponent = Position::getOpponent(dummyPosition.context.turn);

    // 列出所有合法的下一招
    switch (dummyPosition.context.action) {
        // 对于选子和落子动作
    case ACTION_CHOOSE:
    case ACTION_PLACE:
        // 对于摆子阶段
        if (dummyPosition.context.phase & (PHASE_PLACING | PHASE_NOTSTARTED)) {
            for (move_t i : movePriorityTable) {
                location = i;

                if (dummyPosition.boardLocations[location]) {
                    continue;
                }

                if (dummyPosition.context.phase != PHASE_NOTSTARTED || node != rootNode) {
                    ai_ab.addNode(node, VALUE_ZERO, (move_t)location, bestMove, dummyPosition.context.turn);
                } else {
                    // 若为先手，则抢占星位
                    if (Board::isStarLocation(location)) {
                        ai_ab.addNode(node, VALUE_INFINITE, (move_t)location, bestMove, dummyPosition.context.turn);
                    }
                }
            }
            break;
        }

        // 对于移子阶段
        if (dummyPosition.context.phase & PHASE_MOVING) {
            int newLocation, oldLocation;

            // 尽量走理论上较差的位置的棋子
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                oldLocation = movePriorityTable[i];

                if (!dummyPosition.choose(oldLocation)) {
                    continue;
                }

                if ((dummyPosition.context.turn == PLAYER_1 &&
                    (dummyPosition.context.nPiecesOnBoard_1 > dummyPosition.currentRule.nPiecesAtLeast || !dummyPosition.currentRule.allowFlyWhenRemainThreePieces)) ||
                     (dummyPosition.context.turn == PLAYER_2 &&
                    (dummyPosition.context.nPiecesOnBoard_2 > dummyPosition.currentRule.nPiecesAtLeast || !dummyPosition.currentRule.allowFlyWhenRemainThreePieces))) {
                    // 对于棋盘上还有3个子以上，或不允许飞子的情况，要求必须在着法表中
                    for (int direction = DIRECTION_CLOCKWISE; direction <= DIRECTION_OUTWARD; direction++) {
                        // 对于原有位置，遍历四个方向的着法，如果棋盘上为空位就加到结点列表中
                        newLocation = moveTable[oldLocation][direction];
                        if (newLocation && !dummyPosition.boardLocations[newLocation]) {
                            move_t move = move_t((oldLocation << 8) + newLocation);
                            ai_ab.addNode(node, VALUE_ZERO, move, bestMove, dummyPosition.context.turn); // (12%)
                        }
                    }
                } else {
                    // 对于棋盘上还有不到3个字，但允许飞子的情况，不要求在着法表中，是空位就行
                    for (newLocation = Board::LOCATION_BEGIN; newLocation < Board::LOCATION_END; newLocation++) {
                        if (!dummyPosition.boardLocations[newLocation]) {
                            move_t move = move_t((oldLocation << 8) + newLocation);
                            ai_ab.addNode(node, VALUE_ZERO, move, bestMove, dummyPosition.context.turn);
                        }
                    }
                }
            }
        }
        break;

        // 对于吃子动作
    case ACTION_CAPTURE:
        if (dummyPosition.context.board.isAllInMills(opponent)) {
            // 全成三的情况
            for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
                location = movePriorityTable[i];
                if (dummyPosition.boardLocations[location] & opponent) {
                    ai_ab.addNode(node, VALUE_ZERO, (move_t)-location, bestMove, dummyPosition.context.turn);
                }
            }
            break;
        }

        // 不是全成三的情况
        for (int i = MOVE_PRIORITY_TABLE_SIZE - 1; i >= 0; i--) {
            location = movePriorityTable[i];
            if (dummyPosition.boardLocations[location] & opponent) {
                if (dummyPosition.getRule()->allowRemoveMill || !dummyPosition.context.board.inHowManyMills(location)) {
                    ai_ab.addNode(node, VALUE_ZERO, (move_t)-location, bestMove, dummyPosition.context.turn);
                }
            }
        }
        break;

    default:
        break;
    }
}

void MoveList::createMoveTable(Position &position)
{
    // Note: 未严格按 direction_t 中枚举的顺序从左到右排列
#if 1
    const int moveTable_obliqueLine[Board::N_LOCATIONS][DIRECTIONS_COUNT] = {
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

    const int moveTable_noObliqueLine[Board::N_LOCATIONS][DIRECTIONS_COUNT] = {
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
    const int moveTable_obliqueLine[Board::N_LOCATIONS][DIRECTIONS_COUNT] = {
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

    const int moveTable_noObliqueLine[Board::N_LOCATIONS][DIRECTIONS_COUNT] = {
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

    if (position.currentRule.hasObliqueLines) {
        memcpy(moveTable, moveTable_obliqueLine, sizeof(moveTable));
    } else {
        memcpy(moveTable, moveTable_noObliqueLine, sizeof(moveTable));
    }

#ifdef DEBUG_MODE
    int sum = 0;
    for (int i = 0; i < Board::N_LOCATIONS; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < DIRECTIONS_COUNT; j++) {
            if (j == DIRECTIONS_COUNT - 1)
                loggerDebug("%d", moveTable[i][j]);
            else
                loggerDebug("%d, ", moveTable[i][j]);
            sum += moveTable[i][j];
        }
        loggerDebug("},\n");
    }
    loggerDebug("sum = %d\n", sum);
#endif
}

void MoveList::shuffleMovePriorityTable(Position &position)
{
    array<move_t, 4> movePriorityTable0 = { (move_t)17, (move_t)19, (move_t)21, (move_t)23 }; // 中圈四个顶点 (星位)
    array<move_t, 8> movePriorityTable1 = { (move_t)25, (move_t)27, (move_t)29, (move_t)31, (move_t)9, (move_t)11, (move_t)13, (move_t)15 }; // 外圈和内圈四个顶点
    array<move_t, 4> movePriorityTable2 = { (move_t)16, (move_t)18, (move_t)20, (move_t)22 }; // 中圈十字架
    array<move_t, 8> movePriorityTable3 = { (move_t)24, (move_t)26, (move_t)28, (move_t)30, (move_t)8, (move_t)10, (move_t)12, (move_t)14 }; // 外内圈十字架

    if (position.getRandomMove() == true) {
        uint32_t seed = static_cast<uint32_t>(now());

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
