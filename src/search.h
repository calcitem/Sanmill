// search.h

#ifndef SEARCH_H_INCLUDED
#define SEARCH_H_INCLUDED

#include <vector>

#include "endgame.h"
#include "position.h"
#include "types.h"
#include "misc.h"
#include "stack.h"

#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

using std::vector;

namespace Search {

void init() noexcept;
void clear();

// Search algorithms
Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value pvs(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
          Depth originDepth, Value alpha, Value beta, Move &bestMove, int i,
          const Color before, const Color after);

Value search(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove);

Value random_search(Position *pos, Move &bestMove);

// Quiescence Search
Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

} // namespace Search

extern vector<Key> posKeyHistory;

#endif // SEARCH_H_INCLUDED
