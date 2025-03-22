// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_test.cpp

// You have to set the working directory to the directory of the database.

// #define no_init_all // Was needed only in VS 2017

// run_perfect_test.cpp

#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING

#include <cstdio>
#include <sstream>
#include <string>

#include "perfect_api.h"
#include "perfect_common.h"

int run_perfect_test(int argc, char *argv[])
{
    Value value = VALUE_UNKNOWN;

    Move move = MOVE_NONE;

    if (argc == 2) {
        secValPath = argv[1];
    }

    // int res = MalomSolutionAccess::get_best_move(0, 0, 9, 9, 0, false, move);
    int res = MalomSolutionAccess::get_best_move(1, 2, 8, 8, 0, false, value,
                                                 move); // Correct
                                                        // output:
                                                        // 16384
    // int res = MalomSolutionAccess::get_best_move(1 + 2 + 4, 8 + 16 + 32, 100,
    // 0, 0, false, value, move); // tests exception
    //  int res = MalomSolutionAccess::get_best_move(1 + 2 + 4, 1 + 8 + 16 + 32,
    //  0, 0, 0, false, value, move); // tests exception int res =
    //  MalomSolutionAccess::get_best_move(1 + 2 + 4, 8 + 16 + 32, 0, 0, 0,
    //  true,
    //                                   value, move);
    //  // Correct output: any of 8, 16, 32

    printf("get_best_move result: %d\n", res);

#ifdef _WIN32
    system("pause");
#endif

    return 0;
}
