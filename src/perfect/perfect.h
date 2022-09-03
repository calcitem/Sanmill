/*********************************************************************
    MiniMaxAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef PERFECT_H_INCLUDED
#define PERFECT_H_INCLUDED

#include "mill.h"
#include "perfectAI.h"
#include "types.h"

extern Mill *mill;
extern PerfectAI *ai;

// Perfect AI
int perfect_init();
int perfect_exit();
int perfect_reset();
Square from_perfect_sq(uint32_t sq);
Move from_perfect_move(uint32_t from, uint32_t to);
unsigned to_perfect_sq(Square sq);
void to_perfect_move(Move move, uint32_t &from, uint32_t &to);
Move perfect_search();
bool perfect_do_move(Move move);
bool perfect_command(const char *cmd);

#endif // PERFECT_H_INCLUDED
