// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_thread_pool.cpp

#include <gtest/gtest.h>
#include <atomic>
#include <chrono>
#include <thread>
#include "thread_pool.h"

using namespace std::chrono_literals;

/**
 * @class ThreadPoolTest
 * @brief A test fixture for ThreadPool-related tests.
 */
class ThreadPoolTest : public ::testing::Test
{
protected:
    // Called before each test in this fixture
    void SetUp() override
    {
        // Clear the global Threads object before each test
        Threads.stop_all();
    }

    // Called after each test in this fixture
    void TearDown() override
    {
        // Stop all threads after each test, to be safe
        Threads.stop_all();
    }
};

/**
 * @test SetThreadPoolSize
 * @brief Ensures that we can set the thread pool size, and tasks are run
 * successfully.
 */
TEST_F(ThreadPoolTest, SetThreadPoolSize)
{
    // Set the thread pool to have 3 worker threads
    Threads.set(3);

    // A simple atomic counter to track how many tasks finished
    std::atomic<int> counter {0};

    // Submit some tasks
    const int numTasks = 5;
    for (int i = 0; i < numTasks; ++i) {
        Threads.submit([&counter]() {
            std::this_thread::sleep_for(50ms); // Simulate some work
            ++counter;
        });
    }

    // Wait for tasks to (hopefully) complete
    std::this_thread::sleep_for(500ms);

    // Check that all tasks incremented the counter
    EXPECT_EQ(counter.load(), numTasks) << "All tasks should have incremented "
                                           "the counter.";
}

/**
 * @test MultipleThreadsConcurrency
 * @brief Submits more tasks than threads to test concurrency and ensure
 *        the tasks all eventually complete.
 */
TEST_F(ThreadPoolTest, MultipleThreadsConcurrency)
{
    // Set up 2 worker threads
    Threads.set(2);

    // We will submit 6 tasks
    const int taskCount = 6;
    std::atomic<int> doneCount {0};

    for (int i = 0; i < taskCount; ++i) {
        Threads.submit([&doneCount]() {
            std::this_thread::sleep_for(100ms); // Some "work"
            ++doneCount;
        });
    }

    // Give some time for threads to complete work
    std::this_thread::sleep_for(1s);

    EXPECT_EQ(doneCount.load(), taskCount) << "All submitted tasks should be "
                                              "completed by the 2-thread pool.";
}

/**
 * @test StopAllStopsThreads
 * @brief Calls stop_all() to ensure no further tasks are processed
 *        after the pool is stopped.
 */
TEST_F(ThreadPoolTest, StopAllStopsThreads)
{
    // Create 2 worker threads
    Threads.set(2);

    // Stop immediately
    Threads.stop_all();

    // Now submit a task. If the queue is stopped, the task should never run.
    std::atomic<bool> runFlag {false};
    Threads.submit([&runFlag]() { runFlag.store(true); });

    // Give time to see if the task would run
    std::this_thread::sleep_for(200ms);

    // The runFlag should remain false if the task never started
    EXPECT_FALSE(runFlag.load()) << "No tasks should run after stop_all() is "
                                    "called.";
}

/**
 * @test ReuseAfterStop
 * @brief Test that after stopping the pool, we can set a new size (reinit)
 *        and the pool can accept tasks again.
 */
TEST_F(ThreadPoolTest, ReuseAfterStop)
{
    // First create and stop
    Threads.set(2);
    Threads.stop_all();

    // Now reuse by setting size again
    Threads.set(2);

    std::atomic<int> counter {0};

    // Submit tasks
    const int taskCount = 3;
    for (int i = 0; i < taskCount; ++i) {
        Threads.submit([&counter]() {
            std::this_thread::sleep_for(50ms);
            ++counter;
        });
    }

    // Wait a little
    std::this_thread::sleep_for(300ms);

    // Verify tasks ran
    EXPECT_EQ(counter.load(), taskCount) << "After re-setting the thread pool, "
                                            "new tasks should be run.";
}
