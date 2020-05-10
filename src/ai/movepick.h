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

#ifndef MOVEPICK_H
#define MOVEPICK_H

#include "stack.h"
#include "types.h"
#include "movegen.h"
#include "position.h"

class Position;
class ExtMove;

void partial_insertion_sort(ExtMove *begin, ExtMove *end, int limit);

class MovePicker
{
    enum PickType
    {
        Next, Best
    };

public:
    MovePicker(Position *position, ExtMove *cur);
    MovePicker(const MovePicker &) = delete;
    MovePicker &operator=(const MovePicker &) = delete;
   // move_t nextMove(bool skipQuiets = false);

#ifdef HOSTORY_HEURISTIC
    // TODO: Fix size
    score_t placeHistory[64];
    score_t removeHistory[64];
    score_t moveHistory[10240];

    score_t getHistoryScore(move_t move);
    void setHistoryScore(move_t move, depth_t depth);
    void clearHistoryScore();
#endif // HOSTORY_HEURISTIC

public:
    void score();

    ExtMove *begin()
    {
        return cur;
    }

//     ExtMove *end()
//     {
//         return endMoves;
//     }

    Position *position;
    ExtMove *cur;
};

#endif // MOVEPICK_H
