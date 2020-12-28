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

#include <algorithm>
#include <bitset>

#include "bitboard.h"
#include "misc.h"

uint8_t PopCnt16[1 << 16];

Bitboard SquareBB[SQ_32];

Bitboard StarSquareBB9;
Bitboard StarSquareBB12;


/// Bitboards::pretty() returns an ASCII representation of a bitboard suitable
/// to be printed to standard output. Useful for debugging.

const std::string Bitboards::pretty(Bitboard b)
{
    std::string str = "+---+---+---+---+---+---+---+---+\n";
    for (File file = FILE_A; file <= FILE_C; ++file) {
        for (Rank rank = RANK_1; rank <= RANK_8; ++rank) {

            str += b & make_square(file, rank) ? "| X " : "|   ";
        }

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

    for (Square s = SQ_BEGIN; s < SQ_END; ++s)
        SquareBB[s] = (1UL << s);

    StarSquareBB9 = square_bb(SQ_16) | square_bb(SQ_18) | square_bb(SQ_20) | square_bb(SQ_22);
    StarSquareBB12 = square_bb(SQ_17) | square_bb(SQ_19) | square_bb(SQ_21) | square_bb(SQ_23);
}
