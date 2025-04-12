// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_rule.cpp

#include <gtest/gtest.h>
#include "rule.h"

// Create a test suite for the Rule type.
class RuleTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Default Rule values
        // We'll use the global rule object for testing rule settings
        expectedRule = {"Nine Men's Morris",
                        "Nine Men's Morris",
                        9,
                        3,
                        3,
                        false,
                        MillFormationActionInPlacingPhase::
                            removeOpponentsPieceFromBoard,
                        false,
                        false,
                        false,
                        false,
                        false,
                        false,
                        BoardFullAction::firstPlayerLose,
                        StalemateAction::endWithStalemateLoss,
                        true,
                        100,
                        100,
                        true};
    }

    // Expected Rule values based on the default.
    Rule expectedRule;
};

// Test that setting the default rule works.
TEST_F(RuleTest, DefaultRule)
{
    // Apply Rule 0 (Nine Men's Morris)
    ASSERT_TRUE(set_rule(0));

    // Check Rule got set correctly
    EXPECT_STREQ(rule.name, expectedRule.name);
    EXPECT_STREQ(rule.description, expectedRule.description);
    EXPECT_EQ(rule.pieceCount, expectedRule.pieceCount);
    EXPECT_EQ(rule.flyPieceCount, expectedRule.flyPieceCount);
    EXPECT_EQ(rule.piecesAtLeastCount, expectedRule.piecesAtLeastCount);
    EXPECT_EQ(rule.hasDiagonalLines, expectedRule.hasDiagonalLines);
    EXPECT_EQ(rule.millFormationActionInPlacingPhase,
              expectedRule.millFormationActionInPlacingPhase);
    EXPECT_EQ(rule.mayMoveInPlacingPhase, expectedRule.mayMoveInPlacingPhase);
    EXPECT_EQ(rule.isDefenderMoveFirst, expectedRule.isDefenderMoveFirst);
    EXPECT_EQ(rule.mayRemoveMultiple, expectedRule.mayRemoveMultiple);
    EXPECT_EQ(rule.restrictRepeatedMillsFormation,
              expectedRule.restrictRepeatedMillsFormation);
    EXPECT_EQ(rule.mayRemoveFromMillsAlways,
              expectedRule.mayRemoveFromMillsAlways);
    EXPECT_EQ(rule.oneTimeUseMill, expectedRule.oneTimeUseMill);
    EXPECT_EQ(rule.boardFullAction, expectedRule.boardFullAction);
    EXPECT_EQ(rule.stalemateAction, expectedRule.stalemateAction);
    EXPECT_EQ(rule.mayFly, expectedRule.mayFly);
    EXPECT_EQ(rule.nMoveRule, expectedRule.nMoveRule);
    EXPECT_EQ(rule.endgameNMoveRule, expectedRule.endgameNMoveRule);
    EXPECT_EQ(rule.threefoldRepetitionRule, expectedRule.threefoldRepetitionRule);
}

// Test that setting another rule works.
TEST_F(RuleTest, TwelveMensMorrisRule)
{
    // Apply Rule 1 (Twelve Men's Morris)
    ASSERT_TRUE(set_rule(1));

    // Update expected rule
    expectedRule.pieceCount = 12;
    expectedRule.hasDiagonalLines = true;
    EXPECT_STREQ(rule.name, "Twelve Men's Morris");
    EXPECT_STREQ(rule.description, "Twelve Men's Morris");
    EXPECT_EQ(rule.pieceCount, expectedRule.pieceCount);
    EXPECT_EQ(rule.flyPieceCount, expectedRule.flyPieceCount);
    EXPECT_EQ(rule.piecesAtLeastCount, expectedRule.piecesAtLeastCount);
    EXPECT_EQ(rule.hasDiagonalLines, expectedRule.hasDiagonalLines);
    EXPECT_EQ(rule.millFormationActionInPlacingPhase,
              expectedRule.millFormationActionInPlacingPhase);
    EXPECT_EQ(rule.mayMoveInPlacingPhase, expectedRule.mayMoveInPlacingPhase);
    EXPECT_EQ(rule.isDefenderMoveFirst, expectedRule.isDefenderMoveFirst);
    EXPECT_EQ(rule.mayRemoveMultiple, expectedRule.mayRemoveMultiple);
    EXPECT_EQ(rule.restrictRepeatedMillsFormation,
              expectedRule.restrictRepeatedMillsFormation);
    EXPECT_EQ(rule.mayRemoveFromMillsAlways,
              expectedRule.mayRemoveFromMillsAlways);
    EXPECT_EQ(rule.oneTimeUseMill, expectedRule.oneTimeUseMill);
    EXPECT_EQ(rule.boardFullAction, expectedRule.boardFullAction);
    EXPECT_EQ(rule.stalemateAction, expectedRule.stalemateAction);
    EXPECT_EQ(rule.mayFly, expectedRule.mayFly);
    EXPECT_EQ(rule.nMoveRule, expectedRule.nMoveRule);
    EXPECT_EQ(rule.endgameNMoveRule, expectedRule.endgameNMoveRule);
    EXPECT_EQ(rule.threefoldRepetitionRule, expectedRule.threefoldRepetitionRule);
}

