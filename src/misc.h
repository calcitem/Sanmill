// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// misc.h

#ifndef MISC_H_INCLUDED
#define MISC_H_INCLUDED

#include <cassert>
#include <chrono>
#include <cstdint>
#include <ostream>
#include <string>
#include <vector>

#include "types.h"

std::string engine_info(bool to_uci = false);
std::string compiler_info();
void prefetch(void *addr);
void prefetch_range(void *addr, size_t len);
void start_logger(const std::string &fname);
void *std_aligned_alloc(size_t alignment, size_t size);
void std_aligned_free(void *ptr);
#ifdef ALIGNED_LARGE_PAGES
// memory aligned by page size, min alignment: 4096 bytes
void *aligned_large_pages_alloc(size_t allocSize);

// nop if mem == nullptr
void aligned_large_pages_free(void *mem);
#endif // ALIGNED_LARGE_PAGES

void dbg_hit_on(bool b) noexcept;
void dbg_hit_on(bool c, bool b) noexcept;
void dbg_mean_of(int v) noexcept;
void dbg_print();

using TimePoint = std::chrono::milliseconds::rep; // A value in milliseconds

static_assert(sizeof(TimePoint) == sizeof(int64_t), "TimePoint should be 64 "
                                                    "bits");

inline TimePoint now()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

template <class Entry, int Size>
struct HashTable
{
    Entry *operator[](Key key) { return &table[key & (Size - 1)]; }

private:
    std::vector<Entry> table = std::vector<Entry>(Size); // Allocate on the heap
};

enum SyncCout { IO_LOCK, IO_UNLOCK };

std::ostream &operator<<(std::ostream &, SyncCout);

// TODO: Revisit the synchronization mechanism for output handling. Current
// Work around bypasses synchronization on Apple devices due to unresolved
// hanging issues in debug mode on iPad. Consider investigating the root
// cause and implementing a more robust synchronization strategy that
// works uniformly across all platforms.
#ifdef __APPLE__
#define sync_cout std::cout
#define sync_endl std::endl
#else
#define sync_cout std::cout << IO_LOCK
#define sync_endl std::endl << IO_UNLOCK
#endif

// `ptr` must point to an array of size at least
// `sizeof(T) * N + alignment` bytes, where `N` is the
// number of elements in the array.
template <uintptr_t Alignment, typename T>
T *align_ptr_up(T *ptr)
{
    static_assert(alignof(T) < Alignment);

    const uintptr_t ptrint = reinterpret_cast<uintptr_t>(
        reinterpret_cast<char *>(ptr));
    return reinterpret_cast<T *>(reinterpret_cast<char *>(
        (ptrint + (Alignment - 1)) / Alignment * Alignment));
}

/// xorshift64star Pseudo-Random Number Generator
/// This class is based on original code written and dedicated
/// to the public domain by Sebastiano Vigna (2014).
/// It has the following characteristics:
///
///  -  Outputs 64-bit numbers
///  -  Passes Dieharder and SmallCrush test batteries
///  -  Does not require warm-up, no zeroland to escape
///  -  Internal state is a single 64-bit integer
///  -  Period is 2^64 - 1
///  -  Speed: 1.60 ns/call (Core i7 @3.40GHz)
///
/// For further analysis see
///   <http://vigna.di.unimi.it/ftp/papers/xorshift.pdf>

class PRNG
{
    uint64_t s;

    uint64_t rand64()
    {
        s ^= s >> 12;
        s ^= s << 25;
        s ^= s >> 27;
        return s * 2685821657736338717LL;
    }

public:
    explicit PRNG(uint64_t seed)
        : s(seed)
    {
        assert(seed);
    }

    template <typename T>
    T rand()
    {
        return T(rand64());
    }

    /// Special generator used to fast init magic numbers.
    /// Output values only have 1/8th of their bits set on average.
    template <typename T>
    T sparse_rand()
    {
        return T(rand64() & rand64() & rand64());
    }
};

constexpr uint64_t mul_hi64(uint64_t a, uint64_t b)
{
#if defined(__GNUC__) && defined(IS_64BIT)
    __extension__ using uint128 = unsigned __int128;
    return (uint128(a) * uint128(b)) >> 64;
#else
    const uint64_t aL = static_cast<uint32_t>(a), aH = a >> 32;
    const uint64_t bL = static_cast<uint32_t>(b), bH = b >> 32;
    const uint64_t c1 = (aL * bL) >> 32;
    const uint64_t c2 = aH * bL + c1;
    const uint64_t c3 = aL * bH + static_cast<uint32_t>(c2);
    return aH * bH + (c2 >> 32) + (c3 >> 32);
#endif
}

/// Under Windows it is not possible for a process to run on more than one
/// logical processor group. This usually means to be limited to use max 64
/// cores. To overcome this, some special platform specific API should be
/// called to set group affinity for each thread. Original code from Texel by
/// Peter A-terlund.

namespace WinProcGroup {
void bindThisThread(size_t idx);
}

#endif // #ifndef MISC_H_INCLUDED
