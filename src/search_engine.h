// search_engine.h

#ifndef SEARCH_ENGINE_H_INCLUDED
#define SEARCH_ENGINE_H_INCLUDED

#include <string>
#include "position.h"
#include "misc.h"

class Thread;

class SearchEngine
{
public:
    explicit SearchEngine();
    void emitCommand();
    std::string next_move() const;
    void analyze(Color c) const;
    Depth get_depth() const;
    int executeSearch();
    std::string get_value() const;

    void setRootPosition(Position *p);
    std::string getBestMoveString() const;
    void setBestMoveString(const std::string &move);
    void getBestMoveFromOpeningBook();

    void runSearch();

    Position *rootPos {nullptr};
    // Timeout check
    bool is_timeout(TimePoint startTime);

private:
    Depth originDepth {0};
    Move bestMove {MOVE_NONE};
    Value bestvalue {VALUE_ZERO};
    Value lastvalue {VALUE_ZERO};
    AiMoveType aiMoveType {AiMoveType::unknown};

    std::string bestMoveString;

#ifdef TIME_STAT
    TimePoint sortTime {0};
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
