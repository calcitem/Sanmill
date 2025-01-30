// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// thread.h

#ifndef THREAD_H_INCLUDED
#define THREAD_H_INCLUDED

#include <thread>
#include <atomic>
#include <condition_variable>
#include <functional>
#include "task_queue.h"

class Thread
{
public:
    explicit Thread(size_t index, TaskQueue &taskQueue)
        : idx(index)
        , taskQueue_(taskQueue)
        , worker_(&Thread::idle_loop, this)
    {
        idx = index;
    }

    ~Thread()
    {
        if (worker_.joinable())
            worker_.join();
    }

    Thread(const Thread &) = delete;
    Thread &operator=(const Thread &) = delete;

private:
    void idle_loop()
    {
        while (true) {
            std::function<void()> task;
            if (!taskQueue_.pop(task)) {
                return;
            }
            task();
        }
    }

    size_t idx;
    TaskQueue &taskQueue_;
    std::thread worker_;
};

#endif // THREAD_H_INCLUDED
