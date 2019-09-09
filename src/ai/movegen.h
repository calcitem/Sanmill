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

#ifndef MOVEGEN_H
#define MOVEGEN_H

#include "config.h"
#include "millgame.h"
#include "search.h"

class MoveList
{
public:
    MoveList() = delete;

    MoveList &operator=(const MoveList &) = delete;
   
    // 生成所有合法的着法并建立子节点
    static void generateLegalMoves(MillGameAi_ab &ai_ab, MillGame &gameTemp,
                                   MillGameAi_ab::Node *node, MillGameAi_ab::Node *rootNode,
                                   move_t bestMove);

    // 生成着法表
    static void createMoveTable(MillGame &game);

    // 随机打乱着法搜索顺序
    static void shuffleMovePriorityTable(MillGame &game);

    // 着法表 // TODO: Move to private
    inline static int moveTable[Board::N_LOCATIONS][N_MOVE_DIRECTIONS] = { {0} };

private:
    // 着法顺序表, 后续会被打乱
    inline static array<int, Board::N_RINGS *Board::N_SEATS> movePriorityTable {
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    };
};

#endif /* MOVEGEN_H */
