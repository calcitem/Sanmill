// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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

    for (cur = moves; cur->move != MOVE_NONE; cur++) {
        Move m = cur->move;
        
        // Give TT move the highest priority
        if (m == ttMove) {
            cur->value = RATING_TT;
            continue;
        }

        const Square to = to_sq(m);
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

            // prefer remove piece that mobility is strong
            cur->value += emptyCount;
        }
#endif // !SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGE
    }

    if (!pos.shouldFocusOnBlockingPaths()) {
        cur->value = -cur->value;
    }
}

// Helper function for selecting moves based on a predicate
template<typename Pred>
Move MovePicker::select(Pred filter) {
    for (; cur < endMoves; ++cur) {
        if (*cur != ttMove && filter()) {
            return *cur++;
        }
    }
    return MOVE_NONE;
}

// Initialize capture moves
void MovePicker::init_captures() {
    if (pos.get_action() == Action::remove) {
        endMoves = generate<REMOVE>(pos, moves);
    } else {
        // For Mill game, "captures" are moves that form mills (tactical moves)
        endMoves = generate<LEGAL>(pos, moves);
    }
    
    cur = endBadCaptures = moves;
    endCaptures = endMoves;
    moveCount = static_cast<int>(endMoves - moves);
    
    score<LEGAL>();
    partial_insertion_sort(cur, endMoves, std::numeric_limits<int>::min());
}

// Initialize quiet moves  
void MovePicker::init_quiets() {
    endMoves = generate<LEGAL>(pos, moves);
    cur = endCaptures;
    moveCount = static_cast<int>(endMoves - moves);
    
    score<LEGAL>();
    partial_insertion_sort(cur, endMoves, -10000); // Threshold for "good" quiet moves
}

/// MovePicker::next_move_legacy() - legacy implementation for backward compatibility
template <GenType Type>
Move MovePicker::next_move_legacy()
{
    endMoves = generate<Type>(pos, moves);
    moveCount = static_cast<int>(endMoves - moves);

    score<Type>();
    partial_insertion_sort(moves, endMoves, INT_MIN);

    return *moves;
}

/// MovePicker::next_move() is the most important method of the MovePicker
/// class. It returns a new pseudo legal move every time it is called until
/// there are no more moves left, picking the move with the highest score from a
/// list of generated moves.
Move MovePicker::next_move()
{
    constexpr int goodQuietThreshold = -5000;

top:
    switch (stage) {
    case MAIN_TT:
    case QSEARCH_TT:
        ++stage;
        if (ttMove != MOVE_NONE) {
            return ttMove;
        }
        goto top;

    case CAPTURE_INIT:
    case QCAPTURE_INIT:
        init_captures();
        ++stage;
        goto top;

    case GOOD_CAPTURE:
        // For Mill game, prioritize mill-forming moves
        if (select([&]() {
            // Mill-forming moves or high-value tactical moves
            return cur->value > RATING_BLOCK_ONE_MILL - 1;
        })) {
            return *(cur - 1);
        }
        
        // Prepare for quiet moves
        cur = endCaptures;
        ++stage;
        goto top;

    case QUIET_INIT:
        if (stage == QUIET_INIT) {
            init_quiets();
        }
        ++stage;
        // fallthrough

    case GOOD_QUIET:
        if (select([&]() { return cur->value > goodQuietThreshold; })) {
            return *(cur - 1);
        }
        
        // Prepare for bad captures
        cur = moves;
        endMoves = endBadCaptures;
        ++stage;
        // fallthrough

    case BAD_CAPTURE:
        if (select([]() { return true; })) {
            return *(cur - 1);
        }
        
        // Prepare for bad quiets
        cur = endCaptures;
        endMoves = generate<LEGAL>(pos, moves) - (endCaptures - moves);
        ++stage;
        // fallthrough

    case BAD_QUIET:
        return select([&]() { return cur->value <= goodQuietThreshold; });

    case QCAPTURE:
        return select([]() { return true; });
    }

    return MOVE_NONE;
}

// Explicit instantiations for legacy functions
template Move MovePicker::next_move_legacy<LEGAL>();
template Move MovePicker::next_move_legacy<PLACE>();
template Move MovePicker::next_move_legacy<MOVE>();
template Move MovePicker::next_move_legacy<REMOVE>();