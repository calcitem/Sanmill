// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_thread.cpp

#include <gtest/gtest.h>
#include <atomic>
#include <thread>
#include <chrono>
#include "thread.h"
#include "thread_win32_osx.h"
#include "task_queue.h"

using namespace std::chrono_literals;

/**
 * @class NativeThreadTest
 * @brief A test fixture for NativeThread-related tests (thread_win32_osx.h).
 */
class NativeThreadTest : public ::testing::Test
{
protected:
    // Called before each test
    void SetUp() override
    {
        // Nothing special to do
    }

    // Called after each test
    void TearDown() override
    {
        // Nothing special to do
    }
};

//------------------------------------------------------------------------------
// Simple class to test member-function spawning
//------------------------------------------------------------------------------
class TaskRunner
{
public:
    explicit TaskRunner(std::atomic<bool> &flag)
        : runFlag(flag)
    { }

    void run()
    {
        // Simulate some work
        std::this_thread::sleep_for(100ms);
        runFlag.store(true);
    }

private:
    std::atomic<bool> &runFlag;
};

/**
 * @test NativeThreadBasic
 * @brief Ensures that we can create a NativeThread, run a member function,
 *        and join it.
 *
 * If compiled on macOS, MinGW, or with USE_PTHREADS, it uses pthread_create
 * with a custom stack size. Otherwise, it falls back to std::thread.
 */
TEST_F(NativeThreadTest, NativeThreadBasic)
{
    // We'll track if the runner has executed
    std::atomic<bool> doneFlag(false);
    TaskRunner runner(doneFlag);

    {
        // Create a NativeThread from thread_win32_osx.h
        NativeThread nt(&TaskRunner::run, &runner);
        // Join the thread
        nt.join();
    }

    EXPECT_TRUE(doneFlag.load()) << "The NativeThread should set the doneFlag "
                                    "after executing TaskRunner::run().";
}

//------------------------------------------------------------------------------
// Tests for the Thread class using the TaskQueue
//------------------------------------------------------------------------------
/**
 * @class ThreadClassTest
 * @brief A test fixture for the custom Thread class (thread.h/thread.cpp).
 */
class ThreadClassTest : public ::testing::Test
{
protected:
    TaskQueue queue; // We can feed tasks into it in each test
};

/**
 * @test CreateAndDestroyThread
 * @brief Ensures that creating and destroying a Thread object does not crash,
 *        and that we can gracefully exit if there are no tasks to run.
 */
TEST_F(ThreadClassTest, CreateAndDestroyThread)
{
    {
        Thread myThread(0, queue);
        // No tasks here, so the thread waits in pop().
        // If we do nothing, it stays stuck. So we need queue.stop().

        std::this_thread::sleep_for(50ms); // (Optional) Wait a bit
        queue.stop();                      // Unblock the thread
    }
    // myThread destructor now can join properly.
    SUCCEED() << "Creating a Thread with no tasks and letting it go out of "
                 "scope succeeded.";
}

/**
 * @test SingleTaskExecution
 * @brief Verifies that a single task is properly executed by the Thread.
 */
TEST_F(ThreadClassTest, SingleTaskExecution)
{
    std::atomic<bool> taskRan(false);

    // We'll push a single task
    queue.push([&taskRan]() {
        std::this_thread::sleep_for(50ms);
        taskRan.store(true);
    });

    // Create a worker thread
    {
        Thread myThread(1, queue);
        // The thread will pop the task, run it, then wait for more
        // We end the test by letting myThread's destructor handle joining
        std::this_thread::sleep_for(200ms); // Give task time to complete
        queue.stop();                       // Unblock the thread
    }
    // Now the queue stops, the thread is destructed

    EXPECT_TRUE(taskRan.load()) << "The single queued task should have run "
                                   "before the thread was destroyed.";
}

/**
 * @test MultipleTasksExecution
 * @brief Submits multiple tasks to the queue, ensures they all run.
 */
TEST_F(ThreadClassTest, MultipleTasksExecution)
{
    const int taskCount = 5;
    std::atomic<int> counter(0);

    // Push several tasks
    for (int i = 0; i < taskCount; i++) {
        queue.push([&counter]() {
            std::this_thread::sleep_for(20ms);
            counter.fetch_add(1);
        });
    }

    // Create the thread; it will pop tasks one by one
    {
        Thread worker(2, queue);
        // Allow time for tasks
        std::this_thread::sleep_for(300ms);
        queue.stop(); // Unblock the thread
    }
    // Thread destructor => stop() => tasks done or no more tasks

    EXPECT_EQ(counter.load(), taskCount)
        << "All " << taskCount << " tasks should have executed.";
}

/**
 * @test ThreadStopsAfterQueueStop
 * @brief Calls stop() on the queue and checks that the thread loop ends soon.
 */
TEST_F(ThreadClassTest, ThreadStopsAfterQueueStop)
{
    // Start a worker thread
    Thread worker(3, queue);

    // Sleep a bit to ensure the thread is waiting on tasks
    std::this_thread::sleep_for(100ms);

    // Now stop the queue
    queue.stop();

    // Wait a bit more to ensure the thread sees exit_ = true
    std::this_thread::sleep_for(100ms);

    // Worker destructor => join => thread loop should have returned
    SUCCEED() << "Thread should have exited after queue.stop() was called.";
}
