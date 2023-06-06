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

#include <queue>

#include "perfect_common.h"

#include "perfect_sector_graph.h"

std::vector<id> std_mora_graph_func(id u)
{
    std::vector<id> v;
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

    std::vector<id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        // this actually only handles the initial part, cf. doc
        if (it->B + it->BF >= 3 && it->B >= 0)
            r.push_back(*it);

    return r;
}

std::vector<id> lask_graph_func(id u)
{
    std::vector<id> v;

    if (u.WF != 0) {
        id a = u;
        id b = u;

        a.WF--;
        a.W++;

        b.WF--;
        b.W++;
        b.B--;

        v.push_back(a);
        v.push_back(b);
    }
    if (u.W != 0) {
        id a = u;
        id b = u;

        b.B--;

        v.push_back(a);
        v.push_back(b);
    }

    std::vector<id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        // This actually only handles the initial part, cf. doc
        if (it->B + it->BF >= 3 && it->B >= 0)
            r.push_back(*it);

    return r;
}

std::vector<id> graph_func(id u, bool elim_loops)
{
    std::vector<id> r0 = GRAPH_FUNC_NOTNEG(u);

    for (auto it = r0.begin(); it != r0.end(); it++)
        it->negate();

    std::set<id> sr(r0.begin(), r0.end()); // parallel electric discharge
    if (elim_loops)
        sr.erase(u); // kizurese of hurokel

    return std::vector<id>(sr.begin(), sr.end());
}

std::unordered_map<id, std::vector<id>> sector_graph;
std::unordered_map<id, std::vector<id>> sector_graph_t;

void init_wu_graph();

std::vector<id> sector_list;

void init_sector_graph()
{
    LOG("init_sector_graph %s", VARIANT_NAME);

    std::queue<id> q;
    std::set<id> volt;
#ifndef FULL_SECTOR_GRAPH
    q.push(id(0, 0, max_ksz, max_ksz));
    volt.insert(q.front());
#else
    for (int i = 3; i <= max_ksz; i++) {
        for (int j = 3; j <= max_ksz; j++) {
            id s = id {0, 0, i, j};
            q.push(s);
            volt.insert(s);
        }
    }
#endif
    while (!q.empty()) {
        id u = q.front();
        q.pop();
        std::vector<id> v = graph_func(u);
        for (auto it = v.begin(); it != v.end(); it++) {
            if (!volt.count(*it)) {
                q.push(*it);
                volt.insert(*it);
            }
            sector_graph[u].push_back(*it);
            sector_graph_t[*it].push_back(u);
        }
    }

    sector_list = std::vector<id>(volt.begin(), volt.end());

    init_wu_graph();

    LOG(".\n");
}

std::unordered_map<id, wu *> wus;

// manages the addition of neighbors of a sector of wu to wu.adj
void add_adj(wu &wu, id id)
{
    auto &e = sector_graph_t[id];
    for (auto it = e.begin(); it != e.end(); ++it)
        // small size of loops (make sure that we only count the wu's according
        // to the pointer!)
        if (wus[*it] != &wu)
            // the parallel elements are squeezed out
            if (wu.parents.insert(wus[*it]).second) 
                wus[*it]->child_count++;
}

std::set<id> wu_ids;

void init_wu_graph()
{
    // the order in the sector_list determines which of the wu's sectors is
    // primary, it can always have the smaller ID
    for (auto it = sector_list.begin(); it != sector_list.end(); ++it)
        wus[*it] = new wu(*it);

    int n = (int)sector_list.size();
    for (int i = 0; i < n - 1; i++) {
        // (it's okay to hit the wu's twice)
        id s1 = sector_list[i];
        for (id s2 : sector_graph[s1]) {
            std::vector<id> &e2 = sector_graph[s2];
            if (std::find(e2.begin(), e2.end(), s1) != e2.end()) {
                assert(s1 == -s2);
                wus[s1]->twine = true;
                wus[s2] = wus[s1];
            }
        }
        //
    }

    for (auto it = wus.begin(); it != wus.end(); ++it) {
        // (it's okay to go on the twines twice)
        auto &wu = *(it->second);

        add_adj(wu, wu.id);

        if (wu.twine)
            add_adj(wu, -wu.id);
    }

    for (auto it = wus.begin(); it != wus.end(); ++it)
        wu_ids.insert(it->second->id);
}
