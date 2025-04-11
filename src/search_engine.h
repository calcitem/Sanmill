// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// search_engine.h

#ifndef SEARCH_ENGINE_H_INCLUDED
#define SEARCH_ENGINE_H_INCLUDED

#include "config.h"

#include <string>
#include <functional>
#include <atomic>
#include <mutex>
#include <condition_variable>
#ifdef QT_GUI_LIB
#include <QObject>
#endif
#include "position.h"
#include "misc.h"

class SearchEngine
#ifdef QT_GUI_LIB
    : public QObject
#endif
{
#ifdef QT_GUI_LIB
    Q_OBJECT
#endif

public:
    explicit SearchEngine(
#ifdef QT_GUI_LIB
        QObject *parent = nullptr
#endif
    );

    /// Methods
    void emitCommand();
    void emitAnalyze();
    std::string next_move() const;
    void analyze(Color c) const;
    Depth get_depth() const;
    int executeSearch();
    std::string get_value() const;

    void setRootPosition(Position *p);
    std::string getBestMoveString() const;
    void setBestMoveString(const std::string &move);
    void getBestMoveFromOpeningBook();

    uint64_t beginNewSearch(Position *p);
    uint64_t beginNewAnalyze(Position *p);
    void runSearch();
    void runAnalyze();

    Position *rootPos {nullptr};

    /// Timeout check
    bool is_timeout(TimePoint startTime);

    /// Atomic flags and counters
    std::atomic_bool searchAborted {false};
    std::atomic_bool analyzeInProgress {false};
    std::atomic<uint64_t> currentSearchId {0};
    std::atomic<uint64_t> currentAnalyzeId {0};

    // Search start time for timeout checks
    TimePoint searchStartTime;

    Depth originDepth {0};
    Move bestMove {MOVE_NONE};
    Value bestvalue {VALUE_ZERO};
    Value lastvalue {VALUE_ZERO};
    AiMoveType aiMoveType {AiMoveType::unknown};
    std::string bestMoveString;
    std::string analyzeResult;

    std::mutex bestMoveMutex;
    std::condition_variable bestMoveCV;
    bool bestMoveReady {false};

    std::mutex analyzeMutex;
    std::condition_variable analyzeCV;
    bool analyzeReady {false};

#ifdef QT_GUI_LIB
signals:
    /// Signal that carries a command string (e.g., for AI moves)
    void command(const std::string &cmd, bool update);

    /// Signal that notifies listeners that the search has completed
    void searchCompleted();

    /// Signal that notifies listeners that the analyze has completed
    void analyzeCompleted();

    /// Signal that notifies listeners that the evaluation has completed
    void evaluationCompleted();
#endif

private:
    std::atomic<uint64_t> searchCounter {0};
    std::atomic<uint64_t> analyzeCounter {0};

#ifdef TIME_STAT
#ifdef QT_GUI_LIB
    TimePoint sortTime {0};
#endif
#endif

#ifdef CYCLE_STAT
    stopwatch::rdtscp_clock::time_point sortCycleStart;
    stopwatch::timer<std::chrono::system_clock>::duration sortCycleDuration {0};
    stopwatch::timer<std::chrono::system_clock>::period sortCyclePeriod;
#endif

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
};

#endif // SEARCH_ENGINE_H_INCLUDED
