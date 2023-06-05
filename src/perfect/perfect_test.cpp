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

// You have to set the working directory to the directory of the database.

// #define no_init_all // Was needed only in VS 2017

#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING

#include <cstdio>
#include <sstream>
#include <string>

#include "perfect_api.h"
#include "perfect_common.h"

int perfect_test(int argc, char *argv[])
{
    if (argc == 2) {
        sec_val_path = argv[1];
    }

    //int res = MalomSolutionAccess::getBestMove(0, 0, 9, 9, 0, false);
    int res = MalomSolutionAccess::getBestMove(1, 2, 8, 8, 0, false); // Correct
                                                                      // output:
                                                                      // 16384
    // int res = MalomSolutionAccess::getBestMove(1 + 2 + 4, 8 + 16 + 32, 100,
    // 0, 0, false); // tests exception
    //  int res = MalomSolutionAccess::getBestMove(1 + 2 + 4, 1 + 8 + 16 + 32,
    //  0, 0, 0, false); // tests exception int res =
    //  MalomSolutionAccess::getBestMove(1 + 2 + 4, 8 + 16 + 32, 0, 0, 0, true);
    //  // Correct output: any of 8, 16, 32

    printf("GetBestMove result: %d\n", res);

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}
