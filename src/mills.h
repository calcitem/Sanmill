// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mills.h

#ifndef MILLS_H_INCLUDED
#define MILLS_H_INCLUDED

#include "config.h"
#include "position.h"
#include "types.h"

#define LOSE_REASON_NO_LEGAL_MOVES \
    "Player %hhu has no legal moves. Player %hhu wins!"
#define LOSE_REASON_TIMEOUT "Time's up. Player %hhu wins!"
#define DRAW_REASON_THREEFOLD_REPETITION "Threefold repetition. It's a draw!"
#define DRAW_REASON_FIFTY_MOVE "50-move rule reached. It's a draw!"
#define DRAW_REASON_ENDGAME_FIFTY_MOVE \
    "Endgame 50-move rule reached. It's a draw!"
#define LOSE_REASON_FULL_BOARD "Board is full. Player 2 wins!"
#define DRAW_REASON_FULL_BOARD "Board is full. It's a draw!"
#define DRAW_REASON_STALEMATE_CONDITION "Stalemate. It's a draw!"
#define LOSE_REASON_LESS_THAN_THREE \
    "Player %hhu wins because the opponent has fewer than three pieces!"
#define LOSE_REASON_PLAYER_RESIGNS "Player %hhu resigns!"

namespace Mills {

void adjacent_squares_init() noexcept;
void mill_table_init();
void move_priority_list_shuffle();
Depth get_search_depth(const Position *pos);
bool is_star_squares_full(Position *pos);

} // namespace Mills

#endif // #ifndef MILLS_H_INCLUDED
