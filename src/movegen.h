// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movegen.h

#ifndef MOVEGEN_H_INCLUDED
#define MOVEGEN_H_INCLUDED

#include <algorithm>
#include <array>

#include "types.h"

class Position;

enum GenType { PLACE, MOVE, REMOVE, LEGAL };

struct ExtMove
{
    Move move;
    int value;

    operator Move() const noexcept { return move; }

    void operator=(Move m) noexcept { move = m; }

    // Inhibit unwanted implicit conversions to Move
    // with an ambiguity that yields to a compile error.
    operator float() const = delete;
};

inline bool operator<(const ExtMove &f, const ExtMove &s) noexcept
{
    return f.value < s.value;
}

template <GenType>
ExtMove *generate(Position &pos, ExtMove *moveList);

/// The MoveList struct is a simple wrapper around generate(). It sometimes
/// comes in handy to use this class instead of the low level generate()
/// function.
template <GenType T>
struct MoveList
{
    explicit MoveList(Position &pos)
        : last(generate<T>(pos, moveList))
    { }

    const ExtMove *begin() const { return moveList; }

    const ExtMove *end() const { return last; }

    size_t size() const { return last - moveList; }

    bool contains(Move move) const
    {
        return std::find(begin(), end(), move) != end();
    }

    ExtMove getMove(int index) { return moveList[index]; }

    static void create();
    static void shuffle();

    inline static std::array<Square, SQUARE_NB> movePriorityList {
        SQ_16, SQ_18, SQ_20, SQ_22, SQ_24, SQ_26, SQ_28, SQ_30,
        SQ_8,  SQ_10, SQ_12, SQ_14, SQ_17, SQ_19, SQ_21, SQ_23,
        SQ_25, SQ_27, SQ_29, SQ_31, SQ_9,  SQ_11, SQ_13, SQ_15};

    inline static Square adjacentSquares[SQUARE_EXT_NB][MD_NB] = {{SQ_NONE}};
    inline static Bitboard adjacentSquaresBB[SQUARE_EXT_NB] = {0};

private:
    ExtMove moveList[MAX_MOVES] {{MOVE_NONE, 0}};
    ExtMove *last {nullptr};
};

#endif // #ifndef MOVEGEN_H_INCLUDED
