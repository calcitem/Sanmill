// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_log.h

// pefect_log.h

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
    static void setup_logfile(std::string fileName, std::string extension);
    static std::string fileName, fileNameLogging, doneFileName;
    static void close_log_file();
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
