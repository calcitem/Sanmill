// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// thread_pool.h

#ifndef THREAD_POOL_H_INCLUDED
#define THREAD_POOL_H_INCLUDED

#include <vector>
#include <memory>
#include "thread.h"
#include "task_queue.h"

class ThreadPool
{
public:
    ThreadPool() = default;
    ~ThreadPool() { stop_all(); }

    void set(size_t n)
    {
        stop_all();
        taskQueue_ = std::make_unique<TaskQueue>();
        for (size_t i = 0; i < n; ++i) {
            threads_.emplace_back(std::make_unique<Thread>(i, *taskQueue_));
        }
    }

    void submit(std::function<void()> fn)
    {
        if (taskQueue_) {
            taskQueue_->push(std::move(fn));
        }
    }

    void stop_all()
    {
        if (taskQueue_) {
            taskQueue_->stop();
        }
        threads_.clear();
    }

private:
    std::vector<std::unique_ptr<Thread>> threads_;
    std::unique_ptr<TaskQueue> taskQueue_;
};

extern ThreadPool Threads;

#endif // THREAD_POOL_H_INCLUDED
