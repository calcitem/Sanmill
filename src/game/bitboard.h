/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2020 Calcitem <calcitem@outlook.com>

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

#ifndef BITBOARD_H
#define BITBOARD_H

#include <string>

#include "types.h"

namespace Bitbases
{

void init();
bool probe(square_t wksq, square_t wpsq, square_t bksq, color_t us);

}

namespace Bitboards
{

void init();
const std::string pretty(bitboard_t b);

}

constexpr bitboard_t AllSquares = ~bitboard_t(0);
//constexpr bitboard_t starSquares12 = 0xAA55AA55AA55AA55UL; // TODO

constexpr bitboard_t FileABB = 0xE0000000;
constexpr bitboard_t FileBBB = 0x00E00000;
constexpr bitboard_t FileCBB = 0x0000E000;
constexpr bitboard_t FileDBB = 0x11111100;
constexpr bitboard_t FileEBB = 0x00000E00;
constexpr bitboard_t FileFBB = 0x000E0000;
constexpr bitboard_t FileGBB = 0x0E000000;

constexpr bitboard_t Rank1BB = 0x38000000;
constexpr bitboard_t Rank2BB = 0x00380000;
constexpr bitboard_t Rank3BB = 0x00003800;
constexpr bitboard_t Rank4BB = 0x44444400;
constexpr bitboard_t Rank5BB = 0x00008300;
constexpr bitboard_t Rank6BB = 0x00830000;
constexpr bitboard_t Rank7BB = 0x83000000;

constexpr bitboard_t Ring1 = 0xFF00;
constexpr bitboard_t Ring2 = Ring1 << (8 * 1);
constexpr bitboard_t Ring3 = Ring1 << (8 * 2);

constexpr bitboard_t Seat1 = 0x01010100;
constexpr bitboard_t Seat2 = Seat1 << 1;
constexpr bitboard_t Seat3 = Seat1 << 2;
constexpr bitboard_t Seat4 = Seat1 << 3;
constexpr bitboard_t Seat5 = Seat1 << 4;
constexpr bitboard_t Seat6 = Seat1 << 5;
constexpr bitboard_t Seat7 = Seat1 << 6;
constexpr bitboard_t Seat8 = Seat1 << 7;

extern uint8_t PopCnt16[1 << 16];
extern uint8_t SquareDistance[SQUARE_COUNT][SQUARE_COUNT];

extern bitboard_t SquareBB[SQUARE_COUNT];
extern bitboard_t LineBB[SQUARE_COUNT][SQUARE_COUNT];

inline bitboard_t square_bb(square_t s)
{
    assert(SQ_8_R1S1_D5 <= s && s <= SQ_31_R3S8_A7);
    return SquareBB[s];
}

/// Overloads of bitwise operators between a bitboard_t and a square_t for testing
/// whether a given bit is set in a bitboard, and for setting and clearing bits.

inline bitboard_t  operator&(bitboard_t  b, square_t s)
{
    return b & square_bb(s);
}
inline bitboard_t  operator|(bitboard_t  b, square_t s)
{
    return b | square_bb(s);
}
inline bitboard_t  operator^(bitboard_t  b, square_t s)
{
    return b ^ square_bb(s);
}
inline bitboard_t &operator|=(bitboard_t &b, square_t s)
{
    return b |= square_bb(s);
}
inline bitboard_t &operator^=(bitboard_t &b, square_t s)
{
    return b ^= square_bb(s);
}

constexpr bool more_than_one(bitboard_t b)
{
    return b & (b - 1);
}

# if 0
/// rank_bb() and file_bb() return a bitboard representing all the squares on
/// the given file or rank.

inline bitboard_t rank_bb(rank_t r)
{
    return Rank1BB << (8 * r);
}

inline bitboard_t rank_bb(square_t s)
{
    return rank_bb(rank_of(s));
}

inline bitboard_t file_bb(File f)
{
    return FileABB << f;
}

inline bitboard_t file_bb(square_t s)
{
    return file_bb(file_of(s));
}
#endif

inline bitboard_t ring_bb(ring_t r)
{
    return Ring1 << (8 * (r - 1));
}

inline bitboard_t seat_bb(seat_t s)
{
    return Seat1 << (s - 1);
}

#if 0
/// shift() moves a bitboard one step along direction D

template<direction_t D>
constexpr bitboard_t shift(bitboard_t b)
{
    return  D == NORTH ? b << 8 : D == SOUTH ? b >> 8
        : D == NORTH + NORTH ? b << 16 : D == SOUTH + SOUTH ? b >> 16
        : D == EAST ? (b & ~FileHBB) << 1 : D == WEST ? (b & ~FileABB) >> 1
        : D == NORTH_EAST ? (b & ~FileHBB) << 9 : D == NORTH_WEST ? (b & ~FileABB) << 7
        : D == SOUTH_EAST ? (b & ~FileHBB) >> 7 : D == SOUTH_WEST ? (b & ~FileABB) >> 9
        : 0;
}


