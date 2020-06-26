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

#ifndef TYPES_H_INCLUDED
#define TYPES_H_INCLUDED

#include "config.h"

using Step = uint16_t;
using Location = uint8_t;
using Score = uint32_t;
//using Bitboard = uint32_t;
typedef uint32_t Bitboard;

constexpr int MAX_MOVES = 64;

#ifdef TRANSPOSITION_TABLE_CUTDOWN
using Key = uint32_t;
#else
using Key = uint64_t;
#endif /* TRANSPOSITION_TABLE_CUTDOWN */

enum Move : int32_t
{
    MOVE_NONE,
    //MOVE_NULL = 65
};

enum MoveType
{
    MOVETYPE_PLACE,
    MOVETYPE_MOVE,
    MOVETYPE_REMOVE
};

enum Color : uint8_t
{
    NOCOLOR,
    BLACK,
    WHITE,
    COLOR_COUNT
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

enum Phase : uint16_t
{
    PHASE_NONE = 0,
    PHASE_READY = 1,       // 未开局
    PHASE_PLACING = 1 << 1,     // 开局（摆棋）
    PHASE_MOVING = 1 << 2,      // 中局（走棋）
    PHASE_GAMEOVER = 1 << 3,    // 结局
    PHASE_PLAYING = PHASE_PLACING | PHASE_MOVING,  // 进行中
    PHASE_NOTPLAYING = PHASE_READY | PHASE_GAMEOVER,  // 不在进行中
};

// 动作状态标识
enum Action : uint16_t
{
    ACTION_NONE = 0x0000,
    ACTION_SELECT = 0x0100,    // 选子
    ACTION_PLACE = 0x0200,     // 落子
    ACTION_REMOVE = 0x0400    // 提子
};

enum Bound : uint8_t
{
    BOUND_NONE,
    BOUND_UPPER,
    BOUND_LOWER,
    BOUND_EXACT = BOUND_UPPER | BOUND_LOWER
};

enum Value : int8_t
{
    VALUE_ZERO = 0,
    VALUE_DRAW = 0,
    VALUE_KNOWN_WIN = 20,
    VALUE_UNIQUE = 60,
    VALUE_MATE = 80,
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

enum Rating : int8_t
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

enum PieceType : uint16_t
{
    NO_PIECE_TYPE = 0,   // 没有棋子
    BLACK_STONE = 1,    // 先手的子
    WHITE_STONE = 2,     // 后手的子
    BAN = 3,    // 禁点
    ALL_PIECES = 0,    // 禁点
    PIECE_TYPE_NB = 4
};

/*
0x00 代表无棋子
0x0F 代表禁点
0x11～0x1C 代表先手第 1～12 子
0x21～0x2C 代表后手第 1～12 子
*/
enum Piece
{
    NO_PIECE = 0x00,
    BAN_STONE = 0x0F,

    B_STONE = 0x10,
    B_STONE_1 = 0x11,
    B_STONE_2 = 0x12,
    B_STONE_3 = 0x13,
    B_STONE_4 = 0x14,
    B_STONE_5 = 0x15,
    B_STONE_6 = 0x16,
    B_STONE_7 = 0x17,
    B_STONE_8 = 0x18,
    B_STONE_9 = 0x19,
    B_STONE_10 = 0x1A,
    B_STONE_11 = 0x1B,
    B_STONE_12 = 0x1C,

    W_STONE = 0x20,
    W_STONE_1 = 0x21,
    W_STONE_2 = 0x22,
    W_STONE_3 = 0x23,
    W_STONE_4 = 0x24,
    W_STONE_5 = 0x25,
    W_STONE_6 = 0x26,
    W_STONE_7 = 0x27,
    W_STONE_8 = 0x28,
    W_STONE_9 = 0x29,
    W_STONE_10 = 0x2A,
    W_STONE_11 = 0x2B,
    W_STONE_12 = 0x2C,

