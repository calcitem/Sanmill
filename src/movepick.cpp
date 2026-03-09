// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// movepick.cpp

#include "movepick.h"
#include "option.h"

// partial_insertion_sort() sorts moves in descending order up to and including
// a given limit. The order of moves smaller than the limit is left unspecified.
void partial_insertion_sort(ExtMove *begin, const ExtMove *end, int limit)
{
    for (ExtMove *sortedEnd = begin, *p = begin + 1; p < end; ++p)
        if (p->value >= limit) {
            ExtMove tmp = *p, *q;
            *p = *++sortedEnd;
            for (q = sortedEnd; q != begin && *(q - 1) < tmp; --q)
                *q = *(q - 1);
            *q = tmp;
        }
}

/// Constructors of the MovePicker class.

/// MovePicker constructor for the main search
MovePicker::MovePicker(Position &p, Move ttm) noexcept
    : pos(p)
    , ttMove(ttm)
{ }

/// MovePicker::score() assigns a numerical value to each move in a list, used
/// for sorting.
template <GenType Type>
void MovePicker::score()
{
    int theirMillsCount;
    int ourPieceCount = 0;
    int theirPiecesCount = 0;
    int markedCount = 0;
    int emptyCount = 0;

    // Safety fix: iterate over [moves, endMoves) instead of relying on
    // MOVE_NONE sentinel. This avoids out-of-bounds when generate() fills
    // exactly MAX_MOVES and no sentinel is set.
    for (cur = moves; cur < endMoves; ++cur) {
        Move m = cur->move;

#ifdef TT_MOVE_ENABLE
        if (m == ttMove) {
            cur->value = RATING_TT;
            continue;
        }
#endif // TT_MOVE_ENABLE

        const Square to = to_sq(m);
        assert(to >= SQ_BEGIN && to < SQ_END);
        const Square from = from_sq(m);

        // if stat before moving, moving phrase maybe from @-0-@ to 0-@-@, but
        // no mill, so need |from| to judge
        const int ourMillsCount = pos.potential_mills_count(
            to, pos.side_to_move(), from);

#ifndef SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGE
        // TODO(calcitem): rule.mayRemoveMultiple adapt other rules
        if (type_of(m) != MOVETYPE_REMOVE) {
            // all phrase, check if place sq can close mill
            if (ourMillsCount > 0) {
                cur->value += RATING_ONE_MILL * ourMillsCount;

                // Double-mill bonus: reaching >= 2 simultaneous potential mills
                // is stronger than a single mill (cardinal / dual-mill concept
                // from strategy guide).
                if (ourMillsCount >= 2) {
                    cur->value += RATING_DOUBLE_MILL;
                }
            } else if (pos.get_phase() == Phase::placing &&
                       !rule.mayMoveInPlacingPhase) {
                // original logic for placing phase without move allowed
                theirMillsCount = pos.potential_mills_count(
                    to, ~pos.side_to_move());
                cur->value += RATING_BLOCK_ONE_MILL * theirMillsCount;
            } else if (pos.get_phase() == Phase::moving ||
                       (pos.get_phase() == Phase::placing &&
                        rule.mayMoveInPlacingPhase)) {
                // logic for moving phase or placing phase with move allowed
                theirMillsCount = pos.potential_mills_count(
                    to, ~pos.side_to_move());

                if (theirMillsCount) {
                    ourPieceCount = theirPiecesCount = markedCount =
                        emptyCount = 0;

                    pos.surrounded_pieces_count(to, ourPieceCount,
                                                theirPiecesCount, markedCount,
                                                emptyCount);

                    if (to % 2 == 0 && theirPiecesCount == 3) {
                        cur->value += RATING_BLOCK_ONE_MILL * theirMillsCount;
                    } else if (to % 2 == 1 && theirPiecesCount == 2) {
                        cur->value += RATING_BLOCK_ONE_MILL * theirMillsCount;
                    }
                }
            }

            // cur->value += markedCount;  // placing phrase, place nearby
            // marked point

            // Cardinal-point bonus: the four orthogonal crossing points on the
            // middle ring (d6, f4, d2, b4) stay strategically valuable in all
            // variants, because they link two independent mill directions.
            if (Position::is_center_cardinal_square(to)) {
                cur->value += RATING_CARDINAL_SQUARE;
            }

            // If has Diagonal Lines, black 2nd move place star point is as
            // important as close mill (TODO)
            if ((rule.hasDiagonalLines || gameOptions.getAlgorithm() == 3) &&
                pos.count<ON_BOARD>(BLACK) < 2 && // patch: only when black 2nd
                // move
                Position::is_star_square(static_cast<Square>(m))) {
                cur->value += RATING_STAR_SQUARE;
            }
        } else {
            // Remove
            ourPieceCount = theirPiecesCount = markedCount = emptyCount = 0;

            pos.surrounded_pieces_count(to, ourPieceCount, theirPiecesCount,
                                        markedCount, emptyCount);

            if (ourMillsCount > 0) {
                // remove point is in our mill
                // cur->value += RATING_REMOVE_ONE_MILL * ourMillsCount;

                if (theirPiecesCount == 0) {
                    // if remove point nearby has no their piece, preferred.
                    cur->value += 1;
                    if (ourPieceCount > 0) {
                        // if remove point nearby our piece, preferred
                        cur->value += ourPieceCount;
                    }
                }
            }

            // remove point is in their mill
            theirMillsCount = pos.potential_mills_count(to,
                                                        ~pos.side_to_move());
            if (theirMillsCount) {
                if (theirPiecesCount >= 2) {
                    // if nearby their piece, prefer do not remove
                    cur->value -= theirPiecesCount;

                    if (ourPieceCount == 0) {
                        // if nearby has no our piece, more prefer do not remove
                        cur->value -= 1;
                    }
                }
            }

            // Feeder-piece bonus: prefer removing the opponent's piece that
            // currently belongs to two or more of their mills (the "common
            // piece" linking dual threats). This implements the strategy-guide
            // advice on "which piece to take" - prioritise the piece most
            // inconvenient for the opponent to lose.
            if (theirMillsCount >= 2) {
                cur->value += RATING_REMOVE_FEEDER;
            }

            // Cardinal-point removal bonus: opponent's cardinal-point pieces
            // are harder to replace; removing them is preferred.
            if (Position::is_center_cardinal_square(to)) {
                cur->value += RATING_CARDINAL_SQUARE;
            }

            // prefer remove piece that mobility is strong
            cur->value += emptyCount;
        }
#endif // !SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGE
    }

    // Historical note: commit 81cc73f1a (2024-07-03) added
    //   if (!shouldFocusOnBlockingPaths()) { cur->value = -cur->value; }
    // here, intending to gate the scoring direction on that flag.  However,
    // the loop was then using a MOVE_NONE sentinel, so at this point cur
    // pointed to the sentinel entry, not any real move. The write therefore
    // always affected only the sentinel and had zero effect on sort order.
    // When the loop was later converted to the range-based [moves, endMoves)
    // form, cur became endMoves (one-past-the-end), turning the write into
    // undefined behaviour.  The line is removed: the scoring direction is
    // already handled correctly by the positive/negative accounting inside
    // the loop body.
}

/// MovePicker::next_move() is the most important method of the MovePicker
/// class. It returns a new pseudo legal move every time it is called until
/// there are no more moves left, picking the move with the highest score from a
/// list of generated moves.
template <GenType Type>
Move MovePicker::next_move()
{
    endMoves = generate<Type>(pos, moves);
    moveCount = static_cast<int>(endMoves - moves);

    score<Type>();
    partial_insertion_sort(moves, endMoves, INT_MIN);

    return *moves;
}

template Move MovePicker::next_move<LEGAL>();
template Move MovePicker::next_move<PLACE>();
template Move MovePicker::next_move<MOVE>();
template Move MovePicker::next_move<REMOVE>();
