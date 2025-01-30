// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_movegen.cpp

#include <gtest/gtest.h>
#include <algorithm>
#include <unordered_set>
#include "movegen.h"
#include "position.h"
#include "mills.h"
#include "rule.h"

namespace {

/// Helper: Convert an ExtMove array to a std::unordered_set<Move> for easy
/// searching.
std::unordered_set<Move> MovesToSet(const ExtMove *begin, const ExtMove *end)
{
    std::unordered_set<Move> moves;
    for (auto *cur = begin; cur < end; ++cur) {
        moves.insert(cur->move);
    }
    return moves;
}

TEST(MoveGenTest, PlaceGeneration_NoPiecesInHand_NoMoves)
{
    // Setup a position where sideToMove has 0 pieces in hand.
    Position pos;
    pos.phase = Phase::placing;
    pos.set_side_to_move(WHITE);
    pos.pieceInHandCount[WHITE] = 0; // no pieces to place
    // We also need to ensure the board is in a normal state.

    ExtMove moveList[MAX_MOVES];
    // Generate place moves
    auto *end = generate<PLACE>(pos, moveList);

    // Expect zero moves
    EXPECT_EQ(end - moveList, 0) << "If no pieces in hand, place generation "
                                    "must yield zero moves.";
}

TEST(MoveGenTest, PlaceGeneration_HasPiecesInHand)
{
    // Setup a position where sideToMove has 2 pieces in hand, empty board
    // So placing should be allowed on all board squares.
    Position pos;
    pos.phase = Phase::placing;
    pos.set_side_to_move(WHITE);
    pos.pieceInHandCount[WHITE] = 2;

    // By default, position initializes an empty board (24 squares).
    // We'll generate place moves now.
    ExtMove moveList[MAX_MOVES];
    auto *end = generate<PLACE>(pos, moveList);
    const int count = static_cast<int>(end - moveList);

    // Typically, there are 24 valid squares on the standard Nine Men’s Morris
    // board. So, we expect 24 place moves. Adjust if your code excludes squares
    // or has different logic.
    EXPECT_EQ(count, 24) << "All empty squares should be candidates for "
                            "placement.";

    // Let's confirm a known square is present among the generated moves, e.g.
    // SQ_8
    auto movesSet = MovesToSet(moveList, end);
    EXPECT_TRUE(movesSet.find(static_cast<Move>(SQ_8)) != movesSet.end())
        << "SQ_8 should be a valid place location for sideToMove if the board "
           "is empty.";
}

TEST(MoveGenTest, MoveGeneration_PhasePlacing_NoMayMoveInPlacing)
{
    // Suppose we are in placing phase and the rule "mayMoveInPlacingPhase" is
    // false. Then generate<MOVE> should produce no moves.
    rule.mayMoveInPlacingPhase = false;

    Position pos;
    pos.phase = Phase::placing;
    pos.set_side_to_move(WHITE);
    // Put a single piece for WHITE on the board.
    pos.put_piece(W_PIECE, SQ_8);

    ExtMove moveList[MAX_MOVES];
    auto *end = generate<MOVE>(pos, moveList);
    int count = static_cast<int>(end - moveList);

    EXPECT_EQ(count, 0) << "If phase=placing and mayMoveInPlacingPhase=false, "
                           "no slide moves allowed.";
}

TEST(MoveGenTest, MoveGeneration_PhaseMoving_MayFly)
{
    // If sideToMove has fewer or equal to 3 pieces, and mayFly=true,
    // we can 'fly' to any empty square.

    // Adjust rule to allow flying
    rule.mayFly = true;
    rule.flyPieceCount = 3;
    // Also allow moves in placing phase if needed, but here we set the phase to
    // moving.
    rule.mayMoveInPlacingPhase = true;

    Position pos;
    std::memset(&pos, 0, sizeof(pos));
    pos.phase = Phase::moving;
    pos.set_side_to_move(BLACK);

    // Suppose black has 3 pieces on board, meaning black can fly.
    pos.pieceOnBoardCount[BLACK] = 3;
    // Place them in arbitrary squares
    pos.put_piece(B_PIECE, SQ_8);
    pos.put_piece(B_PIECE, SQ_9);
    pos.put_piece(B_PIECE, SQ_10);

    // White pieces can be anything; not relevant, but let's just ensure
    // some squares remain free
    pos.pieceOnBoardCount[WHITE] = 0;

    // Generate move moves
    ExtMove moveList[MAX_MOVES];
    auto *end = generate<MOVE>(pos, moveList);
    int count = static_cast<int>(end - moveList);

    // If black can fly, each of black's 3 pieces can move to any empty square.
    // The board has 24 standard squares. 3 are occupied by black. 21 remain
    // free. Each of the 3 pieces can jump to those 21 squares => 3*21 = 63
    // possible moves. Adjust if your logic has special restrictions.
    EXPECT_EQ(count, 63) << "When sideToMove can fly, each piece can jump to "
                            "any empty square.";

    // Optionally, confirm a specific jump is in the set
    auto movesSet = MovesToSet(moveList, end);
    // For instance, check from SQ_8 to SQ_23 is included:
    Move flyMove = make_move(SQ_8, SQ_23);
    EXPECT_TRUE(movesSet.find(flyMove) != movesSet.end())
        << "Side can fly from SQ_8 to SQ_23 if the board is empty there.";
}

TEST(MoveGenTest, MoveGeneration_PhaseMoving_Slide)
{
    // If sideToMove has more than the flyPieceCount, we only generate adjacency
    // moves.

    // Setup rule: mayFly = true, but sideToMove has 4 pieces => no flying
    rule.mayFly = true;
    rule.flyPieceCount = 3;

    Position pos;
    pos.phase = Phase::moving;
    pos.set_side_to_move(WHITE);

    // Suppose white has 4 pieces, so not allowed to fly
    pos.pieceOnBoardCount[WHITE] = 4;
    // Place them so we can test adjacency. We only show 2 for demonstration:
    pos.put_piece(W_PIECE, SQ_8);
    pos.put_piece(W_PIECE, SQ_9);
    // Make a few squares around them empty.
    // Possibly place some black pieces somewhere else if relevant.

    ExtMove moveList[MAX_MOVES];
    auto *end = generate<MOVE>(pos, moveList);
    const int count = static_cast<int>(end - moveList);

    // For standard adjacency, we rely on MoveList<LEGAL>::adjacentSquares.
    // For SQ_8 in the default no-diagonal rule, adjacency is {16, 9, 15}.
    // However, SQ_9 is occupied by white, so from SQ_8 we have potential moves
    // to 16, 15 if they're empty. Similarly, from SQ_9 adjacency is {10, 8};
    // but 8 is occupied by white. So effectively, if 15 and 16 are empty, from
    // SQ_8 => 2 moves. From SQ_9 => possibly 1 move if SQ_10 is free.

    // For demonstration, let's assume all are empty except where we put white:
    // => from SQ_8 => moves to {16,15}
    // => from SQ_9 => moves to {10}
    // => total 3 adjacency moves.

    EXPECT_EQ(count, 3) << "With adjacency only, we expect 3 moves from "
                           "squares (8->16, 8->15, 9->10).";

    // Confirm certain moves are included
    auto movesSet = MovesToSet(moveList, end);
    EXPECT_TRUE(movesSet.find(make_move(SQ_8, SQ_16)) != movesSet.end());
    EXPECT_TRUE(movesSet.find(make_move(SQ_8, SQ_15)) != movesSet.end());
    EXPECT_TRUE(movesSet.find(make_move(SQ_9, SQ_10)) != movesSet.end());
}

TEST(MoveGenTest, RemoveGeneration_AllOpponentPiecesInMills)
{
    // If all of opponent's pieces are in mills, they can all be removed.
    // This is a simplified scenario. We'll set them up so each piece is in a
    // mill.

    Position pos;
    pos.set_side_to_move(WHITE);
    // We'll pretend black is the "them" to be removed.

    // Let's say black has 3 pieces on board, all in a "mill".
    // We'll mock is_all_in_mills(BLACK) -> true by overriding or by setting up
    // squares in a known mill. For simplicity, forcibly define them in e.g.
    // squares 8, 9, 10 that form a horizontal mill in the default board.

    // But we must also ensure pos.is_all_in_mills(BLACK) returns true.
    // That function depends on your code, but let's assume it returns true
    // if they are indeed in a recognized mill.

    pos.put_piece(B_PIECE, SQ_8);
    pos.put_piece(B_PIECE, SQ_9);
    pos.put_piece(B_PIECE, SQ_10);
    pos.pieceOnBoardCount[BLACK] = 3;

    // Manually set an internal flag or do it properly:
    // In real usage, you'd do pos.create_mill_table() or similar. For test:
    // We'll mock the function or just trust your code sees 8,9,10 as a mill.

    ExtMove moveList[MAX_MOVES];
    auto *end = generate<REMOVE>(pos, moveList);
    int count = static_cast<int>(end - moveList);

    // If all black's pieces are in mills, we can remove any of them.
    // We expect 3 remove moves, i.e. [ -8, -9, -10 ] in your sign convention.
    EXPECT_EQ(count, 3) << "All black pieces are in mills => all can be "
                           "removed (3).";

    // Check for the presence of each removal
    auto movesSet = MovesToSet(moveList, end);
    EXPECT_TRUE(movesSet.find(static_cast<Move>(-SQ_8)) != movesSet.end());
    EXPECT_TRUE(movesSet.find(static_cast<Move>(-SQ_9)) != movesSet.end());
    EXPECT_TRUE(movesSet.find(static_cast<Move>(-SQ_10)) != movesSet.end());
}

TEST(MoveGenTest, LegalGeneration_DefaultCase)
{
    // Test generate<LEGAL> which should combine PLACE or MOVE or REMOVE
    // depending on pos.get_action() and pos.get_phase().

    // 1) Setup a position in placing phase, action=place
    Position pos;
    pos.phase = Phase::placing;
    pos.action = Action::place;
    pos.set_side_to_move(WHITE);
    pos.pieceInHandCount[WHITE] = 2; // can place 2

    ExtMove moveList[MAX_MOVES];
    auto *end = generate<LEGAL>(pos, moveList);

    // This should call generate<PLACE> plus generate<MOVE> if
    // mayMoveInPlacingPhase is true. Suppose rule.mayMoveInPlacingPhase = false
    // => only place moves appear
    rule.mayMoveInPlacingPhase = false;

    int count = static_cast<int>(end - moveList);
    EXPECT_EQ(count, 24) << "With 24 empty squares and 2 pieces in hand, if no "
                            "'move' is allowed, we get 24 place moves.";

    // 2) Now let's enable mayMoveInPlacingPhase = true, and place a single
    // piece so that a move is possible
    rule.mayMoveInPlacingPhase = true;
    pos.put_piece(W_PIECE, SQ_8);
    pos.pieceOnBoardCount[WHITE] = 1;

    // Re-generate
    end = generate<LEGAL>(pos, moveList);
    count = static_cast<int>(end - moveList);

    // We now expect 24 place moves + adjacency moves from SQ_8 (if it has any)
    // -> e.g. SQ_8 adjacency: {16,9,15} if empty => up to 3 moves.
    // But one of them might be taken if 8 is occupied, etc.
    // So possibly 24 + 2 or 3. Let's do a rough check:
    EXPECT_GT(count, 24) << "If we can now also slide from SQ_8, expect "
                            "additional moves on top of 24 place moves.";
}

} // namespace
