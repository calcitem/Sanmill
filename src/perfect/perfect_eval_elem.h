// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_eval_elem.h

#ifndef PERFECT_EVAL_ELEM_H_INCLUDED
#define PERFECT_EVAL_ELEM_H_INCLUDED

#include "perfect_common.h"

struct eval_elem;
struct eval_elem_sym2;
struct eval_elem2;

struct eval_elem_sym
{
    enum cas { val, count, sym };
    cas c;
    int x;
    eval_elem_sym(cas c, int x);
    bool operator==(const eval_elem_sym &o) const;
    eval_elem_sym(const eval_elem &o);
    eval_elem_sym(const eval_elem_sym2 &o);
};

struct eval_elem
{
    enum cas { val, count };
    cas c;
    int x;
    eval_elem(cas the_c, int the_x);
    bool operator==(const eval_elem &o) const;
    eval_elem(const eval_elem_sym &o);
    eval_elem(const eval_elem2 &o);
};

class Sector;

struct eval_elem2
{
    // azert cannot be valid, because it cannot contain a count (as asserted by
    // the ctor)
    sec_val key1;
    int key2;

    enum Cas { Val, Count };

    eval_elem2(val v);
    eval_elem2(int c);
    eval_elem2(eval_elem ee);
    eval_elem2(sec_val key_1, int key_2)
        : key1 {key_1}
        , key2 {key_2}
    { }

    val value() const;
    int count() const;
    Cas cas() const;

private:
    bool operator==(const eval_elem2 &o) const;

public:
    bool operator!=(const eval_elem2 &o) const;
    eval_elem2(const eval_elem_sym2 &o);
    bool operator<(const eval_elem2 &b) const;
    bool operator>(const eval_elem2 &b) const;
    bool operator<=(const eval_elem2 &b) const;
    bool operator>=(const eval_elem2 &b) const;

    eval_elem2 corr(int corr);

    // static eval_elem2 min_value();
};

struct eval_elem_sym2
{
    // azert cannot be valid, because it cannot contain a count (as asserted by
    // the ctor)
    sec_val key1;
    int key2;

    enum Cas { Val, Count, Sym };

    eval_elem_sym2(val v);
    eval_elem_sym2(int c);
    static eval_elem_sym2 make_sym(int s);
    eval_elem_sym2(eval_elem_sym ee);
    eval_elem_sym2(sec_val key_1, int key_2);

    val value() const;
    int count() const;
    int sym() const;
    Cas cas() const;

    bool operator==(const eval_elem_sym2 &o) const;
    eval_elem_sym2(const eval_elem2 &o);
};

#endif // PERFECT_EVAL_ELEM_H_INCLUDED
