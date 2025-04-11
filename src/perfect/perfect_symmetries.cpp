// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_symmetries.cpp

#include "perfect_symmetries.h"
#include "perfect_common.h"
#include "perfect_symmetries_slow.h"

int (*slow[16])(int) = {rotate90,
                        rotate180,
                        rotate270,
                        mirror_vertical,
                        mirror_horizontal,
                        mirror_backslash,
                        mirror_slash,
                        swap,
                        swap_rotate90,
                        swap_rotate180,
                        swap_rotate270,
                        swap_mirror_vertical,
                        swap_mirror_horizontal,
                        swap_mirror_backslash,
                        swap_mirror_slash,
                        id_transform};

const int patsize = 8, patc = 1 << patsize;
static_assert(24 % patsize == 0, "");

int table1[16][patc], table2[16][patc], table3[16][patc]; // 64 KB in total

void init_symmetry_lookup_tables()
{
    static bool called = false;
    if (called)
        return;
    called = true;

    LOG("init_symmetry_lookup_tables\n");

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

board sym24_transform(int op, board a)
{
    int mask = (1 << patsize) - 1;
    board b = 0;

    b |= table1[op][(a >> 0) & mask];
    b |= table2[op][(a >> 8) & mask];
    b |= table3[op][(a >> 16) & mask];

    return b;
}

board sym48_transform(int op, board a)
{
    return sym24_transform(op, a & mask24) |
           (sym24_transform(op, a >> 24) << 24);
}

int8_t inv[] = {2, 1, 0, 3, 4, 5, 6, 7, 10, 9, 8, 11, 12, 13, 14, 15};
