// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movegen.cpp

#include "movegen.h"
#include "mills.h"
#include "position.h"

/// generate<MOVE> generates all moves.
/// Returns a pointer to the end of the move moves.
template <>
ExtMove *generate<MOVE>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    if (pos.phase == Phase::placing && !rule.mayMoveInPlacingPhase) {
        return cur;
    }

    const int pieceOnBoardCount = pos.piece_on_board_count(pos.side_to_move());
    Piece *board = pos.get_board();

    // Iterate over all squares in reverse priority order
    // Move piece that location weak first
    for (auto i = SQUARE_NB - 1; i >= 0; --i) {
        const Square from = MoveList<LEGAL>::movePriorityList[i];

        // Skip if no piece of the current side to move
        if (!(pos.board[from] & make_piece(pos.sideToMove))) {
            continue;
        }

        bool restrictRepeatedMillsFormation =
            rule.restrictRepeatedMillsFormation &&
            (from == pos.lastMillToSquare[pos.sideToMove]);

        // Special condition to generate "fly" moves
        if (rule.mayFly && pieceOnBoardCount <= rule.flyPieceCount &&
            pos.pieceInHandCount[pos.side_to_move()] == 0) {
            for (Square to = SQ_BEGIN; to < SQ_END; ++to) {
                if (!board[to]) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = make_move(from, to);
                }
            }
        } else {
            // Generate standard adjacent moves
            for (auto direction = MD_BEGIN; direction < MD_NB; ++direction) {
                const Square to =
                    MoveList<LEGAL>::adjacentSquares[from][direction];
                if (to && !board[to]) {
                    if (restrictRepeatedMillsFormation) {
                        // Check if form a mill
                        if (pos.potential_mills_count(to, pos.side_to_move(),
                                                      from) > 0 &&
                            pos.mills_count(from) > 0) {
                            continue;
                        }
                    }

                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = make_move(from, to);
                }
            }

            // Optionally generate leap moves when leap capture is enabled.
            // Leap works in moving phase, or in placing phase when
            // mayMoveInPlacingPhase is enabled. We scan candidate lines
            // that include 'from' and an empty 'to'. This is a limited scan
            // to avoid a full-board O(N^2) sweep.
            const bool leapAllowed = rule.leapCapture.enabled &&
                                     ((pos.phase == Phase::moving &&
                                       rule.leapCapture.inMovingPhase) ||
                                      (pos.phase == Phase::placing &&
                                       rule.mayMoveInPlacingPhase &&
                                       rule.leapCapture.inPlacingPhase)) &&
                                     pos.piece_in_hand_count(
                                         pos.side_to_move()) == 0;

            if (leapAllowed) {
                auto tryAddLeap = [&](Square a, Square mid, Square b) {
                    if (!a || !mid || !b)
                        return;
                    if (a == from && !board[b] &&
                        board[mid] & make_piece(~pos.side_to_move())) {
                        std::vector<Square> captured;
                        if (pos.checkLeapCapture(b, pos.side_to_move(),
                                                 captured, from)) {
                            assert(cur < moveList + MAX_MOVES);
                            *cur++ = make_move(from, b);
                        }
                    } else if (b == from && !board[a] &&
                               board[mid] & make_piece(~pos.side_to_move())) {
                        std::vector<Square> captured;
                        if (pos.checkLeapCapture(a, pos.side_to_move(),
                                                 captured, from)) {
                            assert(cur < moveList + MAX_MOVES);
                            *cur++ = make_move(from, a);
                        }
                    }
                };

                // Check three-point lines (they model 3-in-line geometry)
                for (const auto &line : kThreePointSquareEdgeLines) {
                    tryAddLeap(line[0], line[1], line[2]);
                }
                for (const auto &line : kThreePointCrossLines) {
                    tryAddLeap(line[0], line[1], line[2]);
                }
                if (rule.hasDiagonalLines && rule.leapCapture.onDiagonalLines) {
                    for (const auto &line : kThreePointDiagonalLines) {
                        tryAddLeap(line[0], line[1], line[2]);
                    }
                }
            }
        }
    }

    return cur;
}

/// generate<PLACE> generates all places.
/// Returns a pointer to the end of the move list.
template <>
ExtMove *generate<PLACE>(Position &pos, ExtMove *moveList)
{
    const Color us = pos.side_to_move();
    ExtMove *cur = moveList;

    if (pos.piece_in_hand_count(us) == 0) {
        return cur;
    }

    for (auto s : MoveList<LEGAL>::movePriorityList) {
        if (!pos.get_board()[s]) {
            assert(cur < moveList + MAX_MOVES);
            *cur++ = static_cast<Move>(s);
        }
    }

    return cur;
}

