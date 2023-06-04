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

#ifndef WRAPPER_H_INCLUDED
#define WRAPPER_H_INCLUDED

#include "common.h"
#include "hash.h"
#include "symmetries.h"
#include "debug.h"
#include "sector.h"
#include "sector_graph.h"

#include <cassert>
#include <cmath> // for factorial function
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

using namespace std;

namespace Wrappers {

class WSector;

extern unordered_map<id, int> sector_sizes;
static int f_inv_count[] {1,     4,     30,    158,    757,    2830,  8774,
                          22188, 46879, 82880, 124124, 157668, 170854};

struct WID
{
    int W, B, WF, BF;
    WID(int W, int B, int WF, int BF)
        : W(W)
        , B(B)
        , WF(WF)
        , BF(BF)
    { }
    WID(id id)
        : W(id.W)
        , B(id.B)
        , WF(id.WF)
        , BF(id.BF)
    { }
    ::id tonat() { return ::id(W, B, WF, BF); }
    void negate();
    WID operator-(WID s);

    string ToString() { return this->tonat().to_string(); }

    int GetHashCode() { return (W << 0) | (B << 4) | (WF << 8) | (BF << 12); }

private:
    static int64_t factorial(int n)
    {
        if (n == 0)
            return 1;
        else
            return n * factorial(n - 1);
    }

    static int64_t nCr(int n, int r)
    {
        return factorial(n) / (factorial(r) * factorial(n - r));
    }

public:
    int size()
    {
        auto tn = tonat();
        if (sector_sizes.count(tn) == 0) {
            sector_sizes[tn] = static_cast<int>(nCr(24 - W, B)) *
                               f_inv_count[W];
        }
        return sector_sizes[tn];
    }

    bool operator==(const WID &other) const
    {
        return W == other.W && B == other.B && WF == other.WF && BF == other.BF;
    }

    bool operator<(const WID &other) const
    {
        return std::tie(W, B, WF, BF) <
               std::tie(other.W, other.B, other.WF, other.BF);
    }
};

struct eval_elem
{
    enum class cas { val, count, sym };
    cas c;
    int x;

    eval_elem(cas c, int x)
        : c(c)
        , x(x)
    { }
    eval_elem(::eval_elem e)
        : c(static_cast<cas>(e.c))
        , x(e.x)
    { }
};

struct gui_eval_elem2;

class WSector
{
public:
    ::Sector *s;
    WSector(WID id)
        : s(new ::Sector(id.tonat()))
    { }

    std::pair<int, Wrappers::gui_eval_elem2> hash(board a);

    sec_val sval() { return s->sval; }
};

struct gui_eval_elem2
{
private:
    // azert nem lehet val, mert az nem tarolhat countot (a ctoranak az assertje
    // szerint)
    sec_val key1;
    int key2;
    ::Sector *s; // ez akkor null, ha virtualis nyeres/vesztes vagy KLE

    enum class Cas { Val, Count };

    eval_elem2 to_eval_elem2() const { return eval_elem2 {key1, key2}; }

public:
    // A key1 nezopontja az s. Viszont ha az s null, akkor meg a
    // virt_unique_sec_val.
    gui_eval_elem2(sec_val key1, int key2, Sector *s)
        : key1 {key1}
        , key2 {key2}
        , s {s}
    { }
    gui_eval_elem2(::eval_elem2 e, ::Sector *s)
        : gui_eval_elem2 {e.key1, e.key2, s}
    { }

    gui_eval_elem2 undo_negate(WSector *s)
    {
        auto a = this->to_eval_elem2().corr(
            (s ? s->sval() : virt_unique_sec_val()) +
            (this->s ? this->s->sval : virt_unique_sec_val()));
        a.key1 *= -1;
        if (s) // ha s null, akkor KLE-be negalunk
            a.key2++;
        return gui_eval_elem2(a, s ? s->s : nullptr);
    }

