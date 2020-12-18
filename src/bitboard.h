/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

#ifndef BITBOARD_H_INCLUDED
#define BITBOARD_H_INCLUDED

#include <string>

#include "types.h"

namespace Bitboards
{

void init();
const std::string pretty(Bitboard b);

}

constexpr Bitboard AllSquares = ~Bitboard(0);
//constexpr Bitboard starSquares12 = 0xAA55AA55AA55AA55UL; // TODO

constexpr Bitboard FileABB = 0x0000FF00;
constexpr Bitboard FileBBB = FileABB << (8 * 1);
constexpr Bitboard FileCBB = FileABB << (8 * 2);

constexpr Bitboard Rank1BB = 0x01010100;
constexpr Bitboard Rank2BB = Rank1BB << 1;
constexpr Bitboard Rank3BB = Rank1BB << 2;
constexpr Bitboard Rank4BB = Rank1BB << 3;
constexpr Bitboard Rank5BB = Rank1BB << 4;
constexpr Bitboard Rank6BB = Rank1BB << 5;
constexpr Bitboard Rank7BB = Rank1BB << 6;
constexpr Bitboard Rank8BB = Rank1BB << 7;

extern uint8_t PopCnt16[1 << 16];
extern uint8_t SquareDistance[SQ_32][SQ_32];

extern Bitboard SquareBB[SQ_32];
extern Bitboard LineBB[EFFECTIVE_SQUARE_NB][SQ_32];

// TODO
const Bitboard Star9 = SquareBB[17] | SquareBB[19] | SquareBB[21] | SquareBB[23];
const Bitboard Star12 = SquareBB[16] | SquareBB[18] | SquareBB[20] | SquareBB[22];

inline Bitboard square_bb(Square s)
{
    assert(SQ_BEGIN <= s && s < SQ_END);
    return SquareBB[s];
}


/// Overloads of bitwise operators between a Bitboard and a Square for testing
/// whether a given bit is set in a bitboard, and for setting and clearing bits.

inline Bitboard  operator&(Bitboard  b, Square s)
{
    return b & square_bb(s);
}

inline Bitboard  operator|(Bitboard  b, Square s)
{
    return b | square_bb(s);
}

inline Bitboard  operator^(Bitboard  b, Square s)
{
    return b ^ square_bb(s);
}

inline Bitboard &operator|=(Bitboard &b, Square s)
{
    return b |= square_bb(s);
}

inline Bitboard &operator^=(Bitboard &b, Square s)
{
    return b ^= square_bb(s);
}

inline Bitboard  operator&(Square s, Bitboard b)
{
    return b & s;
}

inline Bitboard  operator|(Square s, Bitboard b)
{
    return b | s;
}

inline Bitboard  operator^(Square s, Bitboard b)
{
    return b ^ s;
}

inline Bitboard  operator|(Square s1, Square s2)
{
    return square_bb(s1) | s2;
}

constexpr bool more_than_one(Bitboard b)
{
    return b & (b - 1);
}


/// rank_bb() and file_bb() return a bitboard representing all the squares on
/// the given file or rank.

inline Bitboard rank_bb(Rank r)
{
    return Rank1BB << (r - 1);
}

inline Bitboard rank_bb(Square s)
{
    return rank_bb(rank_of(s));
}

inline Bitboard file_bb(File f)
{
    return FileABB << (f - 1);
}

inline Bitboard file_bb(Square s)
{
    return file_bb(file_of(s));
}

/// distance() functions return the distance between x and y, defined as the
/// number of steps for a king in x to reach y.

template<typename T1 = Square> inline int distance(Square x, Square y);

template<> inline int distance<File>(Square x, Square y)
{
    return std::abs(file_of(x) - file_of(y));
}

template<> inline int distance<Rank>(Square x, Square y)
{
    return std::abs(rank_of(x) - rank_of(y));
}

template<> inline int distance<Square>(Square x, Square y)
{
    return SquareDistance[x][y];
}

inline int edge_distance(File f)
{
    return std::min(f, File(FILE_C - f));
}

inline int edge_distance(Rank r)
{
    return std::min(r, Rank(RANK_8 - r));
}

/// popcount() counts the number of non-zero bits in a bitboard

inline int popcount(Bitboard b)
{
#ifndef USE_POPCNT

    union
    {
        Bitboard bb; uint16_t u[2];
    } v = { b };

    return PopCnt16[v.u[0]] + PopCnt16[v.u[1]];

#elif defined(_MSC_VER) || defined(__INTEL_COMPILER)

    return (int)_mm_popcnt_u32(b);

#else // Assumed gcc or compatible compiler

    return __builtin_popcount(b);

#endif
}


/// lsb() and msb() return the least/most significant bit in a non-zero bitboard

#if defined(__GNUC__)  // GCC, Clang, ICC

inline Square lsb(Bitboard b)
{
    assert(b);
    return Square(__builtin_ctz(b));
}

inline Square msb(Bitboard b)
{
    assert(b);
    return Square(31 ^ __builtin_clz(b));
}

#elif defined(_MSC_VER)  // MSVC

#ifdef _WIN64  // MSVC, WIN64

inline Square lsb(Bitboard b)
{
    assert(b);
    unsigned long idx;
    _BitScanForward(&idx, b);
    return (Square)idx;
}

inline Square msb(Bitboard b)
{
    assert(b);
    unsigned long idx;
    _BitScanReverse(&idx, b);
    return (Square)idx;
}

#else  // MSVC, WIN32

inline Square lsb(Bitboard b)
{
    assert(b);
    unsigned long idx;

    if (b & 0xffffffff) {
        _BitScanForward(&idx, int32_t(b));
        return Square(idx);
    } else {
        _BitScanForward(&idx, int32_t(b >> 32));
        return Square(idx + 32);
    }
}

inline Square msb(Bitboard b)
{
    assert(b);
    unsigned long idx;

    if (b >> 32) {
        _BitScanReverse(&idx, int32_t(b >> 32));
        return Square(idx + 32);
    } else {
        _BitScanReverse(&idx, int32_t(b));
        return Square(idx);
    }
}

#endif

#else  // Compiler is neither GCC nor MSVC compatible

#error "Compiler not supported."

#endif


/// pop_lsb() finds and clears the least significant bit in a non-zero bitboard

inline Square pop_lsb(Bitboard *b)
{
    const Square s = lsb(*b);
    *b &= *b - 1;
    return s;
}


/// frontmost_sq() returns the most advanced square for the given color,
/// requires a non-zero bitboard.
inline Square frontmost_sq(Color c, Bitboard b)
{
    return c == WHITE ? msb(b) : lsb(b);
}

#endif // #ifndef BITBOARD_H_INCLUDED
