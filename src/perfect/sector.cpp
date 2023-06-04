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

#include <chrono>
#include <cstdio>

#include "common.h"
#include "hash.h"
#include "sector.h"
#include "symmetries.h"

Sector *sectors[max_ksz + 1][max_ksz + 1][max_ksz + 1][max_ksz + 1];

vector<Sector *> sector_objs;

const int sbufsize = 1024 * 1024;
char sbuf[sbufsize]; // vigyazat

Sector::Sector(::id id)
    : W(id.W)
    , B(id.B)
    , WF(id.WF)
    , BF(id.BF)
    , id(id)
    , max_val(-1)
    , max_count(-1)
    , hash(nullptr)
    ,
#ifdef DD
    sval((assert(sec_vals.count(id)), sec_vals[id]))
#else
    sval(0)
#endif
#ifndef WRAPPER
    , sid((char)sector_objs.size())
    , wms(-1)
#endif
#ifdef WRAPPER
,f(nullptr)
#endif
{
    sector_objs.push_back(this);

    strcpy_s(fname, id.file_name().c_str());
    LOG("Creating sector object for %s\n", fname);

#ifndef WRAPPER
    allocate_hash();
#endif
}

template <class T>
size_t fread1(T &x, FILE *f)
{
    return fread(&x, sizeof(x), 1, f);
}
template <class T>
size_t fwrite1(T &x, FILE *f)
{
    return fwrite(&x, sizeof(x), 1, f);
}
void Sector::read_header(FILE *f)
{
#ifdef DD
    int _version, _eval_struct_size, _field2_offset;
    char _stone_diff_flag;
    fread1(_version, f);
    fread1(_eval_struct_size, f);
    fread1(_field2_offset, f);
    fread1(_stone_diff_flag, f);
    REL_ASSERT(_version == version);
    REL_ASSERT(_eval_struct_size == eval_struct_size);
    REL_ASSERT(_field2_offset == field2_offset);
    REL_ASSERT(_stone_diff_flag == stone_diff_flag);
    fseek(f, header_size, SEEK_SET);
#endif
}
void Sector::write_header(FILE *f)
{
#ifdef DD
    fwrite1(version, f);
    fwrite1(eval_struct_size, f);
    fwrite1(field2_offset, f);
    fwrite1(stone_diff_flag, f);
    int ffu_size = header_size - ftell(f);
    char *dummy = new char[ffu_size];
    memset(dummy, 0, ffu_size);
    fwrite(dummy, 1, ffu_size, f);
    delete[] dummy;
#endif
}

void Sector::read_em_set(FILE *f)
{
    auto start = std::chrono::steady_clock::now(); // Record the start time
    auto last_update = std::chrono::steady_clock::now(); // Record the last
                                                         // update time

    int em_set_size = 0;
    fread(&em_set_size, 4, 1, f);
    for (int i = 0; i < em_set_size; i++) {
        int e[2];
        fread(e, 4, 2, f);
        em_set[e[0]] = e[1];

        auto now = std::chrono::steady_clock::now();
        auto time_since_last_update =
            std::chrono::duration_cast<std::chrono::seconds>(now - last_update)
                .count();

        // Only update the console every second
        if (time_since_last_update >= 1) {
            // Calculate memory usage
            float memoryUsageMB = ((i + 1) * 8.0f) / (1024 * 1024); // MB

            // Calculate elapsed time
            auto elapsed_seconds =
                std::chrono::duration_cast<std::chrono::seconds>(now - start)
                    .count();
            int hours = elapsed_seconds / 3600;
            int minutes = (elapsed_seconds % 3600) / 60;
            int seconds = elapsed_seconds % 60;

            // Calculate remaining time
            int remaining_iterations = em_set_size - (i + 1);
            auto avg_seconds_per_iteration = elapsed_seconds / (float)(i + 1);
            auto remaining_seconds = remaining_iterations *
                                     avg_seconds_per_iteration;
            int remaining_hours = remaining_seconds / 3600;
            int remaining_minutes = ((unsigned int)remaining_seconds % 3600) /
                                    60;
            int remaining_secs = (unsigned int)remaining_seconds % 60;

            if (memoryUsageMB < 1024) {
                printf("\rProgress: %.2f%%, Memory Usage: %.2fMB, Elapsed "
                       "time: %02d:%02d:%02d, Remaining time: %02d:%02d:%02d",
                       ((float)(i + 1) / em_set_size) * 100, memoryUsageMB,
                       hours, minutes, seconds, remaining_hours,
                       remaining_minutes, remaining_secs);
            } else {
                printf("\rProgress: %.2f%%, Memory Usage: %.2fGB, Elapsed "
                       "time: %02d:%02d:%02d, Remaining time: %02d:%02d:%02d",
                       ((float)(i + 1) / em_set_size) * 100,
                       memoryUsageMB / 1024, hours, minutes, seconds,
                       remaining_hours, remaining_minutes, remaining_secs);
            }

            fflush(stdout); // Flush the output buffer to immediately update the
                            // output

            last_update = now;
        }
    }
    printf("\n"); // Print a new line after the loop ends to avoid subsequent
                  // outputs on the same line
}

