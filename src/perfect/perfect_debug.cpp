// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_debug.cpp

#include "perfect_debug.h"
#include "perfect_common.h"

#include <cstring>
#include <sstream>
#include <vector>

extern int ruleVariant;
extern int field2Offset;
extern int maxKsz;

const char *to_clp(board b)
{
    board mask = 1;
    std::vector<int> kit(24, -1);
    for (int i = 0; i < 24; i++) {
        if ((mask << i) & b)
            kit[i] = 0;
    }
    for (int i = 24; i < 48; i++) {
        if ((mask << i) & b)
            kit[i - 24] = 1;
    }

    std::stringstream ss;
    for (int i = 0; i < 24; i++)
        ss << kit[i] << ",";
    ss << "0,0,0,2,9,9," << POPCNT((unsigned int)(b & mask24)) << ","
       << POPCNT((unsigned int)((b & (mask24 << 24)) >> 24))
       << ",False,60,-1000,0,3,malom2";

    char *ret = new char[1024];
    STRCPY(ret, 1024, ss.str().c_str());
    return ret;
}

std::string to_clp2(board b)
{
    board mask = 1;
    std::vector<int> kit(24, -1);
    for (int i = 0; i < 24; i++) {
        if ((mask << i) & b)
            kit[i] = 0;
    }
    for (int i = 24; i < 48; i++) {
        if ((mask << i) & b)
            kit[i - 24] = 1;
    }

    std::stringstream ss;
    for (int i = 0; i < 24; i++)
        ss << kit[i] << ",";
    ss << "0,0,0,2,9,9,3,3,False,60,-1000,0,3,malom2";

    return ss.str();
}

std::string to_clp3(board b, Id Id)
{
    board mask = 1;
    std::vector<int> kit(24, -1);
    for (int i = 0; i < 24; i++) {
        if ((mask << i) & b)
            kit[i] = 0;
    }
    for (int i = 24; i < 48; i++) {
        if ((mask << i) & b)
            kit[i - 24] = 1;
    }

    std::stringstream ss;
    for (int i = 0; i < 24; i++)
        ss << kit[i] << ",";

    ss << "0,0,0," << (Id.WF ? 1 : 2) << "," << maxKsz - Id.WF << ","
       << maxKsz - Id.BF << "," << Id.W << "," << Id.B
       << ",False,60,-1000,0,3,malom2";

    return ss.str();
}