// Test that the Six Men's Morris rule works
TEST_F(RuleTest, SixMensMorrisRule)
{
    // Apply Rule 11 (Six Men's Morris)
    ASSERT_TRUE(set_rule(11));

    // Update expected rule
    expectedRule.pieceCount = 6;
    expectedRule.hasDiagonalLines = false;
    EXPECT_STREQ(rule.name, "Six Men's Morris");
    EXPECT_STREQ(rule.description, "Six Men's Morris");
    EXPECT_EQ(rule.pieceCount, expectedRule.pieceCount);
    EXPECT_EQ(rule.flyPieceCount, expectedRule.flyPieceCount);
    EXPECT_EQ(rule.piecesAtLeastCount, expectedRule.piecesAtLeastCount);
    EXPECT_EQ(rule.hasDiagonalLines, expectedRule.hasDiagonalLines);
    EXPECT_EQ(rule.millFormationActionInPlacingPhase,
              expectedRule.millFormationActionInPlacingPhase);
    EXPECT_EQ(rule.mayMoveInPlacingPhase, expectedRule.mayMoveInPlacingPhase);
    EXPECT_EQ(rule.isDefenderMoveFirst, expectedRule.isDefenderMoveFirst);
    EXPECT_EQ(rule.mayRemoveMultiple, expectedRule.mayRemoveMultiple);
    EXPECT_EQ(rule.restrictRepeatedMillsFormation,
              expectedRule.restrictRepeatedMillsFormation);
    EXPECT_EQ(rule.mayRemoveFromMillsAlways,
              expectedRule.mayRemoveFromMillsAlways);
    EXPECT_EQ(rule.oneTimeUseMill, expectedRule.oneTimeUseMill);
    EXPECT_EQ(rule.boardFullAction, expectedRule.boardFullAction);
    EXPECT_EQ(rule.stalemateAction, expectedRule.stalemateAction);
    EXPECT_EQ(rule.mayFly, expectedRule.mayFly);
    EXPECT_EQ(rule.nMoveRule, expectedRule.nMoveRule);
    EXPECT_EQ(rule.endgameNMoveRule, expectedRule.endgameNMoveRule);
    EXPECT_EQ(rule.threefoldRepetitionRule, expectedRule.threefoldRepetitionRule);
}

// Test that setting rule with a non-existent index fails.
TEST_F(RuleTest, InvalidRuleIndices)
{
    // For index < 0
    bool resultNegative = set_rule(-1);
    EXPECT_FALSE(resultNegative) << "set_rule(-1) should fail because it's "
                                    "outside the valid index range.";

    // We'll iterate from 0 to N_RULES-1 and call set_rule(...) to check if it
    // works as expected (it should return true for all valid indices)
    for (int i = 0; i < N_RULES; i++) {
        bool result = set_rule(i);
        EXPECT_TRUE(result) << "set_rule(" << i
                            << ") should succeed because it's "
                               "within the valid index range.";
    }

    // For index >= N_RULES
    bool resultTooBig = set_rule(N_RULES);
    EXPECT_FALSE(resultTooBig) << "set_rule(N_RULES) should fail because it's "
                                  "outside the valid index range.";
}
