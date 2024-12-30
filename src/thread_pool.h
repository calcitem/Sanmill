// thread_pool.h

#ifndef THREAD_POOL_H_INCLUDED
#define THREAD_POOL_H_INCLUDED

#include "config.h"

#include <atomic>
#include <condition_variable>
#include <string>
#include <vector>
#include <memory> // For smart pointers

#include "movepick.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "thread_win32_osx.h"
#include "search_engine.h"

#ifdef QT_GUI_LIB
#include <QObject>
#endif // QT_GUI_LIB

using std::string;

class SearchEngine;

/// MainThread is a derived class specific for main thread

struct MainThread final : Thread
{
    using Thread::Thread;

    bool stopOnPonderhit {false};
    std::atomic_bool ponder {false};
};

/// ThreadPool struct handles all the threads-related stuff like init, starting,
/// parking and, most importantly, launching a thread. All the access to threads
/// is done through this class.

struct ThreadPool : std::vector<Thread *>
{
    void start_thinking(Position *, bool = false);
    void clear() const;
    void set(size_t);

    MainThread *main() const { return dynamic_cast<MainThread *>(front()); }

    std::atomic_bool stop, increaseDepth;

private:
    uint64_t accumulate(std::atomic<uint64_t> Thread::*member) const noexcept
    {
        uint64_t sum = 0;
        for (const Thread *th : *this)
            sum += (th->*member).load(std::memory_order_relaxed);
        return sum;
    }
};

#endif // THREAD_POOL_H_INCLUDED
