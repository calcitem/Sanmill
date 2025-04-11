// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_types.cpp

/**
 * @file test_types.cpp
 * @brief Unit tests for various operations and definitions in types.h
 *
 * This test suite checks correctness of enumerations, helper functions,
 * and utility macros defined in types.h. The tests specifically focus on:
 *   - Color toggles and manipulations
 *   - Piece creation and queries (color_of, type_of)
 *   - Square manipulations (make_square, is_ok, file_of, rank_of)
 *   - Move creation and analysis (make_move, from_sq, to_sq, reverse_move)
 *   - Basic enumerations for bounds, values, etc.
 */

#include <gtest/gtest.h>
#include "types.h"

namespace {

/**
 * @class TypesTest
 * @brief A test fixture for verifying elements within types.h
 */
class TypesTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Runs before each test.
    }

    void TearDown() override
    {
        // Runs after each test.
    }
};

/**
 * @test ColorToggle
 * @brief Ensures that ~ operator on Color toggles WHITE <-> BLACK,
 *        and that toggling NOCOLOR yields a (somewhat) distinct value.
 */
TEST_F(TypesTest, ColorToggle)
{
    EXPECT_EQ(~WHITE, BLACK) << "Toggling WHITE should yield BLACK.";
    EXPECT_EQ(~BLACK, WHITE) << "Toggling BLACK should yield WHITE.";

    // The NOCOLOR toggling is an artifact of how the bitwise operation is
    // defined:
    //   c ^ 3 => 0 ^ 3 = 3, which is actually the numeric value for DRAW.
    // This is not typically used in normal logic but let's verify for
    // consistency.
    EXPECT_EQ(~NOCOLOR, static_cast<Color>(3)) << "Toggling NOCOLOR (0) with "
                                                  "^3 yields 3, typically "
                                                  "'DRAW'.";
}

/**
 * @test MakePieceAndQueries
 * @brief Checks correctness of make_piece() and piece color/type checks.
 */
TEST_F(TypesTest, MakePieceAndQueries)
{
    // Construct a black piece
    Piece blackPc = make_piece(BLACK);
    EXPECT_EQ(color_of(blackPc), BLACK) << "make_piece(BLACK) should have "
                                           "color BLACK.";
    EXPECT_EQ(type_of(blackPc), BLACK_PIECE) << "By default, type_of() should "
                                                "see a black piece as "
                                                "BLACK_PIECE.";

    // Construct a white piece
    Piece whitePc = make_piece(WHITE);
    EXPECT_EQ(color_of(whitePc), WHITE) << "make_piece(WHITE) should have "
                                           "color WHITE.";
    EXPECT_EQ(type_of(whitePc), WHITE_PIECE) << "By default, type_of() should "
                                                "see a white piece as "
                                                "WHITE_PIECE.";

    // Construct a marked piece
    Piece markedPc = make_piece(NOCOLOR, MARKED);
    EXPECT_EQ(markedPc, MARKED_PIECE) << "When color is NOCOLOR and type is "
                                         "MARKED, result should be "
                                         "MARKED_PIECE.";
    EXPECT_EQ(type_of(markedPc), MARKED) << "type_of(MARKED_PIECE) should be "
                                            "MARKED.";
    EXPECT_EQ(color_of(markedPc), NOCOLOR) << "A marked piece has NOCOLOR in "
                                              "higher nibble.";
}

/**
 * @test MakeSquareChecks
 * @brief Verifies square creation from file/rank and checks properties with
 * is_ok(), file_of(), rank_of().
 */
TEST_F(TypesTest, MakeSquareChecks)
{
    // For a valid square, e.g. FILE_C (3) and RANK_5 => (3 << 3) + (5 - 1) =>
    // 3*8 + 4 = 28
    Square sq = make_square(FILE_C, RANK_5);
    EXPECT_EQ(sq, SQ_28) << "make_square(FILE_C, RANK_5) should produce SQ_28.";
    EXPECT_TRUE(is_ok(sq)) << "SQ_28 is within [SQ_BEGIN..SQ_END).";

    // Check file_of and rank_of
    EXPECT_EQ(file_of(sq), FILE_C) << "file_of(SQ_28) should be FILE_C(3).";
    EXPECT_EQ(rank_of(sq), RANK_5) << "rank_of(SQ_28) should be RANK_5(5).";

    // Check boundary or invalid squares
    // EXPECT_FALSE(is_ok(SQ_0))
    //    << "SQ_0 is not within [SQ_BEGIN..SQ_END), so is_ok(SQ_0) is false.";
    EXPECT_FALSE(is_ok(static_cast<Square>(33))) << "Square beyond SQ_31 also "
                                                    "fails is_ok check.";
}

