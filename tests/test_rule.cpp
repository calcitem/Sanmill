// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_rule.cpp

#include <gtest/gtest.h>
#include "rule.h"

// A test fixture for Rule-related tests
class RuleTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Optionally re-initialize the global 'rule' to a known default
        // before each test. For example, set the default or
        // re-apply a certain set_rule(...).
        set_rule(0); // e.g., the default "Nine Men's Morris" rule
    }
};

// Test that the global 'rule' matches the default Nine Men's Morris definition
TEST_F(RuleTest, DefaultRuleValues)
{
    // Expect that the global 'rule' is "Nine Men's Morris" after SetUp
    EXPECT_STREQ(rule.name, "Nine Men's Morris") << "The default rule name "
                                                    "should be 'Nine Men's "
                                                    "Morris'.";

    EXPECT_STREQ(rule.description, "Nine Men's Morris") << "The default rule "
                                                           "description should "
                                                           "match as well.";

    EXPECT_EQ(rule.pieceCount, 9) << "In Nine Men's Morris, each side has 9 "
                                     "pieces.";
    EXPECT_EQ(rule.flyPieceCount, 3) << "In many variations, you can 'fly' "
                                        "after dropping below 3 pieces.";

    EXPECT_EQ(rule.piecesAtLeastCount, 3) << "A typical NMM rule: you lose if "
                                             "you have fewer than 3 left.";

    EXPECT_FALSE(rule.hasDiagonalLines) << "Nine Men's Morris typically "
                                           "doesn't have diagonal lines in "
                                           "default representation.";

    // Check the typical action for forming mills in placing phase
    EXPECT_EQ(rule.millFormationActionInPlacingPhase,
              MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard)
        << "Default: removeOpponentsPieceFromBoard for Nine Men's Morris.";

    EXPECT_FALSE(rule.mayMoveInPlacingPhase) << "Standard NMM does not allow "
                                                "moving on the board during "
                                                "placing phase.";

    EXPECT_FALSE(rule.isDefenderMoveFirst) << "In standard NMM, the first "
                                              "mover is White, so not "
                                              "'DefenderMoveFirst'.";

    EXPECT_FALSE(rule.mayRemoveMultiple) << "Normal NMM allows removing "
                                            "exactly 1 piece per mill formed.";

    EXPECT_FALSE(rule.restrictRepeatedMillsFormation) << "By default, we do "
                                                         "not restrict "
                                                         "repeated formation "
                                                         "of the same mill in "
                                                         "standard NMM.";

    EXPECT_FALSE(rule.mayRemoveFromMillsAlways) << "By default, you can't "
                                                   "remove from an existing "
                                                   "mill if there's another "
                                                   "piece not in a mill.";

    EXPECT_FALSE(rule.oneTimeUseMill) << "Some variants allow a once-per-mill "
                                         "removal. Standard NMM does not.";

    EXPECT_EQ(rule.boardFullAction, BoardFullAction::firstPlayerLose)
        << "When the board is full at the end of placing, White (first player) "
           "loses by default in this rule array.";

    EXPECT_EQ(rule.stalemateAction, StalemateAction::endWithStalemateLoss)
        << "If a player can't move, they lose in standard NMM as implemented "
           "here.";

    EXPECT_TRUE(rule.mayFly) << "The 'mayFly' flag is true, meaning when down "
                                "to 3 pieces, you can jump to any vacant "
                                "point.";

    EXPECT_EQ(rule.nMoveRule, (unsigned int)100) << "We might set 100-move "
                                                    "rule as an "
                                                    "example. Or 0 if not used "
                                                    "in your "
                                                    "variant.";

    EXPECT_EQ(rule.endgameNMoveRule, (unsigned int)100) << "Similarly for the "
                                                           "endgame rule. "
                                                           "This test depends "
                                                           "on how your "
                                                           "code sets them.";

    EXPECT_TRUE(rule.threefoldRepetitionRule) << "The default is to allow "
                                                 "draws by threefold "
                                                 "repetition in your code.";
}

// Test setting each rule in the RULES array
TEST_F(RuleTest, SetRuleByIndex)
{
    // We'll iterate from 0 to N_RULES-1 and call set_rule(...) to check if it
    // returns true
    for (int i = 0; i < N_RULES; i++) {
        bool result = set_rule(i);
        EXPECT_TRUE(result)
            << "set_rule(" << i << ") should succeed within valid range.";
        // Optionally, we can verify the 'rule' global has the same name as
        // RULES[i] The array is not declared const char*, so we must check with
        // strncmp or so:
        EXPECT_STREQ(rule.name, RULES[i].name)
            << "Rule name mismatch at index " << i;
        EXPECT_STREQ(rule.description, RULES[i].description)
            << "Rule description mismatch at index " << i;
        EXPECT_EQ(rule.pieceCount, RULES[i].pieceCount)
            << "Piece count mismatch at index " << i;
        // ... and so on, or do partial checks as needed.
    }
}

// Test that out-of-range set_rule(...) fails
TEST_F(RuleTest, SetRuleOutOfRange)
{
    // For negative index
    bool resultNeg = set_rule(-1);
    EXPECT_FALSE(resultNeg) << "set_rule(-1) should fail because it's out of "
                               "range.";

    // For index >= N_RULES
    bool resultTooBig = set_rule(N_RULES);
    EXPECT_FALSE(resultTooBig) << "set_rule(N_RULES) should fail because it's "
                                  "out of range.";
}

// Example test to ensure rule modifications are retained
TEST_F(RuleTest, ModifyRuleFields)
{
    // After set_rule(0), the global 'rule' is Nine Men's Morris
    // Suppose we manually tweak 'rule' to see if it's stored
    rule.pieceCount = 10; // e.g., a custom scenario
    rule.hasDiagonalLines = true;

    // Check
    EXPECT_EQ(rule.pieceCount, 10) << "We updated pieceCount to 10, so it "
                                      "should remain stored in the global rule "
                                      "struct.";
    EXPECT_TRUE(rule.hasDiagonalLines) << "We set hasDiagonalLines = true, so "
                                          "this should persist in 'rule'.";
}
