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

#ifndef MOVEGEN_H_INCLUDED
#define MOVEGEN_H_INCLUDED

#include <array>

#include "types.h"

class Position;

struct ExtMove
{
    Move move;
    int value;

    operator Move() const
    {
        return move;
    }

    void operator = (Move m)
    {
        move = m;
    }

    // Inhibit unwanted implicit conversions to Move
    // with an ambiguity that yields to a compile error.
    operator float() const = delete;
};

inline bool operator<(const ExtMove &f, const ExtMove &s)
{
    return f.value < s.value;
}

ExtMove *generate(Position *pos, ExtMove *moveList);

/// The MoveList struct is a simple wrapper around generate(). It sometimes comes
/// in handy to use this class instead of the low level generate() function.
struct MoveList
{
    explicit MoveList(Position *pos) : last(generate(pos, moveList)) {}

    const ExtMove *begin() const
    {
        return moveList;
    }

    const ExtMove *end() const
    {
        return last;
    }

    size_t size() const
    {
        return last - moveList;
    }

    bool contains(Move move) const
    {
        return std::find(begin(), end(), move) != end();
    }


    static void create();
    static void shuffle();

    inline static std::array<Square, FILE_NB *RANK_NB> movePriorityTable {
        SQ_8, SQ_9, SQ_10, SQ_11, SQ_12, SQ_13, SQ_14, SQ_15,
        SQ_16, SQ_17, SQ_18, SQ_19, SQ_20, SQ_21, SQ_22, SQ_23,
        SQ_24, SQ_25, SQ_26, SQ_27, SQ_28, SQ_29, SQ_30, SQ_31,
    };

    inline static Move moveTable[SQUARE_NB][MD_NB] = { {MOVE_NONE} };

private:
    ExtMove moveList[MAX_MOVES], *last;
};

#endif // #ifndef MOVEGEN_H_INCLUDED
