// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_mills.cpp

#include <gtest/gtest.h>
#include <algorithm>
#include <unordered_set>
#include <numeric>

#include "bitboard.h"
#include "mills.h"
#include "movegen.h"
#include "option.h"
#include "position.h"
#include "rule.h"

// We can place these test cases in the same namespace or in an anonymous
// namespace.
namespace {

// A helper function to quickly set a rule and re-init adjacency/mill tables.
void ReInitBoardEnvironment(bool hasDiagonalLines)
{
    // Set some rule index or copy from an existing rule as needed
    // For demonstration, we manually set the rule's values here.
    rule.hasDiagonalLines = hasDiagonalLines;
    rule.pieceCount = 9;
    rule.flyPieceCount = 3;
    rule.mayFly = true;
    rule.millFormationActionInPlacingPhase =
        MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard;

    // Re-initialize adjacency squares based on the rule
    Mills::adjacent_squares_init();
    // Re-initialize mill table based on the rule
    Mills::mill_table_init();
}

// Test adjacency squares initialization without diagonal lines
TEST(MillsTest, AdjacentSquaresInit_NoDiagonalLines)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ false);

    // Check a few adjacency entries to confirm they match the expected values
    // For instance, for SQ_8, the adjacency should be {16, 9, 15}
    // in normal (non-diagonal) rules.
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][0], 16);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][1], 9);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][2], 15);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][3], 0);

    // Similarly, for SQ_16, the adjacency should be {8, 24, 17, 23} in normal
    // rules.
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][0], 8);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][1], 24);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][2], 17);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][3], 23);
}

// Test adjacency squares initialization *with* diagonal lines
TEST(MillsTest, AdjacentSquaresInit_DiagonalLines)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ true);

    // Check a few adjacency entries to confirm they match the expected values
    // For instance, for SQ_8, with diagonals, adjacency should be {9, 15, 16}.
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][0], 9);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][1], 15);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][2], 16);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_8][3], 0);

    // Similarly, check for SQ_16 in diagonal lines mode: {17, 23, 8, 24}.
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][0], 17);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][1], 23);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][2], 8);
    EXPECT_EQ(MoveList<LEGAL>::adjacentSquares[SQ_16][3], 24);
}

// Test mill table initialization
TEST(MillsTest, MillTableInit)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ false);

    // Check that certain squares contain known mill patterns.
    // For example, SQ_8 in non-diagonal lines mode:
    // Position::millTableBB[SQ_8][0] should be a bitboard with bits for (16,
    // 24). We can check if (16, 24) are set in the bitboard. In 32-bit form, we
    // can do small checks.
    Bitboard expected0 = square_bb(SQ_16) | square_bb(SQ_24);
    Bitboard actual0 = Position::millTableBB[SQ_8][0];
    EXPECT_EQ(expected0, actual0);

    // Another set for the same square: [1] -> (9, 15), [2] -> ~0U if you have
    // placeholders, etc. For demonstration, let's check [1].
    Bitboard expected1 = square_bb(SQ_9) | square_bb(SQ_15);
    Bitboard actual1 = Position::millTableBB[SQ_8][1];
    EXPECT_EQ(expected1, actual1);
}

// Test move priority list shuffling
TEST(MillsTest, MovePriorityListShuffle)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ false);

    // Before shuffling, let's enforce some known condition to see if it's
    // changed. For demonstration, we'll set skill level to 1, which triggers a
    // shuffle of squares [8..31].
    gameOptions.setSkillLevel(1);

    // Manually call shuffle
    Mills::move_priority_list_shuffle();

    // Because it's random, we can't exactly check a single arrangement.
    // But we can check that all squares from [8..31] are present.
    std::unordered_set<Square> squares;
    for (auto sq : MoveList<LEGAL>::movePriorityList)
        squares.insert(sq);

    // Expect all squares in [8..31] are in the set, and set size is 24
    EXPECT_EQ(squares.size(), 24UL);
    for (int sq = 8; sq < 32; sq++)
        EXPECT_TRUE(squares.find(static_cast<Square>(sq)) != squares.end());
}

// Test if 'is_star_squares_full()' detects star squares being occupied
TEST(MillsTest, IsStarSquaresFull)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ false);
    Position pos;

    // Fill star squares for the non-diagonal rule: {16, 18, 20, 22}.
    // Here we put a white piece in each star square to simulate them being
    // full.
    pos.put_piece(W_PIECE, SQ_16);
    pos.put_piece(W_PIECE, SQ_18);
    pos.put_piece(W_PIECE, SQ_20);
    pos.put_piece(W_PIECE, SQ_22);

    // is_star_squares_full() should now be true
    EXPECT_TRUE(Mills::is_star_squares_full(&pos));

    // If we remove one piece, it should become false
    pos.board[SQ_22] = NO_PIECE;
    EXPECT_FALSE(Mills::is_star_squares_full(&pos));
}

// Test the get_search_depth function logic
TEST(MillsTest, GetSearchDepth)
{
    ReInitBoardEnvironment(/* hasDiagonalLines = */ false);

    // We can also modify rule details or gameOptions here if necessary
    gameOptions.setSkillLevel(3);

    // Create a test position
    Position pos;
    pos.phase = Phase::placing;
    // By default, pieceInHandCount for each color is 9 if rule.pieceCount=9,
    // so effectively 18 pieces are not yet on the board in total.

    // E.g. let's remove some pieces from hand to simulate progress in placing
    // phase
    pos.pieceInHandCount[WHITE] = 5; // 4 pieces placed
    pos.pieceInHandCount[BLACK] = 5; // 4 pieces placed

    // Now check what get_search_depth returns
    Depth depth = Mills::get_search_depth(&pos);

    // Depending on the internal table, you might expect a certain depth around
    // 7-12 for an 8-placed game state. This is just an example expectation.
    // Adjust as necessary if your internal logic returns a specific value in
    // your scenario. For demonstration, let's just check it's in a valid range
    // (not zero and not extremely large).
    EXPECT_GT(depth, 0);
    EXPECT_LE(depth, 32); // Our code asserts max depth of 32

    // Switch to moving phase and check if logic changes
    pos.phase = Phase::moving;
    // Suppose each side now has 9 - 5 = 4 pieces on board.
    // Let's actually place them to keep count consistent:
    // (In reality, you'd do pos.put_piece(...) calls for squares, etc.)

    pos.pieceOnBoardCount[WHITE] = 4;
    pos.pieceOnBoardCount[BLACK] = 4;

    depth = Mills::get_search_depth(&pos);
    EXPECT_GT(depth, 0);
    EXPECT_LE(depth, 32);
}

} // namespace
