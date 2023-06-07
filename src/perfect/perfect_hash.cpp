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
#include "perfect_hash.h"
#include "perfect_symmetries.h"

#include <algorithm>
#include <vector>

const int binom[25][25] = {
    {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 3, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 4, 6, 4, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 5, 10, 10, 5, 1, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0,  0,  0, 0, 0, 0, 0, 0, 0, 0},
    {1, 6, 15, 20, 15, 6, 1, 0, 0, 0, 0, 0, 0,
     0, 0, 0,  0,  0,  0, 0, 0, 0, 0, 0, 0},
    {1, 7, 21, 35, 35, 21, 7, 1, 0, 0, 0, 0, 0,
     0, 0, 0,  0,  0,  0,  0, 0, 0, 0, 0, 0},
    {1, 8, 28, 56, 70, 56, 28, 8, 1, 0, 0, 0, 0,
     0, 0, 0,  0,  0,  0,  0,  0, 0, 0, 0, 0},
    {1, 9, 36, 84, 126, 126, 84, 36, 9, 1, 0, 0, 0,
     0, 0, 0,  0,  0,   0,   0,  0,  0, 0, 0, 0},
    {1, 10, 45, 120, 210, 252, 210, 120, 45, 10, 1, 0, 0,
     0, 0,  0,  0,   0,   0,   0,   0,   0,  0,  0, 0},
    {1, 11, 55, 165, 330, 462, 462, 330, 165, 55, 11, 1, 0,
     0, 0,  0,  0,   0,   0,   0,   0,   0,   0,  0,  0},
    {1, 12, 66, 220, 495, 792, 924, 792, 495, 220, 66, 12, 1,
     0, 0,  0,  0,   0,   0,   0,   0,   0,   0,   0,  0},
    {1, 13, 78, 286, 715, 1287, 1716, 1716, 1287, 715, 286, 78, 13,
     1, 0,  0,  0,   0,   0,    0,    0,    0,    0,   0,   0},
    {1,  14, 91, 364, 1001, 2002, 3003, 3432, 3003, 2002, 1001, 364, 91,
     14, 1,  0,  0,   0,    0,    0,    0,    0,    0,    0,    0},
    {1,   15, 105, 455, 1365, 3003, 5005, 6435, 6435, 5005, 3003, 1365, 455,
     105, 15, 1,   0,   0,    0,    0,    0,    0,    0,    0,    0},
    {1,     16,   120,  560,  1820, 4368, 8008, 11440, 12870,
     11440, 8008, 4368, 1820, 560,  120,  16,   1,     0,
     0,     0,    0,    0,    0,    0,    0},
    {1,     17,    136,   680,  2380, 6188, 12376, 19448, 24310,
     24310, 19448, 12376, 6188, 2380, 680,  136,   17,    1,
     0,     0,     0,     0,    0,    0,    0},
    {1,     18,    153,   816,   3060, 8568, 18564, 31824, 43758,
     48620, 43758, 31824, 18564, 8568, 3060, 816,   153,   18,
     1,     0,     0,     0,     0,    0,    0},
    {1,     19,    171,   969,   3876,  11628, 27132, 50388, 75582,
     92378, 92378, 75582, 50388, 27132, 11628, 3876,  969,   171,
     19,    1,     0,     0,     0,     0,     0},
    {1,      20,     190,    1140,   4845,  15504, 38760, 77520, 125970,
     167960, 184756, 167960, 125970, 77520, 38760, 15504, 4845,  1140,
     190,    20,     1,      0,      0,     0,     0},
    {1,      21,     210,    1330,   5985,   20349,  54264, 116280, 203490,
     293930, 352716, 352716, 293930, 203490, 116280, 54264, 20349,  5985,
     1330,   210,    21,     1,      0,      0,      0},
    {1,      22,     231,    1540,   7315,   26334,  74613,  170544, 319770,
     497420, 646646, 705432, 646646, 497420, 319770, 170544, 74613,  26334,
     7315,   1540,   231,    22,     1,      0,      0},
    {1,      23,      253,     1771,    8855,    33649,  100947, 245157, 490314,
     817190, 1144066, 1352078, 1352078, 1144066, 817190, 490314, 245157, 100947,
     33649,  8855,    1771,    253,     23,      1,      0},
    {1,       24,      276,     2024,    10626,   42504,   134596,
     346104,  735471,  1307504, 1961256, 2496144, 2704156, 2496144,
     1961256, 1307504, 735471,  346104,  134596,  42504,   10626,
     2024,    276,     24,      1}};

int next_choose(int x)
{
    if (x == 0)
        return 1 << 24;

    int c = x & -x, r = x + c;
    return (((r ^ x) >> 2) / c) | r;
}

void init_collapse_lookup();

