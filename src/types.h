// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef TYPES_H_INCLUDED
#define TYPES_H_INCLUDED

#include "config.h"

/// When compiling with provided Makefile (e.g. for Linux and OSX),
/// configuration is done automatically. To get started type 'make help'.
///
/// When Makefile is not used (e.g. with Microsoft Visual Studio) some switches
/// need to be set manually:
///
/// -DNDEBUG      | Disable debugging mode. Always use this for release.
///
/// -DNO_PREFETCH | Disable use of prefetch asm-instruction. You may need this
/// to
///               | run on some very old machines.
///
/// -DUSE_POPCNT  | Add runtime support for use of popcnt asm-instruction. Works
///               | only in 64-bit mode and requires hardware with popcnt
///               support.
///
/// -DUSE_PEXT    | Add runtime support for use of pext asm-instruction. Works
///               | only in 64-bit mode and requires hardware with pext support.

#include <algorithm>
#include <cassert>
#include <cctype>
#include <climits>
#include <cstdint>
#include <cstdlib>

#if defined(_MSC_VER)
// Disable some silly and noisy warning from MSVC compiler
#pragma warning(disable : 4127) // Conditional expression is constant
#pragma warning(disable : 4146) // Unary minus operator applied to unsigned type
#pragma warning(disable : 4800) // Forcing value to bool 'true' or 'false'
#endif

/// Predefined macros hell:
///
/// __GNUC__           Compiler is gcc, Clang or Intel on Linux
/// __INTEL_COMPILER   Compiler is Intel
/// _MSC_VER           Compiler is MSVC or Intel on Windows
/// _WIN32             Building on Windows (any)
/// _WIN64             Building on Windows 64 bit

#if defined(__GNUC__)                                                          \
    && (__GNUC__ < 9 || (__GNUC__ == 9 && __GNUC_MINOR__ <= 2))                \
    && defined(_WIN32) && !defined(__clang__)
#define ALIGNAS_ON_STACK_VARIABLES_BROKEN
#endif

#define ASSERT_ALIGNED(ptr, alignment)                                         \
    assert(reinterpret_cast<uintptr_t>(ptr) % alignment == 0)

#if defined(_WIN64) && defined(_MSC_VER) // No Makefile used
#include <intrin.h> // Microsoft header for _BitScanForward64()
#define IS_64BIT
#endif

#if defined(USE_POPCNT) && (defined(__INTEL_COMPILER) || defined(_MSC_VER))
#include <nmmintrin.h> // Intel and Microsoft header for _mm_popcnt_u64()
#endif

#if !defined(NO_PREFETCH) && (defined(__INTEL_COMPILER) || defined(_MSC_VER))
#include <xmmintrin.h> // Intel and Microsoft header for _mm_prefetch()
#endif

#if defined(USE_PEXT)
#include <immintrin.h> // Header for _pext_u64() intrinsic
#define pext(b, m) _pext_u64(b, m)
#else
#define pext(b, m) 0
#endif

#ifdef USE_POPCNT
constexpr bool HasPopCnt = true;
#else
constexpr bool HasPopCnt = false;
#endif

#ifdef USE_PEXT
constexpr bool HasPext = true;
#else
constexpr bool HasPext = false;
#endif

#ifdef IS_64BIT
constexpr bool Is64Bit = true;
#else
constexpr bool Is64Bit = false;
#endif

#ifdef TRANSPOSITION_TABLE_64BIT_KEY
typedef uint64_t Key;
#else
typedef uint32_t Key;
#endif /* TRANSPOSITION_TABLE_64BIT_KEY */

typedef uint32_t Bitboard;

constexpr int MAX_MOVES = 72; // (24 - 4 - 3) * 4 = 68
constexpr int MAX_PLY = 48;

enum Move : int32_t { MOVE_NONE, MOVE_NULL = 65 };

enum MoveType { MOVETYPE_PLACE, MOVETYPE_MOVE, MOVETYPE_REMOVE };

enum Color : uint8_t {
    NOCOLOR = 0,
    WHITE = 1,
    BLACK = 2,
    COLOR_NB = 3,
    DRAW = 4,
    NOBODY = 8
};

