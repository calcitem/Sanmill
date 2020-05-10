/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef TYPES_H
#define TYPES_H

#include "config.h"

using step_t = uint16_t;
using depth_t = int8_t;
using location_t = uint8_t;
using score_t = uint32_t;
//using bitboard_t = uint32_t;
typedef uint32_t bitboard_t;

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

enum movetype_t
{
    MOVETYPE_PLACE,
    MOVETYPE_MOVE,
    MOVETYPE_REMOVE
};

constexpr int MAX_MOVES = 40;

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
     SQ_8_R1S1_D5 = 8,   SQ_9_R1S2_E5 = 9,  SQ_10_R1S3_E4 = 10, SQ_11_R1S4_E3 = 11, SQ_12_R1S5_D3 = 12, SQ_13_R1S6_C3 = 13, SQ_14_R1S7_C4 = 14, SQ_15_R1S8_C5 = 15,
    SQ_16_R2S1_D6 = 16, SQ_17_R2S2_F6 = 17, SQ_18_R2S3_F4 = 18, SQ_19_R2S4_F2 = 19, SQ_20_R2S5_D2 = 20, SQ_21_R2S6_B2 = 21, SQ_22_R2S7_B4 = 22, SQ_23_R2S8_B6 = 23,
    SQ_24_R3S1_D7 = 24, SQ_25_R3S2_G7 = 25, SQ_26_R3S3_G4 = 26, SQ_27_R3S4_G1 = 27, SQ_28_R3S5_D1 = 28, SQ_29_R3S6_A1 = 29, SQ_30_R3S7_A4 = 30, SQ_31_R3S8_A7 = 31,
    SQ_32 = 32, SQ_33 = 33, SQ_34 = 34, SQ_35 = 35, SQ_36 = 36, SQ_37 = 37, SQ_38 = 38, SQ_39 = 39,
    SQUARE_COUNT = 24,
    SQ_EXPANDED_COUNT = 40,
    SQ_BEGIN = SQ_8_R1S1_D5,
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

// 圈
enum ring_t : int
{
    RING_NONE, RING_1, RING_2, RING_3, RING_COUNT = RING_3
};

// 位
enum seat_t : int
{
    SEAT_NONE, SEAT_1, SEAT_2, SEAT_3, SEAT_4, SEAT_5, SEAT_6, SEAT_7, SEAT_8, SEAT_COUNT = SEAT_8
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

enum value_t : int8_t
{
    VALUE_ZERO = 0,
    VALUE_DRAW = 0,
    VALUE_STRONG = 20,
    VALUE_WIN = 80,
    VALUE_INFINITE = 125,
    VALUE_UNKNOWN = std::numeric_limits<int8_t>::min(),

    VALUE_EACH_PIECE = 5,
    VALUE_EACH_PIECE_INHAND = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_ONBOARD = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_PLACING_NEEDREMOVE = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_MOVING_NEEDREMOVE = VALUE_EACH_PIECE,

    VALUE_MTDF_WINDOW = VALUE_EACH_PIECE,
    VALUE_PVS_WINDOW = VALUE_EACH_PIECE,

    VALUE_IDS_WINDOW = 16, // IDS 前面的迭代可能至少要达到16,才不改变自对弈棋谱 TODO: 原因待查, 且前面的 value 调整后需跟着调整
    VALUE_PLACING_WINDOW = VALUE_EACH_PIECE_PLACING_NEEDREMOVE + (VALUE_EACH_PIECE_ONBOARD - VALUE_EACH_PIECE_INHAND) + 1,
    VALUE_MOVING_WINDOW = VALUE_EACH_PIECE_MOVING_NEEDREMOVE + 1
};

enum rating_t : int8_t
{
    RATING_ZERO = 0,
 
    RATING_BLOCK_ONE_MILL = 10,
    RATING_ONE_MILL = 11,

    RATING_STAR_SQUARE = 11,

    RATING_BLOCK_TWO_MILLS = RATING_BLOCK_ONE_MILL * 2,
    RATING_TWO_MILLS = RATING_ONE_MILL * 2,

    RATING_BLOCK_THREE_MILLS = RATING_BLOCK_ONE_MILL * 3,
    RATING_THREE_MILLS = RATING_ONE_MILL * 3,

    RATING_REMOVE_ONE_MILL = RATING_ONE_MILL,
    RATING_REMOVE_TWO_MILLS = RATING_TWO_MILLS,
    RATING_REMOVE_THREE_MILLS = RATING_THREE_MILLS,

    RATING_REMOVE_OPPONENT_ONE_MILL = -RATING_REMOVE_ONE_MILL,
    RATING_REMOVE_OPPONENT_TWO_MILLS = -RATING_REMOVE_TWO_MILLS,
    RATING_REMOVE_OPPONENT_THREE_MILLS = -RATING_REMOVE_THREE_MILLS,

    RATING_TT = 100,
    RATING_MAX = std::numeric_limits<int8_t>::max(),
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
    ACTION_SELECT = 0x0100,    // 选子
    ACTION_PLACE = 0x0200,     // 落子
    ACTION_REMOVE = 0x0400    // 提子
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
ENABLE_FULL_OPERATORS_ON(rating_t)
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
    return color_t(color ^ BLACK);   // Toggle color
}

// constexpr piece_t operator~(piece_t p)
// {
//     return piece_t(p ^ 8);   // Swap color of piece
// }


// TODO
constexpr square_t make_square(ring_t r, seat_t s)
{
    return square_t((r << 3) + s - 1);
}

#if 0
constexpr ring_t ring_of(square_t s)
{
   // return File(s & 7);
}

constexpr seat_t seat_of(square_t s)
{
    //return seat(s >> 3);
}
#endif

constexpr square_t from_sq(move_t m)
{
    return static_cast<square_t>(m >> 8);
}

inline const square_t to_sq(move_t m)
{
    return static_cast<square_t>(abs(m) & 0x00ff);
}

inline const movetype_t type_of(move_t m)
{
    if (m < 0) {
        return MOVETYPE_REMOVE;
    } else if (m & 0x1f00) {
        return MOVETYPE_MOVE;
    }

    return MOVETYPE_PLACE;  // m & 0x00ff
}

constexpr move_t make_move(square_t from, square_t to)
{
    return move_t((from << 8) + to);
}

#endif /* TYPES_H */