#ifndef WRAPPER

void Sector::allocate(bool doinit, ::id parent)
{
    LOG("Allocating sector  %s  ", fname);

    eval = new unsigned char[eval_size];
    memset(eval, 0, eval_size);

    FILE *f;
    errno_t r = fopen_s(&f, fname, "rb");
    file_existed = !r;

    if (doinit) {
        if (file_existed) {
            LOG("Deleting existing file,  ");
            fclose(f);
            remove(fname);
        }

        init();
    } else {
        if (!file_existed) {
            LOG("!!! Fatal error: Sector not found: %s\n", fname);
            system("pause");
            exit(2);
        }

        LOG("Reading from file");

        setvbuf(f, sbuf, _IOFBF, sbufsize);
        read_header(f);
        fread(eval, 1, eval_size, f);
        read_em_set(f);
        fclose(f);

        if (parent != id::null()) {
            //(nem a wrapperben vagyunk, mert az mashol olvas be)
            // assert(mode != analyze_mode); //we don't get here in analyze
            // mode, because we only read one sector
            LOG(", Corrections");
            int cor = sval + sectors(parent)->sval;
            for (int i = 0; i < hash->hash_count; i++) {
                auto x = get_eval_inner(i);
                if (x.cas() != eval_elem_sym2::Sym)
                    set_eval(i, ((eval_elem2)x).corr(cor));
            }
        }
    }

    LOG(".\n");
}

void Sector::release()
{
    LOG("Releasing sector  %s\n", fname);
    delete[] eval;
    em_set.clear();
}

void Sector::save()
{
    LOG("Saving %s...\n", fname);

#if _DEBUG
    check_consis();
#endif

    FILE *f;
    char new_fname[255];
    strcpy_s(new_fname, fname);
    strcat_s(new_fname, ".saving");
    errno_t r = fopen_s(&f, new_fname, "wb");
    if (r) {
        printf("!!! Unable to open or create the file !!!");
        system("PAUSE");
        return;
    }

    setvbuf(f, sbuf, _IOFBF, sbufsize);

    write_header(f);
    fwrite(eval, 1, eval_size, f);

    int em_set_size = (int)(em_set.size());
    fwrite(&em_set_size, 4, 1, f);
    for (auto it = em_set.begin(); it != em_set.end(); it++) {
        int e[] = {it->first, it->second};
        fwrite(e, 4, 2, f);
    }
    fclose(f);

    rename(new_fname, fname);

    LOG("%s saved\n", fname);
}

void Sector::check_consis()
{
    LOG("Checking consistency\n");

    // nincs sym
    for (int h = 0; h < hash->hash_count; h++) {
        auto ih = hash->inv_hash(h);
        auto h2 = hash->hash(ih);
        assert(h2.second.cas() != eval_elem_sym2::Sym);
    }

    LOG("Consistency ok\n");
}

#endif

