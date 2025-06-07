// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_sector.cpp

#include "perfect_sector.h"
#include "perfect_common.h"
#include "perfect_hash.h"
#include "perfect_symmetries.h"
#include "perfect_errors.h"

#include <chrono>
#include <cstdio>
#include <vector>

std::vector<std::vector<std::vector<std::vector<Sector *>>>> sectors;

std::vector<Sector *> sector_objs;

const int sbufsize = 1024 * 1024;
char sbuf[sbufsize]; // Caution

Sector::Sector(::Id the_id)
    : W(the_id.W)
    , B(the_id.B)
    , WF(the_id.WF)
    , BF(the_id.BF)
    , id(the_id)
    , max_val(-1)
    , max_count(-1)
    , hash(nullptr)
#ifdef WRAPPER
    , f(nullptr)
    , sval(
#else
    , sval(
#endif
#ifdef DD
          sec_vals[id]
#else
          0
#endif
      )
{
    assert(sec_vals.count(id) > 0);

    sector_objs.push_back(this);

    STRCPY(fileName, sizeof(fileName), id.file_name().c_str());
    LOG("Creating sector object for %s\n", fileName);

#ifndef WRAPPER
    allocate_hash();
#endif
}

template <class T>
bool fread1(T &x, FILE *file)
{
    size_t ret = fread(&x, sizeof(x), 1, file);
    if (ret != 1) {
        SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "fread1 failed");
        return false;
    }
    return true;
}

template <class T>
bool fwrite1(T &x, FILE *file)
{
    size_t ret = fwrite(&x, sizeof(x), 1, file);
    if (ret != 1) {
        SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "fwrite1 failed");
        return false;
    }
    return true;
}

void Sector::read_header(FILE *file)
{
#ifdef DD
    int _version, _eval_struct_size, _field2_offset;
    char _stone_diff_flag;
    if (!fread1(_version, file))
        return;
    if (!fread1(_eval_struct_size, file))
        return;
    if (!fread1(_field2_offset, file))
        return;
    if (!fread1(_stone_diff_flag, file))
        return;
    assert(_version == version);
    assert(_eval_struct_size == eval_struct_size);
    assert(_field2_offset == field2Offset);
    assert(_stone_diff_flag == stone_diff_flag);
    fseek(f, header_size, SEEK_SET);
#endif
}
void Sector::write_header(FILE *file)
{
#ifdef DD
    if (!fwrite1(version, file))
        return;
    if (!fwrite1(eval_struct_size, file))
        return;
    if (!fwrite1(field2Offset, file))
        return;
    if (!fwrite1(stone_diff_flag, file))
        return;
    long ffu_size = header_size - ftell(file);
    char *dummy = new char[ffu_size];
    memset(dummy, 0, ffu_size);
    fwrite(dummy, 1, ffu_size, file);
    delete[] dummy;
#endif
}

void Sector::read_em_set(FILE *file)
{
    auto start = std::chrono::steady_clock::now();
    auto last_update = std::chrono::steady_clock::now();

    int em_set_size = 0;
    size_t ret = fread(&em_set_size, 4, 1, file);
    if (ret != 1) {
        SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "Failed to read "
                                                        "em_set_size");
        return;
    }

    for (int i = 0; i < em_set_size; i++) {
        int e[2];
        ret = fread(e, 4, 2, file);
        if (ret != 2) {
            SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "Failed to read "
                                                            "array 'e'");
            return;
        }
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
            auto hours = elapsed_seconds / 3600;
            int minutes = (elapsed_seconds % 3600) / 60;
            int seconds = elapsed_seconds % 60;

            // Calculate remaining time
            int remaining_iterations = em_set_size - (i + 1);
            auto avg_seconds_per_iteration = elapsed_seconds / (float)(i + 1);
            auto remaining_seconds = remaining_iterations *
                                     avg_seconds_per_iteration;
            auto remaining_hours = remaining_seconds / 3600;
            int remaining_minutes = ((unsigned int)remaining_seconds % 3600) /
                                    60;
            int remaining_secs = (unsigned int)remaining_seconds % 60;

            if (memoryUsageMB < 1024) {
                printf("\rProgress: %.2f%%, Memory Usage: %.2fMB, Elapsed "
                       "time: %02d:%02d:%02d, Remaining time: %02d:%02d:%02d",
                       ((float)(i + 1) / em_set_size) * 100, memoryUsageMB,
                       static_cast<int>(hours), static_cast<int>(minutes),
                       static_cast<int>(seconds),
                       static_cast<int>(remaining_hours),
                       static_cast<int>(remaining_minutes),
                       static_cast<int>(remaining_secs));
            } else {
                printf("\rProgress: %.2f%%, Memory Usage: %.2fGB, Elapsed "
                       "time: %02d:%02d:%02d, Remaining time: %02d:%02d:%02d",
                       ((float)(i + 1) / em_set_size) * 100,
                       memoryUsageMB / 1024.0, static_cast<int>(hours),
                       static_cast<int>(minutes), static_cast<int>(seconds),
                       static_cast<int>(remaining_hours),
                       static_cast<int>(remaining_minutes),
                       static_cast<int>(remaining_secs));
            }

            // Flush the output buffer to immediately update the output
            fflush(stdout);

            last_update = now;
        }
    }

    // Print a new line after the loop ends to avoid subsequent outputs
    // on the same line
    printf("\n");
}

