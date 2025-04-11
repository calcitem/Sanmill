// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_position.cpp

#include <gtest/gtest.h>
#include "position.h"
#include "stack.h" // So we can undo moves with Sanmill::Stack<Position>
#include <string>

namespace {

// A simple test fixture for Position-related tests
class PositionTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Any global re-initialization or rule-setup can be done here if needed
        // E.g. reset the rule object, if you want a default rule each time
        // set_rule(DEFAULT_RULE_NUMBER);
    }

    // We can create a Position object for each test, or do it in the tests
};

// Test that a new default Position is in the expected state
TEST_F(PositionTest, DefaultConstructor)
{
    Position pos;
    pos.reset();
    // Check that the position is in "ready" phase (per your logic).
    // But note that in your code you set phase=Phase::ready at reset(), so this
    // might differ.
    EXPECT_EQ(pos.get_phase(), Phase::ready) << "Newly constructed position "
                                                "should be in the 'ready' "
                                                "phase.";
    EXPECT_EQ(pos.side_to_move(), WHITE) << "Default side to move should be "
                                            "WHITE in a new position.";

    // The board should be empty if your default constructor calls reset().
    EXPECT_TRUE(pos.is_board_empty()) << "A newly constructed position is "
                                         "expected to have an empty board.";
}

// Test that reset() puts the Position into a known starting state
TEST_F(PositionTest, ResetPosition)
{
    Position pos;
    pos.reset();
    // We can do some moves or set a custom fen
    // Then reset and verify it is the standard start again
    pos.start(); // e.g. changes phase to placing

    pos.reset();
    EXPECT_EQ(pos.get_phase(), Phase::ready);
    EXPECT_TRUE(pos.is_board_empty());
    EXPECT_EQ(pos.side_to_move(), WHITE);
}

// Test loading a FEN string, and verifying the stored data
TEST_F(PositionTest, SetFEN_LoadsState)
{
    Position pos;
    pos.reset();

    // Example: This FEN might indicate a certain arrangement of O/*/@ pieces,
    // side=White, etc. Adapt to your actual FEN structure.
    std::string fenStr = "****@***/****O***/******** w p p 1 8 1 8 0 0 0 0 0 0 "
                         "0 0 1";

    pos.set(fenStr);
    EXPECT_FALSE(pos.is_board_empty()) << "Should have at least one piece "
                                          "after set().";

    // Check side to move
    EXPECT_EQ(pos.side_to_move(), WHITE) << "FEN said 'w', so sideToMove "
                                            "should be WHITE.";

    // Check phase
    EXPECT_EQ(pos.get_phase(), Phase::placing) << "We used 'n' in that FEN's "
                                                  "phase field. Verify if that "
                                                  "matches your code.";

    // Check action
    EXPECT_EQ(pos.get_action(), Action::place) << "We used '?' for action "
                                                  "field, which mapped to "
                                                  "Action::none in your code.";

    // Check a known location
    EXPECT_EQ(pos.piece_on(SQ_12), B_PIECE) << "Should have a white piece on "
                                               "square 12 according to our "
                                               "mock FEN.";
}

// Round-trip: set() then fen()
TEST_F(PositionTest, FenRoundTrip)
{
    Position pos;
    pos.reset();

    // A FEN that places a black piece at SQ_9, white piece at SQ_8, etc.
    std::string originalFen = "O@******  w  m  p  1 8 1 8 0 0 0 0  0  0 1";
    pos.set(originalFen);
    std::string fenOut = pos.fen();

    // Now create another position and set from fenOut
    Position pos2;
    pos2.set(fenOut);

    // Compare key or fen to see if it matches
    EXPECT_EQ(pos2.key(), pos.key()) << "After loading fenOut, the position "
                                        "keys should match the original.";

    // If your fen() is stable, you can compare the string representation
    // directly: But note that some positions might reorder fields in fenOut. If
    // so, compare key() or piece states instead. EXPECT_EQ(fenOut, pos2.fen());
}

// Test do_move() with a single place move in placing phase
TEST_F(PositionTest, DoMove_Place)
{
    Position pos;
    pos.reset();
    pos.start(); // now in placing phase?

    // Assume we have 9 pieces in hand for each side. Let's do a place move at
    // SQ_8 Move format: from=0 => place, to=8 => position
    Move placeMove = make_move(SQ_0, SQ_8); // type_of() => MOVETYPE_PLACE
    // Actually 'make_move(SQ_0, SQ_8)' might be needed if your code
    // expects from_sq(m) != to_sq(m), but your code treats negative or
    // partial bits. Double-check your code's logic for place moves.

    EXPECT_TRUE(type_of(placeMove) == MOVETYPE_PLACE) << "The move should be a "
                                                         "place move.";

    EXPECT_TRUE(pos.empty(SQ_8)) << "Square 8 must be empty for a place move "
                                    "to be valid.";

    pos.do_move(placeMove);

    EXPECT_EQ(color_of(pos.piece_on(SQ_8)), WHITE) << "After a place move, we "
                                                      "expect a white piece on "
                                                      "SQ_8.";
    EXPECT_EQ(type_of(pos.piece_on(SQ_8)), WHITE_PIECE) << "After a place "
                                                           "move, we expect a "
                                                           "white piece on "
                                                           "SQ_8.";
    EXPECT_EQ(pos.piece_in_hand_count(WHITE), 8) << "White should have 8 "
                                                    "pieces left in hand after "
                                                    "placing one.";

    // We can also check that side changed if your rules do so immediately:
    // (or maybe side changes only if no mill was formed, etc.)
}

