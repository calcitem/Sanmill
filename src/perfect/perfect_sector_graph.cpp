// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_sector_graph.cpp

#include "perfect_common.h"

#include "perfect_sector_graph.h"

#include <algorithm>
#include <queue>

extern int ruleVariant;
extern int field2Offset;
extern int maxKsz;

std::vector<Id> std_mora_graph_func(Id u)
{
    std::vector<Id> v;
    v.push_back(u);
    v.push_back(u);

    if (u.WF) {
        v[0].WF--;
        v[0].W++;

        v[1].WF--;
        v[1].W++;
        v[1].B--;
    } else {
        v[1].B--;
    }

    std::vector<Id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        // this actually only handles the initial part, cf. doc
        if (it->B + it->BF >= 3 && it->B >= 0)
            r.push_back(*it);

    return r;
}

std::vector<Id> lask_graph_func(Id u)
{
    std::vector<Id> v;

    if (u.WF != 0) {
        Id a = u;
        Id b = u;

        a.WF--;
        a.W++;

        b.WF--;
        b.W++;
        b.B--;

        v.push_back(a);
        v.push_back(b);
    }
    if (u.W != 0) {
        Id a = u;
        Id b = u;

        b.B--;

        v.push_back(a);
        v.push_back(b);
    }

    std::vector<Id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        // This actually only handles the initial part, cf. doc
        if (it->B + it->BF >= 3 && it->B >= 0)
            r.push_back(*it);

    return r;
}

std::vector<Id> graph_func(Id u, bool elim_loops)
{
    std::vector<Id> r0;

    if (ruleVariant == STANDARD) {
        r0 = std_mora_graph_func(u);
    } else if (ruleVariant == MORABARABA) {
        r0 = std_mora_graph_func(u);
    } else if (ruleVariant == LASKER) {
        r0 = lask_graph_func(u);
    } else {
        assert(false);
    }

    for (auto it = r0.begin(); it != r0.end(); it++)
        it->negate_id();

    std::set<Id> sr(r0.begin(), r0.end()); // parallel electric discharge

    // kizurese of hurokel
    if (elim_loops)
        sr.erase(u);

    return std::vector<Id>(sr.begin(), sr.end());
}

std::unordered_map<Id, std::vector<Id>> sector_graph;
std::unordered_map<Id, std::vector<Id>> sector_graph_t;

void init_wu_graph();

std::vector<Id> sector_list;

void init_sector_graph()
{
    LOG("init_sector_graph %s", ruleVariantName.c_str());

    std::queue<Id> q;
    std::set<Id> volt;
#ifndef FULL_SECTOR_GRAPH
    q.push(Id(0, 0, maxKsz, maxKsz));
    volt.insert(q.front());
#else
    for (int i = 3; i <= maxKsz; i++) {
        for (int j = 3; j <= maxKsz; j++) {
            Id s = Id {0, 0, i, j};
            q.push(s);
            volt.insert(s);
        }
    }
#endif
    while (!q.empty()) {
        Id u = q.front();
        q.pop();
        std::vector<Id> v = graph_func(u);
        for (auto it = v.begin(); it != v.end(); it++) {
            if (!volt.count(*it)) {
                q.push(*it);
                volt.insert(*it);
            }
            sector_graph[u].push_back(*it);
            sector_graph_t[*it].push_back(u);
        }
    }

    sector_list = std::vector<Id>(volt.begin(), volt.end());

    init_wu_graph();

    LOG(".\n");
}

std::unordered_map<Id, wu *> wus;

// manages the addition of neighbors of a sector of wu to wu.adj
void add_adj(wu &wu, Id Id)
{
    auto &e = sector_graph_t[Id];
    for (auto it = e.begin(); it != e.end(); ++it)
        // small size of loops (make sure that we only count the wu's according
        // to the pointer!)
        if (wus[*it] != &wu)
            // the parallel elements are squeezed out
            if (wu.parents.insert(wus[*it]).second)
                wus[*it]->child_count++;
}

std::set<Id> wu_ids;

void init_wu_graph()
{
    // the order in the sector_list determines which of the wu's sectors is
    // primary, it can always have the smaller ID
    for (auto it = sector_list.begin(); it != sector_list.end(); ++it)
        wus[*it] = new wu(*it);

    int n = (int)sector_list.size();
    for (int i = 0; i < n - 1; i++) {
        // (it's okay to hit the wu's twice)
        Id s1 = sector_list[i];
        for (Id s2 : sector_graph[s1]) {
            std::vector<Id> &e2 = sector_graph[s2];
            if (std::find(e2.begin(), e2.end(), s1) != e2.end()) {
                assert(s1 == -s2);
                wus[s1]->is_twine = true;
                wus[s2] = wus[s1];
            }
        }
        //
    }

    for (auto it = wus.begin(); it != wus.end(); ++it) {
        // (it's okay to go on the twines twice)
        auto &wu = *(it->second);

        add_adj(wu, wu.id);

        if (wu.is_twine)
            add_adj(wu, -wu.id);
    }

    for (auto it = wus.begin(); it != wus.end(); ++it)
        wu_ids.insert(it->second->id);
}
