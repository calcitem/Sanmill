/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifdef _WIN32
#if _WIN32_WINNT < 0x0601
#undef  _WIN32_WINNT
#define _WIN32_WINNT 0x0601 // Force to include needed API prototypes
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
// The needed Windows API for processor groups could be missed from old Windows
// versions, so instead of calling them directly (forcing the linker to resolve
// the calls at compile time), try to load them at runtime. To do this we need
// first to define the corresponding function pointers.
extern "C" {
    typedef bool(*fun1_t)(LOGICAL_PROCESSOR_RELATIONSHIP,
                          PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, PDWORD);
    typedef bool(*fun2_t)(USHORT, PGROUP_AFFINITY);
    typedef bool(*fun3_t)(HANDLE, CONST GROUP_AFFINITY *, PGROUP_AFFINITY);
}
#endif

#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>
#include <cstdlib>

#if defined(__linux__) && !defined(__ANDROID__)
#include <stdlib.h>
#include <sys/mman.h>
#endif

#if defined(__APPLE__) || defined(__ANDROID__) || defined(__OpenBSD__) || (defined(__GLIBCXX__) && !defined(_GLIBCXX_HAVE_ALIGNED_ALLOC) && !defined(_WIN32))
#define POSIXALIGNEDALLOC
#include <stdlib.h>
#endif

#include "misc.h"
#include "thread.h"

using namespace std;

namespace
{

/// Version number. If Version is left empty, then compile date in the format
/// DD-MM-YY and show in engine_info.
const string Version = "";

} // namespace


/// Used to serialize access to std::cout to avoid multiple threads writing at
/// the same time.

std::ostream &operator<<(std::ostream &os, SyncCout sc)
{
    static std::mutex m;

    if (sc == IO_LOCK)
        m.lock();

    if (sc == IO_UNLOCK)
        m.unlock();

    return os;
}


/// prefetch() preloads the given address in L1/L2 cache. This is a non-blocking
/// function that doesn't stall the CPU waiting for data to be loaded from memory,
/// which can be quite slow.
#ifdef NO_PREFETCH

void prefetch(void *)
{
}

#else

void prefetch(void *addr)
{
#  if defined(__INTEL_COMPILER)
    // This hack prevents prefetches from being optimized away by
    // Intel compiler. Both MSVC and gcc seem not be affected by this.
    __asm__("");
#  endif

#  if defined(__INTEL_COMPILER) || defined(_MSC_VER)
    _mm_prefetch((char *)addr, _MM_HINT_T0);
#  else
    __builtin_prefetch(addr);
#  endif
}

#ifndef PREFETCH_STRIDE
/* L1 cache line size */
#define L1_CACHE_SHIFT	7
#define L1_CACHE_BYTES	(1 << L1_CACHE_SHIFT)

#define PREFETCH_STRIDE (4 * L1_CACHE_BYTES)
#endif

void prefetch_range(void *addr, size_t len)
{
    char *cp = nullptr;
    const char *end = (char *)addr + len;

    for (cp = (char *)addr; cp < end; cp += PREFETCH_STRIDE)
        prefetch(cp);
}

#endif


#ifdef _WIN32
#include <direct.h>
#define GETCWD _getcwd
#else
#include <unistd.h>
#define GETCWD getcwd
#endif

namespace CommandLine
{

string argv0;            // path+name of the executable binary, as given by argv[0]
string binaryDirectory;  // path of the executable directory
string workingDirectory; // path of the working directory

void init(int argc, const char *argv[])
{
    (void)argc;
    string pathSeparator;

    // extract the path+name of the executable binary
    argv0 = argv[0];

#ifdef _WIN32
    pathSeparator = "\\";
#ifdef _MSC_VER
    // Under windows argv[0] may not have the extension. Also _get_pgmptr() had
    // issues in some windows 10 versions, so check returned values carefully.
    char *pgmptr = nullptr;
    if (!_get_pgmptr(&pgmptr) && pgmptr != nullptr && *pgmptr)
        argv0 = pgmptr;
#endif
#else
    pathSeparator = "/";
#endif

    // extract the working directory
    workingDirectory = "";
    char buff[40000];
    const char *cwd = GETCWD(buff, 40000);
    if (cwd)
        workingDirectory = cwd;

    // extract the binary directory path from argv0
    binaryDirectory = argv0;
    const size_t pos = binaryDirectory.find_last_of("\\/");
    if (pos == std::string::npos)
        binaryDirectory = "." + pathSeparator;
    else
        binaryDirectory.resize(pos + 1);

    // pattern replacement: "./" at the start of path is replaced by the working directory
    if (binaryDirectory.find("." + pathSeparator) == 0)
        binaryDirectory.replace(0, 1, workingDirectory);
}


} // namespace CommandLine
