// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// test_movepick.cpp
// Regression tests for move-ordering heuristics added from the strategy guide:
//   - Double-mill bonus
//   - Cardinal-square bonus (place / move / remove)
//   - Feeder-piece removal bonus

#include <gtest/gtest.h>
#include <cstring>
#include "movepick.h"
#include "movegen.h"
#include "position.h"
#include "mills.h"
#include "rule.h"
#include "option.h"

extern Rule rule;
extern GameOptions gameOptions;

namespace {

class MovePickTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        set_rule(DEFAULT_RULE_NUMBER);
        rule.mayRemoveFromMillsAlways = false;
        rule.oneTimeUseMill = false;
        Mills::adjacent_squares_init();
        Mills::mill_table_init();
        Position::create_mill_table();
        gameOptions.setConsiderMobility(true);
        gameOptions.setFocusOnBlockingPaths(false);
        gameOptions.setShufflingEnabled(false);
    }
};

// Helper: find the score assigned to a specific move in the MovePicker's
// internal move list.
static int find_move_score(MovePicker &mp, Move target)
{
    for (ExtMove *it = mp.moves; it < mp.moves + mp.move_count(); ++it) {
        if (it->move == target)
            return it->value;
    }
    return INT_MIN;
}

// 1) Cardinal-square placement bonus: placing on a cardinal point should
//    score higher than placing on a non-cardinal corner, all else being equal.
TEST_F(MovePickTest, CardinalPlacementBonus)
{
    rule.hasDiagonalLines = false;

    Position pos;
    pos.reset();
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));
    pos.phase = Phase::placing;
    pos.sideToMove = WHITE;
    pos.action = Action::place;
    pos.pieceInHandCount[WHITE] = 5;
    pos.pieceInHandCount[BLACK] = 5;
    pos.pieceOnBoardCount[WHITE] = 0;
    pos.pieceOnBoardCount[BLACK] = 0;
    pos.reset_bb();

    MovePicker mp(pos, MOVE_NONE);
    mp.next_move<LEGAL>();

    // SQ_16 is a cardinal square; SQ_25 is a corner square
    const int cardinalScore = find_move_score(
        mp, static_cast<Move>(SQ_16));
    const int cornerScore = find_move_score(
        mp, static_cast<Move>(SQ_25));

    EXPECT_NE(cardinalScore, INT_MIN) << "SQ_16 should be among legal moves.";
    EXPECT_NE(cornerScore, INT_MIN) << "SQ_25 should be among legal moves.";
    EXPECT_EQ(cardinalScore - cornerScore, RATING_CARDINAL_SQUARE)
        << "Cardinal-square placement should add exactly the configured "
           "cardinal bonus on an otherwise empty board.";
}

// 2) Double-mill bonus: if placing at a square creates >= 2 potential mills
//    for the side to move, it should score higher than a single-mill square.
TEST_F(MovePickTest, DoubleMillBonus)
{
    rule.hasDiagonalLines = false;

    Position pos;
    pos.reset();
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // Outer ring top line: SQ_31-SQ_24-SQ_25.  Put White on SQ_31 and SQ_25.
    // Outer ring left column: SQ_31-SQ_30-SQ_29.  Put White on SQ_30.
    // Now SQ_31 already occupied.  For a *placing* scenario let's set up
    // so that placing at SQ_24 closes the horizontal mill (31-24-25) while
    // also nearing a vertical mill (24-16-8 requires one more piece).
    //
    // Instead, build a cleaner 2-mill scenario:
    //   Horizontal line 7 (SQ_31-SQ_24-SQ_25): White on SQ_31, SQ_25
    //   Vertical line (SQ_24-SQ_16-SQ_8): White on SQ_16
    // Placing at SQ_24 yields 1 horizontal + "potential" on vertical (only 1
    // of 2 filled, so potential_mills_count == 1 for horizontal only).
    //
    // Better: create a position where potential_mills_count >= 2 for a target.
    // Line a: SQ_31-SQ_24-SQ_25 (horizontal), White SQ_31, SQ_25
    // Line b: SQ_24-SQ_16-SQ_8 (vertical),    White SQ_16, SQ_8
    // Placing at SQ_24 closes both => potential_mills_count(SQ_24, WHITE) == 2
    pos.board[SQ_31] = W_PIECE;
    pos.board[SQ_25] = W_PIECE;
    pos.board[SQ_16] = W_PIECE;
    pos.board[SQ_8] = W_PIECE;
    pos.board[SQ_30] = W_PIECE; // makes SQ_29 a clean single-mill target
    pos.pieceOnBoardCount[WHITE] = 5;
    pos.pieceOnBoardCount[BLACK] = 0;
    pos.pieceInHandCount[WHITE] = 3;
    pos.pieceInHandCount[BLACK] = 5;
    pos.phase = Phase::placing;
    pos.sideToMove = WHITE;
    pos.action = Action::place;
    pos.reset_bb();

    MovePicker mp(pos, MOVE_NONE);
    mp.next_move<LEGAL>();

    // SQ_24 should close 2 mills simultaneously
    const int doubleMill = find_move_score(mp, static_cast<Move>(SQ_24));

    // SQ_29 closes exactly one mill via 31-30-29.
    const int singleMill = find_move_score(mp, static_cast<Move>(SQ_29));

    EXPECT_NE(doubleMill, INT_MIN);
    EXPECT_NE(singleMill, INT_MIN);
    EXPECT_EQ(doubleMill - singleMill,
              RATING_ONE_MILL + RATING_DOUBLE_MILL)
        << "A double-mill target should beat a single-mill target by one extra "
           "mill plus the configured double-mill bonus.";
}

