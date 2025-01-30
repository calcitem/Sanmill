// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movepick.h

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
    explicit MovePicker(Position &p, Move ttm) noexcept;

    template <GenType>
    Move next_move();

    template <GenType>
    void score();

    ExtMove *begin() const noexcept { return cur; }

    ExtMove *end() const noexcept { return endMoves; }

    Position &pos;
    Move ttMove {MOVE_NONE};
    ExtMove *cur {nullptr};
    ExtMove *endMoves {nullptr};
    ExtMove moves[MAX_MOVES] {{MOVE_NONE, 0}};

    int moveCount {0};

    int move_count() const noexcept { return moveCount; }
};

#endif // #ifndef MOVEPICK_H_INCLUDED
