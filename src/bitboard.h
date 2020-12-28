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

#define	SET_BIT(x, bit)     (x |= (1 << bit))	
#define	CLEAR_BIT(x, bit)   (x &= ~(1 << bit))

namespace Bitboards
{

void init();
const std::string pretty(Bitboard b);

}

constexpr Bitboard AllSquares = ~Bitboard(0);

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

extern Bitboard SquareBB[SQ_32];

extern Bitboard StarSquareBB9;
extern Bitboard StarSquareBB12;

inline Bitboard square_bb(Square s)
{
    assert(SQ_BEGIN <= s && s < SQ_END);
    return SquareBB[s];
}

inline Bitboard star_square_bb_9()
{
    return StarSquareBB9;
}

inline Bitboard star_square_bb_12()
{
    return StarSquareBB12;
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

inline Bitboard operator&(Square s, Bitboard b)
{
    return b & s;
}

inline Bitboard operator|(Square s, Bitboard b)
{
    return b | s;
}

inline Bitboard operator^(Square s, Bitboard b)
{
    return b ^ s;
}

inline Bitboard operator|(Square s1, Square s2)
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

/// popcount() counts the number of non-zero bits in a bitboard

inline int popcount(Bitboard b)
{
#ifdef DONOT_USE_POPCNT

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

#endif // #ifndef BITBOARD_H_INCLUDED
