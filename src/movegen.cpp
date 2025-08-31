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
                    *cur++ = make_move(from, to);
                }
            }
        } else {
            // Generate standard moves based on direction vectors
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

                    *cur++ = make_move(from, to);
                }
            }
        }
    }

    return cur;
}

/// generate<PLACE> generates all places.
/// For Zhuolu Chess, generates separate moves for each available special piece.
/// Returns a pointer to the end of the move list.
template <>
ExtMove *generate<PLACE>(Position &pos, ExtMove *moveList)
{
    const Color us = pos.side_to_move();
    ExtMove *cur = moveList;

    if (pos.piece_in_hand_count(us) == 0) {
        return cur;
    }

    // For Zhuolu Chess, generate moves for each special piece type
    if (rule.zhuoluMode) {
        // Get available special pieces for current player
        const uint16_t availableMask = pos.get_available_special_pieces_mask(
            us);

        for (auto s : MoveList<LEGAL>::movePriorityList) {
            if (!pos.get_board()[s]) {
                // Generate moves for each available special piece
                // No heuristic filtering - let search algorithm decide
                for (int pieceType = 0; pieceType < 15; ++pieceType) {
                    if (availableMask & (1 << pieceType)) {
                        // Check basic placement validity only
                        if (pos.can_place_special_piece_at(
                                static_cast<SpecialPieceType>(pieceType), s)) {
                            *cur++ = make_special_place_move(s, pieceType);
                        }
                    }
                }

                // Always generate normal piece placement as an option
                // Let search algorithm decide between special and normal pieces
                *cur++ = make_special_place_move(s, 15); // 15 = NORMAL_PIECE
            }
        }
    } else {
        // Standard Nine Men's Morris - only normal pieces
        for (auto s : MoveList<LEGAL>::movePriorityList) {
            if (!pos.get_board()[s]) {
                *cur++ = static_cast<Move>(s);
            }
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

    // Debug output for Zhuolu mode
    if (rule.zhuoluMode) {
        debugPrintf("[REMOVE DEBUG] us=%d, them=%d, removeColor=%d, "
                    "removeOwnPieces=%s\n",
                    us, them, removeColor, removeOwnPieces ? "true" : "false");
        debugPrintf("[REMOVE DEBUG] pieceToRemoveCount[us]=%d\n",
                    pos.pieceToRemoveCount[us]);
        debugPrintf("[REMOVE DEBUG] is_stalemate_removal=%s, "
                    "is_all_in_mills=%s\n",
                    pos.is_stalemate_removal() ? "true" : "false",
                    pos.is_all_in_mills(removeColor) ? "true" : "false");
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
                    *cur++ = static_cast<Move>(-s);
                }
                // If removing own pieces, allow removal without adjacency
                else if (removeOwnPieces) {
                    *cur++ = static_cast<Move>(-s);
                }
            }
        }

        return cur;
    }

    // Handle removal when all opponent's pieces are in mills
    if (pos.is_all_in_mills(removeColor)) {
        if (rule.zhuoluMode) {
            debugPrintf("[REMOVE DEBUG] All pieces in mills - checking "
                        "squares\n");
        }
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            Square s = MoveList<LEGAL>::movePriorityList[i];

            // Check if the square has a piece of the color to remove
            if (pos.get_board()[s] & make_piece(removeColor)) {
                if (rule.zhuoluMode) {
                    debugPrintf("[REMOVE DEBUG] Adding remove move for square "
                                "%d\n",
                                s);
                }
                *cur++ = static_cast<Move>(-s);
            }
        }
        if (rule.zhuoluMode) {
            debugPrintf("[REMOVE DEBUG] Generated %d moves (all in mills)\n",
                        (int)(cur - moveList));
        }
        return cur;
    }

    // Handle general removal (not all in mills)
    if (rule.zhuoluMode) {
        debugPrintf("[REMOVE DEBUG] General removal - checking squares\n");
    }
    for (int i = SQUARE_NB - 1; i >= 0; i--) {
        const Square s = MoveList<LEGAL>::movePriorityList[i];

        // Check if the square has a piece of the color to remove
        if (pos.get_board()[s] & make_piece(removeColor)) {
            // If the rule allows removing from mills always
            // or the piece is not part of a potential mill, allow removal
            if (rule.mayRemoveFromMillsAlways ||
                !pos.potential_mills_count(s, NOBODY)) {
                if (rule.zhuoluMode) {
                    debugPrintf("[REMOVE DEBUG] Adding general remove move for "
                                "square %d\n",
                                s);
                }
                *cur++ = static_cast<Move>(-s);
            } else if (rule.zhuoluMode) {
                debugPrintf("[REMOVE DEBUG] Cannot remove square %d (in "
                            "mill)\n",
                            s);
            }
        }
    }

    if (rule.zhuoluMode) {
        debugPrintf("[REMOVE DEBUG] Generated %d moves total\n",
                    (int)(cur - moveList));
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
