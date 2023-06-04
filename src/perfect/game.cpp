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

#include <cassert>
#include <list>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "MalomSolutionAccess.h"
#include "PerfectPlayer.h"
#include "Player.h"
#include "game.h"
#include "game_state.h"
#include "move.h"
#include "rules.h"

class Player;    // forward declaration, implement this
class GameState; // forward declaration, implement this
class CMove;      // forward declaration, implement this

GameState &Game::s() const
{ // wrapper of current.value
    return *current;
}

Game::Game(Player *p1, Player *p2)
{
    history.push_back(GameState());
    current = std::prev(history.end());
    _ply[0] = p1;
    _ply[1] = p2;
}

Player **Game::plys()
{
    return _ply;
}

Player *Game::ply(int i) const
{ // get players in the game
    return _ply[i];
}

void Game::set_ply(int i, Player *p)
{ // set players in the game
    if (p == nullptr) {
        _ply[i] = nullptr;
        return;
    }

    p->quit(); // we exit p to see if it was in a game (e.g. NewGame in the
               // previous one)
    if (_ply[i] != nullptr)
        _ply[i]->quit(); // the player replaced by p is kicked out
    _ply[i] = p;
    p->enter(this);
}

void Game::makeMove(CMove *M)
{ // called by player objects when they want to move
    try {
        ply(1 - s().sideToMove)->followMove(M);

        history.insert(std::next(current), GameState(s()));
        current++;

        s().makeMove(M);
    } catch (std::exception &ex) {
        // If TypeOf ex Is KeyNotFoundException Then Throw
        std::cerr << "Exception in makeMove\n" << ex.what() << std::endl;
    }
}

void Game::applySetup(GameState toSet)
{
    history.insert(std::next(current), toSet);
    current++;
}

void Game::cancelThinking()
{
    for (int i = 0; i < 2; ++i) {
        ply(i)->cancelThinking();
    }
}

bool Game::playertypeChangingCmdAllowed()
{
    // Return TypeOf ply(s.sideToMove) Is HumanPlayer
    return true;
}

void Game::copyMoveList()
{
    throw std::runtime_error("NotImplementedException");
}
