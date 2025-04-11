// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_rules.h

#ifndef PERFECT_RULES_H_INCLUDED
#define PERFECT_RULES_H_INCLUDED

#include "perfect_wrappers.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

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
    static void init_rules();
    static void cleanup_rules();

    // Returns -1 if there is no mill on the given field, otherwise returns the
    // sequence number in StdLaskerMalomPoz
    static int check_mill(int m, GameState s);

    // Tells whether the next player can move '(doesn't handle the kle case)
    static bool can_move(const GameState &s);

    static bool all_opponent_pieces_in_mill(GameState s);

    // Checking if AlphaBeta is available
    static bool is_alpha_beta_available();

    static void set_variant();
};

#endif // PERFECT_RULES_H_INCLUDED
