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
bool probe(Square wksq, Square wpsq, Square bksq, Color us);

}

namespace Bitboards
{

void init();
const std::string pretty(Bitboard b);

}

constexpr Bitboard AllSquares = ~Bitboard(0);
//constexpr Bitboard starSquares12 = 0xAA55AA55AA55AA55UL; // TODO

constexpr Bitboard FileABB = 0xE0000000;
constexpr Bitboard FileBBB = 0x00E00000;
constexpr Bitboard FileCBB = 0x0000E000;
constexpr Bitboard FileDBB = 0x11111100;
constexpr Bitboard FileEBB = 0x00000E00;
constexpr Bitboard FileFBB = 0x000E0000;
constexpr Bitboard FileGBB = 0x0E000000;

constexpr Bitboard Rank1BB = 0x38000000;
constexpr Bitboard Rank2BB = 0x00380000;
constexpr Bitboard Rank3BB = 0x00003800;
constexpr Bitboard Rank4BB = 0x44444400;
constexpr Bitboard Rank5BB = 0x00008300;
constexpr Bitboard Rank6BB = 0x00830000;
constexpr Bitboard Rank7BB = 0x83000000;

constexpr Bitboard Ring1 = 0xFF00;
constexpr Bitboard Ring2 = Ring1 << (8 * 1);
constexpr Bitboard Ring3 = Ring1 << (8 * 2);

constexpr Bitboard Seat1 = 0x01010100;
constexpr Bitboard Seat2 = Seat1 << 1;
constexpr Bitboard Seat3 = Seat1 << 2;
constexpr Bitboard Seat4 = Seat1 << 3;
constexpr Bitboard Seat5 = Seat1 << 4;
constexpr Bitboard Seat6 = Seat1 << 5;
constexpr Bitboard Seat7 = Seat1 << 6;
constexpr Bitboard Seat8 = Seat1 << 7;

extern uint8_t PopCnt16[1 << 16];
extern uint8_t SquareDistance[SQ_32][SQ_32];

extern Bitboard SquareBB[SQ_32];
extern Bitboard LineBB[SQUARE_COUNT][SQ_32];

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

constexpr bool more_than_one(Bitboard b)
{
    return b & (b - 1);
}

# if 0
/// rank_bb() and file_bb() return a bitboard representing all the squares on
/// the given file or rank.

inline Bitboard rank_bb(Rank r)
{
    return Rank1BB << (8 * r);
}

inline Bitboard rank_bb(Square s)
{
    return rank_bb(rank_of(s));
}

inline Bitboard file_bb(File f)
{
    return FileABB << f;
}

inline Bitboard file_bb(Square s)
{
    return file_bb(file_of(s));
}
#endif

inline Bitboard ring_bb(File r)
{
    return Ring1 << (8 * (r - 1));
}

inline Bitboard seat_bb(Rank s)
{
    return Seat1 << (s - 1);
}

#if 0
/// shift() moves a bitboard one step along direction D

template<MoveDirection D>
constexpr Bitboard shift(Bitboard b)
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

inline Bitboard adjacent_files_bb(Square s)
{
    return shift<EAST>(file_bb(s)) | shift<WEST>(file_bb(s));
}


/// between_bb() returns squares that are linearly between the given squares
/// If the given squares are not on a same file/rank/diagonal, return 0.

inline Bitboard between_bb(Square s1, Square s2)
{
    return LineBB[s1][s2] & ((AllSquares << (s1 + (s1 < s2)))
                             ^ (AllSquares << (s2 + !(s1 < s2))));
}


/// forward_ranks_bb() returns a bitboard representing the squares on the ranks
/// in front of the given one, from the point of view of the given color. For instance,
/// forward_ranks_bb(BLACK, SQ_12_R1S5_D3) will return the 16 squares on ranks 1 and 2.

inline Bitboard forward_ranks_bb(Color c, Square s)
{
    return c == WHITE ? ~Rank1BB << 8 * (rank_of(s) - RANK_1)
        : ~Rank8BB >> 8 * (RANK_8 - rank_of(s));
}


/// forward_file_bb() returns a bitboard representing all the squares along the
/// line in front of the given one, from the point of view of the given color.

inline Bitboard forward_file_bb(Color c, Square s)
{
    return forward_ranks_bb(c, s) & file_bb(s);
}


/// aligned() returns true if the squares s1, s2 and s3 are aligned either on a
/// straight or on a diagonal line.

inline bool aligned(Square s1, Square s2, Square s3)
{
    return LineBB[s1][s2] & s3;
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

template<class T> constexpr const T &clamp(const T &v, const T &lo, const T &hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}
#endif

/// popcount() counts the number of non-zero bits in a bitboard

inline int popcount(Bitboard b)
{

#ifndef USE_POPCNT

    union
    {
        Bitboard bb; uint16_t u[4];
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

inline Square lsb(Bitboard b)
{
    assert(b);
    return Square(__builtin_ctzll(b));
}

inline Square msb(Bitboard b)
{
    assert(b);
    return Square(63 ^ __builtin_clzll(b));
}

#elif defined(_MSC_VER)  // MSVC

#ifdef _WIN64  // MSVC, WIN64

inline Square lsb(Bitboard b)
{
    assert(b);
    unsigned long idx;
    _BitScanForward64(&idx, b);
    return (Square)idx;
}

inline Square msb(Bitboard b)
{
    assert(b);
    unsigned long idx;
    _BitScanReverse64(&idx, b);
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


/// frontmost_sq() returns the most advanced square for the given color
inline Square frontmost_sq(Color c, Bitboard b)
{
    return c == WHITE ? msb(b) : lsb(b);
}

#endif // BITBOARD_H
