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

#include <algorithm>
#include <bitset>

#include "bitboard.h"
#include "misc.h"

uint8_t PopCnt16[1 << 16];
uint8_t SquareDistance[SQUARE_COUNT][SQUARE_COUNT];

bitboard_t SquareBB[SQUARE_COUNT];
bitboard_t LineBB[SQUARE_COUNT][SQUARE_COUNT];

/// Bitboards::pretty() returns an ASCII representation of a bitboard suitable
/// to be printed to standard output. Useful for debugging.

// TODO: Pretty
const std::string Bitboards::pretty(bitboard_t b)
{

    std::string str = "+---+---+---+---+---+---+---+---+\n";

    for (seat_t s = SEAT_1; s <= SEAT_8; s = (seat_t)(s + 1)) {
        for (ring_t r = RING_1; r <= RING_3; r = (ring_t)(r + 1))
            str += b & make_square(r, s) ? "| X " : "|   ";

        str += "|\n+---+---+---+---+---+---+---+---+\n";
    }

    return str;
}


/// Bitboards::init() initializes various bitboard tables. It is called at
/// startup and relies on global objects to be already zero-initialized.

void Bitboards::init()
{

    for (unsigned i = 0; i < (1 << 16); ++i)
        PopCnt16[i] = (uint8_t)std::bitset<16>(i).count();

    for (square_t s = SQ_8_R1S1_D5; s <= SQ_31_R3S8_A7; ++s)
        SquareBB[s] = (1UL << s);
}
