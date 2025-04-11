// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_game.h

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
    GameState &get_current_game_state() const;

    Game(Player *p1, Player *p2);

    Player **get_players();

    Player *get_player(int i) const;

    void set_player(int i, Player *p);

    void make_move(CMove *M);

    void apply_setup(GameState toSet);

    void cancel_thinking();

    bool is_player_type_change_allowed();

    void copy_move_list();
};

#endif // PERFECT_MAIN_H_INCLUDED
