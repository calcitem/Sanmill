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
    explicit SearchEngine(Thread *thread);
    void emitCommand();
    std::string next_move() const;
    void analyze(Color c) const;
    Depth get_depth() const;
    int executeSearch();
    std::string get_value() const;
    Position *rootPos {nullptr};
    // Timeout check
    bool is_timeout(TimePoint startTime);

private:
    Thread *thread;
    Depth originDepth {0};
    Move bestMove {MOVE_NONE};
    Value bestvalue {VALUE_ZERO};
    Value lastvalue {VALUE_ZERO};
    AiMoveType aiMoveType {AiMoveType::unknown};
};

#endif // SEARCH_ENGINE_H_INCLUDED
