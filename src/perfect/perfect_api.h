// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_api.h

#ifndef PERFECT_MALOM_SOLUTION_H_INCLUDED
#define PERFECT_MALOM_SOLUTION_H_INCLUDED

#include "perfect_player.h"
#include "types.h"

// Forward declarations
class Position;
enum Move : int;

// Structure to hold detailed evaluation information from perfect database
struct PerfectEvaluation
{
    Value value;   // Game evaluation (WIN/DRAW/LOSS)
    int stepCount; // Steps to reach the result (-1 if unavailable)
    bool isValid;  // Whether the evaluation is from database

    PerfectEvaluation()
        : value(VALUE_NONE)
        , stepCount(-1)
        , isValid(false)
    { }
    PerfectEvaluation(Value v, int steps = -1)
        : value(v)
        , stepCount(steps)
        , isValid(true)
    { }
};

class MalomSolutionAccess
{
private:
    static PerfectPlayer *perfectPlayer;

public:
    // Error-code based implementation (no exceptions for performance)
    static int get_best_move(int whiteBitboard, int blackBitboard,
                             int whiteStonesToPlace, int blackStonesToPlace,
                             int playerToMove, bool onlyStoneTaking,
                             Value &value, const Move &refMove);

    static void deinitialize_if_needed();

    // Error-code based helper functions
    static bool initialize_if_needed();
    static int get_move_from_database(const GameState &s, Value &value,
                                      const Move &refMove);
    static PerfectEvaluation
    get_detailed_evaluation(const GameState &gameState);

    static void set_variant_stripped();

    // Method to get detailed evaluation information
    static PerfectEvaluation
    get_detailed_evaluation(int whiteBitboard, int blackBitboard,
                            int whiteStonesToPlace, int blackStonesToPlace,
                            int playerToMove, bool onlyStoneTaking);
};

namespace PerfectAPI {
// Get evaluation value from perfect database
// Returns VALUE_NONE if position is not in database or cannot be evaluated
Value getValue(const Position &pos);

// Get detailed evaluation information including step count from perfect
// database Returns PerfectEvaluation with isValid=false if position is not in
// database
PerfectEvaluation getDetailedEvaluation(const Position &pos);
} // namespace PerfectAPI

#endif // PERFECT_MALOM_SOLUTION_H_INCLUDED