#ifdef DD
eval_elem2 Sector::get_eval(int i)
{
    return (eval_elem2)(get_eval_inner(i));
}

eval_elem_sym2 Sector::get_eval_inner(int i)
{
    pair<sec_val, field2_t> resi = extract(i);
    if (resi.second == eval_elem_sym2::spec_field2) {
        assert(em_set.count(i));
        return eval_elem_sym2 {resi.first, em_set[i]};
    } else {
        return eval_elem_sym2 {resi.first, resi.second};
    }
}
#else
eval_elem2 Sector::get_eval(int i)
{
    return (eval_elem2)(get_eval_inner(i));
}

eval_elem_sym2 Sector::get_eval_inner(int i)
{
#ifndef WRAPPER
    int resi = eval[i];
#else
    fseek(f, i, SEEK_SET);
    unsigned char read;
    fread(&read, 1, 1, f);
    int resi = read;
#endif
    if (resi == SPEC) {
        assert(em_set.count(i));
        int x = em_set[i];
        return x >= 0 ? eval_elem_sym(eval_elem_sym::val, x) :
                        eval_elem_sym(eval_elem_sym::count, -x);
    } else
        return resi <= MAX_VAL ?
                   eval_elem_sym(eval_elem_sym::val, resi) :
                   (resi <= MAX_VAL + 16 ?
                        eval_elem_sym(eval_elem_sym::sym, resi - SPEC - 1) :
                        eval_elem_sym(eval_elem_sym::count, 255 - resi));
}
#endif

#ifdef DD

template <int b, class T>
T sign_extend(T x)
{
    if ((1 << (b - 1)) & x)
        return x | ((-1) ^ ((1 << b) - 1));
    else
        return x;
}

pair<sec_val, field2_t> Sector::extract(int i)
{
    unsigned int a = 0;
    static_assert(sizeof(a) >= eval_struct_size, "vedd nagyobbra az a-t is! "
                                                 "(meg az intractnal is) (es "
                                                 "nezd meg a literal 1-ek "
                                                 "tipusait (az extendben is))) "
                                                 "(meg minden intte castolast "
                                                 "is)");
#ifndef WRAPPER
    for (int j = 0; j < eval_struct_size; j++)
        a |= (int)eval[eval_struct_size * i + j] << 8 * j;
#else
    fseek(f, header_size + eval_struct_size * i, SEEK_SET);
    unsigned char read[eval_struct_size];
    fread(&read, 1, eval_struct_size, f);
    for (int j = 0; j < eval_struct_size; j++)
        a |= (int)read[j] << 8 * j;
#endif
    auto r = make_pair(
        sign_extend<field1_size, sec_val>(a & ((1 << field1_size) - 1)),
        sign_extend<field2_size, field2_t>(a >> field2_offset));
    //#if VARIANT != STANDARD
    //	r.first -= sval;
    //#endif
    return r;
}

#endif

#ifndef WRAPPER

#ifdef DD
void Sector::set_eval(int h, eval_elem2 r)
{
    assert(get_eval_inner(h).cas() != eval_elem_sym2::Sym);
    set_eval_inner(h, r);
}

void Sector::set_eval_inner(int h, eval_elem_sym2 r)
{
    if (abs(r.key2) > eval_elem_sym2::max_field2) {
        intract(h, make_pair(r.key1, eval_elem_sym2::spec_field2));
        em_set[h] = r.key2;
    } else {
        if (extract(h).second == eval_elem_sym2::spec_field2)
            em_set.erase(h);
        intract(h, make_pair(r.key1, r.key2));
    }
}

void Sector::intract(int i, pair<sec_val, field2_t> x)
{
    //#if VARIANT != STANDARD
    //	x.first += sval;
    //#endif
    unsigned int a = (x.first & ((1 << field1_size) - 1)) |
                     ((int)x.second << field2_offset);
    for (int j = 0; j < eval_struct_size; j++)
        eval[eval_struct_size * i + j] = (unsigned char)(a >> 8 * j);
    //#if VARIANT != STANDARD
    //	x.first -= sval;
    //#endif
    assert(extract(i) == x);
}