// 3) Cardinal removal bonus: when removing an opponent's piece, a piece on
//    a cardinal square should be preferred over one on a corner.
TEST_F(MovePickTest, CardinalRemovalBonus)
{
    rule.hasDiagonalLines = false;

    Position pos;
    pos.reset();
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // Set up a position where White is in the remove action.
    // Use MARKED pieces to equalise empty-neighbour counts so that the score
    // delta comes from the cardinal bonus itself, not from mobility noise.
    pos.board[SQ_16] = B_PIECE; // cardinal
    pos.board[SQ_25] = B_PIECE; // corner
    pos.board[SQ_8] = MARKED_PIECE;
    pos.board[SQ_23] = MARKED_PIECE;
    pos.pieceOnBoardCount[BLACK] = 2;

    // White has enough pieces and a remove action
    pos.board[SQ_31] = W_PIECE;
    pos.board[SQ_24] = W_PIECE;
    pos.board[SQ_8] = W_PIECE;
    pos.pieceOnBoardCount[WHITE] = 3;

    pos.phase = Phase::moving;
    pos.sideToMove = WHITE;
    pos.action = Action::remove;
    pos.pieceInHandCount[WHITE] = 0;
    pos.pieceInHandCount[BLACK] = 0;
    pos.pieceToRemoveCount[WHITE] = 1;

    pos.reset_bb();

    MovePicker mp(pos, MOVE_NONE);
    mp.next_move<REMOVE>();

    // Removing SQ_16 (cardinal) should score higher than SQ_25 (corner)
    const Move removeCardinal = static_cast<Move>(-static_cast<int>(SQ_16));
    const Move removeCorner = static_cast<Move>(-static_cast<int>(SQ_25));

    const int scoreCardinal = find_move_score(mp, removeCardinal);
    const int scoreCorner = find_move_score(mp, removeCorner);

    EXPECT_NE(scoreCardinal, INT_MIN);
    EXPECT_NE(scoreCorner, INT_MIN);
    EXPECT_EQ(scoreCardinal - scoreCorner, RATING_CARDINAL_SQUARE)
        << "After equalising neighbourhood counts, removing a cardinal-point "
           "piece should differ only by the configured cardinal bonus.";
}

// 4) Feeder-piece removal bonus: when removal-from-mills is allowed, the piece
//    common to two mills should outrank a piece that belongs to only one mill,
//    all else being equal.
TEST_F(MovePickTest, FeederRemovalBonus)
{
    rule.hasDiagonalLines = false;
    rule.mayRemoveFromMillsAlways = true;

    Position pos;
    pos.reset();
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));
    pos.phase = Phase::moving;
    pos.sideToMove = WHITE;
    pos.action = Action::remove;
    pos.pieceInHandCount[WHITE] = 0;
    pos.pieceInHandCount[BLACK] = 0;
    pos.pieceToRemoveCount[WHITE] = 1;

    // Black piece at SQ_24 belongs to two mills:
    //   31-24-25 and 24-16-8
    pos.board[SQ_24] = B_PIECE;
    pos.board[SQ_31] = B_PIECE;
    pos.board[SQ_25] = B_PIECE;
    pos.board[SQ_16] = B_PIECE;
    pos.board[SQ_8] = B_PIECE;

    // Black piece at SQ_30 belongs to one mill only:
    //   31-30-29
    pos.board[SQ_30] = B_PIECE;
    pos.board[SQ_29] = B_PIECE;
    pos.board[SQ_22] = B_PIECE; // equalise adjacent piece count around SQ_30

    pos.pieceOnBoardCount[BLACK] = 8;
    pos.pieceOnBoardCount[WHITE] = 0;
    pos.reset_bb();

    MovePicker mp(pos, MOVE_NONE);
    mp.next_move<REMOVE>();

    const Move removeFeeder = static_cast<Move>(-static_cast<int>(SQ_24));
    const Move removeSingleMill = static_cast<Move>(-static_cast<int>(SQ_30));

    const int feederScore = find_move_score(mp, removeFeeder);
    const int singleMillScore = find_move_score(mp, removeSingleMill);

    EXPECT_NE(feederScore, INT_MIN);
    EXPECT_NE(singleMillScore, INT_MIN);
    EXPECT_EQ(feederScore - singleMillScore, RATING_REMOVE_FEEDER)
        << "The piece shared by two mills should receive exactly the feeder "
           "removal bonus when other local factors are equalised.";
}

} // namespace
