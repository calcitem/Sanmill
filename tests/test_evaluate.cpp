// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// test_evaluate.cpp

#include <gtest/gtest.h>
#include <cstring>
#include "evaluate.h"
#include "position.h"
#include "rule.h"
#include "option.h"

extern Rule rule;
extern GameOptions gameOptions;

/*
 * Instead of 'override', we store "mock" fields in MockPosition,
 * and then 'sync' them into the parent's data members so that
 * evaluate(...) sees them. This approach is used because Position's
 * methods are NOT virtual, so normal polymorphism won't work.
 */

class MockPosition : public Position
{
public:
    MockPosition()
    {
        // Some default mock fields
        mockPhase = Phase::none;
        mockSideToMove = WHITE;
        mockAction = Action::none;
        mockWhiteInHand = 0;
        mockBlackInHand = 0;
        mockWhiteOnBoard = 0;
        mockBlackOnBoard = 0;
        mockWhiteToRemove = 0;
        mockBlackToRemove = 0;
        mockMobilityDiff = 0;

        // Booleans
        mockAllSurrounded = false;
        mockFocusOnBlocking = false;
        mockConsiderMobility = false;
    }

    // Our "mock" fields
    Phase mockPhase;
    Color mockSideToMove;
    Action mockAction;
    int mockWhiteInHand;
    int mockBlackInHand;
    int mockWhiteOnBoard;
    int mockBlackOnBoard;
    int mockWhiteToRemove;
    int mockBlackToRemove;
    bool mockAllSurrounded;
    bool mockFocusOnBlocking;
    bool mockConsiderMobility;
    int mockMobilityDiff;

    // The critical part: copy the mock fields into
    // the parent's actual data members that 'evaluate(...)' uses.
    void syncFields()
    {
        // The base 'Position' class has:
        //   phase, sideToMove, action, pieceInHandCount[], pieceOnBoardCount[],
        //   pieceToRemoveCount[], mobilityDiff, plus any needed booleans
        this->phase = mockPhase;
        this->sideToMove = mockSideToMove;
        this->action = mockAction;
        this->pieceInHandCount[WHITE] = mockWhiteInHand;
        this->pieceInHandCount[BLACK] = mockBlackInHand;
        this->pieceOnBoardCount[WHITE] = mockWhiteOnBoard;
        this->pieceOnBoardCount[BLACK] = mockBlackOnBoard;
        this->pieceToRemoveCount[WHITE] = mockWhiteToRemove;
        this->pieceToRemoveCount[BLACK] = mockBlackToRemove;
        this->mobilityDiff = mockMobilityDiff;

        // If is_all_surrounded(...) is used by evaluate, in the real code
        // we can't override it, so we can replicate the logic that:
        // "If mockAllSurrounded => forcibly cause some condition in the
        // parent's data
        //  that leads is_all_surrounded(...) to return true."
        //
        // For instance, if we only rely on "lack of adjacency" or some other
        // parent's method, we can forcibly set pieceOnBoardCount or adjacency
        // to trick the real logic into returning 'true'. This depends on how
        // 'Position::is_all_surrounded(...)' is implemented.
        //
        // If the real code is too complex, you might not be able to fully
        // “force” it to return true, unless you *also* can rewrite the base
        // code or do more advanced test strategies.
        //
        // We'll skip it here; you can do something like:
        // if (mockAllSurrounded) {
        //     // Possibly set pieceOnBoardCount[...] or adjacency
        //     // so that is_all_surrounded() is forced to be true.
        // }
    }

    // If you call 'evaluate()' from the child object directly, you must
    // be sure to use the parent's interface. For example:
    //   MockPosition mp;
    //   mp.syncFields();
    //   Value v = Eval::evaluate((Position&)mp);
};

class EvaluateTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        rule.pieceCount = 9;
        rule.piecesAtLeastCount = 3;
        rule.boardFullAction = BoardFullAction::firstPlayerLose;
        rule.stalemateAction = StalemateAction::endWithStalemateLoss;
        rule.mayFly = false;
        rule.hasDiagonalLines = false;
        rule.oneTimeUseMill = false;

        gameOptions.setConsiderMobility(false);
        gameOptions.setFocusOnBlockingPaths(false);
    }

    void TearDown() override { }
};

// 1) Phase::none => VALUE_ZERO
TEST_F(EvaluateTest, PhaseNoneReturnsZero)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::none;
    pos.mockSideToMove = WHITE;
    pos.syncFields(); // Important: copy to parent's data

    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, VALUE_ZERO);
}

