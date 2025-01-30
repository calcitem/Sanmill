// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_mcts.cpp

#include <gtest/gtest.h>
#include <string>
#include "bitboard.h"
#include "mcts.h"
#include "position.h"
#include "rule.h"
#include "search.h"
#include "types.h"

// A simple test fixture for MCTS-related tests
class MCTSTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Initialize components that are typically required by the engine.
        // For instance, if your engine or tests rely on any specific
        // initialization steps, place them here.
        Search::init();
        set_rule(0); // Use the default rules or any specific rule index.
    }

    void TearDown() override
    {
        // Cleanup code if necessary
    }
};

// Test that MCTS returns a valid (i.e., not MOVE_NONE) move from an empty
// board. We expect the position to be in placing phase, so the best move should
// be a "place" move.
TEST_F(MCTSTest, EmptyBoardReturnsValidMove)
{
    Position pos;
    pos.reset();
    pos.start(); // Typically sets sideToMove, phase = Phase::placing, etc.

    // Check that side to move is indeed not NOCOLOR and is in placing phase
    EXPECT_NE(pos.side_to_move(), NOCOLOR);
    EXPECT_EQ(pos.get_phase(), Phase::placing);

    Move bestMove = MOVE_NONE;
    // Call the MCTS function
    Value bestValue = monte_carlo_tree_search(&pos, bestMove);

    // We expect a legal move, so it should not be MOVE_NONE
    EXPECT_NE(bestMove, MOVE_NONE);
    // We also expect the value to not be VALUE_NONE if the engine found a move
    EXPECT_NE(bestValue, VALUE_NONE);
}

// Test that MCTS can handle a position where one piece is already on the board.
TEST_F(MCTSTest, SinglePieceOnBoard)
{
    Position pos;
    pos.reset();
    pos.start(); // The board is empty at start

    // Manually place a single piece for WHITE on some square, e.g., SQ_A1
    // or (File=FILE_A, Rank=RANK_1).
    // In typical Nine Men's Morris, or a variant, we might have a coordinate
    // system; for demonstration, let's assume make_square(FILE_A, RANK_1) =
    // SQ_8, etc. Make sure the position remains consistent.
    bool success = pos.put_piece(FILE_A, RANK_1);
    ASSERT_TRUE(success);

    // Confirm that the piece is actually placed
    EXPECT_FALSE(pos.empty(SQ_A1));
    EXPECT_EQ(pos.piece_on_board_count(WHITE), 1);

    Move bestMove = MOVE_NONE;
    Value bestValue = monte_carlo_tree_search(&pos, bestMove);

    EXPECT_NE(bestMove, MOVE_NONE);
    EXPECT_NE(bestValue, VALUE_NONE);
}

// Test MCTS with a minimal number of iterations by reducing the engine skill
// level. We want to confirm that MCTS won't crash and returns a move quickly.
TEST_F(MCTSTest, MinimalIterations)
{
    // Temporarily set a very low skill level or move time to reduce MCTS
    // iterations. If your engine uses a global or static 'gameOptions' object:
    gameOptions.setSkillLevel(1);
    // Alternatively, if you handle time controls, ensure they are minimal.

    Position pos;
    pos.reset();
    pos.start();

    Move bestMove = MOVE_NONE;
    Value bestValue = monte_carlo_tree_search(&pos, bestMove);

    // Even with minimal iterations, we expect MCTS to return some move.
    EXPECT_NE(bestMove, MOVE_NONE);
    // The value is likely quite rough but should be valid.
    EXPECT_NE(bestValue, VALUE_NONE);
}

// Test that MCTS can handle a partially filled board (placing phase not yet
// completed). This ensures MCTS handles typical mid-game states without error.
TEST_F(MCTSTest, PartialBoardMidPlacing)
{
    Position pos;
    pos.reset();
    pos.start();

    // Put 3 pieces for WHITE and 2 for BLACK, just to simulate a partial
    // placing phase. We don't check correctness of the game flow for
    // demonstration, only engine stability.
    pos.set_side_to_move(WHITE);
    pos.put_piece(FILE_A, RANK_1); // White piece
    pos.put_piece(FILE_B, RANK_1); // White piece
    pos.put_piece(FILE_C, RANK_1); // White piece

    pos.set_side_to_move(BLACK);
    pos.put_piece(FILE_A, RANK_2); // Black piece
    pos.put_piece(FILE_B, RANK_2); // Black piece

    // Return turn to WHITE for MCTS
    pos.set_side_to_move(WHITE);

    Move bestMove = MOVE_NONE;
    Value bestValue = monte_carlo_tree_search(&pos, bestMove);

    EXPECT_NE(bestMove, MOVE_NONE);
    EXPECT_NE(bestValue, VALUE_NONE);
}
