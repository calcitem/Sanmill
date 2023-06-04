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

#ifndef PLAYER_H_INCLUDED
#define PLAYER_H_INCLUDED

#include <memory> // for std::shared_ptr

#include "PerfectPlayer.h"
#include "game.h"
#include "move.h"
#include "rules.h"

class Player
{
protected:
    Game *g {nullptr}; // Assuming Game is a pre-defined class

public:
    Player()
        : g(nullptr)
    { }

    // The object is informed to enter the specified game
    virtual void enter(Game *_g);

    // The object is informed to exit from the game
    virtual void quit();

    // The object is informed that it is its turn to move
    virtual void toMove(const GameState &s) = 0; // Assuming GameState is a
                                                 // pre-defined class

    // Notifies about the opponent's move
    virtual void followMove(CMove *) { } // Assuming Object is a pre-defined
                                        // class or built-in type

    // The object is informed that it is the opponent's turn to move
    virtual void oppToMove(const GameState &) { }

    // Game is over
    virtual void over(const GameState &) { }

    // Cancel thinking
    virtual void cancelThinking() { }

    // Determine the opponent player
protected:
    Player *opponent()
    {
        return (g->ply(0) == this) ? g->ply(1) : g->ply(0); // Assuming Game has
                                                            // a ply function
    }
};

#endif // PLAYER_H_INCLUDED
