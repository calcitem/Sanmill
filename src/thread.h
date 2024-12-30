// thread.h

#ifndef THREAD_H_INCLUDED
#define THREAD_H_INCLUDED

#include "config.h"

#include <atomic>
#include <condition_variable>
#include <string>
#include <vector>
#include <memory> // For smart pointers

#include "movepick.h"
#include "position.h"
#include "search.h"
#include "thread_win32_osx.h"
#include "search_engine.h"

#ifdef QT_GUI_LIB
#include <QObject>
#endif // QT_GUI_LIB

using std::string;

class SearchEngine;
struct ThreadPool;

/// Thread class keeps together all the thread-related stuff. We use
/// per-thread pawn and material hash tables so that once we get
/// a pointer to an entry its life time is unlimited and we don't have
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

    string get_value() const;
    Depth get_depth() const;

    int getTimeLimit() const { return timeLimit; }

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
    AiMoveType aiMoveType {AiMoveType::unknown};

    Color us {WHITE};

private:
    int timeLimit;

#ifdef QT_GUI_LIB
    Q_OBJECT

public:
    // Removed emitCommand()

signals:
#else
public:
    // Removed emitCommand()
#endif // QT_GUI_LIB

    // Removed command() signal
private:
    std::unique_ptr<SearchEngine> searchEngine;
};

extern ThreadPool Threads;

#endif // THREAD_H_INCLUDED
