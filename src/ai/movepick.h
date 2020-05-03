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

// TODO: Fix size
typedef Stack<score_t, 64> PlaceHistory;
typedef Stack<score_t, 64> CaptureHistory;
typedef Stack<score_t, 10240> MoveHistory;

class MovePicker
{
public:
    static PlaceHistory placeHistory;
    static CaptureHistory captureHistory;
    static MoveHistory moveHistory;

    static score_t getHistoryScore(move_t move)
    {
        score_t ret;

        if (move < 0) {
            ret = placeHistory[-move];
        } else if (move & 0x7f00) {
            ret = moveHistory[move];
        } else {
            ret = placeHistory[move & 0x007f];
        }

        return ret;
    }

    static void setHistoryScore(move_t move, depth_t depth)
    {
        if (move == MOVE_NONE) {
            return;
        }

        score_t score = 1 << depth;

        if (move < 0) {
            placeHistory[-move] += score;
        } else if (move & 0x7f00) {
            moveHistory[move] += score;
        } else {
            moveHistory[move & 0x007f] += score;
        }
    }

    static void clearHistoryScore()
    {
        placeHistory.clear();
        captureHistory.clear();
        moveHistory.clear();
    }
};

#endif // MOVEPICK_H
