// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_api.h

#ifndef PERFECT_MALOM_SOLUTION_H_INCLUDED
#define PERFECT_MALOM_SOLUTION_H_INCLUDED

#include "perfect_player.h"

class MalomSolutionAccess
{
private:
    static PerfectPlayer *perfectPlayer;
    static std::exception *lastError;

public:
    static int
    get_best_move(int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
                  int blackStonesToPlace, int playerToMove,
                  bool onlyStoneTaking, Value &value, const Move &refMove,
                  std::vector<std::pair<AdvancedMove, int>> &distances);

    static int get_best_move_no_exception(
        int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
        int blackStonesToPlace, int playerToMove, bool onlyStoneTaking,
        Value &value, const Move &refMove,
        std::vector<std::pair<AdvancedMove, int>> &distances);

    static std::string get_last_error();

    static void initialize_if_needed();
    static void deinitialize_if_needed();

    static void must_be_between(std::string paramName, int value, int min,
                                int max);

    static void set_variant_stripped();
};

#endif // PERFECT_MALOM_SOLUTION_H_INCLUDED