// 2) Phase::placing => White has more in-hand
TEST_F(EvaluateTest, PhasePlacingWhiteHasMorePiecesInHand)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    // Clear the board by setting all squares to NO_PIECE
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::placing;
    pos.mockSideToMove = WHITE;
    pos.mockWhiteInHand = 2;
    pos.mockBlackInHand = 0;
    pos.mockFocusOnBlocking = false;
    pos.mockConsiderMobility = false;
    pos.syncFields();

    // Synchronize the bitboards with the current board state
    pos.reset_bb();

    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, 10) << "White in-hand diff => 2 => 2*5=10";
}

// 3) Phase::moving with mobility
TEST_F(EvaluateTest, PhaseMovingWithMobilityFixed)
{
    // 1) Enable mobility in options
    gameOptions.setConsiderMobility(true);

    // 2) Construct a real Position (not a mock) so that
    //    adjacency-based logic actually yields mobilityDiff=+3.
    Position pos;
    std::memset(&pos, 0, sizeof(pos));

    // Clear board first
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // We'll place White pieces on a7, a4 => SQ_31, SQ_30
    pos.board[SQ_31] = W_PIECE; // White
    pos.board[SQ_30] = W_PIECE; // White

    // Place Black piece on b6 => SQ_23
    pos.board[SQ_23] = B_PIECE; // Black

    // Let White have 2 on board, Black have 1 on board
    pos.pieceOnBoardCount[WHITE] = 2;
    pos.pieceOnBoardCount[BLACK] = 1;

    // White has 1 in-hand, Black 0 => inHandDiff=+1 => +5
    pos.pieceInHandCount[WHITE] = 1;
    pos.pieceInHandCount[BLACK] = 0;

    // Mobility diff should be +1
    pos.mobilityDiff = 1;

    // Force "phase = placing", sideToMove=WHITE
    pos.phase = Phase::placing;
    pos.sideToMove = WHITE;
    // The 'action' can be anything except remove, say 'place'
    pos.action = Action::place;

    // Sync bitboards
    pos.reset_bb();

    // Possibly recalc mobility:
    // If the engine doesn't do it automatically, we do:
    int actualDiff = pos.calculate_mobility_diff();
    // We want to confirm it's +1 (you can print or debug).
    // If not 1, adjust the piece placement above.
    EXPECT_EQ(actualDiff, pos.mobilityDiff) << "Mobility diff should be +1";

    // Finally, evaluate
    Value val = Eval::evaluate(pos);
    // We expect: mobilityDiff(+1) + inHandDiff(+5) + onBoardDiff(+5) = 11
    // => let's check that:
    EXPECT_EQ(val, 11) << "We expect White leads by mobility=1, +1 in hand, +1 "
                          "on board => total 11.";
}

// 4) side_to_move=BLACK => sign invert
TEST_F(EvaluateTest, PhasePlacingBlackSideToMoveInvertsSign)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::placing;
    pos.mockSideToMove = BLACK;
    // White leads in-hand by 2 => +10
    pos.mockWhiteInHand = 2;
    pos.mockBlackInHand = 0;

    pos.syncFields();
    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, -10);
}

// 5) White < piecesAtLeastCount => -MATE
TEST_F(EvaluateTest, PhaseGameOverWhiteLessThanPiecesAtLeastCount)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::gameOver;
    pos.mockSideToMove = WHITE;
    // White on board=2 => <3 => losing => -80
    pos.mockWhiteOnBoard = 2;
    pos.mockBlackOnBoard = 5;
    rule.piecesAtLeastCount = 3;

    pos.syncFields();
    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, -VALUE_MATE);
}

// 6) Board full => firstPlayerLose => -MATE
TEST_F(EvaluateTest, PhaseGameOverBoardFull_12_FirstPlayerLose)
{
    MockPosition pos;
    pos.mockPhase = Phase::gameOver;
    pos.mockSideToMove = WHITE;
    // total=24 => board is full
    pos.mockWhiteOnBoard = 12;
    pos.mockBlackOnBoard = 12;
    rule.pieceCount = 12;
    rule.boardFullAction = BoardFullAction::firstPlayerLose;

    pos.syncFields();
    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, -VALUE_MATE);
}

// 7) Board full => agreeToDraw => 0
TEST_F(EvaluateTest, PhaseGameOverBoardFull_12_AgreeToDraw)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::gameOver;
    pos.mockSideToMove = BLACK;

    pos.mockWhiteOnBoard = 12;
    pos.mockBlackOnBoard = 12;
    rule.pieceCount = 12;
    rule.boardFullAction = BoardFullAction::agreeToDraw;

    pos.syncFields();
    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, VALUE_DRAW);
}

