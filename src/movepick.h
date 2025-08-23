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

// Move ordering stages inspired by Stockfish
enum Stage {
    // Main search stages
    MAIN_TT,
    CAPTURE_INIT,
    GOOD_CAPTURE,
    QUIET_INIT, 
    GOOD_QUIET,
    BAD_CAPTURE,
    BAD_QUIET,
    
    // Quiescence search stages
    QSEARCH_TT,
    QCAPTURE_INIT,
    QCAPTURE
};

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
    explicit MovePicker(Position &p, Move ttm, int ply = 0) noexcept;

    Move next_move();
    
    template <GenType>
    Move next_move_legacy();  // For backward compatibility

    template <GenType>
    void score();

    ExtMove *begin() const noexcept { return cur; }

    ExtMove *end() const noexcept { return endMoves; }

    Position &pos;
    Move ttMove {MOVE_NONE};
    ExtMove *cur {nullptr};
    ExtMove *endMoves {nullptr};
    ExtMove *endBadCaptures {nullptr};
    ExtMove *endCaptures {nullptr};
    ExtMove moves[MAX_MOVES] {{MOVE_NONE, 0}};

    int moveCount {0};
    int stage {MAIN_TT};
    int currentPly {0};  // For killer move detection

    int move_count() const noexcept { return moveCount; }

private:
    template<typename Pred>
    Move select(Pred filter);
    
    void init_captures();
    void init_quiets();
};

#endif // #ifndef MOVEPICK_H_INCLUDED
