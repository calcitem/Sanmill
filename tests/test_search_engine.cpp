// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_search_engine.cpp

#include <gtest/gtest.h>
#include "search_engine.h"
#include "position.h"
#include "rule.h"
#include "stack.h"
#include <string>

// A fixture for SearchEngine-related tests
class SearchEngineTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Set a default rule if needed
        set_rule(DEFAULT_RULE_NUMBER);

        // For each test, we can reset or create a new Position
        pos.reset();
        engine = &SearchEngine::getInstance();

        // Typically, you might want to start the position in a "moving" phase
        // to allow searching. But for certain tests, "placing" might also work.
        pos.start(); // This sets phase=Phase::placing for Nine Men's Morris by
                     // default
        // If your code requires that "phase=moving", you may do so:
        // pos.phase = Phase::moving;
    }

    // Helper function to do a short search on the test position
    void runShortSearch(Position &p, int depth = 2)
    {
        // Set up the search engine
        engine->beginNewSearch(&p);
        // Optionally set the move time to something short if you wish to force
        // a quick return
        gameOptions.setMoveTime(1); // 1 second, for example

        // Simulate a small override of depth logic by altering search engine's
        // originDepth if needed (But in practice, 'executeSearch' handles logic
        // automatically.)
        engine->originDepth = depth;

        // Run search
        engine->runSearch();
    }

    // The test position and engine
    Position pos;
    SearchEngine *engine;
};

// Test basic initialization of the SearchEngine singleton
TEST_F(SearchEngineTest, SingletonInitialization)
{
    // Confirm we have a valid instance
    EXPECT_NE(engine, nullptr) << "SearchEngine singleton instance should not "
                                  "be null.";
}

// Test setting the root position and ensuring the search doesn't crash
TEST_F(SearchEngineTest, SetRootPosition)
{
    // Just call setRootPosition and see if it can store p
    engine->setRootPosition(&pos);

    // We can do minimal checks: e.g. the internal pointer should match
    // But as we don't store it publicly, no direct assertion is possible
    // Instead, confirm we don't crash or throw.
    SUCCEED() << "Setting root position didn't cause errors.";
}

// Test a short search to see if it returns a best move in "placing" phase
// For Nine Men's Morris, the search might place a piece at an empty location
TEST_F(SearchEngineTest, ShortSearchInPlacingPhase)
{
    // Keep the position in placing phase
    // (pos.start() from SetUp() already sets phase=Phase::placing if rule
    // doesn't allow move)

    // Conduct a small search
    runShortSearch(pos, /*depth*/ 2);

    // Retrieve the best move
    std::string bestMove = engine->getBestMoveString();

    // We expect a move string is returned, e.g. "d5", "a1" or similar
    EXPECT_FALSE(bestMove.empty()) << "Short search should yield a non-empty "
                                      "best move string in placing phase.";

    // If you know the standard format, you can do more checks. For example:
    // Usually placing moves are in standard notation like "d5", "a1", etc.
    // e.g. "SearchEngine::emitCommand()" prints something like "bestmove d5"
    // But we won't rely on that exact formatting in this sample.
}

// Test a short search to see if it returns a best move in "moving" phase
TEST_F(SearchEngineTest, ShortSearchInMovingPhase)
{
    // Force the position to be in moving phase
    // We'll do it artificially. Usually we rely on pos having placed all
    // pieces.
    pos.phase = Phase::moving;

    // Perhaps we put a few pieces on the board:
    pos.board[SQ_8] = W_PIECE;
    pos.pieceOnBoardCount[WHITE]++;
    pos.board[SQ_9] = B_PIECE;
    pos.pieceOnBoardCount[BLACK]++;
    // side_to_move is White by default
    // Now a small search
    runShortSearch(pos, /*depth*/ 3);

    // Retrieve the best move
    std::string bestMove = engine->getBestMoveString();

    EXPECT_FALSE(bestMove.empty()) << "In moving phase, short search should "
                                      "produce a valid move string.";
}

// Test that the search respects a quick time limit (moveTime=1)
TEST_F(SearchEngineTest, SearchRespectsTimeLimit)
{
    // We'll store the start time
    auto start = now();

    gameOptions.setMoveTime(1); // 1ms or 1 second? If your code does conversion
    // The search should exit quickly
    runShortSearch(pos, /*depth*/ 6);

    auto end = now();
    auto elapsed = end - start;

    // We want to ensure the search finished "reasonably quickly"
    // because of the small moveTime we set. If your code uses ms vs sec,
    // adapt the threshold accordingly.
    // For instance, if setMoveTime(1) means 1 second, we expect < 2s, etc.
    EXPECT_LE(elapsed, 4000 /*ms or so*/) << "Search should finish quickly "
                                             "under the tight time limit.";
}

// Test usage of get_value() after a normal search
TEST_F(SearchEngineTest, GetValueAfterSearch)
{
    engine->beginNewSearch(&pos);
    engine->executeSearch();

    // Typically, bestvalue is stored
    std::string valStr = engine->get_value();

    // Check it's a valid integer string
    // e.g. stoi should not throw if it's a valid integer representation
    try {
        int val = std::stoi(valStr);
        (void)val; // just to avoid an unused warning
    } catch (...) {
        FAIL() << "The get_value() should return a string convertible to int, "
                  "e.g. '0' or '25'.";
    }
}

#if 0
// If your code uses perfect DB logic, test a fallback scenario
TEST_F(SearchEngineTest, PerfectDatabaseFallback) {
#if defined(GABOR_MALOM_PERFECT_AI)
    // Force usage of the perfect DB
    gameOptions.setUsePerfectDatabase(true);    // TODO: Crash
    // We can do a small scenario or partial test
    engine->beginNewSearch(&pos);
    engine->executeSearch();

    // Just confirm the code path doesn't throw or crash
    SUCCEED() << "Successfully executed search with perfect DB enabled (if compiled).";
#else
    GTEST_SKIP() << "GABOR_MALOM_PERFECT_AI not defined, skipping test.";
#endif
}
#endif

// Additional tests can be added as needed, for instance:
// - Testing different algorithms: setAlgorithm(3) => MCTS, etc.
// - Checking the final bestMove is in the MoveList the engine generates
// - Verifying that the search updates bestvalue consistently