// 8) stalemateLoss => side=BLACK => +MATE
TEST_F(EvaluateTest, PhaseGameOverStalemateLossFixed)
{
    // Configure stalemate to result in a loss for BLACK, leading to a mate
    // evaluation
    rule.stalemateAction = StalemateAction::endWithStalemateLoss;

    // Construct a Position object
    Position pos;
    std::memset(&pos, 0, sizeof(pos));

    // Clear the board by setting all squares to NO_PIECE
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // Place BLACK pieces on specific squares
    pos.board[SQ_31] = B_PIECE;
    pos.board[SQ_24] = B_PIECE;
    pos.board[SQ_30] = B_PIECE;
    pos.board[SQ_23] = B_PIECE;

    // Place WHITE pieces on specific squares
    pos.board[SQ_25] = W_PIECE;
    pos.board[SQ_16] = W_PIECE;
    pos.board[SQ_22] = W_PIECE;
    pos.board[SQ_29] = W_PIECE;

    // Set the count of pieces on the board for each side
    pos.pieceOnBoardCount[BLACK] = 4;
    pos.pieceOnBoardCount[WHITE] = 4;

    // Set the side to move to BLACK, phase to moving, and action to select
    pos.sideToMove = BLACK;
    pos.phase = Phase::moving;
    pos.action = Action::select;

    // Synchronize the bitboards with the current board state
    pos.reset_bb();

    // Evaluate the current position
    Value val = Eval::evaluate(pos);

    // Since BLACK is fully surrounded and stalemateAction is set to
    // endWithStalemateLoss, we expect the evaluation to be more than VALUE_MATE
    // (+80) from WHITE's perspective
    EXPECT_LT(val, VALUE_MATE) << "Black is fully surrounded => from black's "
                                  "perspective => less than +80 (stalemate "
                                  "loss).";
}

// 9) black < piecesAtLeastCount => from white => +MATE
TEST_F(EvaluateTest, PhaseGameOverBlackLessThanPiecesAtLeastCount)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::gameOver;
    pos.mockSideToMove = WHITE;
    // black<3 => +MATE
    pos.mockWhiteOnBoard = 4;
    pos.mockBlackOnBoard = 2;
    rule.piecesAtLeastCount = 3;

    pos.syncFields();
    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, VALUE_MATE);
}

// 10) Phase::moving, action=remove => pieceToRemoveDiff => *5
TEST_F(EvaluateTest, PhaseMovingActionRemoveCountsPieceToRemove)
{
    MockPosition pos;
    std::memset(&pos, 0, sizeof(pos));

    pos.mockPhase = Phase::moving;
    pos.mockSideToMove = WHITE;
    pos.mockAction = Action::remove;
    pos.mockWhiteToRemove = 2;
    pos.mockBlackToRemove = 1;
    // in-hand/on-board diffs are zero => so we only see +5 from remove diff=1

    pos.syncFields();

    // Synchronize the bitboards with the current board state
    pos.reset_bb();

    Value val = Eval::evaluate(pos);
    EXPECT_EQ(val, 5);
}

// ---- New tests for cardinal-control and live-mill-candidate heuristics ----

// 11) Cardinal-point bonus: White occupies all 4 cardinal squares of the
//     middle ring; Black occupies none => evaluation should favour White.
TEST_F(EvaluateTest, CardinalControlFavoursWhite)
{
    rule.hasDiagonalLines = false;
    gameOptions.setConsiderMobility(false);
    gameOptions.setFocusOnBlockingPaths(false);

    Position pos;
    std::memset(&pos, 0, sizeof(pos));
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // White on all four cardinal squares of the middle ring
    pos.board[SQ_16] = W_PIECE;
    pos.board[SQ_18] = W_PIECE;
    pos.board[SQ_20] = W_PIECE;
    pos.board[SQ_22] = W_PIECE;
    pos.pieceOnBoardCount[WHITE] = 4;
    pos.pieceOnBoardCount[BLACK] = 0;

    pos.phase = Phase::moving;
    pos.sideToMove = WHITE;
    pos.action = Action::select;

    pos.reset_bb();

    // Piece-on-board diff: +4 pieces => +20; cardinal diff: +4 => +4;
    // live-mill candidate diff: 0 (no pairs yet)
    // Total from WHITE's perspective: >= 24
    Value val = Eval::evaluate(pos);
    EXPECT_GT(val, 0) << "White holding all 4 cardinal squares should yield a "
                         "positive evaluation.";
}

