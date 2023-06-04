// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023 The Sanmill developers (see AUTHORS file)
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

#ifndef MALOM_SOLUTION_H_INCLUDED
#define MALOM_SOLUTION_H_INCLUDED

#include <iostream>
#include <stdexcept>
#include <string>
#include <unordered_map>

#include "PerfectPlayer.h"
#include "Player.h"
//#include "main.h"
#include "move.h"
#include "rules.h"

class MalomSolutionAccess
{
private:
    static PerfectPlayer *pp;
    static std::exception *lastError;

public:
    static int getBestMove(int whiteBitboard, int blackBitboard,
                           int whiteStonesToPlace, int blackStonesToPlace,
                           int playerToMove, bool onlyStoneTaking);

    static int getBestMoveNoException(int whiteBitboard, int blackBitboard,
                                      int whiteStonesToPlace,
                                      int blackStonesToPlace, int playerToMove,
                                      bool onlyStoneTaking);

    static std::string getLastError();

    static int getBestMoveStr(std::string args);

    static void initializeIfNeeded();
    static void deinitializeIfNeeded();

    static void mustBeBetween(std::string paramName, int value, int min,
                              int max);

    static void setVariantStripped();
};

#endif // MALOM_SOLUTION_H_INCLUDED