enum class Phase : uint16_t {
    none,
    ready,
    placing, // Placing men on vacant points
    moving, // Moving men to adjacent points or
    // (optional) Moving men to any vacant point when the player has been
    // reduced to three men
    gameOver
};

// enum class that represents an action that one player can take when it's
// his turn at the board. The can be on of the following:
//   - Select a piece on the board;
//   - Place a piece on the board;
//   - Move a piece on the board:
//       - Slide a piece between two adjacent locations;
//       - 'Jump' a piece to any empty location if the player has less than
//         three or four pieces and mayFly is |true|;
//   - Remove an opponent's piece after successfully closing a mill.
enum class Action : uint16_t { none, select, place, remove };

enum class GameOverReason {
    noReason,

    // A player wins by reducing the opponent to two pieces
    // (where they could no longer form mills and thus be unable to win)
    loseReasonlessThanThree,

    // A player wins by leaving them without a legal move.
    loseReasonNoWay,
    loseReasonBoardIsFull,

    loseReasonResign,
    loseReasonTimeOver,
    drawReasonThreefoldRepetition,
    drawReasonRule50,
    drawReasonEndgameRule50,
    drawReasonBoardIsFull,
};

enum Bound : uint8_t {
    BOUND_NONE,
    BOUND_UPPER,
    BOUND_LOWER,
    BOUND_EXACT = BOUND_UPPER | BOUND_LOWER
};

enum Value : int8_t {
    VALUE_ZERO = 0,
    VALUE_DRAW = 0,
#ifdef ENDGAME_LEARNING
    VALUE_KNOWN_WIN = 25,
#endif
    VALUE_MATE = 80,
    VALUE_UNIQUE = 100,
    VALUE_INFINITE = 125,
    VALUE_UNKNOWN = INT8_MIN,
    VALUE_NONE = VALUE_UNKNOWN,

    VALUE_TB_WIN_IN_MAX_PLY = VALUE_MATE - 2 * MAX_PLY,
    VALUE_TB_LOSS_IN_MAX_PLY = -VALUE_TB_WIN_IN_MAX_PLY,
    VALUE_MATE_IN_MAX_PLY = VALUE_MATE - MAX_PLY,
    VALUE_MATED_IN_MAX_PLY = -VALUE_MATE_IN_MAX_PLY,

    StoneValue = 5,
    VALUE_EACH_PIECE = StoneValue,
    VALUE_EACH_PIECE_INHAND = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_ONBOARD = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_PLACING_NEEDREMOVE = VALUE_EACH_PIECE,
    VALUE_EACH_PIECE_MOVING_NEEDREMOVE = VALUE_EACH_PIECE,

    VALUE_MTDF_WINDOW = VALUE_EACH_PIECE,
    VALUE_PVS_WINDOW = VALUE_EACH_PIECE,

    VALUE_PLACING_WINDOW = VALUE_EACH_PIECE_PLACING_NEEDREMOVE
        + (VALUE_EACH_PIECE_ONBOARD - VALUE_EACH_PIECE_INHAND) + 1,
    VALUE_MOVING_WINDOW = VALUE_EACH_PIECE_MOVING_NEEDREMOVE + 1,
};

enum Rating : int8_t {
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

    RATING_REMOVE_THEIR_ONE_MILL = -RATING_REMOVE_ONE_MILL,
    RATING_REMOVE_THEIR_TWO_MILLS = -RATING_REMOVE_TWO_MILLS,
    RATING_REMOVE_THEIR_THREE_MILLS = -RATING_REMOVE_THREE_MILLS,

    RATING_TT = 100,
    RATING_MAX = INT8_MAX,
};

enum PieceType : uint16_t {
    NO_PIECE_TYPE = 0,
    WHITE_STONE = 1,
    BLACK_STONE = 2,
    BAN = 3,
    ALL_PIECES = 0,
    PIECE_TYPE_NB = 4,

    IN_HAND = 0x10,
    ON_BOARD = 0x20,
};

enum Piece : uint8_t {
    NO_PIECE = 0x00,
    BAN_STONE = 0x0F,

    W_STONE = 0x10,
    W_STONE_1 = 0x11,
    W_STONE_2 = 0x12,
    W_STONE_3 = 0x13,
    W_STONE_4 = 0x14,
    W_STONE_5 = 0x15,
    W_STONE_6 = 0x16,
    W_STONE_7 = 0x17,
    W_STONE_8 = 0x18,
    W_STONE_9 = 0x19,
    W_STONE_10 = 0x1A,
    W_STONE_11 = 0x1B,
    W_STONE_12 = 0x1C,

