// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// evaluate.cpp

#include "evaluate.h"
#include "bitboard.h"
#include "option.h"
#include "thread.h"
#include "position.h"
#include "perfect_api.h"

namespace {

class Evaluation
{
public:
    Evaluation() = delete;

    explicit Evaluation(Position &p) noexcept
        : pos(p)
    { }

    Evaluation &operator=(const Evaluation &) = delete;
    Value value() const;

private:
    Position &pos;

    // Count the number of "center cardinal" squares (middle-ring crossing
    // points) occupied by the given side.  Cardinal squares are the most
    // valuable positional assets per the strategy guide - they connect two
    // mill lines and are hardest to replace.  O(1), pure bit-lookup.
    int cardinal_count(Color c) const noexcept;

    // Count the number of potential-mill lines (lines where the side already
    // has 2 pieces and the third square is empty, i.e. one move from a mill).
    // O(board), uses the existing mill table.
    int live_mill_candidates(Color c) const;
};

int Evaluation::cardinal_count(Color c) const noexcept
{
    int n = 0;
    if (pos.color_on(SQ_16) == c)
        ++n;
    if (pos.color_on(SQ_18) == c)
        ++n;
    if (pos.color_on(SQ_20) == c)
        ++n;
    if (pos.color_on(SQ_22) == c)
        ++n;
    return n;
}

int Evaluation::live_mill_candidates(Color c) const
{
    // Iterate over all board squares; for each square occupied by `c` ask
    // how many mills it could close if we "pretend" placing there (from = SQ_0
    // means no source square, i.e. the piece is already there).  We only count
    // lines where the square is indeed occupied, so we use the two-piece +
    // empty-third pattern: for each occupied square s, count potential mills
    // that are one step away.
    //
    // Implementation: for each square s that is occupied by c, count the mills
    // that would be formed by a hypothetical piece at s (which is already
    // there) - this equals the number of lines containing s where the other
    // two squares are also occupied by c (i.e. already a mill) OR where
    // exactly one of the other two squares is empty and one is c. To keep
    // things simple and consistent with the rest of the codebase we count
    // "lines with exactly 2 of our pieces where the third is empty":
    int n = 0;
    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        if (pos.color_on(s) != c)
            continue;
        // Count potential mills the piece at s could contribute to if the
        // missing square were filled.  potential_mills_count(to, c) asks how
        // many mills would be formed by placing at `to`; we use it to probe
        // each adjacent/missing square.
        //
        // Simpler approach: scan all mill lines that include s; if the line
        // has exactly 2 of c's pieces (one of which is s) and one empty
        // square, that is a live candidate.
        const Bitboard *mt = Position::millTableBB[s];
        const Bitboard bc = pos.byColorBB[c];
        const Bitboard empty = ~(pos.byTypeBB[ALL_PIECES]);
        for (int d = 0; d < LD_NB; ++d) {
            Bitboard line = mt[d];
            if (!line)
                continue;
            // Among the other two squares in this line, one is c's piece
            // and one is empty -> together with s that gives 2-of-3 filled,
            // i.e. a live mill candidate (one step from completion).
            Bitboard lineC = bc & line;
            Bitboard lineEmpty = empty & line;
            if (popcount(lineC) == 1 && popcount(lineEmpty) == 1) {
                // Respect one-time-use mill rules: if the completed line has
                // already been consumed by this side, it is no longer a live
                // candidate and should not be counted by the evaluator.
                const Bitboard completedLine = square_bb(s) | line;
                if (!rule.oneTimeUseMill ||
                    (completedLine & pos.formedMillsBB[c]) != completedLine) {
                    ++n;
                }
            }
        }
    }
    // Each line is counted twice (once per each of the two pieces), so halve.
    return n / 2;
}

// Evaluation::value() is the main function of the class. It computes the
// various parts of the evaluation and returns the value of the position from
// the point of view of the side to move.

