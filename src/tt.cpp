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

// Generation management constants are now defined in tt.h

// TTEntry::save implementation with better replacement strategy (Stockfish-inspired)
void TTEntry::save(Key k, Value v, Value e, bool pv, Bound b, Depth d, Move m, uint8_t generation8)
{
    // Check if we should overwrite this entry (Stockfish replacement scheme)
    // 1. If entry is empty, always overwrite
    // 2. If same position (key match), always overwrite
    // 3. If we have exact bound, overwrite (exact scores are valuable)
    // 4. If new depth is greater than old depth plus some margin for PV nodes
    // 5. If entry is from old generation (aged entry)
    
    const uint16_t newKey16 = static_cast<uint16_t>(k);
    const uint8_t newDepth8 = static_cast<uint8_t>(d - DEPTH_OFFSET);
    
    bool replace = false;
    
    if (!is_occupied()) {
        // Empty entry, always replace
        replace = true;
    }
    else if (key16_ == newKey16) {
        // Same position, always replace
        replace = true;
    }
    else if (b == BOUND_EXACT) {
        // Exact bound is very valuable
        replace = true;
    }
    else {
        // Calculate replacement priority based on depth, PV status, and age
        const int oldPriority = depth8 - 4 * relative_age(generation8);
        const int newPriority = newDepth8 + 2 * static_cast<int>(pv);
        
        replace = (newPriority > oldPriority);
    }

    if (replace) {
        key16_ = newKey16;
        value16 = static_cast<int16_t>(v);
        eval16 = static_cast<int16_t>(e);
        depth8 = newDepth8;
        
        // Pack generation and bound into genBound8
        genBound8 = static_cast<uint8_t>((generation8 & 0xFC) | static_cast<uint8_t>(b));
        
#ifdef TT_MOVE_ENABLE
        // Always save move if we have one, or preserve old move if we don't
        if (m != MOVE_NONE) {
            ttMove = static_cast<uint16_t>(m);
        }
        // If we don't have a move but entry is new, clear the old move
        else if (key16_ != newKey16) {
            ttMove = MOVE_NONE;
        }
#endif
    }
    else {
        // Don't replace, but preserve TT move if we have a good one
#ifdef TT_MOVE_ENABLE
        if (m != MOVE_NONE && key16_ == newKey16) {
            ttMove = static_cast<uint16_t>(m);
        }
#endif
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