// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_capture.cpp

#include <gtest/gtest.h>
#include "position.h"
#include "stack.h"
#include <string>

namespace {

// Test fixture for capture rule tests
class CaptureTest : public ::testing::Test
{
protected:
    Position pos;

    void SetUp() override
    {
        // Set up a rule that enables leap capture for testing
        set_rule(0); // Use a base rule like Nine Men's Morris
        rule.leapCapture.enabled = true;
        rule.leapCapture.inPlacingPhase = true;
        rule.leapCapture.inMovingPhase = true;
        rule.leapCapture.onSquareEdges = true;
        rule.leapCapture.onCrossLines = true;
        rule.leapCapture.onDiagonalLines = true;
        rule.hasDiagonalLines = true; // For diagonal leap tests
        pos.reset();
        pos.start();
    }
};

TEST_F(CaptureTest, LeapCaptureNotInPlacingPhaseWithoutMovement)
{
    // Leap capture should NOT work when placing a new piece in placing phase
    // because there's no "from" square to jump from.
    pos.put_piece(W_PIECE, SQ_8);
    pos.put_piece(B_PIECE, SQ_9);

    std::vector<Square> captured;
    // White places at SQ_10 without a from square - should NOT trigger leap
    // capture
    EXPECT_FALSE(pos.checkLeapCapture(SQ_10, WHITE, captured));
    EXPECT_TRUE(captured.empty());
}

TEST_F(CaptureTest, LeapCaptureInPlacingPhaseWithMovement)
{
    // When mayMoveInPlacingPhase is enabled, leap capture should work
    // in placing phase because movement is possible
    rule.mayMoveInPlacingPhase = true;
    rule.leapCapture.inPlacingPhase = true;

    pos.reset();
    pos.start();
    pos.phase = Phase::placing;

    // Setup: W at SQ_8, B at SQ_9, SQ_10 empty
    pos.board[SQ_8] = W_PIECE;
    pos.byColorBB[WHITE] |= square_bb(SQ_8);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_8);
    pos.pieceOnBoardCount[WHITE] = 1;

    pos.board[SQ_9] = B_PIECE;
    pos.byColorBB[BLACK] |= square_bb(SQ_9);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_9);
    pos.pieceOnBoardCount[BLACK] = 1;

    std::vector<Square> captured;
    // White moves from SQ_8 to SQ_10 (with from parameter) - should trigger
    // leap
    EXPECT_TRUE(pos.checkLeapCapture(SQ_10, WHITE, captured, SQ_8));
    ASSERT_EQ(captured.size(), 1);
    EXPECT_EQ(captured[0], SQ_9);
}

TEST_F(CaptureTest, LeapCaptureInMovingPhase)
{
    // Create FEN with white at d3 (SQ_12), black at d2 (SQ_20)
    // d3=12, d2=20, d1=28 (empty)
    std::string fen = "********/********/******** w m m 0 0 0 0 0 0 0 0 0 0 0";
    pos.set(fen);

    // Place white at d3 (SQ_12)
    pos.board[SQ_12] = W_PIECE;
    pos.byColorBB[WHITE] |= square_bb(SQ_12);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_12);
    pos.pieceOnBoardCount[WHITE] = 1;

    // Place black at d2 (SQ_20)
    pos.board[SQ_20] = B_PIECE;
    pos.byColorBB[BLACK] |= square_bb(SQ_20);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_20);
    pos.pieceOnBoardCount[BLACK] = 1;

    pos.phase = Phase::moving;
    rule.hasDiagonalLines = true;
    rule.leapCapture.enabled = true;
    rule.leapCapture.inMovingPhase = true;

    // White at d3 (SQ_12), Black at d2 (SQ_20)
    // White moves from d3 to d1 (SQ_12 -> SQ_28), leaping over d2
    std::vector<Square> captured;
    EXPECT_TRUE(pos.checkLeapCapture(SQ_28, WHITE, captured, SQ_12));
    ASSERT_EQ(captured.size(), 1);
    EXPECT_EQ(captured[0], SQ_20);

    // And the move should be legal now via move generation & do_move
    // Generate moves and ensure (12->28) exists when leap is possible
    MoveList<LEGAL> list(pos);
    bool found = false;
    for (const auto &m : list) {
        if (type_of(m) == MOVETYPE_MOVE && from_sq(m) == SQ_12 &&
            to_sq(m) == SQ_28) {
            found = true;
            break;
        }
    }
    EXPECT_TRUE(found);
}

