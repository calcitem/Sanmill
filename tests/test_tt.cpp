// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_tt.cpp

#include <gtest/gtest.h>
#include "tt.h"
#include "types.h"

#ifdef TRANSPOSITION_TABLE_ENABLE

/**
 * @class TTTest
 * @brief A test fixture for TranspositionTable-related tests.
 *
 * This fixture ensures that any required setup or teardown is done
 * for each test in this group.
 */
class TTTest : public ::testing::Test
{
protected:
    /**
     * @brief Called before each test method in this fixture.
     */
    void SetUp() override
    {
        // Clear the transposition table before each test
        TranspositionTable::clear();
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        // Ensure the age is reset for each test if using FAKE_CLEAN logic
        transpositionTableAge = 0;
#endif
    }

    /**
     * @brief Called after each test method in this fixture.
     */
    void TearDown() override
    {
        // Clear again to avoid any side effects
        TranspositionTable::clear();
    }
};

/**
 * @test InsertAndProbeSimple
 * @brief Verifies basic insertion and retrieval from the TranspositionTable.
 */
TEST_F(TTTest, InsertAndProbeSimple)
{
    Key testKey = 123456;     // Example key
    Depth depth = 5;          // Example depth
    Value value = VALUE_MATE; // Example value (80 in default)
    Bound boundType = BOUND_EXACT;

    // Insert an entry
    int res = TranspositionTable::save(value, depth, boundType, testKey
#ifdef TT_MOVE_ENABLE
                                       ,
                                       MOVE_NONE
#endif
    );
    EXPECT_EQ(res, 0) << "Insertion into TT should succeed with res=0";

    // Probe
    Bound readBound = BOUND_NONE;
#ifdef TT_MOVE_ENABLE
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, depth, readBound,
                                                readMove);
#else
    Value probedVal = TranspositionTable::probe(testKey, depth, readBound);
#endif

    // Check correctness
    EXPECT_EQ(probedVal, value) << "Probed value should match inserted value.";
    EXPECT_EQ(readBound, boundType) << "Probed bound should match inserted "
                                       "bound.";

#ifdef TT_MOVE_ENABLE
    EXPECT_EQ(readMove, MOVE_NONE) << "We inserted MOVE_NONE, so we expect to "
                                      "retrieve it.";
#endif
}

/**
 * @test ProbeEntryWithInsufficientDepth
 * @brief Ensures that if we probe with a smaller depth than stored, we can
 *        still retrieve the entry if the stored depth is greater.
 *
 * By default logic, if TT has depth >= probed depth, it's considered valid.
 * If the probed depth is higher, we might get VALUE_UNKNOWN.
 */
TEST_F(TTTest, ProbeEntryWithInsufficientDepth)
{
    Key testKey = 87654321;
    Depth storedDepth = 10;
    Value storedValue = (Value)42;
    Bound storedBound = BOUND_LOWER;

    // Insert an entry with depth=10
    TranspositionTable::save(storedValue, storedDepth, storedBound, testKey
#ifdef TT_MOVE_ENABLE
                             ,
                             MOVE_NONE
#endif
    );

    // Probe at a lesser depth
    Depth probeDepth = 8;
    Bound readBound = BOUND_NONE;

#ifdef TT_MOVE_ENABLE
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, probeDepth, readBound,
                                                readMove);
#else
    Value probedVal = TranspositionTable::probe(testKey, probeDepth, readBound);
#endif

    // We expect to retrieve the same value/bound if storedDepth >= probeDepth
    EXPECT_EQ(probedVal, storedValue);
    EXPECT_EQ(readBound, storedBound);
}

/**
 * @test ProbeEntryWithGreaterDepth
 * @brief Tests that if we probe with a higher depth than stored, we get
 * VALUE_UNKNOWN.
 */
TEST_F(TTTest, ProbeEntryWithGreaterDepth)
{
    Key testKey = 987654;
    Depth storedDepth = 5;
    Value storedValue = (Value)55;
    Bound storedBound = BOUND_UPPER;

    // Insert an entry with depth=5
    TranspositionTable::save(storedValue, storedDepth, storedBound, testKey
#ifdef TT_MOVE_ENABLE
                             ,
                             MOVE_NONE
#endif
    );

    // Now probe with depth=7, which is greater
    Depth probeDepth = 7;
    Bound readBound = BOUND_NONE;

#ifdef TT_MOVE_ENABLE
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, probeDepth, readBound,
                                                readMove);
#else
    Value probedVal = TranspositionTable::probe(testKey, probeDepth, readBound);
#endif

    // Because the stored depth is less than the probed depth, we expect unknown
    EXPECT_EQ(probedVal, VALUE_UNKNOWN) << "If stored depth < probed depth, "
                                           "probe should return VALUE_UNKNOWN.";
    EXPECT_EQ(readBound, BOUND_NONE) << "Read bound remains BOUND_NONE when "
                                        "retrieval fails at higher depth.";
}

