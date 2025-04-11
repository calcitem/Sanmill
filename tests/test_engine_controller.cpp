// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_engine_controller.cpp

#include <gtest/gtest.h>
#include <sstream>
#include <string>

// Include the headers for the code under test
#include "engine_controller.h"
#include "engine_commands.h"
#include "position.h"
#include "search.h"
#include "thread_pool.h"

// We need to provide some global or mock objects if engine_controller.cpp
// relies on them, e.g., the 'Threads' or any rule/pieceCount. But here we
// assume that all external dependencies are either already mocked or
// safe to call in a test environment.

// A simple mock or dummy for 'Position' that we can use to observe changes
// or confirm that certain calls happen.
class MockPosition : public Position
{
public:
    // We can override methods if we want to detect calls or
    // store data for verification.
    // For simplicity, we leave it as-is.
};

/// Test fixture for EngineController tests
class EngineControllerTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // If we need to initialize anything in EngineCommands or Search, do it
        // here. For example: rule.pieceCount = 9;
        // EngineCommands::init_start_fen();
        // Search::init();
    }

    void TearDown() override
    {
        // Cleanup or reset if necessary
    }

    EngineController &controller = EngineController::getInstance();
};

#if 0
/// Test that "go" command calls EngineCommands::go(pos)
TEST_F(EngineControllerTest, HandleGoCommand)
{
    MockPosition pos;

    // We'll pass "go" to EngineController and see if it runs. We can't
    // easily check internal calls unless we mock out EngineCommands::go.
    // However, we at least verify that it doesn't crash.
    const std::string cmd = "go";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    // No direct state to verify unless we had mocks or a global flag.
    // We'll just confirm no crash or exceptions.
    SUCCEED();
}

/// Test that "position" command calls EngineCommands::position(pos, is)
TEST_F(EngineControllerTest, HandlePositionCommand)
{
    MockPosition pos;

    // We'll pass "position startpos moves a1b2"
    // The function will attempt to parse and set up the position,
    // but we won't check the final board state in detail.
    // We only confirm it doesn't crash or throw exceptions.
    const std::string cmd = "position startpos moves a1b2";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    // As with the "go" command, no direct verification is done here.
    // We only check that code path is reached successfully.
    SUCCEED();
}

/// Test that "ucinewgame" triggers Search::clear()
TEST_F(EngineControllerTest, HandleUcinewgameCommand)
{
    MockPosition pos;

    // We can check that Search::clear() is called. However, in practice,
    // we don't have a direct way to detect that call unless we mock Search
    // or intercept the function. For demonstration, we rely on the code path
    // not throwing an error or doing something unexpected.
    const std::string cmd = "ucinewgame";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    // If Search::clear() modifies some internal state,
    // we might check it after the call. For now, just success.
    SUCCEED();
}

/// Test that "d" command prints the position
TEST_F(EngineControllerTest, HandleDCommand)
{
    MockPosition pos;

    // "d" command should output the position to sync_cout.
    // We don't attempt to intercept or parse that output in this test,
    // but we confirm no crash or exceptions occur.
    const std::string cmd = "d";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    SUCCEED();
}

/// Test that "compiler" command prints compiler info
TEST_F(EngineControllerTest, HandleCompilerCommand)
{
    MockPosition pos;

    // The "compiler" command prints the compiler_info() string.
    // We do not parse the output here, we just ensure no exceptions.
    const std::string cmd = "compiler";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    SUCCEED();
}

/// Test that an unknown command logs an "Unknown command" message
TEST_F(EngineControllerTest, HandleUnknownCommand)
{
    MockPosition pos;

    // Passing something not recognized by handleCommand
    const std::string cmd = "someRandomCommand xyz 123";
    controller.handleCommand(cmd, &pos);

    // Wait for any background threads to finish before the local 'pos' is destroyed.
    // This is a simple approach: force ThreadPool to stop all tasks.
    //Threads.stop_all();

    // The code logs a message to sync_cout. We can't easily verify
    // console output, but we ensure it doesn't crash.
    SUCCEED();
}
#endif