#ifdef DD
eval_elem2 Sector::get_eval(int i)
{
    return (eval_elem2)(get_eval_inner(i));
}

eval_elem_sym2 Sector::get_eval_inner(int i)
{
#ifdef DD
    field2_t spec_field2 = -(1 << (field2Size - 1));
    // field2_t max_field2 = -(spec_field2 + 1);
#endif

    std::pair<sec_val, field2_t> resi = extract_value(i);
    if (resi.second == spec_field2) {
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
    size_t ret;
#ifndef WRAPPER
    int resi = evaluate[i];
#else
    fseek(f, i, SEEK_SET);
    unsigned char read;
    ret = fread(&read, 1, 1, f);
    if (ret != 1) {
        SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "Failed to read 'read' "
                                                        "variable");
        return {};
    }
    int resi = read;
#endif

    if (resi == SPEC) {
        assert(em_set.count(i));
        int x = em_set[i];
        return x >= 0 ? eval_elem_sym(eval_elem_sym::val, x) :
                        eval_elem_sym(eval_elem_sym::count, -x);
    } else {
        return resi <= MAX_VAL ?
                   eval_elem_sym(eval_elem_sym::val, resi) :
                   (resi <= MAX_VAL + 16 ?
                        eval_elem_sym(eval_elem_sym::sym, resi - SPEC - 1) :
                        eval_elem_sym(eval_elem_sym::count, 255 - resi));
    }
}
#endif

#ifdef DD

template <class T>
T sign_extend(T x, int b)
{
    if ((1 << (b - 1)) & x)
        return x | ((-1) ^ ((1 << b) - 1));
    else
        return x;
}

std::pair<sec_val, field2_t> Sector::extract_value(int i)
{
    unsigned int a = 0;
    static_assert(sizeof(a) >= eval_struct_size, "Increase the size of 'a'! "
                                                 "(Also consider in 'intract') "
                                                 "(And "
                                                 "check the types of literal "
                                                 "1s "
                                                 "(in 'extend' as well))) "
                                                 "(And also check all int type "
                                                 "casts)");
#ifndef WRAPPER
    for (int j = 0; j < eval_struct_size; j++)
        a |= (int)evaluate[eval_struct_size * i + j] << 8 * j;
#else
    fseek(f, header_size + eval_struct_size * i, SEEK_SET);
    unsigned char read[eval_struct_size];
    size_t ret = fread(&read, 1, eval_struct_size, f);
    if (ret != eval_struct_size) {
        SET_ERROR_CODE(PerfectErrors::PE_FILE_IO_ERROR, "Failed to read the "
                                                        "expected number of "
                                                        "bytes");
        return {};
    }
    for (int j = 0; j < eval_struct_size; j++)
        a |= (int)read[j] << 8 * j;
#endif

    auto r = std::make_pair(
        sign_extend(static_cast<sec_val>(a & ((1 << field1Size) - 1)),
                    field1Size),
        sign_extend(static_cast<field2_t>(a >> field2Offset), field2Size));

    return r;
}

#endif

void Sector::allocate_hash()
{
    // and read em_set (should be renamed)
    hash = new Hash(W, B, this);
#ifdef DD
    eval_size = hash->hash_count * eval_struct_size;
#else
    eval_size = hash->hash_count;
#endif

#ifdef WRAPPER
    if (!f) {
        std::string filename = std::string(fileName);
#ifdef _WIN32
        filename = secValPath + "\\" + filename;
#else
        filename = secValPath + "/" + filename;
#endif

        if (FOPEN(&f, filename.c_str(), "rb") == -1) {
            std::cerr << "Failed to open file " << filename << '\n';
            return;
        }
        read_header(f);
    }
    fseek(f, header_size + eval_size, SEEK_SET);
    read_em_set(f);
#endif
}

void Sector::release_hash()
{
    // and clear em_set (should be renamed)
    delete hash;
    hash = nullptr;

    em_set.clear();

#ifdef WRAPPER
    fclose(f);
    f = nullptr;
#endif
}
