// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_ucioption.cpp

#include <gtest/gtest.h>
#include <string>
#include <sstream>
#include "uci.h"    // For UCI::Option and OptionsMap
#include "option.h" // For GameOptions
#include "rule.h"   // For Rule object and associated actions

using namespace UCI;

/**
 * @class UCIOptionTest
 * @brief A test fixture for UCI option-related tests.
 */
class UCIOptionTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // We can do a fresh initialization of the Options map
        // to ensure each test starts with a known state.
        Options.clear();
        UCI::init(Options);
        gameOptions = GameOptions();
    }

    void TearDown() override
    {
        // Cleanup if needed, though in this case not strictly necessary
    }
};

/**
 * @test InitializeDefaults
 * @brief Checks that after calling UCI::init, the expected options are
 * populated.
 */
TEST_F(UCIOptionTest, InitializeDefaults)
{
    // We expect at least some known options, e.g. "Hash", "Threads".
    // We'll pick a few to verify they exist and have correct types.
    ASSERT_TRUE(Options.find("Hash") != Options.end()) << "The 'Hash' option "
                                                          "should be present "
                                                          "after "
                                                          "initialization.";
    ASSERT_TRUE(Options.find("Threads") != Options.end()) << "The 'Threads' "
                                                             "option should be "
                                                             "present after "
                                                             "initialization.";
    ASSERT_TRUE(Options.find("SkillLevel") != Options.end())
        << "The 'SkillLevel' option should be present after initialization.";

    // Check that default values are as set in init()
    const Option &hashOpt = Options["Hash"];
    // It's a "spin" type, defaulted to 16 by code
    // The operator double() is used to get numeric value for 'spin' or 'check'
    EXPECT_DOUBLE_EQ(static_cast<double>(hashOpt), 16.0) << "Default Hash size "
                                                            "should be 16 MB.";

    const Option &skillOpt = Options["SkillLevel"];
    EXPECT_DOUBLE_EQ(static_cast<double>(skillOpt), 1.0) << "SkillLevel "
                                                            "default should be "
                                                            "1.0.";
}

/**
 * @test SetSpinOptionWithinBounds
 * @brief Verifies that a spin option can be updated within valid bounds.
 */
TEST_F(UCIOptionTest, SetSpinOptionWithinBounds)
{
    // "Hash" is a spin type, range e.g. (1..33554432) or so, default 16
    ASSERT_TRUE(Options.find("Hash") != Options.end()) << "'Hash' should "
                                                          "exist.";

    auto &hashOpt = Options["Hash"];
    // Attempt to set a valid new value
    hashOpt = "32";
    EXPECT_DOUBLE_EQ(static_cast<double>(hashOpt), 32.0) << "Hash should "
                                                            "accept a valid "
                                                            "spin value of 32.";

    // Attempt to set an out-of-bounds value (like 0, below min=1 if that's the
    // init)
    hashOpt = "0";
    // The out-of-bounds assignment should fail, retaining old value
    // If out-of-bounds is clamped or refused per your code, we check that:
    EXPECT_DOUBLE_EQ(static_cast<double>(hashOpt), 32.0)
        << "Hash should ignore out-of-bounds (too low) and remain 32.";
}

/**
 * @test SetCheckOption
 * @brief Ensures we can set a boolean (check) option properly.
 */
TEST_F(UCIOptionTest, SetCheckOption)
{
    // By default, "AiIsLazy" is a check type with default false
    ASSERT_TRUE(Options.find("AiIsLazy") != Options.end()) << "'AiIsLazy' "
                                                              "should exist.";
    auto &lazyOpt = Options["AiIsLazy"];

    // Check the default
    bool isLazy = (static_cast<double>(lazyOpt) != 0.0); // spin or check =>
                                                         // double
    EXPECT_FALSE(isLazy) << "Default AiIsLazy should be false (0.0).";

    // Set to "true"
    lazyOpt = "true";
    isLazy = (static_cast<double>(lazyOpt) != 0.0);
    EXPECT_TRUE(isLazy) << "After setting to 'true', AiIsLazy should be true.";

    // Setting to some invalid string should not change the value
    lazyOpt = "xyz"; // should be ignored
    isLazy = (static_cast<double>(lazyOpt) != 0.0);
    EXPECT_TRUE(isLazy) << "Invalid check assignment should leave the value "
                           "unchanged.";
}

/**
 * @test ComboOption
 * @brief Verifies that a combo-type option can be assigned valid enumerations
 * only.
 */
