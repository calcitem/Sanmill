// thread.cpp

#include <iomanip>
#include <sstream>
#include <iostream>
#include <string>
#include <utility>

#include "mills.h"
#include "option.h"
#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include "tt.h"
#include "search_engine.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

#ifdef OPENING_BOOK
#include "opening_book.h"
#endif // OPENING_BOOK

using std::cout;
using std::string;

ThreadPool Threads; // Global object

/// Thread constructor launches the thread and waits until it goes to sleep
/// in idle_loop(). Note that 'searching' and 'exit' should be already set.

Thread::Thread(size_t n
#ifdef QT_GUI_LIB
               ,
               QObject *parent
#endif
               )
    :
#ifdef QT_GUI_LIB
    QObject(parent)
    ,
#endif
    idx(n)
    , stdThread(&Thread::idle_loop, this)
    , searchEngine(std::make_unique<SearchEngine>())
    , timeLimit(3600)
{
    wait_for_search_finished();
}

/// Thread destructor wakes up the thread in idle_loop() and waits
/// for its termination. Thread should be already waiting.

Thread::~Thread()
{
    assert(!searching);

    exit = true;
    start_searching();
    stdThread.join();
}

/// Thread::clear() reset histories, usually before a new game

void Thread::clear() noexcept
{
    // TODO(calcitem): Reset histories
    return;
}

/// Thread::start_searching() wakes up the thread that will start the search

void Thread::start_searching()
{
    std::lock_guard lk(mutex);
    searching = true;
    cv.notify_one(); // Wake up the thread in idle_loop()
}

void Thread::pause()
{
    std::lock_guard lk(mutex);
    searching = false;
    cv.notify_one(); // Wake up the thread in idle_loop()
}

/// Thread::wait_for_search_finished() blocks on the condition variable
/// until the thread has finished searching.

void Thread::wait_for_search_finished()
{
    std::unique_lock lk(mutex);
    cv.wait(lk, [&] { return !searching; });
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern Value nnueTrainingDataBestValue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// Thread::idle_loop() is where the thread is parked, blocked on the
/// condition variable, when it has no work to do.

void Thread::idle_loop()
{
    while (true) {
        std::unique_lock lk(mutex);
        // CID 338451: Data race condition(MISSING_LOCK)
        // missing_lock : Accessing this->searching without holding lock
        // Thread.mutex. Elsewhere, Thread.searching is accessed with
        // Thread.mutex held 2 out of 3 times(2 of these accesses strongly imply
        // that it is necessary).
        searching = false;

        cv.notify_one(); // Wake up anyone waiting for search finished
        cv.wait(lk, [&] { return searching; });

        if (exit)
            return;

        lk.unlock();

        // Note: Stockfish doesn't have this
        if (searchEngine->rootPos == nullptr ||
            searchEngine->rootPos->side_to_move() != us) {
            continue;
        }

        searchEngine->runSearch();
    }
}

void Thread::setAi(Position *p)
{
    std::lock_guard lk(mutex);

    searchEngine->setRootPosition(p);
}

void Thread::setAi(Position *p, int time)
{
    setAi(p);

    timeLimit = time;
}
