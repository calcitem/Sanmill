// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_hash.h

#ifndef PERFECT_HASH_H_INCLUDED
#define PERFECT_HASH_H_INCLUDED

#include "perfect_sector.h"

#include <cstring>

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
    Hash(int the_w, int the_b, Sector *sec);

    std::pair<int, eval_elem2> hash(board a);
    board inverse_hash(int h);

    int hash_count {0};

    unsigned short f_sym_lookup2[1 << 24];

    void check_hash_init_consistency();

    ~Hash();
};

int collapse(board a);
board uncollapse(board a);
int next_choose(int x);

#endif // PERFECT_HASH_H_INCLUDED
