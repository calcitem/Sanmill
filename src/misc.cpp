// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// misc.cpp

#ifdef _WIN32
#if _WIN32_WINNT < 0x0601
#undef _WIN32_WINNT
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
using fun1_t = bool (*)(LOGICAL_PROCESSOR_RELATIONSHIP,
                        PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, PDWORD);
using fun2_t = bool (*)(USHORT, PGROUP_AFFINITY);
using fun3_t = bool (*)(HANDLE, CONST GROUP_AFFINITY *, PGROUP_AFFINITY);
}
#endif

#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

#if defined(__linux__) && !defined(__ANDROID__)
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

#if defined(__APPLE__) || defined(__ANDROID__) || defined(__OpenBSD__) || \
    (defined(__GLIBCXX__) && !defined(_GLIBCXX_HAVE_ALIGNED_ALLOC) && \
     !defined(_WIN32))
#define POSIXALIGNEDALLOC
#include <stdlib.h>
#endif

#include "misc.h"
#include "thread.h"

using std::cerr;
using std::cin;
using std::cout;
using std::endl;
using std::ifstream;
using std::iostream;
using std::ofstream;
using std::setfill;
using std::setw;
using std::streambuf;
using std::string;
using std::stringstream;

namespace {

/// Version number. If Version is left empty, then compile date in the format
/// DD-MM-YY and show in engine_info.
const string Version;

/// Our fancy logging facility. The trick here is to replace cin.rdbuf() and
/// cout.rdbuf() with two Tie objects that tie cin and cout to a file stream. We
/// can toggle the logging of std::cout and std:cin at runtime whilst preserving
/// usual I/O functionality, all without changing a single line of code!
/// Idea from http://groups.google.com/group/comp.lang.c++/msg/1d941c0f26ea0d81

struct Tie final : streambuf
{
    // MSVC requires split streambuf for cin and cout

    Tie(streambuf *b, streambuf *lb)
        : buf(b)
        , logBuf(lb)
    { }

    int sync() override
    {
        logBuf->pubsync();
        return buf->pubsync();
    }

    int overflow(int c) override
    {
        return log(buf->sputc(static_cast<char>(c)), "<< ");
    }

    int underflow() override { return buf->sgetc(); }

    int uflow() override { return log(buf->sbumpc(), ">> "); }

    streambuf *buf, *logBuf;

    int log(int c, const char *prefix) const
    {
        static int last = '\n'; // Single log file

        if (last == '\n')
            logBuf->sputn(prefix, 3);

        return last = logBuf->sputc(static_cast<char>(c));
    }
};

class Logger
{
    Logger()
        : in(cin.rdbuf(), file.rdbuf())
        , out(cout.rdbuf(), file.rdbuf())
    { }

    ~Logger() { start(""); }

    ofstream file;
    Tie in, out;

public:
    static void start(const std::string &fname)
    {
        static Logger logger;

        if (!fname.empty() && !logger.file.is_open()) {
            logger.file.open(fname, ifstream::out);

            if (!logger.file.is_open()) {
                cerr << "Unable to open debug log file " << fname << endl;
                exit(EXIT_FAILURE);
            }

            cin.rdbuf(&logger.in);
            cout.rdbuf(&logger.out);
        } else if (fname.empty() && logger.file.is_open()) {
            cout.rdbuf(logger.out.buf);
            cin.rdbuf(logger.in.buf);
            logger.file.close();
        }
    }
};

} // namespace

/// engine_info() returns the full name of the current Sanmill version. This
/// will be either "Sanmill <Tag> DD-MM-YY" (where DD-MM-YY is the date when
/// the program was compiled) or "Sanmill <Version>", depending on whether
/// Version is empty.

string engine_info(bool to_uci)
{
    const string months("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec");
    string month, day, year;
    stringstream ss, date(__DATE__); // From compiler, format is "Sep 21 2008"

    ss << "Sanmill " << Version << setfill('0');

    if (Version.empty()) {
        date >> month >> day >> year;
        ss << setw(2) << day << setw(2) << (1 + months.find(month) / 4)
           << year.substr(2);
    }

    ss << (to_uci ? "\nid author " : " by ")
       << "the Sanmill developers (see AUTHORS file)";

    return ss.str();
}

/// compiler_info() returns a string trying to describe the compiler we use