/**
 * @test MoveCreationAndAnalysis
 * @brief Tests making moves and extracting from_sq, to_sq, and verifying
 * type_of moves.
 */
TEST_F(TypesTest, MoveCreationAndAnalysis)
{
    // Create a "move" from SQ_9 to SQ_17 (some random squares).
    // If from_sq != to_sq, by default we treat it as a MOVETYPE_MOVE if it fits
    // the bit pattern.
    Move m = make_move(SQ_9, SQ_17);
    EXPECT_EQ(from_sq(m), SQ_9) << "from_sq() should extract the origin from "
                                   "the move bits.";
    EXPECT_EQ(to_sq(m), SQ_17) << "to_sq() should extract the destination from "
                                  "the move bits.";

    // Because the difference from 9->17 has the high bits set (0x1f00),
    // or at least the value is not the same, we expect type_of(m) =
    // MOVETYPE_MOVE:
    EXPECT_EQ(type_of(m), MOVETYPE_MOVE) << "A normal from->to (9->17) should "
                                            "be treated as MOVETYPE_MOVE.";

    // Now test a "place" move: If from == 0 and to != 0 => MOVETYPE_PLACE
    Move placeMove = make_move(SQ_0, SQ_8);
    EXPECT_EQ(type_of(placeMove), MOVETYPE_PLACE) << "When from_sq == to_sq == "
                                                     "0? Actually we do "
                                                     "from_sq=0, to=8 => place "
                                                     "move.";
    EXPECT_EQ(from_sq(placeMove), SQ_0) << "from_sq(PlaceMove) = 0 indicates "
                                           "place from 'off-board'.";
    EXPECT_EQ(to_sq(placeMove), SQ_8) << "to_sq(PlaceMove) = 8 is the board "
                                         "square for placing.";

    // Now test a remove move with negative
    // e.g. remove SQ_10 => m = static_cast<Move>(-SQ_10)
    Move removeMove = static_cast<Move>(-SQ_10);
    EXPECT_EQ(type_of(removeMove), MOVETYPE_REMOVE) << "A negative move "
                                                       "implies removal. "
                                                       "type_of() should "
                                                       "detect "
                                                       "MOVETYPE_REMOVE.";
    EXPECT_EQ(to_sq(removeMove), SQ_10) << "For remove moves, we interpret "
                                           "'to' as the actual square being "
                                           "removed.";
}

/**
 * @test ReverseMove
 * @brief Confirms that reverse_move() inverts from/to squares.
 */
TEST_F(TypesTest, ReverseMove)
{
    Move original = make_move(SQ_8, SQ_24);
    Move reversed = reverse_move(original);

    EXPECT_EQ(from_sq(original), SQ_8) << "Original from_sq should be SQ_8.";
    EXPECT_EQ(to_sq(original), SQ_24) << "Original to_sq should be SQ_24.";
    EXPECT_EQ(from_sq(reversed), SQ_24) << "Reversed from_sq should be "
                                           "original's to_sq.";
    EXPECT_EQ(to_sq(reversed), SQ_8) << "Reversed to_sq should be original's "
                                        "from_sq.";
}

/**
 * @test EnumerationBasicChecks
 * @brief Basic checks on enumerations like Bound, Value, etc.
 */
TEST_F(TypesTest, EnumerationBasicChecks)
{
    // Simple checks to confirm enumerators remain as expected
    EXPECT_EQ(static_cast<int>(BOUND_EXACT),
              static_cast<int>(BOUND_UPPER | BOUND_LOWER))
        << "BOUND_EXACT should combine BOUND_UPPER and BOUND_LOWER bits.";

    // Check a couple of Values
    EXPECT_GT(VALUE_MATED_IN_MAX_PLY, VALUE_UNKNOWN) << "A mated score is "
                                                        "typically larger than "
                                                        "an unknown score.";

    EXPECT_GT(VALUE_MATE, 0) << "A mate score is positive and well above 0.";
}

} // namespace
