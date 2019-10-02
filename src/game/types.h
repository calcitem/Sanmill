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
using location_t = uint8_t;

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

enum color_t : uint8_t
{
    NOCOLOR,
    BLACK,
    WHITE,
    COLOR_COUNT
};

enum square_t : int32_t
{
    SQ_0 = 0, SQ_1 = 1, SQ_2 = 2, SQ_3 = 3, SQ_4 = 4, SQ_5 = 5, SQ_6 = 6, SQ_7 = 7,
    SQ_D5 = 8, SQ_E5 = 9, SQ_E4 = 10, SQ_E3 = 11, SQ_D3 = 12, SQ_C3 = 13, SQ_C4 = 14, SQ_C5 = 15,
    SQ_D6 = 16, SQ_F6 = 17, SQ_F4 = 18, SQ_F2 = 19, SQ_D2 = 20, SQ_B2 = 21, SQ_B4 = 22, SQ_B6 = 23,
    SQ_D7 = 24, SQ_G7 = 25, SQ_G4 = 26, SQ_G1 = 27, SQ_D1 = 28, SQ_A1 = 29, SQ_A4 = 30, SQ_A7 = 31,
    SQ_32 = 32, SQ_33 = 33, SQ_34 = 34, SQ_35 = 35, SQ_36 = 36, SQ_37 = 37, SQ_38 = 38, SQ_39 = 39,
    SQ_EXPANDED_COUNT = 40,
    SQ_BEGIN = SQ_D5,
    SQ_END = SQ_32
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

// 列
enum file_t : int
{
    FILE_A, FILE_B, FILE_C, FILE_D, FILE_E, FILE_F, FILE_G, FILE_COUNT
};

// 行
enum rank_t : int
{
    RANK_1, RANK_2, RANK_3, RANK_4, RANK_5, RANK_6, RANK_7, RANK_COUNT
};

// 横直斜3个方向，禁止修改!
enum line_t
{
    LINE_HORIZONTAL = 0,        // 横线
    LINE_VERTICAL = 1,          // 直线
    LINE_SLASH = 2,  // 斜线
    LINE_TYPES_COUNT = 3               // 移动方向数
};

#define PLAYER_SHIFT    4

// 玩家标识, 轮流状态, 胜负标识
enum player_t : uint8_t
{
    PLAYER_BLACK = 0x1 << PLAYER_SHIFT,   // 玩家1
    PLAYER_WHITE = 0x2 << PLAYER_SHIFT,   // 玩家2
    PLAYER_DRAW = 0x4 << PLAYER_SHIFT,      // 双方和棋
    PLAYER_NOBODY = 0x8 << PLAYER_SHIFT     // 胜负未分
};

// 局面阶段标识
enum phase_t : uint16_t
{
    PHASE_NONE = 0,
    PHASE_READY = 1,       // 未开局
    PHASE_PLACING = 1 << 1,     // 开局（摆棋）
    PHASE_MOVING = 1 << 2,      // 中局（走棋）
    PHASE_GAMEOVER = 1 << 3,    // 结局
    PHASE_PLAYING = PHASE_PLACING | PHASE_MOVING,  // 进行中
    PHASE_NOTPLAYING = PHASE_READY | PHASE_GAMEOVER,  // 不在进行中
};

enum value_t : int16_t
{
    VALUE_ZERO = 0,
    VALUE_DRAW = 0,
    VALUE_STRONG = 400,
    VALUE_WIN = 10000,
    VALUE_INFINITE = 32001,
    VALUE_UNKNOWN = INT16_MIN,

    VALUE_EACH_PIECE_INHAND = 50,
    VALUE_EACH_PIECE_ONBOARD = 100,
    VALUE_EACH_PIECE_PLACING_NEEDREMOVE = 100,
    VALUE_EACH_PIECE_MOVING_NEEDREMOVE = 128,

    VALUE_IDS_WINDOW = 301, // IDS 前面的迭代至少要达到301,才不改变自对弈棋谱 TODO: 原因待查
    VALUE_PLACING_WINDOW = VALUE_EACH_PIECE_PLACING_NEEDREMOVE + (VALUE_EACH_PIECE_ONBOARD - VALUE_EACH_PIECE_INHAND) + 1,
    VALUE_MOVING_WINDOW = VALUE_EACH_PIECE_MOVING_NEEDREMOVE + 1
};

// 棋盘点上棋子的类型
enum piecetype_t : uint16_t
{
    PIECETYPE_EMPTY = 0,   // 没有棋子
    PIECETYPE_PLAYER_BLACK = 1,    // 先手的子
    PIECETYPE_PLAYER_WHITE = 2,     // 后手的子
    PIECETYPE_FORBIDDEN = 3,    // 禁点
    PIECETYPE_COUNT = 4
};

/*
0x00 代表无棋子
0x0F 代表禁点
0x11～0x1C 代表先手第 1～12 子
0x21～0x2C 代表后手第 1～12 子
*/
enum piece_t
{
    NO_PIECE = 0x00,
    PIECE_FORBIDDEN = 0x0F,

    PIECE_BLACK = 0x10,
    PIECE_B1 = 0x11,
    PIECE_B2 = 0x12,
    PIECE_B3 = 0x13,
    PIECE_B4 = 0x14,
    PIECE_B5 = 0x15,
    PIECE_B6 = 0x16,
    PIECE_B7 = 0x17,
    PIECE_B8 = 0x18,
    PIECE_B9 = 0x19,
    PIECE_B10 = 0x1A,
    PIECE_B11 = 0x1B,
    PIECE_B12 = 0x1C,

    PIECE_WHITE = 0x20,
    PIECE_W1 = 0x21,
    PIECE_W2 = 0x22,
    PIECE_W3 = 0x23,
    PIECE_W4 = 0x24,
    PIECE_W5 = 0x25,
    PIECE_W6 = 0x26,
    PIECE_W7 = 0x27,
    PIECE_W8 = 0x28,
    PIECE_W9 = 0x29,
    PIECE_W10 = 0x2A,
    PIECE_W11 = 0x2B,
    PIECE_W12 = 0x2C,
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
ENABLE_INCR_OPERATORS_ON(piecetype_t)
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

constexpr color_t operator~(color_t color)
{
    return (color == BLACK? WHITE : BLACK);   // Toggle color
}

#endif /* TYPES_H */
