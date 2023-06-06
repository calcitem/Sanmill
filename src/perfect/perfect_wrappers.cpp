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

#include "perfect_wrappers.h"

std::unordered_map<id, int> sector_sizes;

// This manages the lookup tables of the hash function: it keeps them in memory
// for a few most recently accessed sectors.
std::pair<int, Wrappers::gui_eval_elem2> Wrappers::WSector::hash(board a)
{
    static std::set<std::pair<int, ::Sector *>> loaded_hashes;
    static std::map<::Sector *, int> loaded_hashes_inv;
    static int timestamp = 0;

    ::Sector *tmp = s;

    if (s->hash == nullptr) {
        // hash object is not present

        if (loaded_hashes.size() == 8) {
            // release one if there are too many
            ::Sector *to_release = loaded_hashes.begin()->second;
            LOG("Releasing hash: %s\n", to_release->id.to_string().c_str());
            to_release->release_hash();
            loaded_hashes.erase(loaded_hashes.begin());
            loaded_hashes_inv.erase(to_release);
        }

        // load new one
        LOG("Loading hash: %s\n", s->id.to_string().c_str());
        s->allocate_hash();
    } else {
        // update access time
        loaded_hashes.erase(std::make_pair(loaded_hashes_inv[tmp], tmp));
    }
    loaded_hashes.insert(std::make_pair(timestamp, tmp));
    // s doesn't work here, which is probably a compiler bug!
    loaded_hashes_inv[tmp] = timestamp; 

    timestamp++;

    auto e = s->hash->hash(a);
    return std::make_pair(e.first, Wrappers::gui_eval_elem2(e.second, s));
}

void Wrappers::WID::negate()
{
    int t = W;
    W = B;
    B = t;

    t = WF;
    WF = BF;
    BF = t;
}

Wrappers::WID operator-(Wrappers::WID s)
{
    id r = s.tonat();
    r.negate();
    return Wrappers::WID(r);
}
