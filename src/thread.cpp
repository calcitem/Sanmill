// thread.cpp

#include <iomanip>
#include <sstream>
#include <string>
#include <utility>

#include "mills.h"
#include "option.h"
#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include "search_engine.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

#ifdef OPENING_BOOK
#include <deque>
#endif

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
    , timeLimit(3600)
    , searchEngine(std::make_unique<SearchEngine>(this))
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
        if (rootPos == nullptr || rootPos->side_to_move() != us) {
            continue;
        }

#ifdef OPENING_BOOK
        // gameOptions.getOpeningBook()
        if (!openingBookDeque.empty()) {
            char obc[16] = {0};
            sq2str(obc);
            bestMoveString = obc;
            // emitCommand();
            searchEngine->emitCommand(); // Changed
        } else {
#endif
            const int ret = search();

#ifdef NNUE_GENERATE_TRAINING_DATA
            nnueTrainingDataBestValue = rootPos->side_toMove == WHITE ?
                                            bestvalue :
                                            -bestvalue;
#endif /* NNUE_GENERATE_TRAINING_DATA */

            if (ret == 3 || ret == 50 || ret == 10) {
                debugPrintf("Draw\n\n");
                bestMoveString = "draw";
                // emitCommand();
                searchEngine->emitCommand(); // Changed
            } else {
                // bestMoveString = next_move();
                bestMoveString = searchEngine->next_move(); // Changed
                if (bestMoveString != "" && bestMoveString != "error!") {
                    // emitCommand();
                    searchEngine->emitCommand(); // Changed
                }
            }
#ifdef OPENING_BOOK
        }
#endif
    }
}

//////////////////////////////////////////////////////////////////////////

void Thread::setAi(Position *p)
{
    std::lock_guard lk(mutex);

    this->rootPos = p;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif
}

void Thread::setAi(Position *p, int time)
{
    setAi(p);

    timeLimit = time;
}

#ifdef OPENING_BOOK
deque<int> openingBookDeque({
    /* B W */
    21,
    23,
    19,
    20,
    17,
    18,
    15,
});

deque<int> openingBookDequeBak;

void sq2str(char *str)
{
    int sq = openingBookDeque.front();
    openingBookDeque.pop_front();
    openingBookDequeBak.push_back(sq);

    File file = FILE_A;
    Rank rank = RANK_1;
    int sig = 1;

    if (sq < 0) {
        sq = -sq;
        sig = 0;
    }

    file = file_of(sq);
    rank = rank_of(sq);

    if (sig == 1) {
        snprintf(str, Position::RECORD_LEN_MAX, 16, "(%d,%d)", file, rank);
    } else {
        snprintf(str, Position::RECORD_LEN_MAX, "-(%d,%d)", file, rank);
    }
}
#endif // OPENING_BOOK

Depth Thread::get_depth() const
{
    return Mills::get_search_depth(rootPos);
}

string Thread::get_value() const
{
    string value = std::to_string(bestvalue);
    return value;
}