Hash::Hash(int W, int B, Sector *s)
    : W(W)
    , B(B)
    , s(s)
{
    g_lookup = new int[1LL << (24 - W)];

    memset(f_lookup, -1, sizeof(f_lookup));
    memset(f_sym_lookup2, 0, sizeof(f_sym_lookup2));
    int c = 0;
    for (int w = (1 << W) - 1; w < 1 << 24; w = next_choose(w))
        if (f_lookup[w] == -1) {
            for (int i = 0; i < 16; i++) {
                // for(int i=15; i>=0; i--){
                auto sw = sym24(i, w);
                f_lookup[sw] = c;
                f_sym_lookup[sw] = inv[i];
                f_sym_lookup2[sw] |= 1 << inv[i];
            }
            /*
            We call a state canonical that can be hashed (i.e., the inv_hash may
            return it). A partition is one that has a matching hash. The
            previous loop sometimes writes to the same place in f_sym_lookup
            more than once. This corresponds to a table that can be symmetrized
            into several canonical states (that is, they match on the white
            part, but may vary on the black part) (several symmetry operations
            (that overwrite the same) bring the whites into the same state, but
            not necessarily the blacks). The point is that f_sym_lookup should
            always lead to a canonical form. It usually doesn't matter which
            one, except when we are already in a canonical form, because then it
            is only allowed to lead into itself. (because partitions can only
            look like they have one canonical member, and each points to the
            canonical state) The line below is needed because if a symmetry
            operation led the whites into itself, then the overwrite can lead
            the canonical into another canonical with f_sym_lookup. The line
            below corrects the f_sym value associated with the canonical. It
            doesn't need to be corrected for the others, because they definitely
            lead to a canonical (which is enough), since the inv[i] in the third
            line of the loop body necessarily leads into w, which will be
            canonical. (We call a position canonical if it is half of a proper
            canonical (then it also fulfills that it is only half of
            canonicals)) Thus, the first reached of a partition will certainly
            be canonical, because thinking through a forward-backward hashing,
            we get back such positions. (this is what the line below is for)

            We call the sets obtained based on the above loop orbits. (we only
            look at the white part of the positions) Below, the ws flip is
            needed because the different elements of the set we get by
            supplementing an orbit with blacks (everywhere in the same way (in a
            collapsed sense)), may be in different partitions. The reason for
            this is that the hash value at the g-s tag may differ because the
            value of f_sym_lookup can be different at that tag.

            New solution:
            We replace the line below by putting the identical into the end of
            the array of symmetry operations. Because then if the identical
            collides with something, 0 will get into f_sym_lookup. // I mean,
            this is written, right? So it's not "0 gets in", but identical gets
            in.
            */
            // f_sym_lookup[w]=0;
            c++;
        }

    f_count = c;
    f_inv_lookup = new int[f_count];

    std::vector<int> ws;
    for (int w = (1 << W) - 1; w < 1 << 24; w = next_choose(w))
        ws.push_back(w);
    reverse(ws.begin(), ws.end());
    for (auto it = ws.begin(); it != ws.end(); ++it) {
        auto w = *it;
        f_inv_lookup[f_lookup[w]] = w;
    }

    g_inv_lookup = new int[binom[24 - W][B]];
    c = 0;
    for (int b = (1 << B) - 1; b < 1 << (24 - W); b = next_choose(b)) {
        if (c >= binom[24 - W][B]) {
            assert(false);
            break;
        }
        g_lookup[b] = c;
        g_inv_lookup[c] = b;
        c++;
    }

    hash_count = f_count * binom[24 - W][B];

    init_collapse_lookup();

#ifdef _DEBUG
#ifndef WRAPPER // The Wrapper uses the manual popcnt, which makes this
                // noticeably slow when playing
    check_hash_init_consistency();
#endif
#endif
}

void Hash::check_hash_init_consistency()
{
    for (int i = 0; i < 1 << 24; i++)
        if (static_cast<int>(POPCNT(i)) == W)
            assert(f_sym_lookup[i] >= 0 && f_sym_lookup[i] < 16);
}

Hash::~Hash()
{
    delete [] f_inv_lookup;
    delete [] g_lookup;
    delete [] g_inv_lookup;
}

std::pair<int, eval_elem2> Hash::hash(board a)
{
    a = sym48(f_sym_lookup[a & mask24], a);
    int h1 = f_lookup[a & mask24] * binom[24 - W][B] + g_lookup[collapse(a)];
    eval_elem_sym2 e = s->get_eval_inner(h1);
    if (e.cas() != eval_elem_sym2::Sym)
        return std::make_pair(h1, e);
    else {
        a = sym48(e.sym(), a);
        int h2 = f_lookup[a & mask24] * binom[24 - W][B] +
                 g_lookup[collapse(a)];
        assert(s->get_eval_inner(h2).cas() != eval_elem_sym2::Sym);
        return std::make_pair(h2, s->get_eval(h2));
    }
}

board Hash::inv_hash(int h)
{
    int m = binom[24 - W][B];
    int f = h / m, g = h % m;
    return uncollapse(f_inv_lookup[f] | ((board)g_inv_lookup[g] << 24));
}

board uncollapse(board a)
{
    int w = (int)(a & mask24), b = (int)(a >> 24), r = 0;
    for (int i = 1; i < 1 << 24; i <<= 1)
        if (w & i)
            b <<= 1;
        else
            r |= b & i;
    return ((board)r << 24) | w;
}

// Original version
// ~83 clock cycles if we increment the hash one by one (probably the branch
// prediction is good at this time, since the positions are similar to each
// other)
// __declspec(noinline)
#ifdef WRAPPER
int collapse(board a)
{
    int w = (int)(a & mask24), b = (int)(a >> 24);
    int i = 1, j = 1, r = 0;
    for (; i < 1 << 24; i <<= 1) {
        if (!(w & i)) {
            r |= b & j;
            j <<= 1;
        } else
            b >>= 1;
    }
    return r;
}
#endif

// 8: 1:24
// 6: 1:29
// 4: 1:32
const int sl = 8, psl = 1 << sl;
unsigned char collapse_lookup[psl][psl];

void init_collapse_lookup()
{
    // LOG("init_collapse_lookup");

    for (int w = 0; w < psl; w++)
        for (int bl = 0; bl < psl; bl++) {
            int b = bl;
            int i = 1, j = 1, r = 0;
            for (; i < psl; i <<= 1) {
                if (!(w & i)) {
                    r |= b & j;
                    j <<= 1;
                } else
                    b >>= 1;
            }
            collapse_lookup[w][bl] = static_cast<uint8_t>(r);
        }

    // LOG(".\n");
}
