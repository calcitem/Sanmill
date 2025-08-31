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
    // Zhuolu-specific evaluation helpers
    Value valueZhuolu() const;
    static int weightForSpecialPiece(SpecialPieceType type) noexcept;
};

// Evaluation::value() is the main function of the class. It computes the
// various parts of the evaluation and returns the value of the position from
// the point of view of the side to move.

Value Evaluation::value() const
{
    Value value = VALUE_ZERO;

    // Shortcut: dedicated evaluation for Zhuolu Chess
    // This mode has different objectives and mechanics (special pieces,
    // abandoned squares, placement-only ending), so we use a tailored
    // static evaluation instead of the standard mill heuristics.
    if (rule.zhuoluMode) {
        Value v = valueZhuolu();
        if (pos.side_to_move() == BLACK)
            v = -v;
        return v;
    }

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

// Return a small integer weight for each special piece type.
// Numbers are intentionally conservative to keep total evaluation
// within the small Value range and to avoid overshadowing material.
int Evaluation::weightForSpecialPiece(SpecialPieceType type) noexcept
{
    switch (type) {
    case HUANG_DI:
        return 4; // Strong conversion impact
    case YAN_DI:
        return 3; // Strong local removal impact
    case CHI_YOU:
        return 2; // Combat-oriented advantage
    case CHANG_XIAN:
        return 2; // Flexible removal potential
    case XING_TIAN:
        return 2; // Positional pressure
    case ZHU_RONG:
        return 2; // Consecutive removal potential
    case YU_SHI:
        return 2; // Control capability
    case FENG_HOU:
        return 1; // Marked-square synergy
    case GONG_GONG:
        return 1; // Marked-square synergy
    case NU_WA:
        return 2; // Creation/protection flavor
    case FU_XI:
        return 2; // Creation/protection flavor
    case KUA_FU:
        return 2; // Removal immunity
    case YING_LONG:
        return 2; // Mobility/strike potential
    case FENG_BO:
        return 1; // Minor control
    case NORMAL_PIECE:
    default:
        return 1; // Default mild bonus if ever encountered
    }
}

// Zhuolu-mode evaluation
// Focus areas:
// 1) Captured pieces: game ends after placing, winner by captured count.
// 2) Pending removals: immediate tactical swing.
// 3) Formed mills: still reflect opportunities (delayed/removal-based rules).
// 4) Special pieces on board: small, type-based positional/tactical bonus.
Value Evaluation::valueZhuolu() const
{
    Value value = VALUE_ZERO; // White-centric score; flip later if needed

    const int initialPieces = rule.pieceCount;

    const int whiteRemaining = pos.piece_on_board_count(WHITE) +
                               pos.piece_in_hand_count(WHITE);
    const int blackRemaining = pos.piece_on_board_count(BLACK) +
                               pos.piece_in_hand_count(BLACK);

    const int whiteCaptured = initialPieces - whiteRemaining;
    const int blackCaptured = initialPieces - blackRemaining;

    // Primary objective in Zhuolu: capture advantage
    // Positive value favors White
    value += (whiteCaptured - blackCaptured) * VALUE_EACH_PIECE;

    // Immediate tactical swing from pending removals
    const int pieceToRemoveDiffCount = pos.piece_to_remove_count(WHITE) -
                                       pos.piece_to_remove_count(BLACK);
    value += VALUE_EACH_PIECE_NEEDREMOVE * pieceToRemoveDiffCount;

    // Reflect formed mills (delayed removal or multi-removal rules may apply)
    // Keep the contribution light: this returns a small integer diff.
    if (pos.get_phase() == Phase::placing)
        value += pos.mills_pieces_count_difference();

    // Special pieces presence: sum small, type-based bonuses by owner
    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        SpecialPieceType sp = pos.special_piece_on(s);
        if (sp == NORMAL_PIECE)
            continue;

        const Color owner = pos.color_on(s);
        const int w = weightForSpecialPiece(sp);
        if (owner == WHITE)
            value += w;
        else if (owner == BLACK)
            value -= w;
    }

    // Abandoned squares (MARKED) synergy: pieces like FENG_HOU / GONG_GONG
    // can leverage marked squares during placement. Reward the side that has
    // such pieces on board (or at least present) with a small bonus per marked
    // square. Kept conservative to avoid overpowering material.
    int markedCount = 0;
    bool whiteHasMarkedSquareSynergy = false;
    bool blackHasMarkedSquareSynergy = false;

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        const Piece pc = pos.piece_on(s);
        if (pc == MARKED_PIECE)
            ++markedCount;

        // Detect presence of synergy pieces by scanning current board
        SpecialPieceType sp = pos.special_piece_on(s);
        if (sp == FENG_HOU || sp == GONG_GONG) {
            const Color owner = pos.color_on(s);
            if (owner == WHITE)
                whiteHasMarkedSquareSynergy = true;
            else if (owner == BLACK)
                blackHasMarkedSquareSynergy = true;
        }
    }

    if (markedCount > 0) {
        if (whiteHasMarkedSquareSynergy)
            value += markedCount; // +1 per marked square
        if (blackHasMarkedSquareSynergy)
            value -= markedCount; // -1 per marked square
    }

    // Extra tactical nudge for high-impact special pieces that are adjacent to
    // enemy pieces during placing (they often trigger immediate effects).
    // Keep the increment small and phase-aware to avoid instability.
    if (pos.get_phase() == Phase::placing) {
        for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
            const SpecialPieceType sp = pos.special_piece_on(s);
            if (sp == NORMAL_PIECE)
                continue;

            const Color owner = pos.color_on(s);
            if (owner == NOBODY)
                continue;

            // Count adjacent opponent pieces
            int adjOpp = 0;
            for (int d = MD_BEGIN; d < MD_NB; ++d) {
                // Note: MoveList adjacency table is used in
                // Position::is_adjacent_to. We reuse color_on on potential
                // neighbors safely via square range check.
                const Square nb = MoveList<LEGAL>::adjacentSquares[s][d];
                if (nb != SQ_0 && pos.color_on(nb) == ~owner)
                    ++adjOpp;
            }

            if (adjOpp == 0)
                continue;

            int bonus = 0;
            switch (sp) {
            case HUANG_DI: // Conversion around
                bonus = 2 * adjOpp;
                break;
            case YAN_DI: // Removal around
                bonus = 2 * adjOpp;
                break;
            case ZHU_RONG: // Consecutive removal potential
                bonus = 1 * adjOpp;
                break;
            default:
                bonus = 0;
                break;
            }

            if (bonus != 0) {
                if (owner == WHITE)
                    value += bonus;
                else
                    value -= bonus;
            }
        }
    }

    // If the game is already over (end of placing), push the score strongly
    // toward win/loss to stabilize search around terminal outcomes.
    if (pos.get_phase() == Phase::gameOver) {
        if (whiteCaptured > blackCaptured)
            value += VALUE_MATE; // White captured more -> White wins
        else if (blackCaptured > whiteCaptured)
            value -= VALUE_MATE; // Black captured more -> Black wins
        else
            value = VALUE_DRAW; // Equal captures
    }

    return value;
}

} // namespace

/// evaluate() is the evaluator for the outer world. It returns a static
/// evaluation of the position from the point of view of the side to move.

Value Eval::evaluate(Position &pos)
{
    return Evaluation(pos).value();
}