TEST_F(CaptureTest, FenRoundTripWithLeapCapture)
{
    pos.set_side_to_move(WHITE);
    pos.setLeapCaptureState(WHITE, square_bb(SQ_10), 1);
    pos.setLeapCaptureState(BLACK, square_bb(SQ_18) | square_bb(SQ_19),
                            0); // test with 0 count but targets

    std::string fen = pos.fen();
    EXPECT_NE(fen.find(" l:w-1-10|b-0-18.19"), std::string::npos);

    Position pos2;
    pos2.set(fen);

    EXPECT_EQ(pos.key(), pos2.key());
    EXPECT_EQ(pos2.leapCaptureTargets[WHITE], square_bb(SQ_10));
    EXPECT_EQ(pos2.leapRemovalCount[WHITE], 1);
    EXPECT_EQ(pos2.leapCaptureTargets[BLACK],
              square_bb(SQ_18) | square_bb(SQ_19));
    EXPECT_EQ(pos2.leapRemovalCount[BLACK], 0);
}

TEST_F(CaptureTest, DoMoveWithLeapCapture)
{
    // Setup a moving phase scenario where a leap move can capture
    // White at a7 (SQ_16), Black at d7 (SQ_19), g7 (SQ_22) empty
    std::string fen = "********/********/******** w m s 1 0 1 0 0 0 0 0 0 0 0";
    pos.set(fen);

    // Place pieces manually for moving phase
    pos.board[SQ_16] = W_PIECE;
    pos.byColorBB[WHITE] |= square_bb(SQ_16);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_16);
    pos.pieceOnBoardCount[WHITE] = 1;

    pos.board[SQ_19] = B_PIECE;
    pos.byColorBB[BLACK] |= square_bb(SQ_19);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_19);
    pos.pieceOnBoardCount[BLACK] = 1;

    pos.phase = Phase::moving;
    pos.action = Action::select;
    pos.currentSquare[WHITE] = SQ_16;

    // White moves from a7 (SQ_16) to g7 (SQ_22), leaping over d7 (SQ_19)
    Move leapMove = make_move(SQ_16, SQ_22);
    pos.do_move(leapMove);

    // After leap move, should be in removal phase
    EXPECT_EQ(pos.get_action(), Action::remove);
    EXPECT_EQ(pos.piece_to_remove_count(WHITE), 1);
    EXPECT_EQ(pos.leapCaptureTargets[WHITE], square_bb(SQ_19));

    // Now, remove the jumped piece
    Move removeMove = make_move<MOVETYPE_REMOVE>(SQ_19);
    pos.do_move(removeMove);

    EXPECT_TRUE(pos.empty(SQ_19));
    EXPECT_EQ(pos.pieceOnBoardCount[BLACK], 0);
    EXPECT_EQ(pos.side_to_move(), BLACK);
}

TEST_F(CaptureTest, UndoLeapCapture)
{
    // Setup a moving phase scenario for leap capture undo test
    std::string fen = "********/********/******** w m s 2 0 1 0 0 0 0 0 0 0 0";
    pos.set(fen);

    // W at SQ_8, B at SQ_9, SQ_10 empty
    pos.board[SQ_8] = W_PIECE;
    pos.byColorBB[WHITE] |= square_bb(SQ_8);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_8);

    pos.board[SQ_9] = B_PIECE;
    pos.byColorBB[BLACK] |= square_bb(SQ_9);
    pos.byTypeBB[ALL_PIECES] |= square_bb(SQ_9);

    pos.pieceOnBoardCount[WHITE] = 1;
    pos.pieceOnBoardCount[BLACK] = 1;
    pos.phase = Phase::moving;
    pos.action = Action::select;
    pos.currentSquare[WHITE] = SQ_8;

    Sanmill::Stack<Position> stack;
    stack.push(pos);

    Key keyBefore = pos.key();
    Move leapMove = make_move(SQ_8, SQ_10);
    pos.do_move(leapMove);

    stack.push(pos);
    Move removeMove = make_move<MOVETYPE_REMOVE>(SQ_9);
    pos.do_move(removeMove);

    EXPECT_TRUE(pos.empty(SQ_9));

    pos.undo_move(stack); // Undo remove
    pos.undo_move(stack); // Undo leap move

    EXPECT_EQ(pos.key(), keyBefore);
    EXPECT_EQ(pos.piece_on(SQ_9), B_PIECE);
    EXPECT_EQ(pos.piece_on(SQ_8), W_PIECE);
    EXPECT_TRUE(pos.empty(SQ_10));
}

} // namespace
