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

#ifndef MOVEGEN_H
#define MOVEGEN_H

#include <array>

#include "config.h"
#include "types.h"

using namespace std;

class Position;

enum GenType
{
    CAPTURES,
    LEGAL
};

struct ExtMove
{
    Move move;
    Value value;
    Rating rating;

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

inline bool operator < (const ExtMove &first, const ExtMove &second)
{
    //return first.value < second.value;
    return first.rating < second.rating;
}

//template <GenType>
ExtMove *generate(Position *pos, ExtMove *moveList);

/// The MoveList struct is a simple wrapper around generate(). It sometimes comes
/// in handy to use this class instead of the low level generate() function.
//template<GenType T>
class MoveList
{
public:
    MoveList() = delete;

    MoveList &operator=(const MoveList &) = delete;

    static void create();
    static void shuffle();

    // TODO: Move to private
    inline static Move moveTable[SQUARE_NB][MD_NB] = { {MOVE_NONE} };

    inline static array<Move, FILE_NB * RANK_NB> movePriorityTable{
        (Move)8, (Move)9, (Move)10, (Move)11, (Move)12, (Move)13, (Move)14, (Move)15,
        (Move)16, (Move)17, (Move)18, (Move)19, (Move)20, (Move)21, (Move)22, (Move)23,
        (Move)24, (Move)25, (Move)26, (Move)27, (Move)28, (Move)29, (Move)30, (Move)31,
    };

    explicit MoveList(Position *pos) : last(generate(pos, moveList))
    {
    }

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

private:
    ExtMove moveList[MAX_MOVES], *last;
};

#endif /* MOVEGEN_H */
