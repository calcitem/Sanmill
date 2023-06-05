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

#include "perfect_common.h"
#include "perfect_symmetries.h"
#include "perfect_symmetries_slow.h"

int (*slow[16])(int) = {rot90,
                        rot180,
                        rot270,
                        tt_fuggoleges,
                        tt_vizszintes,
                        tt_bslash,
                        tt_slash,
                        swap,
                        swap_rot90,
                        swap_rot180,
                        swap_rot270,
                        swap_tt_fuggoleges,
                        swap_tt_vizszintes,
                        swap_tt_bslash,
                        swap_tt_slash,
                        id};

const int patsize = 8, patc = 1 << patsize;
static_assert(24 % patsize == 0, "");

int table1[16][patc], table2[16][patc], table3[16][patc]; // 64 KB in total

void init_sym_lookuptables()
{
    static bool called = false;
    if (called)
        return;
    called = true;

    LOG("init_sym_lookuptables\n");

    for (int pat = 0; pat < patc; pat++) {
        /*for(int i=0; i<16; i++)
                table1[i][pat] = slow[i](pat << 0);
        for(int i=0; i<16; i++)
                table2[i][pat] = slow[i](pat << 6);
        for(int i=0; i<16; i++)
                table3[i][pat] = slow[i](pat << 12);
        for(int i=0; i<16; i++)
                table4[i][pat] = slow[i](pat << 18);*/

        /*for(int k = 0; k < patn; k++)
                for(int i = 0; i<16; i++)
                        table[k][i][pat] = slow[i](pat << k*patsize);*/

        for (int i = 0; i < 16; i++)
            table1[i][pat] = slow[i](pat << 0);
        for (int i = 0; i < 16; i++)
            table2[i][pat] = slow[i](pat << 8);
        for (int i = 0; i < 16; i++)
            table3[i][pat] = slow[i](pat << 16);
    }
}

board sym24(int op, board a)
{
    int mask = (1 << patsize) - 1;
    board b = 0;

    b |= table1[op][(a >> 0) & mask];
    b |= table2[op][(a >> 8) & mask];
    b |= table3[op][(a >> 16) & mask];

    return b;
}

board sym48(int op, board a)
{
    return sym24(op, a & mask24) | (sym24(op, a >> 24) << 24);
}

int8_t inv[] = {2, 1, 0, 3, 4, 5, 6, 7, 10, 9, 8, 11, 12, 13, 14, 15};
