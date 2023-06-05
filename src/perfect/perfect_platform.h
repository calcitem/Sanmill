// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023 The Sanmill developers (see AUTHORS file)
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

#ifndef PERFECT_PLATFORM_H_INCLUDED
#define PERFECT_PLATFORM_H_INCLUDED

#include <cstdio>
#include <string>

#if defined(_WIN32)
#define SPRINTF(buffer, buffer_size, format, ...) \
    sprintf_s(buffer, buffer_size, format, ##__VA_ARGS__)
#define FOPEN(file, filename, mode) fopen_s(file, filename, mode)
#define FSCANF(file, format, ...) fscanf_s(file, format, ##__VA_ARGS__)
#define STRCPY(destination, destination_size, source) \
    strcpy_s(destination, destination_size, source)
#define POPCNT(x) __popcnt(x)
#else // _WIN32
#define SPRINTF(buffer, buffer_size, format, ...) \
    snprintf(buffer, buffer_size, format, ##__VA_ARGS__)
#define FOPEN(file, filename, mode) \
    ((*file = fopen(filename, mode)) != NULL ? 0 : -1)
#define FSCANF(file, format, ...) fscanf(file, format, ##__VA_ARGS__)
#define STRCPY(destination, destination_size, source) \
    strncpy(destination, source, destination_size)
#define POPCNT(x) __builtin_popcount(x)
#endif // _WIN32

#endif // PERFECT_PLATFORM_H_INCLUDED
