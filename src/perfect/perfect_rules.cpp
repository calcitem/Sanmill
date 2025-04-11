// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_rules.cpp

#include "perfect_rules.h"
#include "perfect_api.h"
#include "perfect_game_state.h"
#include "perfect_move.h"
#include "perfect_player.h"

#include <algorithm>
#include <cassert>
#include <iostream>
#include <vector>

uint8_t Rules::millPos[20][3];
uint8_t Rules::stdLaskerMillPos[16][3];
int *Rules::stdLaskerInvMillPos[24] = {nullptr};
bool Rules::stdLaskerBoardGraph[24][24] = {{false}};
uint8_t Rules::stdLaskerALBoardGraph[24][5] = {{0}};
uint8_t Rules::moraMillPos[20][3];
int *Rules::moraInvMillPos[24];
bool Rules::moraBoardGraph[24][24];
uint8_t Rules::moraALBoardGraph[24][5];
int *Rules::invMillPos[24];
size_t Rules::invMillPosLengths[24];
bool Rules::boardGraph[24][24];
uint8_t Rules::aLBoardGraph[24][5];
std::string Rules::variantName;
int Rules::maxKSZ = 0;

void Rules::init_rules()
{
    stdLaskerMillPos[0][0] = 1;
    stdLaskerMillPos[0][1] = 2;
    stdLaskerMillPos[0][2] = 3;
    stdLaskerMillPos[1][0] = 3;
    stdLaskerMillPos[1][1] = 4;
    stdLaskerMillPos[1][2] = 5;
    stdLaskerMillPos[2][0] = 5;
    stdLaskerMillPos[2][1] = 6;
    stdLaskerMillPos[2][2] = 7;
    stdLaskerMillPos[3][0] = 7;
    stdLaskerMillPos[3][1] = 0;
    stdLaskerMillPos[3][2] = 1;
    for (int i = 4; i <= 11; i++) {
        stdLaskerMillPos[i][0] = stdLaskerMillPos[i - 4][0] + 8;
        stdLaskerMillPos[i][1] = stdLaskerMillPos[i - 4][1] + 8;
        stdLaskerMillPos[i][2] = stdLaskerMillPos[i - 4][2] + 8;
    }
    stdLaskerMillPos[12][0] = 0;
    stdLaskerMillPos[13][0] = 2;
    stdLaskerMillPos[14][0] = 4;
    stdLaskerMillPos[15][0] = 6;
    for (int i = 12; i <= 15; i++) {
        stdLaskerMillPos[i][1] = stdLaskerMillPos[i][0] + 8;
        stdLaskerMillPos[i][2] = stdLaskerMillPos[i][0] + 16;
    }
    // Since C++ arrays cannot be resized dynamically, we'll need to allocate
    // memory for stdLaskerInvMillPos beforehand, and then populate it in this
    // function.
    bool kell;
    for (int i = 0; i <= 23; i++) {
        std::vector<int> l;
        for (int j = 0; j <= 15; j++) {
            kell = false;
            for (int k = 0; k <= 2; k++) {
                if (stdLaskerMillPos[j][k] == i)
                    kell = true;
            }
            if (kell) {
                l.push_back(j);
            }
        }
        // Store the length
        invMillPosLengths[i] = l.size();
        // Convert the vector into an array and store it in stdLaskerInvMillPos
        stdLaskerInvMillPos[i] = new int[l.size()];
        for (size_t j = 0; j < l.size(); j++) {
            stdLaskerInvMillPos[i][j] = l[j];
        }
    }
    // Initialize stdLaskerBoardGraph with false
    for (int i = 0; i <= 23; i++) {
        for (int j = 0; j <= 23; j++) {
            stdLaskerBoardGraph[i][j] = false;
        }
    }
    // Fill the board
    for (int i = 0; i <= 6; i++) {
        stdLaskerBoardGraph[i][i + 1] = true;
    }
    stdLaskerBoardGraph[7][0] = true;
    for (int i = 8; i <= 14; i++) {
        stdLaskerBoardGraph[i][i + 1] = true;
    }
    stdLaskerBoardGraph[15][8] = true;
    for (int i = 16; i <= 22; i++) {
        stdLaskerBoardGraph[i][i + 1] = true;
    }
    stdLaskerBoardGraph[23][16] = true;
    for (int j = 0; j <= 6; j += 2) {
        for (int i = 0; i <= 8; i += 8) {
            stdLaskerBoardGraph[j + i][j + i + 8] = true;
        }
    }
    // Fill the rest of the graph
    for (int i = 0; i <= 23; i++) {
        for (int j = 0; j <= 23; j++) {
            if (stdLaskerBoardGraph[i][j] == true) {
                stdLaskerBoardGraph[j][i] = true;
            }
        }
    }
    // Initialize stdLaskerALBoardGraph with 0
    for (int i = 0; i <= 23; i++) {
        stdLaskerALBoardGraph[i][0] = 0;
    }
    // Fill the rest of the graph
    for (int i = 0; i <= 23; i++) {
        for (uint8_t j = 0; j <= 23; j++) {
            if (stdLaskerBoardGraph[i][j] == true) {
                stdLaskerALBoardGraph[i][stdLaskerALBoardGraph[i][0] + 1] = j;
                stdLaskerALBoardGraph[i][0] += 1;
            }
        }
    }

    for (int i = 0; i <= 15; i++) {
        for (int j = 0; j <= 2; j++) {
            moraMillPos[i][j] = stdLaskerMillPos[i][j];
        }
    }

    moraMillPos[16][0] = 1;
    moraMillPos[16][1] = 9;
    moraMillPos[16][2] = 17;
    moraMillPos[17][0] = 3;
    moraMillPos[17][1] = 11;
    moraMillPos[17][2] = 19;
    moraMillPos[18][0] = 5;
    moraMillPos[18][1] = 13;
    moraMillPos[18][2] = 21;
    moraMillPos[19][0] = 7;
    moraMillPos[19][1] = 15;
    moraMillPos[19][2] = 23;

    for (int i = 0; i <= 23; i++) {
        std::vector<int> l;
        for (int j = 0; j <= 19; j++) {
            bool needed = false;
            for (int k = 0; k <= 2; k++) {
                if (moraMillPos[j][k] == i) {
                    needed = true;
                    break;
                }
            }
            if (needed) {
                l.push_back(j);
            }
        }
        moraInvMillPos[i] = new int[l.size()];
        std::copy(l.begin(), l.end(), moraInvMillPos[i]);
    }

    for (int i = 0; i <= 23; i++) {
        for (int j = 0; j <= 23; j++) {
            moraBoardGraph[i][j] = stdLaskerBoardGraph[i][j];
        }
    }

    for (int i = 0; i <= 15; i++) {
        moraBoardGraph[i][i + 8] = true;
    }

    for (int i = 0; i <= 23; i++) {
        for (int j = 0; j <= 23; j++) {
            if (moraBoardGraph[i][j] == true) {
                moraBoardGraph[j][i] = true;
            }
        }
    }

    for (int i = 0; i <= 23; i++) {
        moraALBoardGraph[i][0] = 0;
    }

    for (int i = 0; i <= 23; i++) {
        for (uint8_t j = 0; j <= 23; j++) {
            if (moraBoardGraph[i][j] == true) {
                moraALBoardGraph[i][moraALBoardGraph[i][0] + 1] = j;
                moraALBoardGraph[i][0] += 1;
            }
        }
    }
}

