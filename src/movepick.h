/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

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

void partial_insertion_sort(ExtMove *begin, ExtMove *end, int limit);


/// MovePicker class is used to pick one pseudo legal move at a time from the
/// current position. The most important method is next_move(), which returns a
/// new pseudo legal move each time it is called, until there are no moves left,
/// when MOVE_NONE is returned. In order to improve the efficiency of the alpha
/// beta algorithm, MovePicker attempts to return the moves which are most likely
/// to get a cut-off first.
class MovePicker
{
    enum PickType
    {
        Next, Best
    };

public:
    MovePicker(const MovePicker &) = delete;
    MovePicker &operator=(const MovePicker &) = delete;
    MovePicker(Position *position);

    Move next_move();

//private:
    template<PickType T, typename Pred> Move select(Pred);
    void score();

    ExtMove *begin()
    {
        return cur;
    }

    ExtMove *end()
    {
        return endMoves;
    }

    Position *pos;
    Move ttMove { MOVE_NONE };
    ExtMove *cur, *endMoves;
    ExtMove moves[MAX_MOVES] { MOVE_NONE };

    int moveCount{ 0 };

    int move_count()
    {
        return moveCount;
    }

#ifdef HOSTORY_HEURISTIC
    // TODO: Fix size
    Score placeHistory[64];
    Score removeHistory[64];
    Score moveHistory[10240];

    Score getHistoryScore(Move move);
    void setHistoryScore(Move move, Depth depth);
    void clearHistoryScore();
#endif // HOSTORY_HEURISTIC
};

#endif // #ifndef MOVEPICK_H_INCLUDED
