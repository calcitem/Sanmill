// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// task_queue.h

#ifndef TASK_QUEUE_H_INCLUDED
#define TASK_QUEUE_H_INCLUDED

#include <queue>
#include <mutex>
#include <condition_variable>
#include <functional>

class TaskQueue
{
public:
    TaskQueue() = default;
    ~TaskQueue() = default;

    void push(std::function<void()> task)
    {
        {
            std::lock_guard<std::mutex> lk(mutex_);
            tasks_.push(std::move(task));
        }
        cv_.notify_one();
    }

    bool pop(std::function<void()> &task)
    {
        std::unique_lock<std::mutex> lk(mutex_);
        cv_.wait(lk, [this] { return exit_ || !tasks_.empty(); });

        if (exit_ && tasks_.empty()) {
            return false;
        }

        task = std::move(tasks_.front());
        tasks_.pop();
        return true;
    }

    void stop()
    {
        {
            std::lock_guard<std::mutex> lk(mutex_);
            exit_ = true;
        }
        cv_.notify_all();
    }

private:
    std::queue<std::function<void()>> tasks_;
    bool exit_ = false;
    std::mutex mutex_;
    std::condition_variable cv_;
};

#endif // TASK_QUEUE_H_INCLUDED
