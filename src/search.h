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
#include "history.h"

#ifdef CYCLE_STAT
#include "stopwatch.h"
#endif

class SearchEngine;

using std::vector;

namespace Search {

void init() noexcept;
void clear();

// History tables (global for all searches)
extern ButterflyHistory mainHistory;
extern PieceToHistory pieceToHistory;
extern KillerMoves killerMoves;
extern CounterMoves counterMoves;

// Search algorithms
Value MTDF(SearchEngine &searchEngine, Position *pos, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value pvs(SearchEngine &searchEngine, Position *pos, Depth depth,
          Depth originDepth, Value alpha, Value beta, Move &bestMove, int i,
          const Color before, const Color after);

Value search(SearchEngine &searchEngine, Position *pos, Depth depth,
             Depth originDepth, Value alpha, Value beta, Move &bestMove);

Value random_search(Position *pos, Move &bestMove);

// Quiescence Search
Value qsearch(SearchEngine &searchEngine, Position *pos, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

// Null move search (adapted for Mill Game dynamics)
// Special considerations:
// - Avoids null move during remove actions (mandatory moves)
// - Conservative near mill formations (potential consecutive moves)
// - Reduced aggressiveness compared to chess engines
Value null_move_search(SearchEngine &searchEngine, Position *pos, Depth depth,
                      Depth originDepth, Value alpha, Value beta, Move &bestMove);

// History and move ordering utilities
void update_history(Position *pos, Move move, Depth depth, bool good);
void update_killers(Move move, int ply);
int move_history_score(Position *pos, Move move);
bool is_killer_move(Move move, int ply);

} // namespace Search

#endif // SEARCH_H_INCLUDED