/**
 * @test CollisionWithLowerDepth
 * @brief Tests that if a TT entry already exists, we do not replace it if
 *        the new one has a smaller search depth, if so implemented.
 *
 * Implementation may vary. The sample code only replaces if new depth >= old
 * depth or if oldBound was BOUND_NONE. Adjust the test if your logic differs.
 */
TEST_F(TTTest, CollisionWithLowerDepth)
{
    Key testKey = 13579;
    Depth olderDepth = 10;
    Value olderValue = (Value)99;
    Bound olderBound = BOUND_EXACT;

    // Insert an entry with depth=10
    TranspositionTable::save(olderValue, olderDepth, olderBound, testKey
#ifdef TT_MOVE_ENABLE
                             ,
                             MOVE_NONE
#endif
    );

    // Attempt to overwrite with a smaller depth
    Depth newDepth = 8;
    Value newValue = (Value)111;
    Bound newBound = BOUND_LOWER;

    int res = TranspositionTable::save(newValue, newDepth, newBound, testKey
#ifdef TT_MOVE_ENABLE
                                       ,
                                       MOVE_NONE
#endif
    );
    EXPECT_EQ(res, -1) << "If TT logic doesn't overwrite deeper entry with "
                          "shallower, it might return -1.";

    // Now probe to see if the older entry was retained
    Bound readBound = BOUND_NONE;
#ifdef TT_MOVE_ENABLE
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, 5, readBound,
                                                readMove);
#else
    Value probedVal = TranspositionTable::probe(testKey, 5, readBound);
#endif

    EXPECT_EQ(probedVal, olderValue) << "We should still see the older, deeper "
                                        "entry in the TT.";
    EXPECT_EQ(readBound, olderBound) << "We should still see the older bound, "
                                        "not the new one.";
}

/**
 * @test FakeCleanEnabled
 * @brief If TRANSPOSITION_TABLE_FAKE_CLEAN is enabled, test that incrementing
 *        the age can eventually cause entries to become invalid.
 *
 * If FAKE_CLEAN is disabled in your build, this test will be skipped.
 */
TEST_F(TTTest, FakeCleanEnabled)
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    Key testKey = 42;
    Depth depth = 5;
    Value value = (Value)12;
    Bound boundType = BOUND_EXACT;

    // Insert an entry
    TranspositionTable::save(value, depth, boundType, testKey
#ifdef TT_MOVE_ENABLE
                             ,
                             MOVE_NONE
#endif
    );
    // The transpositionTableAge at the time was presumably 0

    Bound readBound = BOUND_NONE;
#ifdef TT_MOVE_ENABLE
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, depth, readBound,
                                                readMove);
#else
    Value probedVal = TranspositionTable::probe(testKey, depth, readBound);
#endif
    EXPECT_EQ(probedVal, value) << "The entry should be retrievable while age "
                                   "matches.";

    // Now do a clear, which increments age if it's below max
    TranspositionTable::clear();
    // transpositionTableAge should have incremented from 0 to 1

    // Try to probe again
#ifdef TT_MOVE_ENABLE
    readMove = MOVE_NONE;
    probedVal = TranspositionTable::probe(testKey, depth, readBound, readMove);
#else
    probedVal = TranspositionTable::probe(testKey, depth, readBound);
#endif
    EXPECT_EQ(probedVal, VALUE_UNKNOWN) << "After incremented age, the old "
                                           "entry should become invalid with "
                                           "FAKE_CLEAN.";
#else
    GTEST_SKIP() << "TRANSPOSITION_TABLE_FAKE_CLEAN is not defined; skipping "
                    "test.";
#endif
}

/**
 * @test MoveStorage
 * @brief If TT_MOVE_ENABLE is defined, ensure we can store and retrieve a move.
 *
 * This test is only meaningful when TT_MOVE_ENABLE is turned on.
 */
TEST_F(TTTest, MoveStorage)
{
#ifdef TT_MOVE_ENABLE
    Key testKey = 2468;
    Depth depth = 4;
    Value value = 31;
    Bound boundType = BOUND_UPPER;

    // We'll store a fictional move. Suppose from=SQ_8, to=SQ_16
    Move storedMove = make_move(SQ_8, SQ_16);

    // Insert an entry
    TranspositionTable::save(value, depth, boundType, testKey, storedMove);

    // Probe
    Bound readBound = BOUND_NONE;
    Move readMove = MOVE_NONE;
    Value probedVal = TranspositionTable::probe(testKey, depth, readBound,
                                                readMove);

    // Check correctness
    EXPECT_EQ(probedVal, value);
    EXPECT_EQ(readBound, boundType);
    EXPECT_EQ(readMove, storedMove) << "Should retrieve the same move we "
                                       "stored.";
#else
    GTEST_SKIP() << "TT_MOVE_ENABLE is not defined; skipping move storage "
                    "test.";
#endif
}

#endif // TRANSPOSITION_TABLE_ENABLE
