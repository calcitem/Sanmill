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

#ifndef PERFECT_LOG_H_INCLUDED
#define PERFECT_LOG_H_INCLUDED

#include <cstdio>
#include <iostream>
#include <string>

struct Log
{
    // This is not in the other branch because log.cpp is not included in the
    // wrapper project (but there would be no obstacle to adding it)
    static bool log_to_file;
    static FILE *logfile;
    static void setup_logfile(std::string fname, std::string extension);
    static std::string fname, fnamelogging, donefname;
    static void close();
};

template <typename... Args>
void LOG(const char *format, Args... args)
{
#if defined(_WIN32)
    printf_s(format, args...);
    fflush(stdout);
    if (Log::log_to_file) {
        fprintf_s(Log::logfile, format, args...);
        fflush(Log::logfile);
    }
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-security"
    printf(format, args...);
    fflush(stdout);
    if (Log::log_to_file) {
        fprintf(Log::logfile, format, args...);
        fflush(Log::logfile);
    }
#pragma GCC diagnostic pop
#endif
}

#endif // PERFECT_LOG_H_INCLUDED
