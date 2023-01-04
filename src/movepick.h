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

#ifndef MOVEPICK_H_INCLUDED
#define MOVEPICK_H_INCLUDED

#include <array>
#include <limits>
#include <type_traits>

#include "movegen.h"
#include "position.h"
#include "types.h"

class Position;
struct ExtMove;

void partial_insertion_sort(ExtMove *begin, const ExtMove *end, int limit);

/// MovePicker class is used to pick one pseudo legal move at a time from the
/// current position. The most important method is next_move(), which returns a
/// new pseudo legal move each time it is called, until there are no moves left,
/// when MOVE_NONE is returned. In order to improve the efficiency of the alpha
/// beta algorithm, MovePicker attempts to return the moves which are most
/// likely to get a cut-off first.
class MovePicker
{
public:
    MovePicker(const MovePicker &) = delete;
    MovePicker &operator=(const MovePicker &) = delete;
    explicit MovePicker(Position &p) noexcept;

    Move next_move();

    template <GenType>
    void score();

    [[nodiscard]] ExtMove *begin() const noexcept { return cur; }

    [[nodiscard]] ExtMove *end() const noexcept { return endMoves; }

    Position &pos;
    Move ttMove {MOVE_NONE};
    ExtMove *cur {nullptr};
    ExtMove *endMoves {nullptr};
    ExtMove moves[MAX_MOVES] {{MOVE_NONE, 0}};

    int moveCount {0};

    [[nodiscard]] int move_count() const noexcept { return moveCount; }
};

#endif // #ifndef MOVEPICK_H_INCLUDED
