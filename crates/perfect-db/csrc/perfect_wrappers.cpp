// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_wrappers.cpp

#include "perfect_wrappers.h"

int ruleVariant;

std::unordered_map<Id, int> sector_sizes;

namespace {

std::set<std::pair<int, ::Sector *>> g_loaded_hashes;
std::map<::Sector *, int> g_loaded_hashes_inv;
int g_loaded_hash_timestamp = 0;

} // namespace

void Wrappers::reset_hash_cache()
{
    g_loaded_hashes.clear();
    g_loaded_hashes_inv.clear();
    g_loaded_hash_timestamp = 0;
}

// This manages the lookup tables of the hash function: it keeps them in memory
// for a few most recently accessed sectors.
std::pair<int, Wrappers::gui_eval_elem2> Wrappers::WSector::hash(board a)
{
    ::Sector *tmp = s;

    if (s->hash == nullptr) {
        // hash object is not present

        if (g_loaded_hashes.size() == 8) {
            // release one if there are too many
            ::Sector *to_release = g_loaded_hashes.begin()->second;
#ifdef DEBUG
            LOG("Releasing hash: %s\n", to_release->id.to_string().c_str());
#endif
            to_release->release_hash();
            g_loaded_hashes.erase(g_loaded_hashes.begin());
            g_loaded_hashes_inv.erase(to_release);
        }

        // load new one
#ifdef DEBUG
        LOG("Loading hash: %s\n", s->id.to_string().c_str());
#endif
        s->allocate_hash();
    } else {
        // update access time
        g_loaded_hashes.erase(std::make_pair(g_loaded_hashes_inv[tmp], tmp));
    }
    g_loaded_hashes.insert(std::make_pair(g_loaded_hash_timestamp, tmp));
    // s doesn't work here, which is probably a compiler bug!
    g_loaded_hashes_inv[tmp] = g_loaded_hash_timestamp;

    g_loaded_hash_timestamp++;

    if (!s->hash) {
        LOG("Error: hash not initialized for sector %s\n",
            s->id.to_string().c_str());
        return std::make_pair(-1,
                              Wrappers::gui_eval_elem2(eval_elem2(val()), s));
    }

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