/// generate<REMOVE> generates all removes.
/// Returns a pointer to the end of the move list.
template <>
ExtMove *generate<REMOVE>(Position &pos, ExtMove *moveList)
{
    const Color us = pos.side_to_move();
    const Color them = ~us;

    // Determine if we need to remove our own pieces based on pieceToRemoveCount
    bool removeOwnPieces = pos.pieceToRemoveCount[us] < 0;

    // Set the color of pieces to remove: own or opponent's
    const Color removeColor = removeOwnPieces ? us : them;

    ExtMove *cur = moveList;

    // Fast path: Check if any capture (custodian/intervention/leap) is active
    // Only read related fields if at least one removal count is non-zero
    const int custodianCount = pos.custodianRemovalCount[us];
    const int interventionCount = pos.interventionRemovalCount[us];
    const int leapCount = pos.leapRemovalCount[us];
    const int captureCount = custodianCount + interventionCount + leapCount;

    Bitboard combinedTargets = 0;

    // Only process captures if capture count is positive
    if (captureCount > 0) {
        // Compute combined targets for all non-mill captures
        combinedTargets = pos.custodianCaptureTargets[us] |
                          pos.interventionCaptureTargets[us] |
                          pos.leapCaptureTargets[us];

        if (combinedTargets != 0) {
            const Piece themPiece = make_piece(them);
            for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
                if ((combinedTargets & square_bb(s)) &&
                    (pos.get_board()[s] & themPiece)) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                }
            }
            // If total removals are not greater than captureCount,
            // only capture targets are allowed this turn.
            const int totalRemovals = pos.pieceToRemoveCount[us];
            if (totalRemovals <= captureCount) {
                return cur;
            }
            // Otherwise, continue to generate regular removes below,
            // excluding the already-added capture targets.
        }
    }

    // Handle stalemate removal
    if (pos.is_stalemate_removal()) {
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            Square s = MoveList<LEGAL>::movePriorityList[i];

            // Check if the square has a piece of the color to remove
            if (pos.get_board()[s] & make_piece(removeColor)) {
                // If removing opponent's pieces, check adjacency to 'us'
                // If removing own pieces, adjacency check may differ or be
                // omitted
                if (!removeOwnPieces && pos.is_adjacent_to(s, us)) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                }
                // If removing own pieces, allow removal without adjacency
                else if (removeOwnPieces) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }

        return cur;
    }

    // 2) Handle removal when all opponent's pieces are in mills
    if (pos.is_all_in_mills(removeColor)) {
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            Square s = MoveList<LEGAL>::movePriorityList[i];

            // Check if the square has a piece of the color to remove
            if (pos.get_board()[s] & make_piece(removeColor)) {
                assert(cur < moveList + MAX_MOVES);
                *cur++ = static_cast<Move>(-s);
            }
        }
        return cur;
    }

    // Handle general removal (not all in mills)
    const Piece removeColorPiece = make_piece(removeColor);
    const bool checkMills = !rule.mayRemoveFromMillsAlways;

    // Optimize: Only check combinedTargets if any non-mill capture is active
    if (combinedTargets != 0) {
        // Path with custodian/intervention: skip already-captured targets
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            const Square s = MoveList<LEGAL>::movePriorityList[i];

            // Skip if this is already a custodian capture target
            if (combinedTargets & square_bb(s)) {
                continue;
            }

            // Check if the square has a piece of the color to remove
            if (pos.get_board()[s] & removeColorPiece) {
                // If the rule allows removing from mills always
                // or the piece is not part of a potential mill, allow removal
                if (!checkMills || !pos.potential_mills_count(s, NOBODY)) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }
    } else {
        // Fast path: No non-mill capture, avoid bitboard checks
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            const Square s = MoveList<LEGAL>::movePriorityList[i];

            // Check if the square has a piece of the color to remove
            if (pos.get_board()[s] & removeColorPiece) {
                // If the rule allows removing from mills always
                // or the piece is not part of a potential mill, allow removal
                if (!checkMills || !pos.potential_mills_count(s, NOBODY)) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }
    }

    return cur;
}

/// generate<LEGAL> generates all the legal moves in the given position

template <>
ExtMove *generate<LEGAL>(Position &pos, ExtMove *moveList)
{
    ExtMove *cur = moveList;

    switch (pos.get_action()) {
    case Action::select:
    case Action::place:
        // Generate both PLACE and MOVE actions if the phase is placing
        if (pos.get_phase() == Phase::placing ||
            pos.get_phase() == Phase::ready) {
            cur = generate<PLACE>(pos, moveList);
            return generate<MOVE>(pos, cur);
        }

        // Generate MOVE actions if the phase is moving
        if (pos.get_phase() == Phase::moving) {
            return generate<MOVE>(pos, moveList);
        }

        break;

    case Action::remove:
        return generate<REMOVE>(pos, moveList);

    case Action::none:
        break;
    }

    return cur;
}

template <>
void MoveList<LEGAL>::create()
{
    Mills::adjacent_squares_init();
}

template <>
void MoveList<LEGAL>::shuffle()
{
    Mills::move_priority_list_shuffle();
}
