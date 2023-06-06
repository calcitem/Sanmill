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

#ifndef PERFECT_HASH_H_INCLUDED
#define PERFECT_HASH_H_INCLUDED

#include "perfect_sector.h"

// void init_hash_lookuptables();

class Hash
{
    int W, B; // It might be worth to put these after the large arrays for cache
              // locality reasons

    int f_lookup[1 << 24] {0};
    char f_sym_lookup[1 << 24] {0}; // Converted from int to char
    int *f_inv_lookup {nullptr};
    int *g_lookup {nullptr};
    int *g_inv_lookup {nullptr};

    int f_count {0};

    Sector *s {nullptr};

public:
    Hash(int W, int B, Sector *s);

    std::pair<int, eval_elem2> hash(board a);
    board inv_hash(int h);

    int hash_count {0};

    unsigned short f_sym_lookup2[1 << 24];

    void check_hash_init_consistency();

    ~Hash();
};

int collapse(board a);
board uncollapse(board a);
int next_choose(int x);

#endif // PERFECT_HASH_H_INCLUDED
