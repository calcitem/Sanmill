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


/// StatsEntry stores the stat table value. It is usually a number but could
/// be a move or even a nested history. We use a class instead of naked value
/// to directly call history update operator<<() on the entry so to use stats
/// tables at caller sites as simple multi-dim arrays.
template<typename T, int D>
class StatsEntry
{
    T entry;

public:
    void operator=(const T &v)
    {
        entry = v;
    }
    T *operator&()
    {
        return &entry;
    }
    T *operator->()
    {
        return &entry;
    }
    operator const T &() const
    {
        return entry;
    }

    void operator<<(int bonus)
    {
        assert(abs(bonus) <= D); // Ensure range is [-D, D]
        static_assert(D <= std::numeric_limits<T>::max(), "D overflows T");

        entry += T(bonus - entry * abs(bonus) / D);

        assert(abs(entry) <= D);
    }
};

/// Stats is a generic N-dimensional array used to store various statistics.
/// The first template parameter T is the base type of the array, the second
/// template parameter D limits the range of updates in [-D, D] when we update
/// values with the << operator, while the last parameters (Size and Sizes)
/// encode the dimensions of the array.
template <typename T, int D, int Size, int... Sizes>
struct Stats : public std::array<Stats<T, D, Sizes...>, Size>
{
    typedef Stats<T, D, Size, Sizes...> stats;

    void fill(const T &v)
    {

        // For standard-layout 'this' points to first struct member
        assert(std::is_standard_layout<stats>::value);

        typedef StatsEntry<T, D> entry;
        entry *p = reinterpret_cast<entry *>(this);
        std::fill(p, p + sizeof(*this) / sizeof(entry), v);
    }
};

template <typename T, int D, int Size>
struct Stats<T, D, Size> : public std::array<StatsEntry<T, D>, Size> {};

/// In stats table, D=0 means that the template parameter is not used
enum StatsParams
{
    NOT_USED = 0
};
enum StatsType
{
    NoCaptures, Captures
};

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
    MovePicker(Position &position);

    Move next_move();

    template<PickType T, typename Pred> Move select(Pred);
    template<GenType> void score();
    ExtMove *begin()
    {
        return cur;
    }

    ExtMove *end()
    {
        return endMoves;
    }

    Position &pos;
    Move ttMove { MOVE_NONE };
    ExtMove *cur { nullptr };
    ExtMove *endMoves { nullptr };
    ExtMove moves[MAX_MOVES]{ {MOVE_NONE, 0} };

    int moveCount{ 0 };

    int move_count()
    {
        return moveCount;
    }
};

#endif // #ifndef MOVEPICK_H_INCLUDED
