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

#include "common.h"

#include "sector_graph.h"

vector<id> std_mora_graph_func(id u)
{
    vector<id> v;
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

    vector<id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        if (it->B + it->BF >= 3 && it->B >= 0) // ez tulajdonkeppen csak a
                                               // kezdoallast kezeli, ld. doc
            r.push_back(*it);

    return r;
}

vector<id> lask_graph_func(id u)
{
    vector<id> v;

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

    vector<id> r;
    for (auto it = v.begin(); it != v.end(); it++)
        if (it->B + it->BF >= 3 && it->B >= 0) // ez tulajdonkeppen csak a
                                               // kezdoallast kezeli, ld. doc
            r.push_back(*it);

    return r;
}

vector<id> graph_func(id u, bool elim_loops)
{
    vector<id> r0 = GRAPH_FUNC_NOTNEG(u);

    for (auto it = r0.begin(); it != r0.end(); it++)
        it->negate();

    set<id> sr(r0.begin(), r0.end()); // parhuzamos elek kiszurese
    if (elim_loops)
        sr.erase(u); // hurokel kiszurese

    return vector<id>(sr.begin(), sr.end());
}

unordered_map<id, vector<id>> sector_graph;
unordered_map<id, vector<id>> sector_graph_t;

void init_wu_graph();

vector<id> sector_list;

void init_sector_graph()
{
    LOG("init_sector_graph %s", VARIANT_NAME);

    queue<id> q;
    set<id> volt;
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
        vector<id> v = graph_func(u);
        for (auto it = v.begin(); it != v.end(); it++) {
            if (!volt.count(*it)) {
                q.push(*it);
                volt.insert(*it);
            }
            sector_graph[u].push_back(*it);
            sector_graph_t[*it].push_back(u);
        }
    }

    sector_list = vector<id>(volt.begin(), volt.end());

    init_wu_graph();

    LOG(".\n");
}

unordered_map<id, wu *> wus;

// elintezi a wu egyik szektoranak a szomszedainak a wu.adj-hoz valo hozzaadasat
void add_adj(wu &wu, id id)
{
    auto &e = sector_graph_t[id];
    for (auto it = e.begin(); it != e.end(); ++it)
        if (wus[*it] != &wu) // hurokelek kiszurese (vigyazzunk, hogy csak
                             // pointer szerint masolgassuk a wu-kat!)
            if (wu.parents.insert(wus[*it]).second) // kiszurodnek a parhuzamos
                                                    // elek
                wus[*it]->child_count++;
}

set<id> wu_ids;

void init_wu_graph()
{
    // a sector_list-beli sorrend hatarozza meg, hogy a wu-k ket szektora kozul
    // melyik az elsodleges, tehat mindig a kisebb id-ju
    for (auto it = sector_list.begin(); it != sector_list.end(); ++it)
        wus[*it] = new wu(*it);

    int n = (int)sector_list.size();
    for (int i = 0; i < n - 1; i++) {
        /*for(int j = i + 1; j < n; j++){
                id s1 = sector_list[i], s2 = sector_list[j];
                auto &e1 = sector_graph[s1];
                if(find(e1.begin(), e1.end(), s2) != e1.end()){
                        auto &e2 = sector_graph[s2];
                        if(find(e2.begin(), e2.end(), s1) != e2.end()){
                                assert(s1 == -s2);
                                wus[s1]->twine = true;
                                wus[s2] = wus[s1];
                        }
                }
        }*/

        //
        //(nem baj, hogy ketszer talaljuk meg a wu-kat)
        id s1 = sector_list[i];
        for (id s2 : sector_graph[s1]) {
            vector<id> &e2 = sector_graph[s2];
            if (find(e2.begin(), e2.end(), s1) != e2.end()) {
                assert(s1 == -s2);
                wus[s1]->twine = true;
                wus[s2] = wus[s1];
            }
        }
        //
    }

    for (auto it = wus.begin(); it != wus.end(); ++it) { //(nem baj, hogy
                                                         // ketszer megyunk a
                                                         // twineken)
        auto &wu = *(it->second);

        add_adj(wu, wu.id);

        if (wu.twine)
            add_adj(wu, -wu.id);
    }

    for (auto it = wus.begin(); it != wus.end(); ++it)
        wu_ids.insert(it->second->id);
}