    PIECE_NB = 24
};

using Depth = int8_t;

enum Square : int32_t
{
     SQ_0 = 0,   SQ_1 = 1,   SQ_2 = 2,   SQ_3 = 3,   SQ_4 = 4,   SQ_5 = 5,   SQ_6 = 6,   SQ_7 = 7,
     SQ_8 = 8,   SQ_9 = 9,  SQ_10 = 10, SQ_11 = 11, SQ_12 = 12, SQ_13 = 13, SQ_14 = 14, SQ_15 = 15,
    SQ_16 = 16, SQ_17 = 17, SQ_18 = 18, SQ_19 = 19, SQ_20 = 20, SQ_21 = 21, SQ_22 = 22, SQ_23 = 23,
    SQ_24 = 24, SQ_25 = 25, SQ_26 = 26, SQ_27 = 27, SQ_28 = 28, SQ_29 = 29, SQ_30 = 30, SQ_31 = 31,

    SQ_A1 =  8, SQ_A2 =  9, SQ_A3 = 10, SQ_A4 = 11, SQ_A5 = 12, SQ_A6 = 13, SQ_A7 = 14, SQ_A8 = 15,
    SQ_B1 = 16, SQ_B2 = 17, SQ_B3 = 18, SQ_B4 = 19, SQ_B5 = 20, SQ_B6 = 21, SQ_B7 = 22, SQ_B8 = 23,
    SQ_C1 = 24, SQ_C2 = 25, SQ_C3 = 26, SQ_C4 = 27, SQ_C5 = 28, SQ_C6 = 29, SQ_C7 = 30, SQ_C8 = 31,

    SQ_32 = 32, SQ_33 = 33, SQ_34 = 34, SQ_35 = 35, SQ_36 = 36, SQ_37 = 37, SQ_38 = 38, SQ_39 = 39,

    SQ_NONE = 0,

    EFFECTIVE_SQUARE_NB = 24,

    SQUARE_NB = 40,

    SQ_BEGIN = SQ_8,
    SQ_END = SQ_32
};

enum MoveDirection
{
    MD_CLOCKWISE = 0,
    MD_BEGIN = MD_CLOCKWISE,
    MD_ANTICLOCKWISE = 1,
    MD_INWARD = 2,
    MD_OUTWARD = 3,
    MD_NB = 4
};

enum LineDirection
{
    LD_HORIZONTAL = 0,
    LD_VERTICAL = 1,
    LD_SLASH = 2,
    LD_NB = 3
};

// 圈
enum File : int
{
    FILE_A = 1, FILE_B, FILE_C, FILE_NB = 3
};

// 位
enum Rank : int
{
    RANK_1, RANK_2, RANK_3, RANK_4, RANK_5, RANK_6, RANK_7, RANK_8, RANK_NB = 8
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

ENABLE_FULL_OPERATORS_ON(Value)
ENABLE_FULL_OPERATORS_ON(Rating)
//ENABLE_FULL_OPERATORS_ON(MoveDirection)

ENABLE_INCR_OPERATORS_ON(PieceType)
ENABLE_INCR_OPERATORS_ON(Square)

// Additional operators to add integers to a Value
constexpr Value operator+(Value v, int i)
{
    return Value(int(v) + i);
}

constexpr Value operator-(Value v, int i)
{
    return Value(int(v) - i);
}

inline Value &operator+=(Value &v, int i)
{
    return v = v + i;
}

inline Value &operator-=(Value &v, int i)
{
    return v = v - i;
}

constexpr Color operator~(Color color)
{
    return Color(color ^ BLACK);   // Toggle color
}

// constexpr Piece operator~(Piece p)
// {
//     return Piece(p ^ 8);   // Swap color of piece
// }


// TODO
constexpr Square make_square(File r, Rank s)
{
    return Square((r << 3) + s - 1);
}

#if 0
constexpr ring_t ring_of(Square s)
{
   // return File(s & 7);
}

constexpr Rank seat_of(Square s)
{
    //return seat(s >> 3);
}
#endif

constexpr Square from_sq(Move m)
{
    return static_cast<Square>(m >> 8);
}

inline const Square to_sq(Move m)
{
    return static_cast<Square>(abs(m) & 0x00ff);
}

inline const MoveType type_of(Move m)
{
    if (m < 0) {
        return MOVETYPE_REMOVE;
    } else if (m & 0x1f00) {
        return MOVETYPE_MOVE;
    }

    return MOVETYPE_PLACE;  // m & 0x00ff
}

constexpr Move make_move(Square from, Square to)
{
    return Move((from << 8) + to);
}

#endif // #ifndef TYPES_H_INCLUDED
