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

#include "config.h"
#include "position.h"
#include "search.h"

class Position;

enum GenType
{
    CAPTURES,
    LEGAL
};

class ExtMove
{
public:
    move_t move;
    value_t value;
    rating_t rating;

    operator move_t() const
    {
        return move;
    }

    void operator = (move_t m)
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

    // 生成着法表
    static void create();

    // 随机打乱着法搜索顺序
    static void shuffle();

    // 着法表 // TODO: Move to private
    inline static move_t moveTable[SQ_EXPANDED_COUNT][DIRECTIONS_COUNT] = { {MOVE_NONE} };

    // 着法顺序表, 后续会被打乱
    inline static array<move_t, Board::N_RINGS *Board::N_SEATS> movePriorityTable{
        (move_t)8, (move_t)9, (move_t)10, (move_t)11, (move_t)12, (move_t)13, (move_t)14, (move_t)15,
        (move_t)16, (move_t)17, (move_t)18, (move_t)19, (move_t)20, (move_t)21, (move_t)22, (move_t)23,
        (move_t)24, (move_t)25, (move_t)26, (move_t)27, (move_t)28, (move_t)29, (move_t)30, (move_t)31,
    };

    //explicit MoveList(const Position &pos) : last(generate<T>(pos, moveList))
//     explicit MoveList(const Position &pos) : last(generate(pos, moveList))
//     {
//     }

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

    bool contains(move_t move) const
    {
        return std::find(begin(), end(), move) != end();
    }

private:
    ExtMove moveList[MAX_MOVES], *last;
};

#endif /* MOVEGEN_H */
