// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_search.cpp

#include <gtest/gtest.h>
#include "search.h"
#include "position.h"
#include "rule.h"
#include "stack.h"
#include "option.h"
#include "uci.h"

// This test suite targets the functions declared in search.h/search.cpp.
// We'll assume we have a minimal environment to construct Position objects
// and can safely call Search:: methods.

namespace {

// A fixture for tests dealing with the Search namespace
class SearchTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // If we need a default rule, we set it here:
        set_rule(DEFAULT_RULE_NUMBER);

        // Ensure global initialization if needed
        Search::init();
        gameOptions.setMoveTime(1); // short time limit for tests
        pos.reset();                // a "clean" position

        // By default, a newly reset Position might be in Phase::ready
        // We can start placing or forcing the phase if we want to do searching
        pos.start(); // typically sets to Phase::placing in Nine Men's Morris
    }

    void TearDown() override
    {
        // Cleanup logic, if required
        Search::clear();
    }

    // Helper to push the current pos onto the stack so we can do/undo moves
    void pushPos() { stack.push(pos); }

    // Our Position object
    Position pos;
    // We'll keep a stack for do/undo
    Sanmill::Stack<Position> stack;
};

// Test that init/clear are callable and don't crash
TEST_F(SearchTest, InitAndClear)
{
    // init called in SetUp, clear at the end
    // Just a trivial check
    SUCCEED() << "Search::init() and Search::clear() both called without "
                 "crash.";
}

// Test random_search on a trivial position
TEST_F(SearchTest, RandomSearch)
{
    // Attempt a random search. We expect it to return a legal move if any
    // exist.
    Move bestMove = MOVE_NONE;
    Value val = Search::random_search(&pos, bestMove);

    // If the position is in placing phase and we have pieces to place,
    // random_search() should find a random place move or a special outcome.
    // We cannot guarantee it won't produce VALUE_DRAW if no moves are
    // available. So let's check minimal conditions:
    EXPECT_GE(val, VALUE_UNKNOWN) << "random_search should return a plausible "
                                     "evaluation value (>= VALUE_UNKNOWN).";

    // If the position actually has moves, bestMove might not be MOVE_NONE.
    // If no moves exist, bestMove might remain MOVE_NONE, or random_search
    // might return VALUE_DRAW. We'll just assert no crash or exceptions
    // occurred.
    SUCCEED() << "random_search produced a stable result: " << val;
}

// Test qsearch with a trivial scenario
TEST_F(SearchTest, QSearch)
{
    Move bestMove = MOVE_NONE;
    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;
    Depth depth = 0; // or negative
    Depth originDepth = 0;

    // We push the pos so we can do/undo within qsearch
    pushPos();

    Value val = Search::qsearch(&pos, stack, depth, originDepth, alpha, beta,
                                bestMove);

    // We only verify the function didn't crash or produce an absurd result
    EXPECT_GE(val, -VALUE_INFINITE) << "qsearch shouldn't return less than "
                                       "-VALUE_INFINITE.";
    EXPECT_LE(val, VALUE_INFINITE) << "qsearch shouldn't return more than "
                                      "VALUE_INFINITE.";

    // There's no strong guarantee about bestMove from qsearch in an empty board
    // scenario
    SUCCEED() << "qsearch completed with value = " << static_cast<int>(val);
}

// Test search() at a shallow depth in a near-empty position
TEST_F(SearchTest, ShallowAlphaBetaSearch)
{
    Move bestMove = MOVE_NONE;
    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;
    Depth depth = 2;       // a very small search depth
    Depth originDepth = 2; // we pass the same

    // Typically we want the position to have some legal moves
    // For Nine Men's Morris, if Phase=placing, we have moves as long as we have
    // pieces in hand We'll run a short search
    pushPos(); // so we can do/undo
    Value val = Search::search(&pos, stack, depth, originDepth, alpha, beta,
                               bestMove);

    // We check if it is a plausible evaluation
    EXPECT_GE(val, -VALUE_INFINITE);
    EXPECT_LE(val, VALUE_INFINITE);

    // If no moves, search might return some fallback. bestMove might remain
    // MOVE_NONE.
    SUCCEED() << "search() returned " << static_cast<int>(val)
              << " bestMove=" << UCI::move(bestMove);
}

// Test MTD(f) with a trivial first guess
TEST_F(SearchTest, MTDfSearch)
{
    Move bestMove = MOVE_NONE;
    Value firstGuess = VALUE_ZERO;
    Depth depth = 2;
    Depth originDepth = 2;

    // We do a minimal MTD(f) call
    pushPos();
    Value val = Search::MTDF(&pos, stack, firstGuess, depth, originDepth,
                             bestMove);

    // There's no guarantee about the numeric range, but it shouldn't exceed the
    // search boundaries
    EXPECT_GE(val, -VALUE_INFINITE);
    EXPECT_LE(val, VALUE_INFINITE);

    SUCCEED() << "MTD(f) returned " << static_cast<int>(val)
              << ", bestMove=" << UCI::move(bestMove);
}

// (Optional) If you wish to test principal variation search specifically
// We can do so by calling pvs() directly, though typically it's used internally
TEST_F(SearchTest, PrincipalVariationSearch)
{
    // We'll do a small scenario:
    Move bestMove = MOVE_NONE;
    Depth depth = 2;
    Depth originDepth = 2;
    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;

    // We'll emulate "first move index=0" in PVS
    // and assume sideToMove doesn't change for demonstration.
    const Color before = pos.side_to_move();
    const Color after = before;

    // Force a do-move so pvs() can be tested in a typical scenario
    pushPos();

    // We'll just directly call pvs() with i=0, but in normal usage
    // search() calls pvs() on each move in a loop. We'll do a single call:
    Value val = Search::pvs(&pos, stack, depth, originDepth, alpha, beta,
                            bestMove, /*i=*/0, before, after);

    EXPECT_GE(val, -VALUE_INFINITE);
    EXPECT_LE(val, VALUE_INFINITE);
    SUCCEED() << "pvs returned " << static_cast<int>(val)
              << ", bestMove=" << UCI::move(bestMove);
}

} // namespace
