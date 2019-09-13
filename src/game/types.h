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

using step_t = uint16_t;

using depth_t = uint8_t;

#ifdef TRANSPOSITION_TABLE_CUTDOWN
using hash_t = uint32_t;
#else
using hash_t = uint64_t;
#endif /* TRANSPOSITION_TABLE_CUTDOWN */

enum move_t : int32_t
{
    MOVE_NONE,
    //MOVE_NULL = 65
};

enum square_t : int
{
    SQ_0, SQ_1, SQ_2, SQ_3, SQ_4, SQ_5, SQ_6, SQ_7,
    SQ_D5, SQ_E5, SQ_E4, SQ_E3, SQ_D3, SQ_C3, SQ_C4, SQ_C5,
    SQ_D6, SQ_F6, SQ_F4, SQ_F2, SQ_D2, SQ_B2, SQ_B4, SQ_B6,
    SQ_D7, SQ_G7, SQ_G4, SQ_G1, SQ_D1, SQ_A1, SQ_A4, SQ_A7,
    SQ_32, SQ_33, SQ_34, SQ_35, SQ_36, SQ_37, SQ_38, SQ_39,
    SQ_COUNT
};

// 移动方向，包括顺时针、逆时针、向内、向外4个方向
enum direction_t
{
    DIRECTION_CLOCKWISE = 0,       // 顺时针
    DIRECTION_BEGIN = DIRECTION_CLOCKWISE,
    DIRECTION_ANTICLOCKWISE = 1,   // 逆时针
    DIRECTION_INWARD = 2,          // 向内
    DIRECTION_OUTWARD = 3,         // 向外
    DIRECTION_FLY = 4,             // 飞子
    DIRECTIONS_COUNT = 4               // 移动方向数
};

// 横直斜3个方向，禁止修改!
enum line_t
{
    LINE_HORIZONTAL = 0,        // 横线
    LINE_VERTICAL = 1,          // 直线
    LINE_SLASH = 2,  // 斜线
    LINE_TYPES_COUNT = 3               // 移动方向数
};

// 棋盘点上棋子的类型
enum piece_t : uint16_t
{
    PIECE_EMPTY = 0,   // 没有棋子
    PIECE_PLAYER_1 = 1,    // 先手的子
    PIECE_PLAYER_2 = 2,     // 后手的子
    PIECE_FORBIDDEN = 3,    // 禁点
    PIECE_TYPE_COUNT = 4
};

// 玩家标识, 轮流状态, 胜负标识
enum player_t : uint8_t
{
    PLAYER_1 = 0x10,   // 玩家1
    PLAYER_2 = 0x20,   // 玩家2
    PLAYER_DRAW = 0x40,      // 双方和棋
    PLAYER_NOBODY = 0x80     // 胜负未分
};

// 局面阶段标识
enum phase_t : uint16_t
{
    PHASE_NONE = 0,
    PHASE_NOTSTARTED = 1,       // 未开局
    PHASE_PLACING = 1 << 1,     // 开局（摆棋）
    PHASE_MOVING = 1 << 2,      // 中局（走棋）
    PHASE_GAMEOVER = 1 << 3     // 结局
};

enum value_t : int16_t
{
    VALUE_ZERO = 0,
    VALUE_DRAW = 0,
    VALUE_WIN = 10000,
    VALUE_INFINITE = 32001,
    VALUE_UNKNOWN = INT16_MIN,

    VALUE_EACH_PIECE_INHAND = 50,
    VALUE_EACH_PIECE_ONBOARD = 100,
    VALUE_EACH_PIECE_NEEDREMOVE = 100,
    VALUE_EACH_PIECE_NEEDREMOVE_2 = 128,
};

// 动作状态标识
enum action_t : uint16_t
{
    ACTION_NONE = 0x0000,
    ACTION_CHOOSE = 0x0100,    // 选子
    ACTION_PLACE = 0x0200,     // 落子
    ACTION_CAPTURE = 0x0400    // 提子
};

#define ENABLE_BASE_OPERATORS_ON(T)                                \
constexpr T operator+(T d1, T d2) { return T(int(d1) + int(d2)); } \
constexpr T operator-(T d1, T d2) { return T(int(d1) - int(d2)); } \
constexpr T operator-(T d) { return T(-int(d)); }                  \
inline T& operator+=(T& d1, T d2) { return d1 = d1 + d2; }         \
inline T& operator-=(T& d1, T d2) { return d1 = d1 - d2; }

#define ENABLE_INCR_OPERATORS_ON(T)                                \
inline T& operator++(T& d) { return d = T(int(d) + 1); }           \
inline T& operator--(T& d) { return d = T(int(d) - 1); }

#define ENABLE_FULL_OPERATORS_ON(T)                                \
ENABLE_BASE_OPERATORS_ON(T)                                        \
constexpr T operator*(int i, T d) { return T(i * int(d)); }        \
constexpr T operator*(T d, int i) { return T(int(d) * i); }        \
constexpr T operator/(T d, int i) { return T(int(d) / i); }        \
constexpr int operator/(T d1, T d2) { return int(d1) / int(d2); }  \
inline T& operator*=(T& d, int i) { return d = T(int(d) * i); }    \
inline T& operator/=(T& d, int i) { return d = T(int(d) / i); }

ENABLE_FULL_OPERATORS_ON(value_t)
ENABLE_FULL_OPERATORS_ON(direction_t)

ENABLE_INCR_OPERATORS_ON(direction_t)
ENABLE_INCR_OPERATORS_ON(piece_t)
ENABLE_INCR_OPERATORS_ON(square_t)

// Additional operators to add integers to a Value
constexpr value_t operator+(value_t v, int i)
{
    return value_t(int(v) + i);
}

constexpr value_t operator-(value_t v, int i)
{
    return value_t(int(v) - i);
}

inline value_t &operator+=(value_t &v, int i)
{
    return v = v + i;
}

inline value_t &operator-=(value_t &v, int i)
{
    return v = v - i;
}

#endif /* TYPES_H */
