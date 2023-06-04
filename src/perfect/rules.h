// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023 The Sanmill developers (see AUTHORS file)
//
// See our webpage (and the paper linked from there):
// http://compalg.inf.elte.hu/~ggevay/mills/index.php
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef RULES_H_INCLUDED
#define RULES_H_INCLUDED

#include <algorithm>
#include <cassert>
#include <iostream>
#include <vector>

#include "wrappers.h"

class GameState;

class Rules
{
public:
    // Define your byte arrays
    static uint8_t millPos[20][3]; // TODO: Initial: [16][3];
    static uint8_t stdLaskerMillPos[16][3];
    static uint8_t moraMillPos[20][3];

    // Define your integer arrays
    static int *invMillPos[24];
    static size_t invMillPosLengths[24];
    static int *stdLaskerInvMillPos[24];
    static int *moraInvMillPos[24];

    // Define your boolean arrays
    static bool boardGraph[24][24];
    static bool stdLaskerBoardGraph[24][24];
    static bool moraBoardGraph[24][24];

    // Define your adjacency list byte arrays
    static uint8_t aLBoardGraph[24][5];
    static uint8_t stdLaskerALBoardGraph[24][5];
    static uint8_t moraALBoardGraph[24][5];

    // Define other variables
    static std::string variantName;
    static int maxKSZ;
    static const int lastIrrevLimit = 50;

public:
    static void initRules();
    static void cleanup();

    // Returns -1 if there is no mill on the given field, otherwise returns the
    // sequence number in StdLaskerMalomPoz
    static int malome(int m, GameState s);

    // Tells whether the next player can move '(doesn't handle the kle case)
    static bool youCanMove(const GameState &s);

    static bool mindenEllensegesKorongMalomban(GameState s);

    // Checking if AlphaBeta is available
    static bool alphaBetaAvailable();

    static void setVariant();
};

#endif // RULES_H_INCLUDED