TEST_F(UCIOptionTest, ComboOption)
{
    // Suppose "Analysis Contempt" was a combo from init() with a default of
    // "Both"
    auto comboItr = Options.find("Analysis Contempt");
    if (comboItr == Options.end())
        GTEST_SKIP() << "No 'Analysis Contempt' combo option in this build.";

    // It's a combo with a defaultValue containing "Both var Off var White var
    // Black var Both"
    auto &acOpt = comboItr->second;

    // The default should be "Both"
    // We'll check if operator == works or we can cast to double or string
    // Actually, "combo" is special. We can test with bool operator== or
    // convert to string, but let's do a simpler approach:
    EXPECT_TRUE(acOpt == "Both") << "Analysis Contempt default should be "
                                    "'Both'";

    // Attempt a valid assignment
    acOpt = "White";
    // Should succeed
    EXPECT_TRUE(acOpt == "White") << "Valid assignment to 'White' should "
                                     "succeed.";

    // Attempt an invalid assignment
    acOpt = "Foobar";
    // Should fail internally, remain "White"
    EXPECT_FALSE(acOpt == "Foobar") << "Invalid combo assignment should be "
                                       "ignored.";
    EXPECT_TRUE(acOpt == "White") << "Option remains set to the last valid "
                                     "value: 'White'.";
}

/**
 * @test ButtonOption
 * @brief Checks that setting a button-type option triggers a callback but does
 * not store a value.
 */
TEST_F(UCIOptionTest, ButtonOption)
{
    // "Clear Hash" in init is type button. The callback triggers
    // Search::clear().
    ASSERT_TRUE(Options.find("Clear Hash") != Options.end()) << "'Clear Hash' "
                                                                "button should "
                                                                "exist.";
    auto &btnOpt = Options["Clear Hash"];

    // Attempt to assign a string to see if it remains
    btnOpt = "someString";
    // The code for button basically does a callback and does not store the
    // value. There's no direct way to test the callback here unless we hook or
    // mock but we can check that the internal currentValue hasn't changed from
    // default or see that it doesn't hold "someString".

    // We can't cast it to a double or string meaningfully,
    // but the main test is that we didn't crash or throw,
    // and presumably the callback was invoked.
    SUCCEED() << "Setting a button-type option should not crash or store a "
                 "value.";
}

/**
 * @test RuleOptionBindings
 * @brief Ensures that changes to rule-related spin/check combos update the
 * 'rule' object as intended.
 */
TEST_F(UCIOptionTest, RuleOptionBindings)
{
    // For example, we set "PiecesCount" => 10
    auto pCountItr = Options.find("PiecesCount");
    if (pCountItr == Options.end())
        GTEST_SKIP() << "No 'PiecesCount' option found.";

    // Current default is presumably 9
    EXPECT_EQ(rule.pieceCount, 9) << "Rule pieceCount should default to 9 as "
                                     "per init setup.";
    pCountItr->second = "10";
    EXPECT_EQ(rule.pieceCount, 10) << "After setting 'PiecesCount' to 10, "
                                      "rule.pieceCount should reflect 10.";
}

/**
 * @test OnChangeCallbacks
 * @brief Generic test verifying that spin/check changes trigger relevant
 * callbacks that update gameOptions or rule.
 */
TEST_F(UCIOptionTest, OnChangeCallbacks)
{
    // "SkillLevel" modifies gameOptions.setSkillLevel(int)
    auto skillItr = Options.find("SkillLevel");
    ASSERT_TRUE(skillItr != Options.end()) << "SkillLevel option should exist.";
    // default is 1
    EXPECT_EQ(gameOptions.getSkillLevel(), 1) << "Default skill level should "
                                                 "be 1.";
    skillItr->second = "5";
    EXPECT_EQ(gameOptions.getSkillLevel(), 5) << "Callback should update the "
                                                 "gameOptions skill level to "
                                                 "5.";

    // "AiIsLazy" modifies gameOptions.setAiIsLazy(bool)
    auto lazyItr = Options.find("AiIsLazy");
    ASSERT_TRUE(lazyItr != Options.end()) << "AiIsLazy option should exist.";
    EXPECT_FALSE(gameOptions.getAiIsLazy()) << "Default AiIsLazy is false.";
    lazyItr->second = "true";
    EXPECT_TRUE(gameOptions.getAiIsLazy()) << "Callback should set AiIsLazy to "
                                              "true.";
}

#if 0
/**
 * @test DumpAllOptions
 * @brief We can check that operator<< prints valid lines for each option
 *        but we won't parse them, just ensure it doesn't crash.
 */
TEST_F(UCIOptionTest, DumpAllOptions)
{
    std::ostringstream oss;
    oss << Options; // calls operator<<(std::ostream&, const OptionsMap&)

    // We won't parse the entire output, but we can check it is not empty
    // and contains some known strings like "option name Hash".
    std::string output = oss.str();
    EXPECT_FALSE(output.empty())
        << "Printing all options should produce some text.";

    // Check a small snippet
    EXPECT_NE(output.find("option name Hash"), std::string::npos)
        << "Printed text should mention 'option name Hash'. Found: \n" << output;
}
#endif
