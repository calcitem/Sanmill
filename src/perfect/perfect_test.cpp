// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_test.cpp

// You have to set the working directory to the directory of the database.

// #define no_init_all // Was needed only in VS 2017

// run_perfect_test.cpp

#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING

#include <cstdio>
#include <sstream>
#include <string>
#include <iostream>
#include <cassert>

#include "perfect_api.h"
#include "perfect_common.h"
#include "perfect_game_state.h"
#include "perfect_errors.h"

int run_perfect_test(int argc, char *argv[])
{
    Value value = VALUE_UNKNOWN;

    Move move = MOVE_NONE;

    if (argc == 2) {
        secValPath = argv[1];
    }

    // int res = MalomSolutionAccess::get_best_move(0, 0, 9, 9, 0, false, move);
    int res = MalomSolutionAccess::get_best_move(1, 2, 8, 8, 0, false, value,
                                                 move); // Correct
                                                        // output:
                                                        // 16384
    // int res = MalomSolutionAccess::get_best_move(1 + 2 + 4, 8 + 16 + 32, 100,
    // 0, 0, false, value, move); // tests exception
    //  int res = MalomSolutionAccess::get_best_move(1 + 2 + 4, 1 + 8 + 16 + 32,
    //  0, 0, 0, false, value, move); // tests exception int res =
    //  MalomSolutionAccess::get_best_move(1 + 2 + 4, 8 + 16 + 32, 0, 0, 0,
    //  true,
    //                                   value, move);
    //  // Correct output: any of 8, 16, 32

    printf("get_best_move result: %d\n", res);

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}

// Test function to verify GameState string serialization compatibility
void test_gamestate_string_compatibility()
{
    std::cout << "Testing GameState string serialization compatibility..."
              << std::endl;

    // Create a test GameState
    GameState original;
    original.board[0] = 0;  // White piece at position 0
    original.board[1] = 1;  // Black piece at position 1
    original.board[2] = -1; // Empty at position 2
    original.stoneCount[0] = 1;
    original.stoneCount[1] = 1;
    original.setStoneCount[0] = 1;
    original.setStoneCount[1] = 1;
    original.phase = 2;
    original.sideToMove = 0;
    original.moveCount = 10;
    original.kle = false;
    original.lastIrrev = 0;

    // Serialize to string
    std::string serialized = original.to_string();
    std::cout << "Serialized: " << serialized << std::endl;

    // Create new GameState from string
    GameState deserialized(serialized);

    // Check for errors
    if (PerfectErrors::hasError()) {
        std::cout << "Error during deserialization: "
                  << PerfectErrors::getLastErrorMessage() << std::endl;
        return;
    }

    // Verify key fields match
    bool success = true;
    if (original.board[0] != deserialized.board[0]) {
        std::cout << "Board[0] mismatch: " << original.board[0]
                  << " != " << deserialized.board[0] << std::endl;
        success = false;
    }
    if (original.board[1] != deserialized.board[1]) {
        std::cout << "Board[1] mismatch: " << original.board[1]
                  << " != " << deserialized.board[1] << std::endl;
        success = false;
    }
    if (original.stoneCount[0] != deserialized.stoneCount[0]) {
        std::cout << "StoneCount[0] mismatch: " << original.stoneCount[0]
                  << " != " << deserialized.stoneCount[0] << std::endl;
        success = false;
    }
    if (original.phase != deserialized.phase) {
        std::cout << "Phase mismatch: " << original.phase
                  << " != " << deserialized.phase << std::endl;
        success = false;
    }
    if (original.sideToMove != deserialized.sideToMove) {
        std::cout << "SideToMove mismatch: " << original.sideToMove
                  << " != " << deserialized.sideToMove << std::endl;
        success = false;
    }

    if (success) {
        std::cout << "✅ GameState string serialization test PASSED!"
                  << std::endl;
    } else {
        std::cout << "❌ GameState string serialization test FAILED!"
                  << std::endl;
    }
}
