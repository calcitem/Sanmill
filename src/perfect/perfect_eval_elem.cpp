// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_eval_elem.cpp

#include "perfect_eval_elem.h"
#include "perfect_common.h"

#include <cassert>

eval_elem_sym::eval_elem_sym(cas the_c, int the_x)
    : c(the_c)
    , x(the_x)
{ }
bool eval_elem_sym::operator==(const eval_elem_sym &o) const
{
    return c == o.c && x == o.x;
}
eval_elem_sym::eval_elem_sym(const eval_elem &o)
    : c((cas)o.c)
    , x(o.x)
{ }

eval_elem::eval_elem(cas the_c, int the_x)
    : c(the_c)
    , x(the_x)
{ }
bool eval_elem::operator==(const eval_elem &o) const
{
    return c == o.c && x == o.x;
}
eval_elem::eval_elem(const eval_elem_sym &o)
    : c((cas)o.c)
    , x(o.x)
{
    assert(o.c != eval_elem_sym::sym);
}

eval_elem_sym::eval_elem_sym(const eval_elem_sym2 &o)
{
    if (o.cas() == eval_elem_sym2::Val) {
        assert(abs(o.value().key1) == 1);
        assert(o.value().key2 >= 0);
        assert((o.value().key2 & 1) == (o.value().key1 < 0 ? 0 : 1));
        c = val;
        x = o.value().key2;
    } else if (o.cas() == eval_elem_sym2::Count) {
        c = count;
        x = o.count();
    } else { // sym
        c = sym;
        x = o.sym();
    }
}

eval_elem::eval_elem(const eval_elem2 &o)
{
    if (o.cas() == eval_elem2::Val) {
        assert(abs(o.value().key1) == 1);
        assert(o.value().key2 >= 0);
        assert((o.value().key2 & 1) == (o.value().key1 < 0 ? 0 : 1));
        c = val;
        x = o.value().key2;
    } else { // count
        c = count;
        x = o.count();
    }
}

eval_elem2::eval_elem2(val v)
    : key1(v.key1)
    , key2(v.key2)
{ }
eval_elem2::eval_elem2(int c)
    : key1(0)
    , key2(c)
{ }

val eval_elem2::value() const
{
    assert(cas() == Val);
    return val {key1, key2};
}

int eval_elem2::count() const
{
    assert(cas() == Count);
    return key2;
}

eval_elem2::Cas eval_elem2::cas() const
{
    return key1 ? Val : Count;
}

eval_elem2::eval_elem2(eval_elem ee)
{
    if (ee.c == eval_elem::val) {
        key1 = ee.x & 1 ? 1 : -1;
        key2 = ee.x;
    } else {
        key1 = 0;
        key2 = ee.x;
    }
}

bool eval_elem2::operator==(const eval_elem2 &o) const
{
    return *this <= o && *this >= o;
}
bool eval_elem2::operator!=(const eval_elem2 &o) const
{
    return !(*this == o);
}

eval_elem_sym2::eval_elem_sym2(val v)
    : key1(v.key1)
    , key2(v.key2)
{ }
eval_elem_sym2::eval_elem_sym2(int c)
    : key1(0)
    , key2(c)
{ }
eval_elem_sym2::eval_elem_sym2(sec_val key_1, int key_2)
    : key1 {key_1}
    , key2 {key_2}
{ }

eval_elem_sym2 eval_elem_sym2::make_sym(int s)
{
    return eval_elem_sym2(-s - 1);
}

val eval_elem_sym2::value() const
{
    assert(cas() == Val);
    return val {key1, key2};
}

int eval_elem_sym2::count() const
{
    assert(cas() == Count);
    return key2;
}

int eval_elem_sym2::sym() const
{
    assert(cas() == Sym);
    return -(key2 + 1);
}

eval_elem_sym2::Cas eval_elem_sym2::cas() const
{
    return key1 ? Val : (key2 >= 0 ? Count : Sym);
}

eval_elem_sym2::eval_elem_sym2(eval_elem_sym ees)
{
    if (ees.c == eval_elem_sym::val) {
        key1 = ees.x & 1 ? 1 : -1;
        key2 = ees.x;
    } else if (ees.c == eval_elem_sym::count) {
        key1 = 0;
        key2 = ees.x;
    } else {
        key1 = 0;
        key2 = -ees.x - 1;
    }
}

bool eval_elem_sym2::operator==(const eval_elem_sym2 &o) const
{
    return key1 == o.key1 && key2 == o.key2;
}

eval_elem2::eval_elem2(const eval_elem_sym2 &o)
    : key1(o.key1)
    , key2(o.key2)
{
    assert(o.cas() != eval_elem_sym2::Sym);
}

eval_elem_sym2::eval_elem_sym2(const eval_elem2 &o)
    : key1(o.key1)
    , key2(o.key2)
{ }

eval_elem2 eval_elem2::corr(int corr)
{
    sec_val new_key1 = static_cast<int16_t>(key1 + corr);

    // magic, don't touch!
    return eval_elem2 {new_key1, sign((long long)new_key1 * key1) * key2};
}

bool eval_elem2::operator<(const eval_elem2 &b) const
{
    auto &a = *this;
    if (a.key1 != b.key1)
        return a.key1 < b.key1;
    else if (a.key1 < 0)
        return a.key2 < b.key2;
    else if (a.key1 > 0)
        return a.key2 > b.key2;
    else
        return false;
}
bool eval_elem2::operator>(const eval_elem2 &b) const
{
    auto &a = *this;
    return b < a;
}
bool eval_elem2::operator<=(const eval_elem2 &b) const
{
    auto &a = *this;
    return !(a > b);
}
bool eval_elem2::operator>=(const eval_elem2 &b) const
{
    auto &a = *this;
    return !(a < b);
}
