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

// perfect_platform.h

#ifndef PERFECT_PLATFORM_H_INCLUDED
#define PERFECT_PLATFORM_H_INCLUDED

#include <cstdio>
#include <string>

#if defined(_WIN32)

#define SPRINTF(buffer, buffer_size, format, ...) \
    sprintf_s(buffer, buffer_size, format, ##__VA_ARGS__)

#define FSCANF(file, format, ...) fscanf_s(file, format, ##__VA_ARGS__)

#define FOPEN(file, filename, mode) fopen_s(file, filename, mode)

#define STRCPY(destination, destination_size, source) \
    strcpy_s(destination, destination_size, source)

#if defined(_M_ARM) || defined(_M_ARM64)
// TODO: See generic_popcount()
inline int popcnt_software(uint32_t x) noexcept
{
    int count = 0;
    while (x) {
        count += x & 1;
        x >>= 1;
    }
    return count;
}
#define POPCNT(x) popcnt_software(x)
#else
#define POPCNT(x) __popcnt(x)
#endif

#else // _WIN32

#if defined(__APPLE__) && defined(__MACH__) || defined(__ANDROID__)
#define SPRINTF(buffer, buffer_size, format, ...) \
    snprintf(buffer, buffer_size, format __VA_OPT__(, ) __VA_ARGS__)

#define FSCANF(file, format, ...) \
    do { \
        int ret = fscanf(file, format __VA_OPT__(, ) __VA_ARGS__); \
        if (ret == EOF) { \
            assert(false); \
        } \
    } while (0)
#else
#define SPRINTF(buffer, buffer_size, format, ...) \
    snprintf(buffer, buffer_size, format, ##__VA_ARGS__)

#define FSCANF(file, format, ...) \
    do { \
        int ret = fscanf(file, format, ##__VA_ARGS__); \
        if (ret == EOF) { \
            assert(false); \
        } \
    } while (0)
#endif

#define FOPEN(file, filename, mode) \
    ((*file = fopen(filename, mode)) != NULL ? 0 : -1)

#define STRCPY(destination, destination_size, source) \
    strncpy(destination, source, destination_size - 1); \
    destination[destination_size - 1] = '\0'

#define POPCNT(x) __builtin_popcount(x)

#endif // _WIN32

#endif // PERFECT_PLATFORM_H_INCLUDED
