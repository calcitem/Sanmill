// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_common.h

#ifndef PERFECT_COMMON_H_INCLUDED
#define PERFECT_COMMON_H_INCLUDED

#include "perfect_platform.h"

#include <cassert>
#include <sstream>
#include <tuple>

#define STANDARD 1
#define MORABARABA 2
#define LASKER 3

extern int ruleVariant;

//-------------------------------------
// Settings:

// #define FULL_SECTOR_GRAPH //extended solution //comment or uncomment

#define DD // distinguish draws (ultra) //comment or uncomment

// #define STONE_DIFF //value of sectors is the stone difference (otherwise, get
//  values from the .secval file) //comment or uncomment

//-------------------------------------

#ifdef STONE_DIFF
#ifndef DD
static_assert(false, "");
#endif
#endif

#ifdef DD
#ifdef FULL_SECTOR_GRAPH
static_assert(false, "sec_val range");
#endif
#endif

#ifdef DD
#ifndef STONE_DIFF
// byte
const int eval_struct_size = 3;
extern int field2Offset;
extern int field1Size;
extern int field2Size;
#else
// byte
const int eval_struct_size = 2;
// bit
const int field2Offset = 6;
#endif
using field2_t = int16_t;
#endif

#ifdef STONE_DIFF
const char stone_diff_flag = 1;
#else
const char stone_diff_flag = 0;
#endif

#ifdef DD
#define FNAME_SUFFIX "2"
#else
#define FNAME_SUFFIX ""
#endif

using sec_val = int16_t;

#ifdef DD
extern sec_val secValMinValue;
#endif

#ifndef DD
// val, spec, sym, count (forditva)
// a 256 ertekbol lefoglalunk 1-et a specnek, 1-et a val0-nak, 1-et a count0-nak
// (ezert 253-...)
#define MAX_VAL 178
#define MAX_COUNT (253 - MAX_VAL - 15) /*60*/
#define SPEC (MAX_VAL + 1)
#endif

const int version = 2;

extern std::string ruleVariantName;

extern std::string secValPath;
extern std::string secValFileName;

// This file is created by the solver
// with the -writemovegenlookups switch.
// The Controller automatically makes
// this, if the file doesn't exist.
const std::string movegenFile = (std::string) "C:\\malom_data_aux\\" +
                                ruleVariantName + ".movegen";

typedef int64_t board;

// azert nem lehet int, mert van olyan
// hasznalata, hogy pl. mask24<<cps (amugy
// ez sehol sem lassit valszeg)
const board mask24 = (1 << 24) - 1;

enum modes { uninit = -1, solution_mode, verification_mode, analyze_mode };
extern modes mode;

#define DANNER 0

#if DANNER
#define __popcnt manual_popcnt::do_it
struct manual_popcnt
{
    static unsigned int do_it(unsigned int x)
    {
        unsigned int r = 0;
        for (int i = 0; i < 32; i++)
            r += 1 & (x >> i);
        return r;
    }
};
#endif

#if DANNER
#pragma message("Warning : Compiled in Danner mode! (conversion warnings)")
#endif

#if __cplusplus
#define WRAPPER
#endif

// #define STATISTICS

#ifdef STATISTICS
#ifdef DD
#pragma message("Warning : STATISTICS and DD are both defined!")
#endif
#endif

// You must not store count in it
struct val
{
    sec_val key1 {0};
    int key2 {0};

    val() { }
    val(sec_val key_1, int key_2)
        : key1(key_1)
        , key2(key_2)
    {
        assert(key1); /* nem count */
    }

    bool operator==(const val &o) const
    {
        return key1 == o.key1 && key2 == o.key2;
    }

    // We correct towards directions depending on the sign of key2.
    std::tuple<sec_val, int> tr() const
    {
        return std::make_tuple(static_cast<sec_val>(-abs(key1)), key2);
    }

    bool operator<(const val &o) const { return tr() < o.tr(); }
    bool operator<=(const val &o) const { return tr() <= o.tr(); }
    bool operator>(const val &o) const { return tr() > o.tr(); }
    bool operator>=(const val &o) const { return tr() >= o.tr(); }

    val undo_negate() { return val(-key1, key2 + 1); }
};

struct Id
{
    int W {0};
    int B {0};
    int WF {0};
    int BF {0};

    Id(int whitePlayer, int blackPlayer, int whiteFree, int blackFree)
        : W(whitePlayer)
        , B(blackPlayer)
        , WF(whiteFree)
        , BF(blackFree)
    { }

    Id() { }

    static Id null() { return Id {-1, -1, -1, -1}; }

    void negate_id()
    {
        std::swap(W, B);
        std::swap(WF, BF);
    }

    Id operator-() const
    {
        Id r = *this;
        r.negate_id();
        return r;
    }

    bool eks() const { return *this == -*this; }

    bool transient() const
    {
        if (ruleVariant == STANDARD || ruleVariant == MORABARABA) {
            return !(WF == 0 && BF == 0);
        } else {
            return !(W != 0 && B != 0);
        }

        return false;
    }

    bool is_twine() const { return !eks() && !transient(); }

    std::string file_name()
    {
        char b[255];
        SPRINTF(b, sizeof(b), "%s_%d_%d_%d_%d.sec%s", ruleVariantName.c_str(),
                W, B, WF, BF, FNAME_SUFFIX);
        std::string r = std::string(b);
        return r;
    }

    bool operator<(const Id &o) const
    {
        return std::make_pair(std::make_pair(W, B), std::make_pair(WF, BF)) <
               std::make_pair(std::make_pair(o.W, o.B),
                              std::make_pair(o.WF, o.BF));
    }
    bool operator>(const Id &o) const
    {
        return std::make_pair(std::make_pair(W, B), std::make_pair(WF, BF)) >
               std::make_pair(std::make_pair(o.W, o.B),
                              std::make_pair(o.WF, o.BF));
    }

    bool operator==(const Id &o) const
    {
        return W == o.W && B == o.B && WF == o.WF && BF == o.BF;
    }
    bool operator!=(const Id &o) const { return !(*this == o); }

    std::string to_string()
    {
        char buf[255];
        SPRINTF(buf, sizeof(buf), "%s_%d_%d_%d_%d", ruleVariantName.c_str(), W,
                B, WF, BF);
        return std::string(buf);
    }
};

template <>
struct std::hash<Id>
{
    size_t operator()(const Id &k) const
    {
        return static_cast<size_t>(k.W) | (static_cast<size_t>(k.B) << 4) |
               (static_cast<size_t>(k.WF) << 8) |
               (static_cast<size_t>(k.BF) << 12);
    }
};

// this must be in the define path of WRAPPER
#include "perfect_log.h"

template <class T>
std::string tostring(T x)
{
    std::stringstream ss;
    ss << x;
    return ss.str();
}

template <class T>
int sign(T x)
{
    return x < 0 ? -1 : (x > 0 ? 1 : 0);
}

void fail_with(std::string s);

#endif // PERFECT_COMMON_H_INCLUDED