std::string compiler_info()
{
#define stringify2(x) #x
#define stringify(x) stringify2(x)
#define make_version_string(major, minor, patch) \
    stringify(major) "." stringify(minor) "." stringify(patch)

    /// Predefined macros hell:
    ///
    /// __GNUC__           Compiler is gcc, Clang or Intel on Linux
    /// __INTEL_COMPILER   Compiler is Intel
    /// _MSC_VER           Compiler is MSVC or Intel on Windows
    /// _WIN32             Building on Windows (any)
    /// _WIN64             Building on Windows 64 bit

    std::string compiler = "\nCompiled by ";

#ifdef __clang__
    compiler += "clang++ ";
    compiler += make_version_string(__clang_major__, __clang_minor__,
                                    __clang_patchlevel__);
#elif __INTEL_COMPILER
    compiler += "Intel compiler ";
    compiler += "(version ";
    compiler += stringify(__INTEL_COMPILER) " update " stringify(
        __INTEL_COMPILER_UPDATE);
    compiler += ")";
#elif _MSC_VER
    compiler += "MSVC ";
    compiler += "(version ";
    compiler += stringify(_MSC_FULL_VER) "." stringify(_MSC_BUILD);
    compiler += ")";
#elif __GNUC__
    compiler += "g++ (GNUC) ";
    compiler += make_version_string(__GNUC__, __GNUC_MINOR__,
                                    __GNUC_PATCHLEVEL__);
#else
    compiler += "Unknown compiler ";
    compiler += "(unknown version)";
#endif

#if defined(__APPLE__)
    compiler += " on Apple";
#elif defined(__CYGWIN__)
    compiler += " on Cygwin";
#elif defined(__MINGW64__)
    compiler += " on MinGW64";
#elif defined(__MINGW32__)
    compiler += " on MinGW32";
#elif defined(__ANDROID__)
    compiler += " on Android";
#elif defined(__linux__)
    compiler += " on Linux";
#elif defined(_WIN64)
    compiler += " on Microsoft Windows 64-bit";
#elif defined(_WIN32)
    compiler += " on Microsoft Windows 32-bit";
#else
    compiler += " on unknown system";
#endif

    compiler += "\nCompilation settings include: ";
    compiler += (Is64Bit ? " 64bit" : " 32bit");
#if defined(USE_VNNI)
    compiler += " VNNI";
#endif
#if defined(USE_AVX512)
    compiler += " AVX512";
#endif
    compiler += (HasPext ? " BMI2" : "");
#if defined(USE_AVX2)
    compiler += " AVX2";
#endif
#if defined(USE_SSE41)
    compiler += " SSE41";
#endif
#if defined(USE_SSSE3)
    compiler += " SSSE3";
#endif
#if defined(USE_SSE2)
    compiler += " SSE2";
#endif
    compiler += (HasPopCnt ? " POPCNT" : "");
#if defined(USE_MMX)
    compiler += " MMX";
#endif
#if defined(USE_NEON)
    compiler += " NEON";
#endif

#if !defined(NDEBUG)
    compiler += " DEBUG";
#endif

    compiler += "\n__VERSION__ macro expands to: ";
#ifdef __VERSION__
    compiler += __VERSION__;
#else
    compiler += "(undefined macro)";
#endif
    compiler += "\n";

    return compiler;
}

/// Debug functions used mainly to collect run-time statistics
static std::atomic<int64_t> hits[2], means[2];

void dbg_hit_on(bool b) noexcept
{
    ++hits[0];
    if (b)
        ++hits[1];
}

void dbg_hit_on(bool c, bool b) noexcept
{
    if (c)
        dbg_hit_on(b);
}

void dbg_mean_of(int v) noexcept
{
    ++means[0];
    means[1] += v;
}

void dbg_print()
{
    if (hits[0])
        cerr << "Total " << hits[0] << " Hits " << hits[1] << " hit rate (%) "
             << 100 * hits[1] / hits[0] << endl;

    if (means[0])
        cerr << "Total " << means[0] << " Mean "
             << static_cast<double>(means[1]) / means[0] << endl;
}

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

/// Trampoline helper to avoid moving Logger to misc.h
void start_logger(const std::string &fname)
{
    Logger::start(fname);
}

/// prefetch() preloads the given address in L1/L2 cache. This is a non-blocking
/// function that doesn't stall the CPU waiting for data to be loaded from
/// memory, which can be quite slow.
#ifdef NO_PREFETCH

void prefetch(void *) { }

#else

void prefetch(void *addr)
{
#if defined(__INTEL_COMPILER)
    // This hack prevents prefetches from being optimized away by
    // Intel compiler. Both MSVC and gcc seem not be affected by this.
    __asm__("");
#endif

#if defined(__INTEL_COMPILER) || \
    (defined(_MSC_VER) && !defined(_M_ARM) && !defined(_M_ARM64))
    _mm_prefetch(static_cast<char *>(addr), _MM_HINT_T0);
#elif defined(__GNUC__) || defined(__clang__)
    __builtin_prefetch(addr);
#else
    (void)addr;
#endif
}

#ifndef PREFETCH_STRIDE
/* L1 cache line size */
constexpr auto L1_CACHE_SHIFT = 7;
constexpr auto L1_CACHE_BYTES = 1 << L1_CACHE_SHIFT;

