// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_log.cpp

// pefect_log.cpp

#include "perfect_log.h"
#include "perfect_common.h"
#include "perfect_errors.h"

#include <iostream>

bool Log::log_to_file = false;
FILE *Log::logfile = stdout;
std::string Log::fileName, Log::fileNameLogging, Log::doneFileName;

void Log::setup_logfile(std::string filename, std::string extension)
{
    Log::fileName = filename;
    log_to_file = true;
    fileNameLogging = filename + ".logging" + FNAME_SUFFIX;

    doneFileName = filename + "." + extension + FNAME_SUFFIX;

    remove(doneFileName.c_str());
    if (FOPEN(&logfile, fileNameLogging.c_str(), "w") == -1) {
        std::string errMsg = "Fatal error: Unable to open log file. (Another "
                             "instance is "
                             "probably running with the same parameters.)";
        std::cerr << errMsg << std::endl;
#if defined(_WIN32) || defined(_WIN64)
        system("pause");
#endif
        SET_ERROR_MESSAGE(PerfectErrors::PE_FILE_IO_ERROR, errMsg);
        return;
    }
    if (logfile == nullptr) {
        SET_ERROR_MESSAGE(PerfectErrors::PE_FILE_IO_ERROR, "Failed to set "
                                                           "buffer for the log "
                                                           "file because it is "
                                                           "null.");
        return;
    }
    setvbuf(logfile, 0, _IONBF, 0);
}

void Log::close_log_file()
{
    if (log_to_file) {
        fclose(logfile);
        if (rename(fileNameLogging.c_str(), doneFileName.c_str()))
            std::cout << "Renaming logfile failed; errno: " << errno
                      << std::endl;
    }
}
