// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023-2025 The Sanmill developers (see AUTHORS file)
//
// See our webpage (and the paper linked from there):
// http://compalg.inf.elte.hu/~ggevay/mills/index.php
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// perfect_sector_graph.h

#ifndef PERFECT_SECTOR_GRAPH_H_INCLUDED
#define PERFECT_SECTOR_GRAPH_H_INCLUDED

#include "perfect_common.h"

#include <set>
#include <unordered_map>
#include <vector>

// (the Analyzer doesn't have the sector graph
// (init_sec_vals() has an ifdef for this))
#define HAS_SECTOR_GRAPH

extern std::unordered_map<Id, std::vector<Id>> sector_graph_t;
std::vector<Id> graph_func(Id u, bool elim_loops = true);

void init_sector_graph();

struct wu
{
    Id id;
    bool is_twine;
    std::set<wu *> parents;
    int child_count;

    wu(::Id myId)
        : id(myId)
        , is_twine(false)
        , child_count(0) { };

    // forbid copying
    wu(const wu &o) = delete;
    wu &operator=(const wu &o) = delete;
};

extern std::unordered_map<Id, wu *> wus;

extern std::vector<Id> sector_list;

// the ids for which there is a wu with this id
extern std::set<Id> wu_ids;

#endif // PERFECT_SECTOR_GRAPH_H_INCLUDED