constexpr auto PREFETCH_STRIDE = 4 * L1_CACHE_BYTES;
#endif

void prefetch_range(void *addr, size_t len)
{
    const char *end = static_cast<char *>(addr) + len;

    for (auto cp = static_cast<char *>(addr); cp < end; cp += PREFETCH_STRIDE)
        prefetch(cp);
}

#endif

/// std_aligned_alloc() is our wrapper for systems where the c++17
/// implementation does not guarantee the availability of aligned_alloc().
/// Memory allocated with std_aligned_alloc() must be freed with
/// std_aligned_free().

void *std_aligned_alloc(size_t alignment, size_t size)
{
#if defined(POSIXALIGNEDALLOC)
    void *mem;
    return posix_memalign(&mem, alignment, size) ? nullptr : mem;
#elif defined(_WIN32)
    return _mm_malloc(size, alignment);
#else
    return std::aligned_alloc(alignment, size);
#endif
}

void std_aligned_free(void *ptr)
{
#if defined(POSIXALIGNEDALLOC)
    free(ptr);
#elif defined(_WIN32)
    _mm_free(ptr);
#else
    free(ptr);
#endif
}

#ifdef ALIGNED_LARGE_PAGES

/// aligned_large_pages_alloc() will return suitably aligned memory, if possible
/// using large pages.

#if defined(_WIN32)

static void *aligned_large_pages_alloc_win(size_t allocSize)
{
    HANDLE hProcessToken {};
    LUID luid {};
    void *mem = nullptr;

    const size_t largePageSize = GetLargePageMinimum();
    if (!largePageSize)
        return nullptr;

    // We need SeLockMemoryPrivilege, so try to enable it for the process
    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
                          &hProcessToken))
        return nullptr;

    if (LookupPrivilegeValue(NULL, SE_LOCK_MEMORY_NAME, &luid)) {
        TOKEN_PRIVILEGES tp {};
        TOKEN_PRIVILEGES prevTp {};
        DWORD prevTpLen = 0;

        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

        // Try to enable SeLockMemoryPrivilege. Note that even if
        // AdjustTokenPrivileges() succeeds, we still need to query
        // GetLastError() to ensure that the privileges were actually obtained.
        if (AdjustTokenPrivileges(hProcessToken, FALSE, &tp,
                                  sizeof(TOKEN_PRIVILEGES), &prevTp,
                                  &prevTpLen) &&
            GetLastError() == ERROR_SUCCESS) {
            // Round up size to full pages and allocate
            allocSize = (allocSize + largePageSize - 1) &
                        ~size_t(largePageSize - 1);
            mem = VirtualAlloc(NULL, allocSize,
                               MEM_RESERVE | MEM_COMMIT | MEM_LARGE_PAGES,
                               PAGE_READWRITE);

            // Privilege no longer needed, restore previous state
            AdjustTokenPrivileges(hProcessToken, FALSE, &prevTp, 0, NULL, NULL);
        }
    }

    CloseHandle(hProcessToken);

    return mem;
}

void *aligned_large_pages_alloc(size_t allocSize)
{
    // Try to allocate large pages
    void *mem = aligned_large_pages_alloc_win(allocSize);

    // Fall back to regular, page aligned, allocation if necessary
    if (!mem)
        mem = VirtualAlloc(NULL, allocSize, MEM_RESERVE | MEM_COMMIT,
                           PAGE_READWRITE);

    return mem;
}

#else

void *aligned_large_pages_alloc(size_t allocSize)
{
#if defined(__linux__)
    size_t alignment = sysconf(_SC_PAGESIZE);
    if (alignment == (size_t)-1) {
        alignment = 4096;
    }
#else
    size_t alignment = sysconf(_SC_PAGESIZE);
    if (alignment == (size_t)-1) {
        alignment = 4096;
    }
#endif

    // round up to multiples of alignment
    size_t size = ((allocSize + alignment - 1) / alignment) * alignment;
    void *mem = std_aligned_alloc(alignment, size);
#if defined(MADV_HUGEPAGE)
    madvise(mem, size, MADV_HUGEPAGE);
#endif
    return mem;
}

#endif

/// aligned_large_pages_free() will free the previously allocated ttmem

#if defined(_WIN32)

void aligned_large_pages_free(void *mem)
{
    if (mem && !VirtualFree(mem, 0, MEM_RELEASE)) {
        DWORD err = GetLastError();
        std::cerr << "Failed to free transposition table. Error code: 0x"
                  << std::hex << err << std::dec << std::endl;
        exit(EXIT_FAILURE);
    }
}

#else

void aligned_large_pages_free(void *mem)
{
    std_aligned_free(mem);
}

#endif
#endif // ALIGNED_LARGE_PAGES

#ifdef _WIN32
#include <direct.h>
#define GETCWD _getcwd
#else
#include <unistd.h>
#define GETCWD getcwd
#endif
