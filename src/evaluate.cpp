// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
};

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
