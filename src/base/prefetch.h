/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#ifndef PREFETCH_H
#define PREFETCH_H

#include "config.h"

/*
    prefetch(x) attempts to pre-emptively get the memory pointed to
    by address "x" into the CPU L1 cache.
    prefetch(x) should not cause any kind of exception, prefetch(0) is
    specifically ok.

    prefetch() should be defined by the architecture, if not, the
    #define below provides a no-op define.

    There are 2 prefetch() macros:

    prefetch(x)  	- prefetches the cacheline at "x" for read
    prefetchw(x)	- prefetches the cacheline at "x" for write

    there is also PREFETCH_STRIDE which is the architecure-preferred
    "lookahead" size for prefetching streamed operations.

*/

/* L1 cache line size */
#define L1_CACHE_SHIFT	12
#define L1_CACHE_BYTES	(1 << L1_CACHE_SHIFT)

static inline void prefetch(void *addr)
{
#if defined(__INTEL_COMPILER)
    // This hack prevents prefetches from being optimized away by
    // Intel compiler. Both MSVC and gcc seem not be affected by this.
    __asm__("");
#endif

#if defined(__INTEL_COMPILER) || defined(_MSC_VER)
    _mm_prefetch((char *)addr, _MM_HINT_T0);
#else
    __builtin_prefetch(addr);
#endif
}

#if 0
#define prefetch(x) __builtin_prefetch(x)

#define prefetchw(x) __builtin_prefetch(x,1)
#endif

#ifndef PREFETCH_STRIDE
#define PREFETCH_STRIDE (4 * L1_CACHE_BYTES)
#endif

static inline void prefetch_range(void *addr, size_t len)
{
    char *cp;
    char *end = (char *)addr + len;

    for (cp = (char *)addr; cp < end; cp += PREFETCH_STRIDE)
        prefetch(cp);
}

#endif // PREFETCH_H
