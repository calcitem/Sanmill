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

#include "perfect_common.h"
#include "perfect_log.h"

#include <iostream>

bool Log::log_to_file = false;
FILE *Log::logfile = stdout;
std::string Log::fname, Log::fnamelogging, Log::donefname;

void Log::setup_logfile(std::string filename, std::string extension)
{
    Log::fname = filename;
    log_to_file = true;
    fnamelogging = filename + ".logging" + FNAME_SUFFIX;

    donefname = filename + "." + extension + FNAME_SUFFIX;

    remove(donefname.c_str());
    if (FOPEN(&logfile, fnamelogging.c_str(), "w") == -1) {
        printf("Fatal error: Unable to open log file. (Another instance is "
               "probably running with the same parameters.)\n");
#if defined(_WIN32) || defined(_WIN64)
        system("pause");
#endif
        exit(1);
    }
    setvbuf(logfile, 0, _IONBF, 0);
}

void Log::close()
{
    if (log_to_file) {
        fclose(logfile);
        if (rename(fnamelogging.c_str(), donefname.c_str()))
            std::cout << "Renaming logfile failed; errno: " << errno
                      << std::endl;
    }
}
