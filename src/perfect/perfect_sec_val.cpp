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

// perfect_sec_val.cpp

#include "perfect_sec_val.h"

#include <cassert>

// Be careful: In the case of STONE_DIFF,
// there are also sectors that do not exist at all.
std::map<Id, sec_val> sec_vals;

#ifndef STONE_DIFF
std::map<sec_val, Id> inv_sec_vals;
#endif
sec_val virt_loss_val = 0, virt_win_val = 0;

void init_sec_vals()
{
#ifdef DD
#ifndef STONE_DIFF
    FILE *f = nullptr;
#ifdef _WIN32
    secValFileName = secValPath + "\\" + (std::string)ruleVariantName +
                     ".secval";
#else
    secValFileName = secValPath + "/" + (std::string)ruleVariantName +
                     ".secval";
#endif
    if (FOPEN(&f, secValFileName.c_str(), "rt") != 0) {
        fail_with(ruleVariantName + ".secval file not found.");
        return;
    }
    FSCANF(f, "virt_loss_val: %hd\nvirt_win_val: %hd\n", &virt_loss_val,
           &virt_win_val);
    assert(virt_win_val == -virt_loss_val);
    int n;
    FSCANF(f, "%d\n", &n);
    for (int i = 0; i < n; i++) {
        int w, b, whiteFree, blackFree;
        int16_t v;
        FSCANF(f, "%d %d %d %d  %hd\n", &w, &b, &whiteFree, &blackFree, &v);
        sec_vals[Id(w, b, whiteFree, blackFree)] = v;
    }
    fclose(f);
#else
    for (int W = 0; W <= maxKsz; W++) {
        for (int WF = 0; WF <= maxKsz; WF++) {
            for (int B = 0; B <= maxKsz; B++) {
                for (int BF = 0; BF <= maxKsz; BF++) {
                    Id s = Id {W, WF, B, BF};
                    sec_vals[s] = s.W + s.WF - s.B - s.BF;
                }
            }
        }
    }
    virt_win_val = maxKsz + 1;
    virt_loss_val = -maxKsz - 1;
#endif
    // It is needed for two reasons: one is for correction, and the other is to
    // subtract one from it at the value of the kle sectors in gui_eval_elem2
    // (the -5 is just for safety, maybe -1 would be enough)
    assert(2 * virt_loss_val - 5 > secValMinValue);
#else
    virt_loss_val = -1;
    virt_win_val = 1;
#endif

#ifndef STONE_DIFF
    for (const auto &sv : sec_vals) {
        if (sv.second) { // not NTREKS if DD  (if not DD, then only the virt
                         // sectors (which btw don't get here) are non-0)
            assert(!inv_sec_vals.count(sv.second)); // non-NTREKS sec_vals
                                                    // should be unique
            inv_sec_vals[sv.second] = Id(sv.first);
        }
    }
#endif

#ifdef HAS_SECTOR_GRAPH
    for (auto s : sector_list) {
        assert(sec_vals.count(s)); // every sector has a value
        auto xx = sec_vals[s];
        assert(s.transient() || sec_vals[s] == -sec_vals[-s]); // wus are
                                                               // zero-sum
    }
#endif
}

std::string sec_val_to_sec_name(sec_val v)
{
    if (v == 0)
#ifdef DD
#ifdef STONE_DIFF
        return "0";
#else
        return "NTESC";
#endif
#else
        return "D";
#endif
    else if (v == virt_loss_val)
        return "L";
    else if (v == virt_win_val)
        return "W";
    else {
#ifdef STONE_DIFF
        return to_string(v);
#else
        assert(inv_sec_vals.count(v));
        return std::to_string(v) + " (" + inv_sec_vals[v].to_string() + ")";
#endif
    }
}
