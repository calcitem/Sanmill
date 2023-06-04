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

#ifndef GAME_STATE_H_INCLUDED
#define GAME_STATE_H_INCLUDED

#include <cassert>
#include <list>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "PerfectPlayer.h"
#include "Player.h"
#include "move.h"
#include "rules.h"

class CMove; // forward declaration, implement this

class GameState
{
public:
    // The board (-1: empty, 0: white piece, 1: black piece)
    std::vector<int> T = std::vector<int>(24, -1);
    int phase = 1;
    // How many stones the players have set
    std::vector<int> setStoneCount = std::vector<int>(2, 0);
    std::vector<int> stoneCount = std::vector<int>(2, 0);
    bool kle = false; // Is there a puck removal coming?
    int sideToMove = 0;
    int moveCount = 0;
    bool over = false;
    int winner = 0; // (-1, if a draw)
    bool block = false;
    int lastIrrev = 0;

    GameState() { } // start of game

    GameState(const GameState &s);

    int futureStoneCount(int p);

    // Sets the state for Setup Mode: the placed stones are unchanged, but we
    // switch to phase 2.
    void initSetup();

    void makeMove(CMove *M);

    void checkValidMove(CMove *M);

    void checkInvariants();

    // Called when applying a free setup. It sets over and checks whether the
    // position is valid. Returns "" if valid, reason str otherwise. Also called
    // when pasting a position.
    std::string setOverAndCheckValidSetup();

    // to paste from clipboard
    GameState(const std::string &s);

    // for clipboard
    std::string toString();
};

class InvalidGameStateException : public std::exception
{
public:
    std::string mymsg;
    InvalidGameStateException(const std::string &msg)
        : mymsg(msg)
    { }

    virtual const char *what() const noexcept override;
};

#endif // GAME_STATE_H_INCLUDED