// Test removing a piece
TEST_F(PositionTest, DoMove_Remove)
{
    Position pos;
    pos.reset();

    // We'll set a scenario where removing is possible
    // e.g. White just formed a mill and sideToMove=WHITE => Action::remove
    // We'll place black piece on SQ_8 and instruct White to remove it
    pos.phase = Phase::moving;
    pos.action = Action::remove;
    pos.pieceInHandCount[WHITE] = 5;
    pos.pieceInHandCount[BLACK] = 5;
    pos.pieceOnBoardCount[WHITE] = 4;
    pos.pieceOnBoardCount[BLACK] = 4;
    pos.pieceToRemoveCount[WHITE] = 1; // indicate White has to remove 1
    pos.board[SQ_8] = W_PIECE;
    pos.board[SQ_9] = W_PIECE;
    pos.board[SQ_15] = W_PIECE;
    pos.board[SQ_17] = W_PIECE;
    pos.board[SQ_10] = B_PIECE;
    pos.board[SQ_11] = B_PIECE;
    pos.board[SQ_12] = B_PIECE;
    pos.board[SQ_19] = B_PIECE;
    pos.set_side_to_move(WHITE);

    // Construct the remove move:
    // remove moves are negative => static_cast<Move>(-SQ_10), in your code
    Move removeMove = static_cast<Move>(-SQ_10);
    EXPECT_TRUE(type_of(removeMove) == MOVETYPE_REMOVE) << "The move should be "
                                                           "a remove move.";
    pos.do_move(removeMove);

    EXPECT_TRUE(pos.empty(SQ_10)) << "Black's piece on SQ_10 should be removed "
                                     "now.";
    EXPECT_EQ(pos.pieceOnBoardCount[BLACK], 3) << "Black's on-board count "
                                                  "should decrement to 3 after "
                                                  "removal.";
    EXPECT_EQ(pos.piece_to_remove_count(WHITE), 0) << "We've removed 1 piece, "
                                                      "so White no longer has "
                                                      "a remove count.";
}

// Test that undo_move() properly restores the position
TEST_F(PositionTest, UndoMove)
{
    Position pos;
    pos.reset();

    Sanmill::Stack<Position> stack;
    // Before do_move, push a copy onto the stack
    stack.push(pos);

    // Do something
    Move placeMove = static_cast<Move>(SQ_8);
    pos.do_move(placeMove);
    // Confirm changes
    EXPECT_FALSE(pos.empty(SQ_8));

    // Now undo
    pos.undo_move(stack);
    // Should revert to old state
    EXPECT_TRUE(pos.empty(SQ_8));
    EXPECT_EQ(pos.get_phase(), Phase::ready) << "The old state was presumably "
                                                "'ready' if we used the "
                                                "default constructor.";
}

// Example test for is_all_in_mills() logic
TEST_F(PositionTest, AllInMills)
{
    Position pos;
    pos.reset();
    pos.start();

    // We'll forcibly place black pieces on squares that definitely form mills
    // in your default or diagonal rule. For instance, squares 8,9,15 is a known
    // row, etc.
    pos.put_piece(B_PIECE, SQ_8);
    pos.put_piece(B_PIECE, SQ_9);
    pos.put_piece(B_PIECE, SQ_15);

    // Suppose sideToMove=WHITE. So them=BLACK => check if black is all in
    // mills. But is_all_in_mills() is about checking every black piece is in a
    // mill? If black only has exactly these 3 pieces, and they do form a mill,
    // then indeed all black pieces are in a mill => return true
    EXPECT_TRUE(pos.is_all_in_mills(BLACK));

    // Now let's put the black piece.
    pos.put_piece(B_PIECE, SQ_16);

    EXPECT_FALSE(pos.is_all_in_mills(BLACK)) << "Not all black pieces are in a "
                                                "mill.";

    pos.put_piece(B_PIECE, SQ_24);
    EXPECT_TRUE(pos.is_all_in_mills(BLACK));
}

// Example test that verifies 3 pieces => can fly if rule.mayFly is true
TEST_F(PositionTest, FlyCheck)
{
    // We assume rule or pos sets mayFly=true somewhere. If not, you can set:
    rule.mayFly = true;
    rule.flyPieceCount = 3;

    Position pos;
    pos.reset();

    pos.phase = Phase::moving;
    // White has 3 on board => can fly
    pos.pieceOnBoardCount[WHITE] = 3;
    pos.pieceOnBoardCount[BLACK] = 4;
    pos.pieceInHandCount[WHITE] = 0;
    pos.pieceInHandCount[BLACK] = 0;
    pos.pieceToRemoveCount[WHITE] = 0;
    pos.pieceToRemoveCount[BLACK] = 0;
    pos.put_piece(W_PIECE, SQ_8);
    pos.put_piece(W_PIECE, SQ_9);
    pos.put_piece(W_PIECE, SQ_11);
    pos.put_piece(B_PIECE, SQ_12);
    pos.put_piece(B_PIECE, SQ_13);
    pos.put_piece(B_PIECE, SQ_14);
    pos.put_piece(B_PIECE, SQ_15);
    pos.set_side_to_move(WHITE);

    // We do a do_move from 8 -> some far away square 25 not adjacent
    Move flyMove = make_move(SQ_8, SQ_25);

    // Typically you'd do legality checks, but for demonstration:
    pos.do_move(flyMove);

    // Should succeed if your code allows flying
    EXPECT_EQ(pos.board[SQ_25], W_PIECE);
    EXPECT_TRUE(pos.empty(SQ_8));
}

} // namespace
