// thread_pool.cpp

#include "thread_pool.h"
#include "uci.h"

/// ThreadPool::set() creates/destroys threads to match the requested number.
/// Created and launched threads will immediately go to sleep in idle_loop.
/// Upon resizing, threads are recreated to allow for binding if necessary.

void ThreadPool::set(size_t requested)
{
    if (!empty()) {
        // destroy any existing thread(s)
        main()->wait_for_search_finished();

        while (!empty()) {
            delete back();
            pop_back();
        }
    }

    if (requested > 0) {
        // create new thread(s)
        push_back(new MainThread(0));

        while (size() < requested)
            push_back(new Thread(size()));
        clear();

#ifdef TRANSPOSITION_TABLE_ENABLE
        // Reallocate the hash with the new thread pool size
        TT.resize(static_cast<size_t>(Options["Hash"]));
#endif

        // Init thread number dependent search params.
        Search::init();
    }
}

/// ThreadPool::clear() sets threadPool data to initial values.

void ThreadPool::clear() const
{
    for (const Thread *th : *this)
        th->clear();
}

/// ThreadPool::start_thinking() wakes up main thread waiting in idle_loop() and
/// returns immediately. Main thread will wake up other threads and start the
/// search.

void ThreadPool::start_thinking(Position *pos, bool ponderMode)
{
    main()->wait_for_search_finished();

    main()->stopOnPonderhit = stop = false;
    increaseDepth = true;
    main()->ponder = ponderMode;

    // We use Position::set() to set root position across threads.
    for (Thread *th : *this) {
        // Fix CID 338443: Data race condition (MISSING_LOCK)
        // missing_lock: Accessing th->rootPos without holding lock
        // Thread.mutex. Elsewhere, Thread.rootPos is accessed with Thread.mutex
        // held 1 out of 2 times (1 of these accesses strongly imply that it is
        // necessary).
        std::lock_guard lk(th->mutex);
        th->rootPos = pos;
    }

    main()->start_searching();
}