void Rules::cleanup_rules()
{
    for (int i = 0; i < 24; ++i) {
        delete[] stdLaskerInvMillPos[i];
    }

    for (int i = 0; i < 24; ++i) {
        delete[] moraInvMillPos[i];
    }
}

// Returns -1 if there is no mill on the given field, otherwise returns the
// sequence number in StdLaskerMalomPoz
int Rules::check_mill(int m, GameState s)
{
    int result = -1;
    // Use the stored length instead of sizeof
    size_t length = invMillPosLengths[m]; // TODO: Right?
    for (size_t i = 0; i < length; i++) {
        if (s.board[millPos[invMillPos[m][i]][0]] == s.board[m] &&
            s.board[millPos[invMillPos[m][i]][1]] == s.board[m] &&
            s.board[millPos[invMillPos[m][i]][2]] == s.board[m]) {
            result = invMillPos[m][i];
        }
    }
    return result;
}

// Tells whether the next player can move '(doesn't handle the kle case)
bool Rules::can_move(const GameState &s)
{
    assert(!s.kle);
    if (s.setStoneCount[s.sideToMove] == maxKSZ &&
        s.stoneCount[s.sideToMove] > 3) {
        for (int i = 0; i <= 23; i++) {
            if (s.board[i] == s.sideToMove) {
                for (int j = 1; j <= aLBoardGraph[i][0]; j++) {
                    if (s.board[aLBoardGraph[i][j]] == -1)
                        return true;
                }
            }
        }
    } else {
        return true;
    }
    return false;
}

bool Rules::all_opponent_pieces_in_mill(GameState s)
{
    for (int i = 0; i <= 23; i++) {
        if (s.board[i] == 1 - s.sideToMove && check_mill(i, s) == -1)
            return false;
    }
    return true;
}

// Checking if AlphaBeta is available
bool Rules::is_alpha_beta_available()
{
    return ruleVariant == (int)Wrappers::Constants::Variants::std &&
           !Wrappers::Constants::extended;
}

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4127)
#endif

void Rules::set_variant()
{
    // Part of this is copy-pasted in MalomAPI
    if (ruleVariant == (int)Wrappers::Constants::Variants::std) {
        std::memcpy(millPos, stdLaskerMillPos, sizeof(stdLaskerMillPos));
        for (int i = 0; i < 24; ++i) {
            invMillPos[i] = stdLaskerInvMillPos[i];
        }
        std::memcpy(boardGraph, stdLaskerBoardGraph,
                    sizeof(stdLaskerBoardGraph));
        std::memcpy(aLBoardGraph, stdLaskerALBoardGraph,
                    sizeof(stdLaskerALBoardGraph));
        maxKSZ = 9;
        variantName = "std";
    } else if (ruleVariant == (int)Wrappers::Constants::Variants::lask) {
        std::memcpy(millPos, stdLaskerMillPos, sizeof(stdLaskerMillPos));
        for (int i = 0; i < 24; ++i) {
            invMillPos[i] = stdLaskerInvMillPos[i];
        }
        std::memcpy(boardGraph, stdLaskerBoardGraph,
                    sizeof(stdLaskerBoardGraph));
        std::memcpy(aLBoardGraph, stdLaskerALBoardGraph,
                    sizeof(stdLaskerALBoardGraph));
        maxKSZ = 10;
        variantName = "lask";
    } else if (ruleVariant == (int)Wrappers::Constants::Variants::mora) {
        std::memcpy(millPos, moraMillPos, sizeof(moraMillPos));
        for (int i = 0; i < 24; ++i) {
            invMillPos[i] = moraInvMillPos[i];
        }
        std::memcpy(boardGraph, moraBoardGraph, sizeof(moraBoardGraph));
        std::memcpy(aLBoardGraph, moraALBoardGraph, sizeof(moraALBoardGraph));
        maxKSZ = 12;
        variantName = "mora";
    }

    if (Wrappers::Constants::extended) {
        maxKSZ = 12;
    }
}

#ifdef _MSC_VER
#pragma warning(pop)
#endif
