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

#ifndef SECTOR_H_INCLUDED
#define SECTOR_H_INCLUDED

#include "common.h"
#include "eval_elem.h"
#include "sec_val.h"
#include "sector_graph.h"

#ifndef WRAPPER
#include "movegen.h"
#endif

class Hash;
class Sector;

class Sector
{
    char fname[255] {0};

    int eval_size;

    map<int, int> em_set;

    FILE* f { nullptr };


#ifdef DD
    static const int header_size = 64;
#else
    static const int header_size = 0;
#endif
    void read_header(FILE *file);
    void write_header(FILE *file);
    void read_em_set(FILE *file);

public:
    int W {0};
    int B {0};
    int WF {0};
    int BF {0};
    id id;

    Sector(::id id);

    eval_elem2 get_eval(int i);
    eval_elem_sym2 get_eval_inner(int i);

#ifdef DD
    pair<sec_val, field2_t> extract(int i);
    void intract(int i, pair<sec_val, field2_t> x);
#endif

    // Statistics:
    int max_val, max_count;

    Hash *hash {nullptr};

    void allocate_hash();
    void release_hash();

public:
    sec_val sval;
};

extern Sector *sectors[max_ksz + 1][max_ksz + 1][max_ksz + 1][max_ksz + 1];
#define sectors(id) (sectors[(id).W][(id).B][(id).WF][(id).BF])

extern vector<Sector *> sector_objs;

#endif // SECTOR_H_INCLUDED
