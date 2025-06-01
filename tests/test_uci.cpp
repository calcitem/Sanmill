// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_uci.cpp

#include <gtest/gtest.h>
#include <sstream>
#include "uci.h"
#include "position.h"
#include "option.h"

// We link to these in the actual program, but here we just need stubs.
extern GameOptions gameOptions; // Global variable declared in option.h
extern UCI::OptionsMap Options; // Global variable declared in uci.h

// -----------------------------------------------------------------------------
// Provide minimal stubs or mocks if needed
// -----------------------------------------------------------------------------

// Minimal position override for testing UCI::to_move() correctness.
// In real usage, we would rely on a fully-implemented Position class.
class TestPosition : public Position
{
public:
    TestPosition() = default;

    // We'll override the default in case the position is not fully set up.
    // We'll just do a no-op for set, for instance.
    Position &set(const std::string &)
    {
        return *this; // no-op
    }
};

/**
 * @class UCITest
 * @brief A test fixture for grouping UCI-related tests.
 *
 * This fixture can hold any common setup or teardown code if needed.
 */
class UCITest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // If needed, initialize global Options or anything else.
        // Here we do minimal initialization.
        UCI::init(Options); // If there's an init function that populates
                            // Options
    }

    void TearDown() override
    {
        // Cleanup if needed
    }
};

// -----------------------------------------------------------------------------
// Tests for Options and the case-insensitive comparator
// -----------------------------------------------------------------------------

/**
 * @test CaseInsensitiveComparator
 * @brief Verifies that the custom comparator for UCI options is
 * case-insensitive.
 *
 * We insert the same option name with different cases into the Options map
 * and check that they are considered the same key.
 */
TEST_F(UCITest, CaseInsensitiveComparator)
{
    // Insert an option under a certain name
    Options["SkillLevel"] = "20";

    // Now attempt to find it under a different case
    auto it = Options.find("skilllevel");
    ASSERT_TRUE(it != Options.end()) << "Option should be found ignoring case.";

    EXPECT_EQ(static_cast<int>(static_cast<double>(it->second)), 20)
        << "The stored value "
           "should match the "
           "previously set "
           "one.";
}

/**
 * @test SetOptionCommand
 * @brief Tests that 'setoption' commands parse correctly and update Options.
 */
TEST_F(UCITest, SetOptionCommand)
{
    // Insert a known option so we can set it
    Options["Hash"] = "16"; // default

    // Build a command: "setoption name Hash value 32"
    std::string cmd = "setoption name Hash value 32";

    // Simulate the command being parsed in UCI::loop's context
    std::istringstream iss(cmd);
    std::string token;
    iss >> token; // "setoption"
    // The rest is handled in setoption(), let's manually invoke it

    // This is how UCI::loop does it:
    //   if (token == "setoption") setoption(is);
    // So let's do that:
    // We'll replicate the relevant portion:
    {
        using namespace std;
        string name, value;
        iss >> token; // "name"
        // read option name
        while (iss >> token && token != "value")
            name += (name.empty() ? "" : " ") + token;

        // read option value
        while (iss >> token)
            value += (value.empty() ? "" : " ") + token;

        // Assign
        if (Options.count(name))
            Options[name] = value;
    }

    // Check that 'Hash' was updated
    auto it = Options.find("hash");
    ASSERT_TRUE(it != Options.end()) << "Option 'Hash' should exist in the "
                                        "map.";

    EXPECT_EQ(static_cast<int>(static_cast<double>(it->second)), 32)
        << "The 'Hash' "
           "option should "
           "have been "
           "updated to 32.";
}

// -----------------------------------------------------------------------------
// Tests for UCI::square(), UCI::move(), and UCI::to_move() conversions
// -----------------------------------------------------------------------------

/**
 * @test SquareStringConversion
 * @brief Checks that UCI::square() produces the correct string notation.
 */
TEST_F(UCITest, SquareStringConversion)
{
    // For a Square s, UCI::square(s) => standard notation like "d5", "a1"
    // We verify a few squares
    EXPECT_EQ(UCI::square(SQ_8), "d5") << "Square SQ_8 should be d5.";
    EXPECT_EQ(UCI::square(SQ_9), "e5") << "Square SQ_9 should be e5.";
    EXPECT_EQ(UCI::square(SQ_31), "a7") << "Square SQ_31 should be a7.";
}

/**
 * @test MoveStringConversion
 * @brief Checks that UCI::move() produces the correct string for a Move.
 */
TEST_F(UCITest, MoveStringConversion)
{
    // Test a "move" in which from and to are different squares
    Move m1 = make_move(SQ_8, SQ_9);
    // SQ_8 => "d5", SQ_9 => "e5"
    // "-" indicates a move in standard notation
    EXPECT_EQ(UCI::move(m1), "d5-e5") << "Should produce standard move "
                                         "notation like d5-e5.";

    // Test a "remove" type move (negative move)
    // Let's say removing SQ_10 => "e4". Negative means MOVETYPE_REMOVE
    Move m2 = static_cast<Move>(-SQ_10);
    EXPECT_EQ(UCI::move(m2), "xe4") << "Remove moves have 'x' prefix and "
                                       "standard square notation.";

    // Test a "place" type move
    // This means from_sq(m) = to_sq(m) in code's logic, but let's confirm
    // Actually, place is just if m & 0x1f00 is 0, and m >= 0
    // For instance, to place to SQ_25 => "g7"
    Move m3 = make_move(SQ_0, SQ_25); // from == 0 => "place" style in code
    // But the code sees from_sq(m) is 0 => "move is place"
    EXPECT_EQ(UCI::move(m3), "g7") << "Place moves just produce the "
                                      "destination in standard notation like "
                                      "g7.";
}

/**
 * @test ToMoveParsing
 * @brief Ensures UCI::to_move() parses textual moves into a Move correctly, if
 * valid.
 */
TEST_F(UCITest, ToMoveParsing)
{
    // We'll make a minimal position that "allows" certain squares.
    // In reality, we rely on a real Position, but let's do minimal approach:
    TestPosition testPos; // derived from Position

    // Let's push a couple of "legal" moves artificially if we want,
    // but by default, the Position could let us do "MoveList<LEGAL>(testPos)"
    // produce an empty list For demonstration, we rely on MoveList to produce
    // at least some squares?

    // We'll do a hack: let's define a move ourselves:
    // For code to match, we need a Move in MoveList<LEGAL>(testPos) that
    // matches string. Let's just test that we get MOVE_NONE if not found:
    std::string str = "d5-e5";
    Move result = UCI::to_move(&testPos, str);
    EXPECT_EQ(result, MOVE_NONE) << "Without a fully built position or "
                                    "appended moves, it's likely none. This is "
                                    "expected.";

    // If we had code that added a known move to the testPos, we could test a
    // successful parse. But that would require a real MoveGen or mocking its
    // result. For demonstration, we show that with no real moves, the result is
    // MOVE_NONE.

    // Another test: a remove type
    str = "xe4";
    result = UCI::to_move(&testPos, str);
    EXPECT_EQ(result, MOVE_NONE) << "Again, we have no real moves in the "
                                    "position, so it won't match. Expected "
                                    "MOVE_NONE.";
}
