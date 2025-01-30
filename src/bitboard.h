// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// bitboard.h

#ifndef BITBOARD_H_INCLUDED
#define BITBOARD_H_INCLUDED

#include <string>

#include "types.h"

#define SET_BIT(x, bit) ((x) |= (1 << (bit)))
#define CLEAR_BIT(x, bit) ((x) &= ~(1 << (bit)))

#define S2(a, b) (square_bb(SQ_##a) | square_bb(SQ_##b))
#define S3(a, b, c) (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c))
#define S4(a, b, c, d) \
    (square_bb(SQ_##a) | square_bb(SQ_##b) | square_bb(SQ_##c) | \
     square_bb(SQ_##d))

namespace Bitboards {

void init();
std::string pretty(Bitboard b);

} // namespace Bitboards

constexpr Bitboard AllSquares = ~static_cast<Bitboard>(0);

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

inline Bitboard square_bb(Square s) noexcept
{
    if (!(SQ_BEGIN <= s && s < SQ_END)) {
        return 0;
    }

    return SquareBB[s];
}

/// Overloads of bitwise operators between a Bitboard and a Square for testing
/// whether a given bit is set in a bitboard, and for setting and clearing bits.

inline Bitboard operator&(Bitboard b, Square s) noexcept
{
    return b & square_bb(s);
}

inline Bitboard operator|(Bitboard b, Square s) noexcept
{
    return b | square_bb(s);
}

inline Bitboard operator^(Bitboard b, Square s) noexcept
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

constexpr bool more_than_one(Bitboard b)
{
    return b & (b - 1);
}

/// rank_bb() and file_bb() return a bitboard representing all the squares on
/// the given file or rank.

constexpr Bitboard rank_bb(Rank r) noexcept
{
    return Rank1BB << (r - 1);
}

constexpr Bitboard rank_bb(Square s)
{
    return rank_bb(rank_of(s));
}

constexpr Bitboard file_bb(File f) noexcept
{
    return FileABB << (f - 1);
}

constexpr Bitboard file_bb(Square s)
{
    return file_bb(file_of(s));
}

/// popcount() counts the number of non-zero bits in a bitboard

inline int generic_popcount(Bitboard b) noexcept
{
    union {
        Bitboard bb;
        uint16_t u[2];
    } v = {b};
    return PopCnt16[v.u[0]] + PopCnt16[v.u[1]];
}

inline int popcount(Bitboard b) noexcept
{
#ifdef DO_NOT_USE_POPCNT

    return generic_popcount(b);

#elif defined(_MSC_VER) || defined(__INTEL_COMPILER)

#if defined(_M_X64) || defined(_M_IX86)
    return _mm_popcnt_u32(b);
#else
    return generic_popcount(b);
#endif

#else // Assumed gcc or compatible compiler

    return __builtin_popcount(b);

#endif
}

#endif // #ifndef BITBOARD_H_INCLUDED
