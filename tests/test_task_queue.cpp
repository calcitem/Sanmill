// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_task_queue.cpp

#include <gtest/gtest.h>
#include <thread>
#include <chrono>
#include "task_queue.h"

using namespace std::literals; // for convenient duration literals

// A test fixture for TaskQueue-related tests
class TaskQueueTest : public ::testing::Test
{
protected:
    // If any shared setup is needed among tests, do it in SetUp()
    void SetUp() override { }

    // If any shared tear-down is needed, do it in TearDown()
    void TearDown() override { }
};

/**
 * @test PushPopSingleTask
 * @brief Push a single task and pop it from the queue, then verify that
 *        the popped task is invoked as expected.
 */
TEST_F(TaskQueueTest, PushPopSingleTask)
{
    TaskQueue tq;
    bool invoked = false;

    // Push a lambda that sets 'invoked' to true
    tq.push([&invoked]() { invoked = true; });

    // Attempt to pop the task
    std::function<void()> poppedTask;
    bool result = tq.pop(poppedTask);

    // We should succeed in popping since the queue is not empty
    EXPECT_TRUE(result) << "Pop should succeed when queue has a task";
    // Execute the popped task
    poppedTask();
    EXPECT_TRUE(invoked) << "The popped task should set 'invoked' to true";
}

/**
 * @test PushPopMultipleTasks
 * @brief Push multiple tasks and ensure they are popped in the order
 *        they were inserted (FIFO).
 */
TEST_F(TaskQueueTest, PushPopMultipleTasks)
{
    TaskQueue tq;
    bool firstInvoked = false;
    bool secondInvoked = false;

    // Push two tasks
    tq.push([&firstInvoked]() { firstInvoked = true; });
    tq.push([&secondInvoked]() { secondInvoked = true; });

    // Pop first
    std::function<void()> task1;
    bool pop1 = tq.pop(task1);
    EXPECT_TRUE(pop1) << "First pop should succeed";
    task1(); // run the popped function
    EXPECT_TRUE(firstInvoked) << "First task should be invoked first";
    EXPECT_FALSE(secondInvoked) << "Second task should not yet be invoked";

    // Pop second
    std::function<void()> task2;
    bool pop2 = tq.pop(task2);
    EXPECT_TRUE(pop2) << "Second pop should succeed";
    task2(); // run the popped function
    EXPECT_TRUE(secondInvoked) << "Second task should be invoked second";
}

/**
 * @test PopBlocksUntilTask
 * @brief Verify that pop() blocks until a task is available or stop() is
 * called.
 *
 * This test spawns a thread that will pop from the queue. The main thread
 * sleeps briefly, then pushes a task. We confirm the popped task runs,
 * indicating pop() was indeed blocked and later unblocked when a task arrived.
 */
TEST_F(TaskQueueTest, PopBlocksUntilTask)
{
    TaskQueue tq;
    bool invoked = false;

    // Worker thread that attempts to pop a task
    std::thread worker([&]() {
        std::function<void()> poppedTask;
        // This will block until there's a task in the queue
        bool res = tq.pop(poppedTask);
        EXPECT_TRUE(res) << "Pop should succeed once a task is pushed";
        // Execute it if available
        if (res) {
            poppedTask();
        }
    });

    // Let the worker thread reach pop() and block
    std::this_thread::sleep_for(200ms);

    // Now push a task to unblock the worker
    tq.push([&]() { invoked = true; });

    // Wait for the worker to finish
    worker.join();

    EXPECT_TRUE(invoked) << "Task pushed after a delay should be invoked";
}

/**
 * @test StopMakesPopReturnFalse
 * @brief Check that when stop() is called, pop() returns false if there
 *        are no tasks left to pop.
 */
TEST_F(TaskQueueTest, StopMakesPopReturnFalse)
{
    TaskQueue tq;

    // Immediately stop the queue
    tq.stop();

    // Now attempt to pop. Since the queue is empty, it should return false.
    std::function<void()> task;
    bool res = tq.pop(task);
    EXPECT_FALSE(res) << "Pop should return false when queue is stopped and "
                         "empty";
}

/**
 * @test StopDoesNotDiscardExistingTasks
 * @brief If tasks are still in the queue when stop() is called, they can still
 *        be popped (assuming we pop before the worker sees an empty queue).
 *        Alternatively, one might design TaskQueue differently, but here we
 *        check that we can pop any existing tasks before the queue signals
 * stop.
 */
TEST_F(TaskQueueTest, StopDoesNotDiscardExistingTasks)
{
    TaskQueue tq;
    bool invoked = false;

    // Push a task
    tq.push([&]() { invoked = true; });

    // We call stop, but there's a task in the queue
    tq.stop();

    std::function<void()> poppedTask;
    bool res = tq.pop(poppedTask);

    // Expect to still get that task
    EXPECT_TRUE(res) << "Even after stop, we should be able to pop the "
                        "existing task";
    poppedTask();
    EXPECT_TRUE(invoked) << "Existing task in the queue should still run";
}
