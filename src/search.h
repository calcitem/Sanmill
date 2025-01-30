// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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

class SearchEngine;

using std::vector;

namespace Search {

void init() noexcept;
void clear();

// Search algorithms
Value MTDF(SearchEngine &searchEngine, Position *pos,
           Sanmill::Stack<Position> &ss, Value firstguess, Depth depth,
           Depth originDepth, Move &bestMove);

Value pvs(SearchEngine &searchEngine, Position *pos,
          Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
          Value alpha, Value beta, Move &bestMove, int i, const Color before,
          const Color after);

Value search(SearchEngine &searchEngine, Position *pos,
             Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
             Value alpha, Value beta, Move &bestMove);

Value random_search(Position *pos, Move &bestMove);

// Quiescence Search
Value qsearch(SearchEngine &searchEngine, Position *pos,
              Sanmill::Stack<Position> &ss, Depth depth, Depth originDepth,
              Value alpha, Value beta, Move &bestMove);

} // namespace Search

extern vector<Key> posKeyHistory;

#endif // SEARCH_H_INCLUDED
