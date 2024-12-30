// search_engine.h

#ifndef SEARCH_ENGINE_H_INCLUDED
#define SEARCH_ENGINE_H_INCLUDED

#include <string>
#include "position.h"

class Thread;

class SearchEngine
{
public:
    explicit SearchEngine(Thread *thread);
    void emitCommand();
    std::string next_move() const;
    void analyze(Color c) const;

private:
    Thread *thread;
};

#endif // SEARCH_ENGINE_H_INCLUDED
