// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_sector.h

#ifndef PERFECT_SECTOR_H_INCLUDED
#define PERFECT_SECTOR_H_INCLUDED

#include "perfect_common.h"
#include "perfect_eval_elem.h"
#include "perfect_sec_val.h"
#include "perfect_sector_graph.h"

#ifndef WRAPPER
#include "movegen.h"
#endif

extern int ruleVariant;
extern int field2Offset;
extern int maxKsz;

class Hash;
class Sector;

class Sector
{
    char fileName[255] {0};

    int eval_size;

public:
    std::map<int, int> em_set;

#ifdef DD
    static const int header_size = 64;
#else
    static const int header_size = 0;
#endif
    void read_header(FILE *file);
    void write_header(FILE *file);
    void read_em_set(FILE *file);

    int W {0};
    int B {0};
    int WF {0};
    int BF {0};
    Id id;

    Sector(::Id the_id);

    eval_elem2 get_eval(int i);
    eval_elem_sym2 get_eval_inner(int i);

#ifdef DD
    std::pair<sec_val, field2_t> extract_value(int i);
#endif

    // Statistics:
    int max_val, max_count;

    Hash *hash {nullptr};

    FILE *f {nullptr};

    void allocate_hash();
    void release_hash();

public:
    sec_val sval;
};

extern std::vector<std::vector<std::vector<std::vector<Sector *>>>> sectors;

#define sectors(Id) (sectors[(Id).W][(Id).B][(Id).WF][(Id).BF])

extern std::vector<Sector *> sector_objs;

#endif // PERFECT_SECTOR_H_INCLUDED
