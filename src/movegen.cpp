// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movegen.cpp

#include "movegen.h"
#include "bitboard.h"
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

    // Use bitboard optimization: only iterate over squares with pieces
    Bitboard ourPieces = pos.pieces(pos.side_to_move());

    // Early exit if no pieces to move
    if (!ourPieces) {
        return cur;
    }

    // Performance optimization: if we have few pieces (endgame),
    // use direct bitboard iteration for maximum efficiency
    // Otherwise, maintain priority order for consistent move ordering
    const bool usePureBitboardIteration = (pieceOnBoardCount <= 6);

    if (usePureBitboardIteration) {
        // Pure bitboard iteration - most efficient for sparse positions
        while (ourPieces) {
            const Square from = pop_lsb(ourPieces);

            bool restrictRepeatedMillsFormation =
                rule.restrictRepeatedMillsFormation &&
                (from == pos.lastMillToSquare[pos.sideToMove]);

            // Special condition to generate "fly" moves
            if (rule.mayFly && pieceOnBoardCount <= rule.flyPieceCount &&
                pos.pieceInHandCount[pos.side_to_move()] == 0) {
                for (Square to = SQ_BEGIN; to < SQ_END; ++to) {
                    if (!board[to]) {
                        *cur++ = make_move(from, to);
                    }
                }
            } else {
                // Generate standard moves based on direction vectors
                for (auto direction = MD_BEGIN; direction < MD_NB;
                     ++direction) {
                    const Square to =
                        MoveList<LEGAL>::adjacentSquares[from][direction];
                    if (to && !board[to]) {
                        if (restrictRepeatedMillsFormation) {
                            // Check if form a mill
                            if (pos.potential_mills_count(
                                    to, pos.side_to_move(), from) > 0 &&
                                pos.mills_count(from) > 0) {
                                continue;
                            }
                        }

                        *cur++ = make_move(from, to);
                    }
                }
            }
        }
    } else {
        // Priority-based iteration with bitboard filtering - maintains move
        // ordering
        for (auto i = SQUARE_NB - 1; i >= 0; --i) {
            const Square from = MoveList<LEGAL>::movePriorityList[i];

            // Skip if no piece of the current side to move (bitboard check)
            if (!(ourPieces & square_bb(from))) {
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
                        *cur++ = make_move(from, to);
                    }
                }
            } else {
                // Generate standard moves based on direction vectors
                for (auto direction = MD_BEGIN; direction < MD_NB;
                     ++direction) {
                    const Square to =
                        MoveList<LEGAL>::adjacentSquares[from][direction];
                    if (to && !board[to]) {
                        if (restrictRepeatedMillsFormation) {
                            // Check if form a mill
                            if (pos.potential_mills_count(
                                    to, pos.side_to_move(), from) > 0 &&
                                pos.mills_count(from) > 0) {
                                continue;
                            }
                        }

                        *cur++ = make_move(from, to);
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

    // Use bitboard optimization for piece removal
    Bitboard targetPieces = pos.pieces(removeColor);

    // Early exit if no pieces to remove
    if (!targetPieces) {
        return cur;
    }

    // Performance optimization: use direct bitboard iteration for sparse
    // positions
    const int targetPieceCount = pos.piece_on_board_count(removeColor);
    const bool usePureBitboardIteration = (targetPieceCount <= 6);

    if (usePureBitboardIteration) {
        // Pure bitboard iteration - most efficient for sparse positions
        if (pos.is_stalemate_removal()) {
            // Handle stalemate removal
            while (targetPieces) {
                const Square s = pop_lsb(targetPieces);

                // If removing opponent's pieces, check adjacency to 'us'
                // If removing own pieces, adjacency check may differ or be
                // omitted
                if (!removeOwnPieces && pos.is_adjacent_to(s, us)) {
                    *cur++ = static_cast<Move>(-s);
                }
                // If removing own pieces, allow removal without adjacency
                else if (removeOwnPieces) {
                    *cur++ = static_cast<Move>(-s);
                }
            }
        } else if (pos.is_all_in_mills(removeColor)) {
            // Handle removal when all opponent's pieces are in mills
            while (targetPieces) {
                const Square s = pop_lsb(targetPieces);
                *cur++ = static_cast<Move>(-s);
            }
        } else {
            // Handle general removal (not all in mills)
            while (targetPieces) {
                const Square s = pop_lsb(targetPieces);

                // If the rule allows removing from mills always
                // or the piece is not part of a potential mill, allow removal
                if (rule.mayRemoveFromMillsAlways ||
                    !pos.potential_mills_count(s, NOBODY)) {
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }
    } else {
        // Priority-based iteration with bitboard filtering - maintains move
        // ordering
        if (pos.is_stalemate_removal()) {
            // Handle stalemate removal
            for (int i = SQUARE_NB - 1; i >= 0; i--) {
                Square s = MoveList<LEGAL>::movePriorityList[i];

                // Skip if no piece of the target color (bitboard check)
                if (!(targetPieces & square_bb(s))) {
                    continue;
                }

                // If removing opponent's pieces, check adjacency to 'us'
                // If removing own pieces, adjacency check may differ or be
                // omitted
                if (!removeOwnPieces && pos.is_adjacent_to(s, us)) {
                    *cur++ = static_cast<Move>(-s);
                }
                // If removing own pieces, allow removal without adjacency
                else if (removeOwnPieces) {
                    *cur++ = static_cast<Move>(-s);
                }
            }
        } else if (pos.is_all_in_mills(removeColor)) {
            // Handle removal when all opponent's pieces are in mills
            for (int i = SQUARE_NB - 1; i >= 0; i--) {
                Square s = MoveList<LEGAL>::movePriorityList[i];

                // Skip if no piece of the target color (bitboard check)
                if (!(targetPieces & square_bb(s))) {
                    continue;
                }

                *cur++ = static_cast<Move>(-s);
            }
        } else {
            // Handle general removal (not all in mills)
            for (int i = SQUARE_NB - 1; i >= 0; i--) {
                const Square s = MoveList<LEGAL>::movePriorityList[i];

                // Skip if no piece of the target color (bitboard check)
                if (!(targetPieces & square_bb(s))) {
                    continue;
                }

                // If the rule allows removing from mills always
                // or the piece is not part of a potential mill, allow removal
                if (rule.mayRemoveFromMillsAlways ||
                    !pos.potential_mills_count(s, NOBODY)) {
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
