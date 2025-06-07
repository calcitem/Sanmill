// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_game_state.h

#ifndef PERFECT_GAME_STATE_H_INCLUDED
#define PERFECT_GAME_STATE_H_INCLUDED

#include <sstream>

class CMove; // forward declaration, implement this

class GameState
{
public:
    // The board (-1: empty, 0: white piece, 1: black piece)
    std::vector<int> board = std::vector<int>(24, -1);
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

    int get_future_piece_count(int p);

    // Sets the state for Setup Mode: the placed stones are unchanged, but we
    // switch to phase 2.
    void init_setup();

    void make_move(CMove *M);

    void check_valid_move(CMove *M);

    void check_invariants();

    // Called when applying a free setup. It sets over and checks whether the
    // position is valid. Returns "" if valid, reason str otherwise. Also called
    // when pasting a position.
    std::string set_over_and_check_valid_setup();

    // to paste from clipboard
    GameState(const std::string &s);

    void fromString(const std::string &s);

    // for clipboard
    std::string to_string();
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

#endif // PERFECT_GAME_STATE_H_INCLUDED
