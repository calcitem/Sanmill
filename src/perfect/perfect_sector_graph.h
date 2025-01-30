// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
        , child_count(0) {};

    // forbid copying
    wu(const wu &o) = delete;
    wu &operator=(const wu &o) = delete;
};

extern std::unordered_map<Id, wu *> wus;

extern std::vector<Id> sector_list;

// the ids for which there is a wu with this id
extern std::set<Id> wu_ids;

#endif // PERFECT_SECTOR_GRAPH_H_INCLUDED
