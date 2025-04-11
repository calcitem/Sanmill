// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_wrappers.h

#ifndef PERFECT_WRAPPER_H_INCLUDED
#define PERFECT_WRAPPER_H_INCLUDED

#include "rule.h"

#include "perfect_common.h"
#include "perfect_debug.h"
#include "perfect_hash.h"
#include "perfect_sector.h"
#include "perfect_sector_graph.h"
#include "perfect_symmetries.h"

#include <cassert>
#include <cmath> // for factorial function
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

namespace Wrappers {

class WSector;

extern std::unordered_map<Id, int> sector_sizes;

struct WID
{
    int W, B, WF, BF;
    WID(int w, int b, int whiteFree, int blackFree)
        : W(w)
        , B(b)
        , WF(whiteFree)
        , BF(blackFree)
    { }
    WID(Id Id)
        : W(Id.W)
        , B(Id.B)
        , WF(Id.WF)
        , BF(Id.BF)
    { }
    ::Id tonat() { return ::Id(W, B, WF, BF); }
    void negate_id();
    WID operator-(WID s);

    std::string ToString() { return this->tonat().to_string(); }

    int GetHashCode() { return (W << 0) | (B << 4) | (WF << 8) | (BF << 12); }

public:
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

    eval_elem(cas the_c, int the_x)
        : c(the_c)
        , x(the_x)
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
    WSector(WID Id)
        : s(new ::Sector(Id.tonat()))
    { }

    std::pair<int, Wrappers::gui_eval_elem2> hash(board a);

    sec_val sval() { return s->sval; }
};

struct gui_eval_elem2
{
private:
    // could not be simply val instead of sec_val, because val cannot contain
    // a count (as asserted by the ctor)
    sec_val key1;
    int key2;
    ::Sector *s; // this is zero if there is a virtual win/loss or KLE

    enum class Cas { Val, Count };

    eval_elem2 to_eval_elem2() const { return eval_elem2 {key1, key2}; }

public:
    // The viewpoint of key1 is s. However, if s is null, then
    // virt_unique_sec_val.
    gui_eval_elem2(sec_val key_1, int key_2, Sector *sec)
        : key1 {key_1}
        , key2 {key_2}
        , s {sec}
    { }
    gui_eval_elem2(::eval_elem2 e, ::Sector *sec)
        : gui_eval_elem2 {e.key1, e.key2, sec}
    { }

    gui_eval_elem2 undo_negate(WSector *sector)
    {
        auto a = this->to_eval_elem2().corr(
            (sector ? sector->sval() : virt_unique_sec_val()) +
            (this->s ? this->s->sval : virt_unique_sec_val()));
        a.key1 *= -1;
        if (sector) // if sector is null, we go to KLE
            a.key2++;
        return gui_eval_elem2(a, sector ? sector->s : nullptr);
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
        assert(e.key1 != ::virt_loss_val - 1); // You can take it out
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
                return key2 == o.key2 ? 0 : (key2 < o.key2 ? -1 : 1);
            else if (key1 > 0)
                return key2 == o.key2 ? 0 : (key2 > o.key2 ? -1 : 1);
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
                return a1.key2 == a2.key2 ? 0 : (a1.key2 < a2.key2 ? -1 : 1);
            else if (a1.key1 > 0)
                // TODO: Right?
                return a2.key2 == a1.key2 ? 0 : (a2.key2 < a1.key2 ? -1 : 1);
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
    {
        // Attention: it works well only in KLE because, in order to work
        // correctly, something meaningful should be subtracted, but we always
        // subtract virt_unique_sec_val from it.
        assert(::virt_loss_val);
        return gui_eval_elem2 {
            static_cast<sec_val>(::virt_loss_val - virt_unique_sec_val()), 0,
            nullptr};
    }

    static sec_val virt_unique_sec_val()
    {
        // It is necessary so that the distance is not reset in KLE positions.
        assert(::virt_loss_val);
#ifdef DD
        return ::virt_loss_val - 1;
#else
        return 0;
#endif
    }

    sec_val akey1() { return key1 + (s ? s->sval : virt_unique_sec_val()); }

    std::string to_string()
    {
        assert(::virt_loss_val);
        assert(::virt_win_val);
        std::string s1, s2;

        sec_val akey1 = this->akey1();
        s1 = sec_val_to_sec_name(akey1);

        if (key1 == 0)
#ifdef DD
            s2 = "C"; // The value of akey2 is always 0 here.
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
    static void initialize_wu_graph()
    {
        init_sector_graph();
        WuIds = std::vector<WID>();
        for (auto it = wu_ids.begin(); it != wu_ids.end(); ++it)
            WuIds.push_back(WID(*it));
    }
    static std::vector<WID> get_wu_graph_t(WID u)
    {
        auto r = std::vector<WID>();
        wu *w = wus[u.tonat()];
        for (auto it = w->parents.begin(); it != w->parents.end(); ++it)
            r.push_back(WID((*it)->id));
        return r;
    }
    static bool is_twine(WID w) { return wus[w.tonat()]->is_twine; }
};

class Init
{
public:
    static void init_symmetry_lookup_tables()
    {
        ::init_symmetry_lookup_tables();
    }
    static void init_sec_vals() { ::init_sec_vals(); }
};

class Constants
{
public:
    inline static const std::string fname_suffix = FNAME_SUFFIX;
    const std::string movegenFname = movegenFile;

    enum class Variants { std = STANDARD, mora = MORABARABA, lask = LASKER };

#ifdef DD
    static const bool dd = true;
#else
    static const bool dd = false;
#endif

#ifdef FULL_SECTOR_GRAPH
    static const bool extended = true;
#else
    static const bool extended = false;
#endif
};

class Helpers
{
public:
    static std::string to_clp(board a) { return ::to_clp(a); }
};
} // namespace Wrappers

#endif // PERFECT_WRAPPER_H_INCLUDED
