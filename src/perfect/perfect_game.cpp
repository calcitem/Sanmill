// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_game.cpp

#include "perfect_player.h"
#include "perfect_game.h"
#include "perfect_game_state.h"

class Player;
class GameState;
class CMove;

GameState &Game::get_current_game_state() const
{
    // wrapper of current.value
    return *current;
}

Game::Game(Player *p1, Player *p2)
{
    history.push_back(GameState());
    current = std::prev(history.end());
    _ply[0] = p1;
    _ply[1] = p2;
}

Player **Game::get_players()
{
    return _ply;
}

Player *Game::get_player(int i) const
{
    // get players in the game
    return _ply[i];
}

void Game::set_player(int i, Player *p)
{
    // set players in the game
    if (p == nullptr) {
        _ply[i] = nullptr;
        return;
    }

    // we exit p to see if it was in a game (e.g. NewGame in the
    // previous one)
    p->quit();

    if (_ply[i] != nullptr)
        _ply[i]->quit(); // the player replaced by p is kicked out
    _ply[i] = p;
    p->enter_game(this);
}

void Game::make_move(CMove *M)
{ // called by player objects when they want to move
    try {
        get_player(1 - get_current_game_state().sideToMove)->followMove(M);

        history.insert(std::next(current), GameState(get_current_game_state()));
        current++;

        get_current_game_state().make_move(M);
    } catch (std::exception &ex) {
        // If TypeOf ex Is KeyNotFoundException Then Throw
        std::cerr << "Exception in make_move\n" << ex.what() << std::endl;
    }
}

void Game::apply_setup(GameState toSet)
{
    history.insert(std::next(current), toSet);
    current++;
}

void Game::cancel_thinking()
{
    for (int i = 0; i < 2; ++i) {
        get_player(i)->cancel_thinking();
    }
}

bool Game::is_player_type_change_allowed()
{
    // Return TypeOf get_player(s.sideToMove) Is HumanPlayer
    return true;
}

void Game::copy_move_list()
{
    throw std::runtime_error("NotImplementedException");
}
