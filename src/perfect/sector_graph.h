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

#ifndef SECTOR_GRAPH_H_INCLUDED
#define SECTOR_GRAPH_H_INCLUDED

#include "common.h"

#include <set>
#include <unordered_map>

#define HAS_SECTOR_GRAPH //(the Analyzer doesn't have the sector graph
                         //(init_sec_vals() has an ifdef for this))

extern unordered_map<id, vector<id>> sector_graph_t;
vector<id> graph_func(id u, bool elim_loops = true);

void init_sector_graph();

struct wu
{
    id id;
    bool twine;
    set<wu *> parents;
    int child_count;

    wu(::id id)
        : id(id)
        , twine(false)
        , child_count(0) {};

    // forbid copying
    wu(const wu &o) = delete;
    wu &operator=(const wu &o) = delete;
};

extern unordered_map<id, wu *> wus;

extern vector<id> sector_list;

extern set<id> wu_ids; // azok az id-k, amelyekre van olyan wu, aminek ez az
                       // id-je

#endif // SECTOR_GRAPH_H_INCLUDED
