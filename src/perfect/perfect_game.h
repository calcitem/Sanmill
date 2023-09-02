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

#ifndef PERFECT_GAME_H_INCLUDED
#define PERFECT_GAME_H_INCLUDED

#include "perfect_player.h"
#include "perfect_rules.h"

#include <list>

class Player;
class CMove;

class Game
{
private:
    Player *_ply[2];              // players in the game
    std::list<GameState> history; // GameStates in this (and previous) games

    // the node of the current GameState in history
    std::list<GameState>::iterator current; 

public:
    GameState &s() const;

    Game(Player *p1, Player *p2);

    Player **plys();

    Player *ply(int i) const;

    void set_ply(int i, Player *p);

    void makeMove(CMove *M);

    void applySetup(GameState toSet);

    void cancelThinking();

    bool playertypeChangingCmdAllowed();

    void copyMoveList();
};

#endif // PERFECT_MAIN_H_INCLUDED