Value Evaluation::value() const
{
    Value value = VALUE_ZERO;

    int pieceInHandDiffCount;
    int pieceOnBoardDiffCount;
    const int pieceToRemoveDiffCount = pos.piece_to_remove_count(WHITE) -
                                       pos.piece_to_remove_count(BLACK);

    switch (pos.get_phase()) {
    case Phase::none:
    case Phase::ready:
        break;

    case Phase::placing:
        if (rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
            if (pos.get_action() == Action::remove) {
                value += VALUE_EACH_PIECE_NEEDREMOVE * pieceToRemoveDiffCount;
            } else {
                value += pos.mills_pieces_count_difference();
            }
            break;
        }
        [[fallthrough]];
    case Phase::moving:
        if (pos.shouldConsiderMobility()) {
            value += pos.get_mobility_diff();
        }

        if (!pos.shouldFocusOnBlockingPaths()) {
            pieceInHandDiffCount = pos.piece_in_hand_count(WHITE) -
                                   pos.piece_in_hand_count(BLACK);
            value += VALUE_EACH_PIECE_INHAND * pieceInHandDiffCount;

            pieceOnBoardDiffCount = pos.piece_on_board_count(WHITE) -
                                    pos.piece_on_board_count(BLACK);
            value += VALUE_EACH_PIECE_ONBOARD * pieceOnBoardDiffCount;

            if (pos.get_action() == Action::remove) {
                value += VALUE_EACH_PIECE_NEEDREMOVE * pieceToRemoveDiffCount;
            }

            // Cardinal-point control: each center-ring crossing square
            // controlled by us vs. them contributes a fractional positional
            // bonus (strategy guide sections 9.4 and 14.7). Scale is 1 per
            // square to
            // stay well below a full piece value (5).
            value += cardinal_count(WHITE) - cardinal_count(BLACK);

            // Live-mill candidate difference: having more "1-step-to-mill"
            // lines than the opponent is a positional advantage (strategy
            // guide sections 8.2 and 12.3). Weight = 1 to stay below a single
            // piece
            // value; the deeper search will amplify the effect.
            value += live_mill_candidates(WHITE) - live_mill_candidates(BLACK);
        }

        break;

    case Phase::gameOver:
        if (rule.pieceCount == 12 && (pos.piece_on_board_count(WHITE) +
                                          pos.piece_on_board_count(BLACK) >=
                                      SQUARE_NB)) {
            if (rule.boardFullAction == BoardFullAction::firstPlayerLose) {
                value -= VALUE_MATE;
            } else if (rule.boardFullAction == BoardFullAction::agreeToDraw) {
                value = VALUE_DRAW;
            } else {
                assert(0);
            }
        } else if (pos.get_action() == Action::select &&
                   pos.is_all_surrounded(pos.side_to_move()) &&
                   rule.stalemateAction ==
                       StalemateAction::endWithStalemateLoss) {
            const Value delta = pos.side_to_move() == WHITE ? -VALUE_MATE :
                                                              VALUE_MATE;
            value += delta;
        } else if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            value -= VALUE_MATE;
        } else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            value += VALUE_MATE;
        }

        break;
    }

    if (pos.side_to_move() == BLACK) {
        value = -value;
    }

#ifdef EVAL_DRAW_WHEN_NOT_KNOWN_WIN_IF_MAY_FLY
    if (pos.get_phase() == Phase::moving && rule.mayFly &&
        !rule.hasDiagonalLines) {
        int piece_on_board_count_future_white = pos.piece_on_board_count(WHITE);
        int piece_on_board_count_future_black = pos.piece_on_board_count(BLACK);

        if (pos.side_to_move() == WHITE) {
            piece_on_board_count_future_black -= pos.piece_to_remove_count(
                                                     WHITE) -
                                                 pos.piece_to_remove_count(
                                                     BLACK);
        }

        if (pos.side_to_move() == BLACK) {
            piece_on_board_count_future_white -= pos.piece_to_remove_count(
                                                     BLACK) -
                                                 pos.piece_to_remove_count(
                                                     WHITE);
            ;
        }

        // TODO(calcitem): flyPieceCount?
        if (piece_on_board_count_future_black == 3 ||
            piece_on_board_count_future_white == 3) {
            if (abs(value) < VALUE_KNOWN_WIN) {
                value = VALUE_DRAW;
            }
        }
    }
#endif

    return value;
}

} // namespace

/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(Position &pos)
{
    return Evaluation(pos).value();
}