/// adjacent_files_bb() returns a bitboard representing all the squares on the
/// adjacent files of the given one.

inline bitboard_t adjacent_files_bb(square_t s)
{
    return shift<EAST>(file_bb(s)) | shift<WEST>(file_bb(s));
}


/// between_bb() returns squares that are linearly between the given squares
/// If the given squares are not on a same file/rank/diagonal, return 0.

inline bitboard_t between_bb(square_t s1, square_t s2)
{
    return LineBB[s1][s2] & ((AllSquares << (s1 + (s1 < s2)))
                             ^ (AllSquares << (s2 + !(s1 < s2))));
}


/// forward_ranks_bb() returns a bitboard representing the squares on the ranks
/// in front of the given one, from the point of view of the given color. For instance,
/// forward_ranks_bb(BLACK, SQ_12_R1S5_D3) will return the 16 squares on ranks 1 and 2.

inline bitboard_t forward_ranks_bb(color_t c, square_t s)
{
    return c == WHITE ? ~Rank1BB << 8 * (rank_of(s) - RANK_1)
        : ~Rank8BB >> 8 * (RANK_8 - rank_of(s));
}


/// forward_file_bb() returns a bitboard representing all the squares along the
/// line in front of the given one, from the point of view of the given color.

inline bitboard_t forward_file_bb(color_t c, square_t s)
{
    return forward_ranks_bb(c, s) & file_bb(s);
}


/// aligned() returns true if the squares s1, s2 and s3 are aligned either on a
/// straight or on a diagonal line.

inline bool aligned(square_t s1, square_t s2, square_t s3)
{
    return LineBB[s1][s2] & s3;
}


/// distance() functions return the distance between x and y, defined as the
/// number of steps for a king in x to reach y.

template<typename T1 = square_t> inline int distance(square_t x, square_t y);
template<> inline int distance<file_t>(square_t x, square_t y)
{
    return std::abs(file_of(x) - file_of(y));
}
template<> inline int distance<rank_t>(square_t x, square_t y)
{
    return std::abs(rank_of(x) - rank_of(y));
}
template<> inline int distance<square_t>(square_t x, square_t y)
{
    return SquareDistance[x][y];
}

template<class T> constexpr const T &clamp(const T &v, const T &lo, const T &hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}
#endif

/// popcount() counts the number of non-zero bits in a bitboard

inline int popcount(bitboard_t b)
{

#ifndef USE_POPCNT

    union
    {
        bitboard_t bb; uint16_t u[4];
    } v = { b };
    return PopCnt16[v.u[0]] + PopCnt16[v.u[1]] + PopCnt16[v.u[2]] + PopCnt16[v.u[3]];

#elif defined(_MSC_VER) || defined(__INTEL_COMPILER)

    return (int)_mm_popcnt_u64(b);

#else // Assumed gcc or compatible compiler

    return __builtin_popcountll(b);

#endif
}


/// lsb() and msb() return the least/most significant bit in a non-zero bitboard

#if defined(__GNUC__)  // GCC, Clang, ICC

inline square_t lsb(bitboard_t b)
{
    assert(b);
    return square_t(__builtin_ctzll(b));
}

inline square_t msb(bitboard_t b)
{
    assert(b);
    return square_t(63 ^ __builtin_clzll(b));
}

#elif defined(_MSC_VER)  // MSVC

#ifdef _WIN64  // MSVC, WIN64

inline square_t lsb(bitboard_t b)
{
    assert(b);
    unsigned long idx;
    _BitScanForward64(&idx, b);
    return (square_t)idx;
}

inline square_t msb(bitboard_t b)
{
    assert(b);
    unsigned long idx;
    _BitScanReverse64(&idx, b);
    return (square_t)idx;
}

#else  // MSVC, WIN32

inline square_t lsb(bitboard_t b)
{
    assert(b);
    unsigned long idx;

    if (b & 0xffffffff) {
        _BitScanForward(&idx, int32_t(b));
        return square_t(idx);
    } else {
        _BitScanForward(&idx, int32_t(b >> 32));
        return square_t(idx + 32);
    }
}

inline square_t msb(bitboard_t b)
{
    assert(b);
    unsigned long idx;

    if (b >> 32) {
        _BitScanReverse(&idx, int32_t(b >> 32));
        return square_t(idx + 32);
    } else {
        _BitScanReverse(&idx, int32_t(b));
        return square_t(idx);
    }
}

#endif

#else  // Compiler is neither GCC nor MSVC compatible

#error "Compiler not supported."

#endif


/// pop_lsb() finds and clears the least significant bit in a non-zero bitboard

inline square_t pop_lsb(bitboard_t *b)
{
    const square_t s = lsb(*b);
    *b &= *b - 1;
    return s;
}


/// frontmost_sq() returns the most advanced square for the given color
inline square_t frontmost_sq(color_t c, bitboard_t b)
{
    return c == WHITE ? msb(b) : lsb(b);
}

#endif // BITBOARD_H
