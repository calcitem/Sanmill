/*
Malom, a Nine Men's Morris (and variants) player and solver program.
Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
Copyright (C) 2023 The Sanmill developers (see AUTHORS file)

See our webpage (and the paper linked from there):
http://compalg.inf.elte.hu/~ggevay/mills/index.php


This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "perfect_debug.h"
#include "perfect_common.h"

#include <sstream>
#include <vector>

const char *toclp(board b)
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

std::string toclp2(board b)
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

std::string toclp3(board b, id id)
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

    ss << "0,0,0," << (id.WF ? 1 : 2) << "," << max_ksz - id.WF << ","
       << max_ksz - id.BF << "," << id.W << "," << id.B
       << ",False,60,-1000,0,3,malom2";

    return ss.str();
}
