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

#ifndef EVAL_ELEM_H_INCLUDED
#define EVAL_ELEM_H_INCLUDED

#include "common.h"

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
    eval_elem(cas c, int x);
    bool operator==(const eval_elem &o) const;
    eval_elem(const eval_elem_sym &o);
    eval_elem(const eval_elem2 &o);
};

class Sector;

struct eval_elem2
{
    // azert nem lehet val, mert az nem tarolhat countot (a ctoranak az assertje
    // szerint)
    sec_val key1;
    int key2;

    enum Cas { Val, Count };

    eval_elem2(val v);
    eval_elem2(int c);
    eval_elem2(eval_elem ee);
    eval_elem2(sec_val key1, int key2)
        : key1 {key1}
        , key2 {key2}
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
    // azert nem lehet val, mert az nem tarolhat countot (a ctoranak az assertje
    // szerint)
    sec_val key1;
    int key2;

    enum Cas { Val, Count, Sym };

    eval_elem_sym2(val v);
    eval_elem_sym2(int c);
    static eval_elem_sym2 make_sym(int s);
    eval_elem_sym2(eval_elem_sym ee);
    eval_elem_sym2(sec_val key1, int key2);

    val value() const;
    int count() const;
    int sym() const;
    Cas cas() const;

    bool operator==(const eval_elem_sym2 &o) const;
    eval_elem_sym2(const eval_elem2 &o);

#ifdef DD
    static const field2_t spec_field2 = -1 << (field2_size - 1);
    static const field2_t max_field2 = -(spec_field2 + 1);
#endif
};

#endif // EVAL_ELEM_H_INCLUDED
