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

#ifndef TYPES_H
#define TYPES_H

#include "config.h"

using move_t = int32_t;
using step_t = uint16_t;
using value_t = int16_t;
using depth_t = uint8_t;

#ifdef TRANSPOSITION_TABLE_CUTDOWN
using hash_t = uint32_t;
#else
using hash_t = uint64_t;
#endif /* TRANSPOSITION_TABLE_CUTDOWN */

// 移动方向，包括顺时针、逆时针、向内、向外4个方向
enum MoveDirection
{
    MOVE_DIRECTION_CLOCKWISE = 0,       // 顺时针
    MOVE_DIRECTION_ANTICLOCKWISE = 1,   // 逆时针
    MOVE_DIRECTION_INWARD = 2,          // 向内
    MOVE_DIRECTION_OUTWARD = 3,         // 向外
    MOVE_DIRECTION_FLY = 4,             // 飞子
    N_MOVE_DIRECTIONS = 4               // 移动方向数
};

// 棋盘点上棋子的类型
enum PointType : uint16_t
{
    POINT_TYPE_EMPTY = 0,   // 没有棋子
    POINT_TYPE_PLAYER1 = 1,    // 先手的子
    POINT_TYPE_PLAYER2 = 2,     // 后手的子
    POINT_TYPE_FORBIDDEN = 3,    // 禁点
    POINT_TYPE_COUNT = 4
};

// 玩家标识, 轮流状态, 胜负标识
enum Player : uint8_t
{
    PLAYER1 = 0x10,   // 玩家1
    PLAYER2 = 0x20,   // 玩家2
    PLAYER_DRAW = 0x40,      // 双方和棋
    PLAYER_NOBODY = 0x80     // 胜负未分
};

// 局面阶段标识
enum PositionStage : uint16_t
{
    GAME_NONE = 0x0000,
    GAME_NOTSTARTED = 0x0001,   // 未开局
    GAME_PLACING = 0x0002,      // 开局（摆棋）
    GAME_MOVING = 0x0004,       // 中局（走棋）
    GAME_OVER = 0x0008          // 结局
};

// 动作状态标识
enum Action : uint16_t
{
    ACTION_NONE = 0x0000,
    ACTION_CHOOSE = 0x0100,    // 选子
    ACTION_PLACE = 0x0200,     // 落子
    ACTION_CAPTURE = 0x0400    // 提子
};

#endif /* TYPES_H */
