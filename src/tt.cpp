// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tt.cpp

#include "tt.h"
#include <limits>

#ifdef TRANSPOSITION_TABLE_ENABLE

static constexpr int TRANSPOSITION_TABLE_SIZE = 0x1000000;
HashMap<Key, TTEntry> TT(TRANSPOSITION_TABLE_SIZE);

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

// Constants for generation management (similar to Stockfish)
static constexpr unsigned GENERATION_BITS = 2;
static constexpr int GENERATION_DELTA = (1 << GENERATION_BITS);
static constexpr int GENERATION_CYCLE = 255 + GENERATION_DELTA;
static constexpr int GENERATION_MASK = (0xFF << GENERATION_BITS) & 0xFF;

// TTEntry::save implementation with better replacement strategy
void TTEntry::save(Key k, Value v, Value e, bool pv, Bound b, Depth d, Move m, uint8_t generation8)
{
#ifdef TT_MOVE_ENABLE
    // Preserve the old ttmove if we don't have a new one
    if (m != MOVE_NONE || !is_occupied()) {
        ttMove = static_cast<uint16_t>(m);
    }
#endif

    // Overwrite less valuable entries (inspired by Stockfish logic)
    if (b == BOUND_EXACT || !is_occupied() || d - DEPTH_OFFSET + 2 * pv > depth8 - 4) {
        key16_ = static_cast<uint16_t>(k);  // Store key for verification
        value16 = static_cast<int16_t>(v);
        eval16 = static_cast<int16_t>(e);
        depth8 = static_cast<uint8_t>(d - DEPTH_OFFSET);
        
        // Pack generation and bound into genBound8
        genBound8 = static_cast<uint8_t>((generation8 & 0xFC) | static_cast<uint8_t>(b));
    }
    // If we can't replace, but depth is significant and bound isn't exact, age the entry
    else if (depth8 + DEPTH_OFFSET >= 5 && bound() != BOUND_EXACT) {
        depth8--;
    }
}

Value TranspositionTable::probe(Key key, Depth depth, Bound &type, Value &eval
#ifdef TT_MOVE_ENABLE
                                ,
                                Move &ttMove
#endif // TT_MOVE_ENABLE
)
{
    TTEntry tte {};
    
    // Initialize outputs
    type = BOUND_NONE;
    eval = VALUE_NONE;
#ifdef TT_MOVE_ENABLE
    ttMove = MOVE_NONE;
#endif

    if (!TT.find(key, tte)) {
        return VALUE_UNKNOWN;
    }

    // CRITICAL: Verify the key matches (like Stockfish)
    if (tte.key16() != static_cast<uint16_t>(key)) {
        return VALUE_UNKNOWN;
    }

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    // Check if entry is from current generation
    if ((tte.genBound8 & GENERATION_MASK) != (transpositionTableAge & GENERATION_MASK)) {
        return VALUE_UNKNOWN;
    }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    // Entry found and verified - always get eval and ttMove for move ordering
    eval = tte.eval();
#ifdef TT_MOVE_ENABLE
    ttMove = tte.tt_move();
#endif

    // Only return TT value if depth is sufficient
    if (tte.depth() >= depth && tte.is_occupied()) {
        type = tte.bound();
        return tte.value();
    }

    return VALUE_UNKNOWN;
}

bool TranspositionTable::search(Key key, TTEntry &tte)
{
    return TT.find(key, tte);
}

void TranspositionTable::prefetch(Key key)
{
    TT.prefetchValue(key);
}

int TranspositionTable::save(Value value, Value staticEval, Depth depth, Bound type, Key key
#ifdef TT_MOVE_ENABLE
                             ,
                             const Move &ttMove
#endif // TT_MOVE_ENABLE
)
{
    TTEntry tte {};
    bool found = search(key, tte);

    // Don't overwrite entries with higher depth unless we have better information
    if (found) {
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        // Check if entry is from current generation
        if ((tte.genBound8 & GENERATION_MASK) == (transpositionTableAge & GENERATION_MASK)) {
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
            if (tte.bound() != BOUND_NONE && tte.depth() > depth && type != BOUND_EXACT) {
                return -1;
            }
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
    }

    // Use the improved save method
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    tte.save(key, value, staticEval, false, type, depth, 
#ifdef TT_MOVE_ENABLE
             ttMove,
#else
             MOVE_NONE,
#endif
             transpositionTableAge);
#else
    tte.save(key, value, staticEval, false, type, depth,
#ifdef TT_MOVE_ENABLE
             ttMove,
#else
             MOVE_NONE,
#endif
             0);
#endif

    TT.insert(key, tte);
    return 0;
}

void TranspositionTable::new_search()
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    // Advance generation for new search
    transpositionTableAge += GENERATION_DELTA;
#endif
}

uint8_t TranspositionTable::generation()
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    return transpositionTableAge;
#else
    return 0;
#endif
}

void TranspositionTable::clear()
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    if (transpositionTableAge >= 252) { // Leave some margin for generation cycle
        debugPrintf("Clean TT\n");
        TT.clear();
        transpositionTableAge = 0;
    } else {
        transpositionTableAge += GENERATION_DELTA;
    }
#else
    TT.clear();
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
}

#endif /* TRANSPOSITION_TABLE_ENABLE */