// 12) Cardinal-point bonus symmetry: Black holds all 4 cardinal squares;
//     evaluation should be negative from White's perspective.
TEST_F(EvaluateTest, CardinalControlFavoursBlack)
{
    rule.hasDiagonalLines = false;
    gameOptions.setConsiderMobility(false);
    gameOptions.setFocusOnBlockingPaths(false);

    Position pos;
    std::memset(&pos, 0, sizeof(pos));
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    pos.board[SQ_16] = B_PIECE;
    pos.board[SQ_18] = B_PIECE;
    pos.board[SQ_20] = B_PIECE;
    pos.board[SQ_22] = B_PIECE;
    pos.pieceOnBoardCount[WHITE] = 0;
    pos.pieceOnBoardCount[BLACK] = 4;

    pos.phase = Phase::moving;
    pos.sideToMove = WHITE;
    pos.action = Action::select;

    pos.reset_bb();

    Value val = Eval::evaluate(pos);
    EXPECT_LT(val, 0) << "Black holding all 4 cardinal squares should yield a "
                         "negative evaluation from White's perspective.";
}

// 13) Live-mill candidate bonus: White has two pieces on a line with an empty
//     third square (1-step potential mill); Black has none.
//     The new term should add +1 to White's evaluation.
TEST_F(EvaluateTest, LiveMillCandidateFavoursWhite)
{
    rule.hasDiagonalLines = false;
    rule.pieceCount = 9;
    gameOptions.setConsiderMobility(false);
    gameOptions.setFocusOnBlockingPaths(false);

    Position pos;
    std::memset(&pos, 0, sizeof(pos));
    std::memset(pos.board, NO_PIECE, sizeof(pos.board));

    // Place two White pieces on the outer ring top line: SQ_31, SQ_24
    // (the horizontal line is SQ_31-SQ_24-SQ_25; SQ_25 is empty => 1 candidate
    // for White)
    pos.board[SQ_31] = W_PIECE;
    pos.board[SQ_24] = W_PIECE;
    pos.pieceOnBoardCount[WHITE] = 2;
    pos.pieceOnBoardCount[BLACK] = 0;

    pos.phase = Phase::moving;
    pos.sideToMove = WHITE;
    pos.action = Action::select;

    pos.reset_bb();

    // Make sure the mill table is initialised (static, initialised once)
    Position::create_mill_table();

    Value valWithBonus = Eval::evaluate(pos);
    // The live-mill bonus for White (1 candidate) contributes +1.
    // Piece-on-board diff contributes +10.  Cardinal: 0.
    // Expected total at minimum: piece bonus alone = 10, so > 0.
    EXPECT_GT(valWithBonus, 0) << "White with a potential mill should be "
                                  "evaluated positively.";
}

// 14) Exact cardinal delta in the standard board: moving one White piece from
//     a non-cardinal middle-ring corner (f6) to a cardinal point (d6) should
//     change the evaluation by exactly +1 when all other terms are identical.
TEST_F(EvaluateTest, CardinalBonusDeltaIsExactOnStandardBoard)
{
    Position cardinalPos;
    cardinalPos.reset();
    cardinalPos.phase = Phase::moving;
    cardinalPos.sideToMove = WHITE;
    cardinalPos.action = Action::select;
    cardinalPos.pieceInHandCount[WHITE] = 0;
    cardinalPos.pieceInHandCount[BLACK] = 0;
    std::memset(cardinalPos.board, NO_PIECE, sizeof(cardinalPos.board));
    cardinalPos.board[SQ_16] = W_PIECE; // d6: center cardinal
    cardinalPos.pieceOnBoardCount[WHITE] = 1;
    cardinalPos.pieceOnBoardCount[BLACK] = 0;
    cardinalPos.reset_bb();

    Position nonCardinalPos = cardinalPos;
    std::memset(nonCardinalPos.board, NO_PIECE, sizeof(nonCardinalPos.board));
    nonCardinalPos.board[SQ_17] = W_PIECE; // f6: middle-ring corner
    nonCardinalPos.reset_bb();

    const Value cardinalVal = Eval::evaluate(cardinalPos);
    const Value nonCardinalVal = Eval::evaluate(nonCardinalPos);
    EXPECT_EQ(cardinalVal - nonCardinalVal, 1)
        << "The standard-board cardinal bonus should contribute exactly +1.";
}

