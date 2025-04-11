// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_wrappers.cpp

#include "perfect_wrappers.h"

int ruleVariant;

std::unordered_map<Id, int> sector_sizes;

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

void Wrappers::WID::negate_id()
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
    Id r = s.tonat();
    r.negate_id();
    return Wrappers::WID(r);
}
