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

#define S2(a, b)        (square_bb(SQ_##a) | square_bb(SQ_##b))
#define S3(a, b, c)     (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c))
#define S4(a, b, c, d)  (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c) | square_bb(SQ_##d))
#define S4(a, b, c, d)  (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c) | square_bb(SQ_##d))

namespace Bitboards
{

void init();

}

constexpr Bitboard AllSquares = ~Bitboard(0);

extern Bitboard SquareBB[SQ_32];

extern Bitboard StarSquareBB9;
extern Bitboard StarSquareBB12;

inline Bitboard square_bb(Square s) noexcept
{
    if (!(SQ_BEGIN <= s && s < SQ_END))
        return 0;

    return SquareBB[s];
}


/// Overloads of bitwise operators between a Bitboard and a Square for testing
/// whether a given bit is set in a bitboard, and for setting and clearing bits.

inline Bitboard operator&(Bitboard  b, Square s) noexcept
{
    return b & square_bb(s);
}

inline Bitboard operator|(Bitboard  b, Square s) noexcept
{
    return b | square_bb(s);
}

inline Bitboard operator^(Bitboard  b, Square s) noexcept
{
    return b ^ square_bb(s);
}

inline Bitboard &operator|=(Bitboard &b, Square s) noexcept
{
    return b |= square_bb(s);
}

inline Bitboard &operator^=(Bitboard &b, Square s) noexcept
{
    return b ^= square_bb(s);
}

inline Bitboard operator&(Square s, Bitboard b) noexcept
{
    return b & s;
}

inline Bitboard operator|(Square s, Bitboard b) noexcept
{
    return b | s;
}

inline Bitboard operator^(Square s, Bitboard b) noexcept
{
    return b ^ s;
}

inline Bitboard operator|(Square s1, Square s2) noexcept
{
    return square_bb(s1) | s2;
}

#endif // #ifndef BITBOARD_H_INCLUDED
