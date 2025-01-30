// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// bitboard.cpp

#include <bitset>

#include "bitboard.h"

uint8_t PopCnt16[1 << 16];

Bitboard SquareBB[SQ_32];

/// Bitboards::pretty() returns an ASCII representation of a bitboard suitable
/// to be printed to standard output. Useful for debugging.

std::string Bitboards::pretty(Bitboard b)
{
    /*
        a7 ----- d7 ----- g7
        |         |        |
        |  b6 -- d6 -- f6  |
        |  |      |     |  |
        |  |  c5-d5-e5  |  |
        a4-b4-c4    e4-f4-g4
        |  |  c3-d3-e3  |  |
        |  |      |     |  |
        |  b2 -- d2 -- f2  |
        |         |        |
        a1 ----- d1 ----- g1

        31 ----- 24 ----- 25
        |         |        |
        |  23 -- 16 -- 17  |
        |  |      |     |  |
        |  |  15- 8- 9  |  |
        30-22-14    10-18-26
        |  |  13-12-11  |  |
        |  |      |     |  |
        |  21 -- 20 -- 19  |
        |         |        |
        29 ----- 28 ----- 27
    */

    auto sq = [&](Square s) { return (b & square_bb(s)) ? 'X' : '.'; };

    std::string str;
    str += " " + std::string(1, sq(SQ_31)) + " ----- " +
           std::string(1, sq(SQ_24)) + " ----- " + std::string(1, sq(SQ_25)) +
           "\n";
    str += "|         |        |\n";
    str += "|  " + std::string(1, sq(SQ_23)) + " -- " +
           std::string(1, sq(SQ_16)) + " -- " + std::string(1, sq(SQ_17)) +
           "  |\n";
    str += "|  |      |     |  |\n";
    str += "|  |  " + std::string(1, sq(SQ_15)) + "-" +
           std::string(1, sq(SQ_8)) + "-" + std::string(1, sq(SQ_9)) +
           "  |  |\n";
    str += std::string(1, sq(SQ_30)) + "-" + std::string(1, sq(SQ_22)) + "-" +
           std::string(1, sq(SQ_14)) + "    " + std::string(1, sq(SQ_10)) +
           "-" + std::string(1, sq(SQ_18)) + "-" + std::string(1, sq(SQ_26)) +
           "\n";
    str += "|  |  " + std::string(1, sq(SQ_13)) + "-" +
           std::string(1, sq(SQ_12)) + "-" + std::string(1, sq(SQ_11)) +
           "  |  |\n";
    str += "|  |      |     |  |\n";
    str += "|  " + std::string(1, sq(SQ_21)) + " -- " +
           std::string(1, sq(SQ_20)) + " -- " + std::string(1, sq(SQ_19)) +
           "  |\n";
    str += "|         |        |\n";
    str += std::string(1, sq(SQ_29)) + " ----- " + std::string(1, sq(SQ_28)) +
           " ----- " + std::string(1, sq(SQ_27)) + "\n";

    return str;
}

/// Bitboards::init() initializes various bitboard tables. It is called at
/// startup and relies on global objects to be already zero-initialized.

void Bitboards::init()
{
    for (unsigned i = 0; i < (1 << 16); ++i) {
        PopCnt16[i] = static_cast<uint8_t>(std::bitset<16>(i).count());
    }

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        SquareBB[s] = (1U << s);
    }
}