    inline static const bool ignore_DD = false;

private:
    static sec_val abs_min_value()
    {
        assert(::virt_loss_val != 0);
        return ::virt_loss_val - 2;
    }
    static void drop_DD(eval_elem2 &e)
    {
        // absolute viewpoint
        assert(e.key1 >= abs_min_value());
        assert(e.key1 <= ::virt_win_val);
        assert(e.key1 != ::virt_loss_val - 1); // kiszedheto
        if (e.key1 != virt_win_val && e.key1 != ::virt_loss_val &&
            e.key1 != abs_min_value())
            e.key1 = 0;
    }

public:
    int compare(const gui_eval_elem2 &o) const
    {
        assert(s == o.s);
        if (!ignore_DD) {
            if (key1 != o.key1)
                return key1 < o.key1 ? -1 : 1;
            else if (key1 < 0)
                return key2 < o.key2 ? -1 : 1;
            else if (key1 > 0)
                return key2 > o.key2 ? -1 : 1;
            else
                return 0;
        } else {
            auto a1 = to_eval_elem2().corr(s ? s->sval : virt_unique_sec_val());
            auto a2 = o.to_eval_elem2().corr(o.s ? o.s->sval :
                                                   virt_unique_sec_val());
            drop_DD(a1);
            drop_DD(a2);
            if (a1.key1 != a2.key1)
                return a1.key1 < a2.key1 ? -1 : 1;
            else if (a1.key1 < 0)
                return a1.key2 < a2.key2 ? -1 : 1;
            else if (a1.key1 > 0)
                return a2.key2 < a1.key2 ? -1 : 1;
            else
                return 0;
        }
    }

    bool operator<(const gui_eval_elem2 &b) const
    {
        return this->compare(b) < 0;
    }
    bool operator>(const gui_eval_elem2 &b) const
    {
        return this->compare(b) > 0;
    }
    bool operator==(const gui_eval_elem2 &b) const
    {
        return this->compare(b) == 0;
    }

    static gui_eval_elem2 min_value(WSector *s)
    {
        return gui_eval_elem2 {
            static_cast<sec_val>(abs_min_value() -
                                 (s ? s->sval() : virt_unique_sec_val())),
            0, s ? s->s : nullptr};
    }

    static gui_eval_elem2 virt_loss_val()
    { // vigyazat: csak KLE-ben mukodik jol, mert ugye ahhoz, hogy jol mukodjon,
      // valami ertelmeset kene kivonni, de mi mindig virt_unique_sec_val-t
      // vonunk ki
        assert(::virt_loss_val);
        return gui_eval_elem2 {
            static_cast<sec_val>(::virt_loss_val - virt_unique_sec_val()), 0,
            nullptr};
    }

    static sec_val virt_unique_sec_val()
    { // azert kell, hogy a KLE-s allasokban ne resetelodjon a tavolsag
        assert(::virt_loss_val);
#ifdef DD
        return ::virt_loss_val - 1;
#else
        return 0;
#endif
    }

    sec_val akey1()
    {
        return key1 + (s ? s->sval : virt_unique_sec_val());
    }

    std::string toString()
    {
        assert(::virt_loss_val);
        assert(::virt_win_val);
        std::string s1, s2;

        sec_val akey1 = this->akey1();
        s1 = sec_val_to_sec_name(akey1);

        if (key1 == 0)
#ifdef DD
            s2 = "C"; // az akey2 itt mindig 0
#else
            s2 = "";
#endif
        else
            s2 = std::to_string(key2);

#ifdef DD
        return s1 + ", (" + std::to_string(key1) + ", " + s2 + ")";
#else
        return s1 + s2;
#endif
    }
};

class Nwu
{
public:
    static std::vector<WID> WuIds;
    static void initWuGraph()
    {
        init_sector_graph();
        WuIds = std::vector<WID>();
        for (auto it = wu_ids.begin(); it != wu_ids.end(); ++it)
            WuIds.push_back(WID(*it));
    }
    static std::vector<WID> wuGraphT(WID u)
    {
        auto r = std::vector<WID>();
        wu *w = wus[u.tonat()];
        for (auto it = w->parents.begin(); it != w->parents.end(); ++it)
            r.push_back(WID((*it)->id));
        return r;
    }
    static bool twine(WID w) { return wus[w.tonat()]->twine; }
};

class Init
{
public:
    static void init_sym_lookuptables() { ::init_sym_lookuptables(); }
    static void init_sec_vals() { ::init_sec_vals(); }
};

class Constants
{
public:
    static const int variant = VARIANT;
    inline static const std::string fname_suffix = FNAME_SUFFIX;
    const std::string movegenFname = movegen_file;

    enum class Variants { std = STANDARD, mora = MORABARABA, lask = LASKER };

#ifdef DD
    static const bool dd = true;
#else
    static const bool dd = false;
#endif

    static const bool FBD = FULL_BOARD_IS_DRAW;

#ifdef FULL_SECTOR_GRAPH
    static const bool extended = true;
#else
    static const bool extended = false;
#endif
};

class Helpers
{
public:
    static std::string toclp(board a) { return ::toclp(a); }
};
} // namespace Wrappers

#endif // WRAPPER_H_INCLUDED
