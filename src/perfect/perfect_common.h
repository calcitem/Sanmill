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

#ifndef PERFECT_COMMON_H_INCLUDED
#define PERFECT_COMMON_H_INCLUDED

#include "perfect_platform.h"

#include <cassert>

#define STANDARD 1
#define MORABARABA 2
#define LASKER 3

//-------------------------------------
// Settings:

#define RULE_VARIANT STANDARD // STANDARD, MORABARABA, or LASKER

#define FULL_BOARD_IS_DRAW 1 // 0 or 1

//#define FULL_SECTOR_GRAPH //extended solution //comment or uncomment

#define DD // distinguish draws (ultra) //comment or uncomment

//#define STONE_DIFF //value of sectors is the stone difference (otherwise, get
// values from the .secval file) //comment or uncomment

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
const int eval_struct_size = 3; // byte
#if RULE_VARIANT == STANDARD
const int field2_offset = 12; // bit
#else
const int field2_offset = 14; // bit
#endif
#else
const int eval_struct_size = 2; // byte
const int field2_offset = 6;    // bit
#endif
const int field1_size = field2_offset;
const int field2_size = 8 * eval_struct_size - field2_offset;
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
const sec_val sec_val_min_value = -(1 << (field1_size - 1));
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

#if RULE_VARIANT == STANDARD
#define VARIANT_NAME "std"
#define GRAPH_FUNC_NOTNEG std_mora_graph_func
#define MILL_POS_CNT 16
#ifndef FULL_SECTOR_GRAPH
const int max_ksz = 9;
#endif
#endif

#if RULE_VARIANT == LASKER
#define VARIANT_NAME "lask"
#define GRAPH_FUNC_NOTNEG lask_graph_func
#define MILL_POS_CNT 16
#ifndef FULL_SECTOR_GRAPH
const int max_ksz = 10;
#endif
#endif

#if RULE_VARIANT == MORABARABA
#define VARIANT_NAME "mora"
#define GRAPH_FUNC_NOTNEG std_mora_graph_func
#define MILL_POS_CNT 20
#ifndef FULL_SECTOR_GRAPH
const int max_ksz = 12;
#endif
#endif

#ifdef FULL_SECTOR_GRAPH
const int max_ksz = 12;
//#pragma message ("Warning: max_ksz leveve")
#endif

extern std::string sec_val_path;
extern std::string sec_val_fname;

// This file is created by the solver
// with the -writemovegenlookups switch.
// The Controller automatically makes
// this, if the file doesn't exist.
const std::string movegen_file = (std::string) "C:\\malom_data_aux\\" +
                                 VARIANT_NAME +
                            ".movegen";

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

//#define STATISTICS

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
    val(sec_val key1, int key2)
        : key1(key1)
        , key2(key2)
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

    bool operator<(const val &o) const
    {
        return tr() < o.tr();
    }
    bool operator<=(const val &o) const { return tr() <= o.tr(); }
    bool operator>(const val &o) const { return tr() > o.tr(); }
    bool operator>=(const val &o) const { return tr() >= o.tr(); }

    val undo_negate() { return val(-key1, key2 + 1); }
};

struct id
{
    int W {0};
    int B {0};
    int WF {0};
    int BF {0};

    id(int W, int B, int WF, int BF)
        : W(W)
        , B(B)
        , WF(WF)
        , BF(BF)
    { }

    id() { }

    static id null() { return id {-1, -1, -1, -1}; }

    void negate()
    {
        std::swap(W, B);
        std::swap(WF, BF);
    }

    id operator-() const
    {
        id r = *this;
        r.negate();
        return r;
    }

    bool eks() const { return *this == -*this; }

    bool transient() const
    {
#if RULE_VARIANT == STANDARD || RULE_VARIANT == MORABARABA
        return !(WF == 0 && BF == 0);
#else
        return !(W != 0 && B != 0);
#endif
    }

    bool twine() const
    {
        return !eks() && !transient();
    }

    std::string file_name()
    {
        char b[255];
        SPRINTF(b, sizeof(b), "%s_%d_%d_%d_%d.sec%s", VARIANT_NAME, W, B, WF,
                BF, FNAME_SUFFIX);
        std::string r = std::string(b);
        return r;
    }

    bool operator<(const id &o) const
    {
        return std::make_pair(std::make_pair(W, B), std::make_pair(WF, BF)) <
               std::make_pair(std::make_pair(o.W, o.B), std::make_pair(o.WF, o.BF));
    }
    bool operator>(const id &o) const
    {
        return std::make_pair(std::make_pair(W, B), std::make_pair(WF, BF)) >
               std::make_pair(std::make_pair(o.W, o.B), std::make_pair(o.WF, o.BF));
    }

    bool operator==(const id &o) const
    {
        return W == o.W && B == o.B && WF == o.WF && BF == o.BF;
    }
    bool operator!=(const id &o) const
    {
        return !(*this == o);
    }

    std::string to_string()
    {
        char buf[255];
        SPRINTF(buf, sizeof(buf), "%s_%d_%d_%d_%d", VARIANT_NAME, W, B, WF, BF);
        return std::string(buf);
    }
};

template <>
struct std::hash<id>
{
    size_t operator()(const id &k) const
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

void failwith(std::string s);

#endif // PERFECT_COMMON_H_INCLUDED
