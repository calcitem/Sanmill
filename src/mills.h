// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

} // namespace Mills

#endif // #ifndef MILLS_H_INCLUDED
