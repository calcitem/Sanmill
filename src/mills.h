// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

#define loseReasonNoWayStr "Player%hhu no way to go. Player%hhu win!"
#define loseReasonTimeOverStr "Time over. Player%hhu win!"
#define drawReasonThreefoldRepetitionStr "Threefold Repetition. Draw!"
#define drawReasonRule50Str "N-move rule. Draw!"
#define drawReasonEndgameRule50Str "Endgame N-move rule. Draw!"
#define loseReasonBoardIsFullStr "Full. Player2 win!"
#define drawReasonBoardIsFullStr "Full. In draw!"
#define loseReasonlessThanThreeStr "Player%hhu win!"
#define loseReasonResignStr "Player%hhu give up!"

namespace Mills {

void adjacent_squares_init() noexcept;
void mill_table_init();
void move_priority_list_shuffle();
Depth get_search_depth(const Position *pos);

} // namespace Mills

#endif // #ifndef MILLS_H_INCLUDED
