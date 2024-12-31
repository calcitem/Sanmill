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

#ifdef OPENING_BOOK
#include "opening_book.h"
#endif // OPENING_BOOK

#ifdef QT_GUI_LIB
#include <QObject>
#endif // QT_GUI_LIB

using std::string;

class SearchEngine;
struct ThreadPool;

/// Thread class keeps together all the thread-related stuff.
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
    std::unique_ptr<SearchEngine> searchEngine;

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
    static void clear() noexcept;
    void idle_loop();
    void start_searching();
    void wait_for_search_finished();

    void pause();

    void setAi(Position *p);
    void setAi(Position *p, int time);

    int getTimeLimit() const { return timeLimit; }

    Color us {WHITE};

#ifdef QT_GUI_LIB
    Q_OBJECT

public:
signals:
#else
public:
#endif // QT_GUI_LIB

private:
    int timeLimit;
};

extern ThreadPool Threads;

#endif // THREAD_H_INCLUDED