    B_STONE = 0x20,
    B_STONE_1 = 0x21,
    B_STONE_2 = 0x22,
    B_STONE_3 = 0x23,
    B_STONE_4 = 0x24,
    B_STONE_5 = 0x25,
    B_STONE_6 = 0x26,
    B_STONE_7 = 0x27,
    B_STONE_8 = 0x28,
    B_STONE_9 = 0x29,
    B_STONE_10 = 0x2A,
    B_STONE_11 = 0x2B,
    B_STONE_12 = 0x2C,

    PIECE_NB = 64, // Fix overflow
};

constexpr Value PieceValue = StoneValue;

using Depth = int8_t;

enum : int { DEPTH_NONE = 0, DEPTH_OFFSET = DEPTH_NONE };

enum Square : int {
    SQ_0 = 0,
    SQ_1 = 1,
    SQ_2 = 2,
    SQ_3 = 3,
    SQ_4 = 4,
    SQ_5 = 5,
    SQ_6 = 6,
    SQ_7 = 7,
    SQ_8 = 8,
    SQ_9 = 9,
    SQ_10 = 10,
    SQ_11 = 11,
    SQ_12 = 12,
    SQ_13 = 13,
    SQ_14 = 14,
    SQ_15 = 15,
    SQ_16 = 16,
    SQ_17 = 17,
    SQ_18 = 18,
    SQ_19 = 19,
    SQ_20 = 20,
    SQ_21 = 21,
    SQ_22 = 22,
    SQ_23 = 23,
    SQ_24 = 24,
    SQ_25 = 25,
    SQ_26 = 26,
    SQ_27 = 27,
    SQ_28 = 28,
    SQ_29 = 29,
    SQ_30 = 30,
    SQ_31 = 31,

    SQ_A1 = 8,
    SQ_A2 = 9,
    SQ_A3 = 10,
    SQ_A4 = 11,
    SQ_A5 = 12,
    SQ_A6 = 13,
    SQ_A7 = 14,
    SQ_A8 = 15,
    SQ_B1 = 16,
    SQ_B2 = 17,
    SQ_B3 = 18,
    SQ_B4 = 19,
    SQ_B5 = 20,
    SQ_B6 = 21,
    SQ_B7 = 22,
    SQ_B8 = 23,
    SQ_C1 = 24,
    SQ_C2 = 25,
    SQ_C3 = 26,
    SQ_C4 = 27,
    SQ_C5 = 28,
    SQ_C6 = 29,
    SQ_C7 = 30,
    SQ_C8 = 31,

    SQ_32 = 32,
    SQ_33 = 33,
    SQ_34 = 34,
    SQ_35 = 35,
    SQ_36 = 36,
    SQ_37 = 37,
    SQ_38 = 38,
    SQ_39 = 39,

    SQ_NONE = 0,

    EFFECTIVE_SQUARE_NB = 24, // The board consists of a grid with twenty-four
                              // intersections or points.

    SQUARE_ZERO = 0,
    SQUARE_NB = 40,

    SQ_BEGIN = SQ_8,
    SQ_END = SQ_32
};

enum MoveDirection : int {
    MD_CLOCKWISE = 0,
    MD_BEGIN = MD_CLOCKWISE,
    MD_ANTICLOCKWISE = 1,
    MD_INWARD = 2,
    MD_OUTWARD = 3,
    MD_NB = 4
};

enum LineDirection : int {
    LD_HORIZONTAL = 0,
    LD_VERTICAL = 1,
    LD_SLASH = 2,
    LD_NB = 3
};

enum File : int { FILE_A = 1, FILE_B, FILE_C, FILE_NB = 3 };

enum Rank : int {
    RANK_1 = 1,
    RANK_2,
    RANK_3,
    RANK_4,
    RANK_5,
    RANK_6,
    RANK_7,
    RANK_8,
    RANK_NB = 8
};

