// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef THREAD_H_INCLUDED
#define THREAD_H_INCLUDED

#include "config.h"

#include <atomic>
#include <condition_variable>
#include <string>
#include <vector>

#include "movepick.h"
#include "position.h"
#include "search.h"
#include "thread_win32_osx.h"

#ifdef QT_GUI_LIB
#include <QObject>
#endif // QT_GUI_LIB

using std::string;

/// Thread class keeps together all the thread-related stuff. We use
/// per-thread pawn and material hash tables so that once we get a
/// pointer to an entry its life time is unlimited and we don't have
/// to care about someone changing the entry under our feet.
class Thread
#ifdef QT_GUI_LIB
    : public QObject
#endif
{
public:
    std::mutex mutex;
    std::condition_variable cv;
    size_t idx;
    bool exit = false, searching = true; // Set before starting std::thread
    NativeThread stdThread;

    explicit Thread(size_t n
#ifdef QT_GUI_LIB
                    ,
                    QObject *parent = nullptr
#endif
    );
#ifdef QT_GUI_LIB
    ~Thread() override;
#else
    virtual ~Thread();
#endif
    int search();
    static void clear() noexcept;
    void idle_loop();
    void start_searching();
    void wait_for_search_finished();

    Position *rootPos {nullptr};

    // Mill Game

    string bestMoveString;

    void pause();

    void setAi(Position *p);
    void setAi(Position *p, int time);

    [[nodiscard]] string next_move() const;
    [[nodiscard]] string get_value() const;
    [[nodiscard]] Depth get_depth() const;

    [[nodiscard]] int getTimeLimit() const { return timeLimit; }

    void analyze(Color c) const;

#ifdef TIME_STAT
    TimePoint sortTime {0};
#endif
#ifdef CYCLE_STAT
    stopwatch::rdtscp_clock::time_point sortCycle;
    stopwatch::timer<std::chrono::system_clock>::duration sortCycle {0};
    stopwatch::timer<std::chrono::system_clock>::period sortCycle;
#endif

#ifdef ENDGAME_LEARNING
    static bool probeEndgameHash(Key key, Endgame &endgame);
    static int saveEndgameHash(Key key, const Endgame &endgame);
    void clearEndgameHashMap();
    static void saveEndgameHashMapToFile();
    static void loadEndgameFileToHashMap();
#endif // ENDGAME_LEARNING

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t tteCount {0};
    size_t ttHitCount {0};
    size_t ttMissCount {0};
    size_t ttInsertNewCount {0};
    size_t ttAddrHitCount {0};
    size_t ttReplaceCozDepthCount {0};
    size_t ttReplaceCozHashCount {0};
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    Depth originDepth {0};

    Move bestMove {MOVE_NONE};
    Value bestvalue {VALUE_ZERO};
    Value lastvalue {VALUE_ZERO};

    Color us {WHITE};

private:
    int timeLimit;

#ifdef QT_GUI_LIB
    Q_OBJECT

public:
    void emitCommand();

signals:
#else
public:
    void emitCommand();
#endif // QT_GUI_LIB

    void command(const string &record, bool update = true);
};

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

extern ThreadPool Threads;

#endif // #ifndef THREAD_H_INCLUDED