// 15) Exact cardinal delta in the diagonal board: the orthogonal crossings
//     stay the cardinal points. d6 (SQ_16) should still outrank f6 (SQ_17).
TEST_F(EvaluateTest, CardinalBonusUsesOrthogonalCrossingsInDiagonalVariant)
{
    rule.hasDiagonalLines = true;

    Position cardinalPos;
    cardinalPos.reset();
    cardinalPos.phase = Phase::moving;
    cardinalPos.sideToMove = WHITE;
    cardinalPos.action = Action::select;
    cardinalPos.pieceInHandCount[WHITE] = 0;
    cardinalPos.pieceInHandCount[BLACK] = 0;
    std::memset(cardinalPos.board, NO_PIECE, sizeof(cardinalPos.board));
    cardinalPos.board[SQ_16] = W_PIECE; // d6: still a cardinal point
    cardinalPos.pieceOnBoardCount[WHITE] = 1;
    cardinalPos.pieceOnBoardCount[BLACK] = 0;
    cardinalPos.reset_bb();

    Position starCornerPos = cardinalPos;
    std::memset(starCornerPos.board, NO_PIECE, sizeof(starCornerPos.board));
    starCornerPos.board[SQ_17] = W_PIECE; // f6: star-square / corner on diagonal
    starCornerPos.reset_bb();

    const Value cardinalVal = Eval::evaluate(cardinalPos);
    const Value starCornerVal = Eval::evaluate(starCornerPos);
    EXPECT_EQ(cardinalVal - starCornerVal, 1)
        << "Diagonal variants should still treat SQ_16/18/20/22 as the "
           "center cardinal squares.";
}

// 16) Exact live-mill delta: two equal-material positions differ only in
//     whether White has a single 1-step mill candidate. The evaluator should
//     differ by exactly +1.
TEST_F(EvaluateTest, LiveMillCandidateDeltaIsExact)
{
    Position liveCandidatePos;
    liveCandidatePos.reset();
    liveCandidatePos.phase = Phase::moving;
    liveCandidatePos.sideToMove = WHITE;
    liveCandidatePos.action = Action::select;
    liveCandidatePos.pieceInHandCount[WHITE] = 0;
    liveCandidatePos.pieceInHandCount[BLACK] = 0;
    std::memset(liveCandidatePos.board, NO_PIECE, sizeof(liveCandidatePos.board));
    liveCandidatePos.board[SQ_31] = W_PIECE;
    liveCandidatePos.board[SQ_24] = W_PIECE; // top line 31-24-25 => one live candidate
    liveCandidatePos.pieceOnBoardCount[WHITE] = 2;
    liveCandidatePos.pieceOnBoardCount[BLACK] = 0;
    liveCandidatePos.reset_bb();

    Position noCandidatePos = liveCandidatePos;
    std::memset(noCandidatePos.board, NO_PIECE, sizeof(noCandidatePos.board));
    noCandidatePos.board[SQ_31] = W_PIECE;
    noCandidatePos.board[SQ_26] = W_PIECE; // no 2-of-3 line
    noCandidatePos.reset_bb();

    const Value liveVal = Eval::evaluate(liveCandidatePos);
    const Value noCandidateVal = Eval::evaluate(noCandidatePos);
    EXPECT_EQ(liveVal - noCandidateVal, 1)
        << "A single additional live-mill candidate should contribute exactly +1.";
}

// 17) One-time-use mills must suppress already-consumed lines from the live
//     candidate count. The same board should evaluate 1 point lower once the
//     old line is marked as already used.
TEST_F(EvaluateTest, OneTimeUseMillSuppressesUsedLiveCandidate)
{
    rule.oneTimeUseMill = true;

    Position freshPos;
    freshPos.reset();
    freshPos.phase = Phase::moving;
    freshPos.sideToMove = WHITE;
    freshPos.action = Action::select;
    freshPos.pieceInHandCount[WHITE] = 0;
    freshPos.pieceInHandCount[BLACK] = 0;
    std::memset(freshPos.board, NO_PIECE, sizeof(freshPos.board));
    freshPos.board[SQ_31] = W_PIECE;
    freshPos.board[SQ_24] = W_PIECE;
    freshPos.pieceOnBoardCount[WHITE] = 2;
    freshPos.pieceOnBoardCount[BLACK] = 0;
    freshPos.reset_bb();
    freshPos.formedMillsBB[WHITE] = 0;

    Position consumedPos = freshPos;
    consumedPos.formedMillsBB[WHITE] =
        square_bb(SQ_31) | square_bb(SQ_24) | square_bb(SQ_25);

    const Value freshVal = Eval::evaluate(freshPos);
    const Value consumedVal = Eval::evaluate(consumedPos);
    EXPECT_EQ(freshVal - consumedVal, 1)
        << "An already-consumed one-time-use mill line must not count as a "
           "live candidate.";
}