#define ENABLE_BASE_OPERATORS_ON(T)                                            \
    constexpr T operator+(T d1, int d2) { return T(int(d1) + d2); }            \
    constexpr T operator-(T d1, int d2) { return T(int(d1) - d2); }            \
    constexpr T operator-(T d) { return T(-int(d)); }                          \
    inline T& operator+=(T& d1, int d2) { return d1 = d1 + d2; }               \
    inline T& operator-=(T& d1, int d2) { return d1 = d1 - d2; }

#define ENABLE_INCR_OPERATORS_ON(T)                                            \
    inline T& operator++(T& d) { return d = T(int(d) + 1); }                   \
    inline T& operator--(T& d) { return d = T(int(d) - 1); }

#define ENABLE_FULL_OPERATORS_ON(T)                                            \
    ENABLE_BASE_OPERATORS_ON(T)                                                \
    constexpr T operator*(int i, T d) noexcept { return T(i * int(d)); }       \
    constexpr T operator*(T d, int i) noexcept { return T(int(d) * i); }       \
    constexpr T operator/(T d, int i) noexcept { return T(int(d) / i); }       \
    constexpr int operator/(T d1, T d2) noexcept { return int(d1) / int(d2); } \
    inline T& operator*=(T& d, int i) noexcept { return d = T(int(d) * i); }   \
    inline T& operator/=(T& d, int i) noexcept { return d = T(int(d) / i); }

ENABLE_FULL_OPERATORS_ON(Value)

ENABLE_INCR_OPERATORS_ON(Piece)
ENABLE_INCR_OPERATORS_ON(PieceType)
ENABLE_INCR_OPERATORS_ON(Square)
ENABLE_INCR_OPERATORS_ON(File)
ENABLE_INCR_OPERATORS_ON(Rank)
ENABLE_INCR_OPERATORS_ON(MoveDirection)

#undef ENABLE_FULL_OPERATORS_ON
#undef ENABLE_INCR_OPERATORS_ON
#undef ENABLE_BASE_OPERATORS_ON

constexpr Color operator~(Color c)
{
    return Color(c ^ 3); // Toggle color
}

constexpr Square make_square(File f, Rank r)
{
    return Square((f << 3) + r - 1);
}

constexpr Piece make_piece(Color c) { return Piece(c << 4); }

constexpr Piece make_piece(Color c, PieceType pt)
{
    if (pt == WHITE_STONE || pt == BLACK_STONE) {
        return make_piece(c);
    }

    if (pt == BAN) {
        return BAN_STONE;
    }

    return NO_PIECE;
}

constexpr Color color_of(Piece pc) { return Color(pc >> 4); }

constexpr PieceType type_of(Piece pc)
{
    if (pc == BAN_STONE) {
        return BAN;
    }

    if (color_of(pc) == WHITE) {
        return WHITE_STONE;
    }

    if (color_of(pc) == BLACK) {
        return BLACK_STONE;
    }

    return NO_PIECE_TYPE;
}

constexpr bool is_ok(Square s)
{
    return s == SQ_NONE || (s >= SQ_BEGIN && s < SQ_END);
}

constexpr File file_of(Square s) { return File(s >> 3); }

constexpr Rank rank_of(Square s) { return Rank((s & 0x07) + 1); }

constexpr Square from_sq(Move m)
{
    if (m < 0)
        m = (Move)-m;

    return static_cast<Square>(m >> 8);
}

constexpr Square to_sq(Move m)
{
    if (m < 0)
        m = (Move)-m;

    return Square(m & 0x00FF);
}

constexpr MoveType type_of(Move m)
{
    if (m < 0) {
        return MOVETYPE_REMOVE;
    } else if (m & 0x1f00) {
        return MOVETYPE_MOVE;
    }

    return MOVETYPE_PLACE; // m & 0x00ff
}

constexpr Move make_move(Square from, Square to)
{
    return Move((from << 8) + to);
}

constexpr Move reverse_move(Move m) { return make_move(to_sq(m), from_sq(m)); }

constexpr bool is_ok(Move m)
{
    return from_sq(m) != to_sq(m); // Catch MOVE_NULL and MOVE_NONE
}

/// Based on a congruential pseudo random number generator
constexpr Key make_key(uint64_t seed)
{
    return Key(seed * 6364136223846793005ULL + 1442695040888963407ULL);
}

#endif // #ifndef TYPES_H_INCLUDED
