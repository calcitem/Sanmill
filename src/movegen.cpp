// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movegen.cpp

#include "movegen.h"
#include "mills.h"
#include "position.h"
#ifdef FLUTTER_UI
#include "base.h"
#endif

// Fallback LOGD definition if not available
#ifndef LOGD
#define LOGD(...) printf(__VA_ARGS__)
#endif

#include <cstdio>

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

                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = make_move(from, to);
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

    LOGD("generate<REMOVE>: us=%d, pieceToRemoveCount[us]=%d, "
         "removeOwnPieces=%d, removeColor=%d\n",
         us, pos.pieceToRemoveCount[us], removeOwnPieces, removeColor);

    const Bitboard custodianTargets = pos.custodianCaptureTargets[us];
    const int custodianCount = pos.custodianRemovalCount[us];
    const Bitboard interventionTargets = pos.interventionCaptureTargets[us];
    const int interventionCount = pos.interventionRemovalCount[us];

    const ActiveCaptureMode mode = pos.activeCaptureMode[us];
    const int pendingMill = pos.pendingMillRemovals[us];
    const int performed = pos.removalsPerformed[us];

    bool allowCustodian = false;
    bool allowIntervention = false;
    bool allowGeneral = false;

    LOGD("generate<REMOVE>: mode=%d, pendingMill=%d, performed=%d, "
         "custodianTargets=0x%llx, custodianCount=%d, "
         "interventionTargets=0x%llx, interventionCount=%d\n",
         static_cast<int>(mode), pendingMill, performed,
         static_cast<unsigned long long>(custodianTargets), custodianCount,
         static_cast<unsigned long long>(interventionTargets),
         interventionCount);

    if (!removeOwnPieces) {
        switch (mode) {
        case ActiveCaptureMode::none:
            allowCustodian = custodianTargets != 0;
            allowIntervention = interventionTargets != 0;
            allowGeneral = pendingMill > 0;
            break;
        case ActiveCaptureMode::custodian:
            if (custodianCount > 0) {
                allowCustodian = custodianTargets != 0;
            } else {
                allowGeneral = pendingMill > performed;
            }
            break;
        case ActiveCaptureMode::intervention:
            if (interventionCount > 0) {
                allowIntervention = interventionTargets != 0;
            } else {
                allowGeneral = pendingMill > performed;
            }
            break;
        case ActiveCaptureMode::mill:
            allowGeneral = pendingMill > performed;
            break;
        }
    }

    LOGD("generate<REMOVE>: allowCustodian=%d, allowIntervention=%d, "
         "allowGeneral=%d\n",
         allowCustodian, allowIntervention, allowGeneral);

    Bitboard specialTargets = 0;
    if (allowCustodian) {
        specialTargets |= custodianTargets;
    }
    if (allowIntervention) {
        specialTargets |= interventionTargets;
    }

    if (specialTargets) {
        for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
            const Bitboard mask = square_bb(s);
            if ((specialTargets & mask) &&
                (pos.get_board()[s] & make_piece(them))) {
                assert(cur < moveList + MAX_MOVES);
                *cur++ = static_cast<Move>(-s);
            }
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

    if (allowGeneral) {
        int movesAdded = 0;
        for (int i = SQUARE_NB - 1; i >= 0; i--) {
            const Square s = MoveList<LEGAL>::movePriorityList[i];
            const Bitboard mask = square_bb(s);

            if (specialTargets & mask) {
                continue;
            }

            if (pos.get_board()[s] & make_piece(removeColor)) {
                if (rule.mayRemoveFromMillsAlways ||
                    !pos.potential_mills_count(s, NOBODY)) {
                    assert(cur < moveList + MAX_MOVES);
                    *cur++ = static_cast<Move>(-s);
                    movesAdded++;
                }
            }
        }
        LOGD("generate<REMOVE>: allowGeneral=true, added %d general moves\n",
             movesAdded);
    }

    const int totalMoves = static_cast<int>(cur - moveList);
    LOGD("generate<REMOVE>: returning %d total moves\n", totalMoves);
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