#else

void Sector::set_eval(int h, eval_elem2 r)
{
    assert(get_eval_inner(h).cas() != eval_elem_sym2::Sym);
    set_eval_inner(h, r);
}

void Sector::set_eval_inner(int h, eval_elem_sym2 r)
{
    set_eval_inner(h, eval_elem_sym {r});
}

void Sector::set_eval_inner(int h, eval_elem_sym r)
{

#ifdef STATISTICS
    if (r.c == eval_elem::count) {
        max_count = max(max_count, r.x);
    } else if (r.c == eval_elem::val) {
        max_val = max(max_val, r.x);
    }
#endif

    bool er = eval[h] == SPEC;
    if (r.c == eval_elem::count) {
        if (r.x <= MAX_COUNT) {
            eval[h] = 255 - r.x;
            if (er)
                em_set.erase(h);
        } else {
            eval[h] = SPEC;
            em_set[h] = -r.x;
        }
    } else {
        if (r.c == eval_elem::val) {
            if (r.x <= MAX_VAL) {
                eval[h] = r.x;
                if (er)
                    em_set.erase(h);
            } else {
                eval[h] = SPEC;
                em_set[h] = r.x;
            }
        } else {
            eval[h] = SPEC + 1 + r.x;
            if (er)
                em_set.erase(h);
        }
    }
}
#endif

void Sector::init()
{
    LOG("init");

#ifndef ANALYZER
    int n = hash->hash_count;
    for (int h = 0; h < n; h++) {
        board a = hash->inv_hash(h);

        board mi = 1LL << 50;
        char mh;
        auto &ops = hash->f_sym_lookup2[a & mask24];
        for (int op = 0; op < 16; op++)
            if ((1 << op) & ops) {
                board a2 = sym48(op, a);
                if (a2 < mi) {
                    mi = a2;
                    mh = op;
                }
            }
        if (mi != a) {
            set_eval_inner(h, eval_elem_sym2::make_sym(mh));
        } else {
            if (B + BF <= 3 && can_close_mill(a, W, B, WF, BF)) {
                assert(virt_win_val);
                set_eval(h, eval_elem2(virt_win_val - sval, 1)); // intellisense
                                                                 // bug, if we
                                                                 // use {}
            } else {
                // int c=CHILD_COUNT(a,W,B,WF,BF);

                /*c*=orbitsize(a);
                set_eval(h,eval_elem(c ? eval_elem::count : eval_elem::val
                ,c));*/

                set_eval(h, eval_elem2 {0}); //(count) ezt a 0-t fogja
                                             // novelgetni a forditott
                                             // gyerekszamolas
            }
        }
    }
#endif
}

#endif

#ifndef WRAPPER

short_id::operator Sector *()
{
    return sector_objs[sid];
}
short_id::short_id(Sector *s)
    : sid(s->sid)
{ }
short_id::short_id() { }
short_id::short_id(char sid)
    : sid(sid)
{ }
short_id::operator id()
{
    return ((Sector *)(*this))->id;
}

#endif

void Sector::allocate_hash()
{ // and read em_set (should be renamed)
    hash = new Hash(W, B, this);
#ifdef DD
    eval_size = hash->hash_count * eval_struct_size;
#else
    eval_size = hash->hash_count;
#endif

#ifdef WRAPPER
    if (!f) {
        std::string filename = std::string(fname);
        filename = sec_val_path + "\\" + filename;
        
        fopen_s(&f, filename.c_str(), "rb"); // the vb code has checked that it
                                            // exists
        read_header(f);
    }
    fseek(f, header_size + eval_size, SEEK_SET);
    read_em_set(f);
#endif
}

// TODO: Why should undef WRAPPER here?
//#if defined(WRAPPER) || defined(ANALYZER)
void Sector::release_hash()
{ // and clear em_set (should be renamed)
    delete hash;
    hash = nullptr;

    em_set.clear();

#ifdef WRAPPER
    fclose(f);
    f = nullptr;
#endif
}
//#endif
