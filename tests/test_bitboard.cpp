// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_bitboard.cpp

#include <gtest/gtest.h>
#include <bitset>
#include <string>

#include "bitboard.h"

// Undefine 'fail' to prevent macro conflicts with std::ios::fail
#undef fail

// Test fixture for Bitboard tests
class BitboardTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Initialize Bitboards before each test
        Bitboards::init();
    }

    void TearDown() override
    {
        // Clean up after each test if necessary
    }
};

// Test Bitboards::init()
TEST_F(BitboardTest, Init)
{
    // Verify that SquareBB is correctly initialized
    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        EXPECT_EQ(SquareBB[s], (1U << s))
            << "SquareBB[" << s << "] is incorrect.";
    }

    // Verify that PopCnt16 is correctly initialized
    for (unsigned i = 0; i < (1 << 16); ++i) {
        EXPECT_EQ(PopCnt16[i], static_cast<uint8_t>(std::bitset<16>(i).count()))
            << "PopCnt16[" << i << "] is incorrect.";
    }
}

// Test Bitboards::pretty()
TEST_F(BitboardTest, Pretty)
{
    // Test an empty bitboard
    {
        Bitboard b = 0;
        std::string boardStr = Bitboards::pretty(b);
        // Expect all '.' characters where squares should be
        // We do a simple substring check for some known lines:
        EXPECT_NE(boardStr.find(" . ----- . ----- .\n"), std::string::npos)
            << "Expected all dots in top line.";
        EXPECT_NE(boardStr.find(".    .-.-."), std::string::npos)
            << "Check for mid lines with dots.";
        // The exact checks above depend on how you want to verify output.
        // A simpler approach is just to verify that there are no 'X' characters
        EXPECT_EQ(boardStr.find('X'), std::string::npos) << "Empty bitboard "
                                                            "should have no "
                                                            "'X'.";
    }

    // Test a bitboard with a single square set: SQ_31
    {
        Bitboard b = square_bb(SQ_31);
        std::string boardStr = Bitboards::pretty(b);

        // Check that there's at least one 'X'
        EXPECT_NE(boardStr.find('X'), std::string::npos) << "Expected an 'X' "
                                                            "at SQ_31.";

        // Since SQ_31 is the top-left position in the ASCII diagram,
        // we can check the first line for an 'X'.
        // A direct check for the first line is:
        //  " X ----- . ----- ."
        // But verifying partial substring is enough.
        EXPECT_NE(boardStr.find("X -----"), std::string::npos)
            << "Expected SQ_31 to appear as 'X' in the top-left corner.";
    }

    // Test multiple squares set: SQ_31, SQ_24, and SQ_25 (top row)
    {
        Bitboard b = square_bb(SQ_31) | square_bb(SQ_24) | square_bb(SQ_25);
        std::string boardStr = Bitboards::pretty(b);

        // Check for multiple 'X'
        // Each is supposed to appear on the top line.
        // The line should look like: " X ----- X ----- X"
        // but let's just check they exist individually:
        EXPECT_NE(boardStr.find("X ----- X ----- X"), std::string::npos)
            << "Expected 'X' at SQ_31, SQ_24, and SQ_25.";
    }
}

// Test setting and clearing bits
TEST_F(BitboardTest, SetAndClearBits)
{
    Bitboard b = 0;

    // Set a bit and verify
    SET_BIT(b, 10);
    EXPECT_TRUE(b & square_bb(static_cast<Square>(10))) << "Bit 10 should be "
                                                           "set.";

    // Clear the bit and verify
    CLEAR_BIT(b, 10);
    EXPECT_FALSE(b & square_bb(static_cast<Square>(10))) << "Bit 10 should be "
                                                            "cleared.";
}

// Example of an additional test
TEST_F(BitboardTest, SomeOtherBitboardFunction)
{
    // Implement additional tests as needed
    // This is just a placeholder for further tests
}
