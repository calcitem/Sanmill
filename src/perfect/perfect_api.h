// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023-2025 The Sanmill developers (see AUTHORS file)
//
// See our webpage (and the paper linked from there):
// http://compalg.inf.elte.hu/~ggevay/mills/index.php
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
    static int get_best_move(int whiteBitboard, int blackBitboard,
                             int whiteStonesToPlace, int blackStonesToPlace,
                             int playerToMove, bool onlyStoneTaking,
                             Value &value, const Move &refMove);

    static int get_best_move_no_exception(int whiteBitboard, int blackBitboard,
                                          int whiteStonesToPlace,
                                          int blackStonesToPlace,
                                          int playerToMove,
                                          bool onlyStoneTaking, Value &value,
                                          const Move &refMove);

    static std::string get_last_error();

    static void initialize_if_needed();
    static void deinitialize_if_needed();

    static void must_be_between(std::string paramName, int value, int min,
                                int max);

    static void set_variant_stripped();
};

#endif // PERFECT_MALOM_SOLUTION_H_INCLUDED
