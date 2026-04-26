// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// test_movegen.cpp

#include <gtest/gtest.h>
#include <algorithm>
#include <cstring>
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
    // If sideToMove has more than flyPieceCount pieces it cannot fly; only
    // adjacent (sliding) moves are generated.

    // Re-initialise to the default rule so state left by previous test
    // fixtures does not affect the adjacency / mill tables.
    set_rule(0); // Nine Men's Morris, no diagonal lines
    Mills::adjacent_squares_init();
    Mills::mill_table_init();

    rule.mayFly = true;
    rule.flyPieceCount = 3;

    Position pos;
    // Clear pieceInHandCount BEFORE calling set_side_to_move, because the
    // inline set_side_to_move() reads pieceInHandCount[sideToMove] and
    // overwrites phase: 0 → Phase::moving, >0 → Phase::placing.
    pos.pieceInHandCount[WHITE] = 0;
    pos.pieceInHandCount[BLACK] = 0;
    pos.set_side_to_move(WHITE); // now correctly derives Phase::moving

    // White has 4 pieces on the board so flying is NOT allowed.
    pos.pieceOnBoardCount[WHITE] = 4;
    // Place pieces via direct field access (consistent with CaptureTest) to
    // avoid triggering the overloaded complex put_piece(Square, bool) path,
    // which would run game-state logic and alter pos.phase.
    pos.board[SQ_8] = W_PIECE;
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_8);
    pos.byColorBB[WHITE] |= square_bb(SQ_8); // d5

    pos.board[SQ_9] = W_PIECE;
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_9);
    pos.byColorBB[WHITE] |= square_bb(SQ_9); // e5 – adjacent to SQ_8

    // Sanity checks: verify the board and adjacency table are as expected.
    ASSERT_EQ(pos.board[SQ_8], W_PIECE) << "W_PIECE must be at SQ_8";
    ASSERT_EQ(pos.board[SQ_9], W_PIECE) << "W_PIECE must be at SQ_9";
    ASSERT_EQ(pos.side_to_move(), WHITE) << "Side to move must be WHITE";
    ASSERT_EQ(pos.get_phase(), Phase::moving) << "Phase must be moving";
    ASSERT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][0], static_cast<Square>(16))
        << "SQ_8 adj[0] should be 16 (d6)";
    ASSERT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][1], static_cast<Square>(9))
        << "SQ_8 adj[1] should be 9 (e5)";
    ASSERT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][2], static_cast<Square>(15))
        << "SQ_8 adj[2] should be 15 (c5)";

    // Adjacency for default (no-diagonal) rule:
    //   SQ_8 (d5): {16, 9, 15}  → 9 is occupied by White → moves to {16, 15}
    //   SQ_9 (e5): {10, 8}      → 8 is occupied by White → move  to {10}
    //   Total: 3 adjacency moves.
    ExtMove moveList[MAX_MOVES];
    auto *end = generate<MOVE>(pos, moveList);
    const int count = static_cast<int>(end - moveList);

    EXPECT_EQ(count, 3) << "With adjacency only, expect 3 moves: "
                           "8->16, 8->15, 9->10";

    auto movesSet = MovesToSet(moveList, end);
    EXPECT_TRUE(movesSet.find(make_move(SQ_8, SQ_16)) != movesSet.end())
        << "SQ_8 -> SQ_16 (d5->d6) should be legal";
    EXPECT_TRUE(movesSet.find(make_move(SQ_8, SQ_15)) != movesSet.end())
        << "SQ_8 -> SQ_15 (d5->c5) should be legal";
    EXPECT_TRUE(movesSet.find(make_move(SQ_9, SQ_10)) != movesSet.end())
        << "SQ_9 -> SQ_10 (e5->e4) should be legal";
}

TEST(MoveGenTest, DISABLED_RemoveGeneration_AllOpponentPiecesInMills)
{
    // If all of opponent's pieces are in mills, they can all be removed.
    // This is a simplified scenario. We'll set them up so each piece is in a
    // mill.
    // NOTE: This test is currently disabled as it requires proper Position
    // setup

    Position pos;
    pos.reset();
    pos.start();
    pos.set_side_to_move(WHITE);
    pos.phase = Phase::moving;
    pos.action = Action::remove;
    // We'll pretend black is the "them" to be removed.

    // Clear the board first
    for (int sq = SQ_BEGIN; sq < SQ_END; sq++) {
        pos.board[sq] = NO_PIECE;
    }

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
    pos.pieceOnBoardCount[WHITE] = 0;
    pos.pieceInHandCount[BLACK] = 0;
    pos.pieceInHandCount[WHITE] = 0;

    ExtMove moveList[MAX_MOVES];
    auto *end = generate<REMOVE>(pos, moveList);
    int count = static_cast<int>(end - moveList);

    // If all black's pieces are in mills, we can remove any of them.
    // We expect at least 1 remove move (any of the 3 pieces can be removed).
    EXPECT_GE(count, 1) << "All black pieces are in mills => at least one can "
                           "be removed.";
    EXPECT_LE(count, 3) << "At most 3 pieces can be removed.";

    // Just verify that generated moves are valid remove moves for the black
    // pieces
    auto movesSet = MovesToSet(moveList, end);
    for (const auto &move : movesSet) {
        // Remove moves should be negative square values
        EXPECT_LT(move, 0) << "Remove move should be negative";
    }
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
