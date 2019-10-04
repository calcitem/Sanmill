//----------------------------------------------------------------
// Statically-allocated memory manager
//
// by Eli Bendersky (eliben@gmail.com)
// Adapted by Calcitem to the Mill Game (Calcitem <calcitem@outlook.com>)
//
// This code is in the public domain.
//----------------------------------------------------------------
#include <cstdio>
#include <cassert>
#include <cstdlib>

#include "memmgr.h"

void MemoryManager::memmgr_init()
{
    pool = static_cast<uint8_t *>(malloc(POOL_SIZE));
    base.s.next = nullptr;
    base.s.size = 0;
    freep = nullptr;
    pool_free_pos = 0;
}

void MemoryManager::memmgr_exit()
{
    free(pool);
}

void MemoryManager::memmgr_print_stats()
{
    #ifdef DEBUG_MEMMGR_SUPPORT_STATS
    mem_header_t* p;

    printf("------ Memory manager stats ------\n\n");
    printf(    "Pool: free_pos = %llu (%llu bytes left)\n\n",
            pool_free_pos, POOL_SIZE - pool_free_pos);

    p = (mem_header_t*) pool;

    while (p < (mem_header_t*) (pool + pool_free_pos))
    {
        if (p->s.size == 0)
        {
            printf("ERROR: p->s.size == 0\n");
            break;
        }

        printf(    "  * Addr: %p; Size: %16llu\n",
                p, p->s.size);

        p += p->s.size;
    }

    printf("\nFree list:\n\n");

    if (freep)
    {
        p = freep;

        while (1)
        {
            printf(    "  * Addr: %p; Size: %16llu; Next: %p\n",
                    p, p->s.size, p->s.next);

            p = p->s.next;

            if (p == freep)
                break;

            if (p == nullptr) {
                printf("ERROR: p == nullptr\n");
                break;
            }
        }
    }
    else
    {
        printf("Empty\n");
    }

    printf("\n");
    #endif // DEBUG_MEMMGR_SUPPORT_STATS
}

mem_header_t* MemoryManager::get_mem_from_pool(size_t nquantas)
{
    size_t total_req_size;

    mem_header_t* h;

    if (nquantas < MIN_POOL_ALLOC_QUANTAS)
        nquantas = MIN_POOL_ALLOC_QUANTAS;

    total_req_size = nquantas * sizeof(mem_header_t);

    if (pool_free_pos + total_req_size <= POOL_SIZE)
    {
        h = (mem_header_t*)(pool + pool_free_pos);
        h->s.size = nquantas;
        memmgr_free((void*)(h + 1));
        pool_free_pos += total_req_size;
    }
    else
    {
        return nullptr;
    }

    return freep;
}


// Allocations are done in 'quantas' of header size.
// The search for a free block of adequate size begins at the point 'freep'
// where the last block was found.
// If a too-big block is found, it is split and the tail is returned (this
// way the header of the original needs only to have its size adjusted).
// The pointer returned to the user points to the free space within the block,
// which begins one quanta after the header.
//
void* MemoryManager::_memmgr_alloc(size_t nbytes)
{
    mem_header_t* p;
    mem_header_t* prevp;

    // Calculate how many quantas are required: we need enough to house all
    // the requested bytes, plus the header. The -1 and +1 are there to make sure
    // that if nbytes is a multiple of nquantas, we don't allocate too much
    //
    size_t nquantas = (nbytes + sizeof(mem_header_t) - 1) / sizeof(mem_header_t) + 1;

    // First alloc call, and no free list yet ? Use 'base' for an initial
    // denegerate block of size 0, which points to itself
    //
    if ((prevp = freep) == nullptr)
    {
        base.s.next = freep = prevp = &base;
        base.s.size = 0;
    }

    for (p = prevp->s.next; ; prevp = p, p = p->s.next)
    {
        // big enough ?
        if (p->s.size >= nquantas)
        {
            // exactly ?
            if (p->s.size == nquantas)
            {
                // just eliminate this block from the free list by pointing
                // its prev's next to its next
                //
                prevp->s.next = p->s.next;
            }
            else // too big
            {
                p->s.size -= nquantas;
                p += p->s.size;
                p->s.size = nquantas;
            }

            freep = prevp;
            return (void*)(p + 1);
        }
        // Reached end of free list ?
        // Try to allocate the block from the pool. If that succeeds,
        // get_mem_from_pool adds the new block to the free list and
        // it will be found in the following iterations. If the call
        // to get_mem_from_pool doesn't succeed, we've run out of
        // memory
        //
        else if (p == freep)
        {
            if ((p = get_mem_from_pool(nquantas)) == nullptr)
            {
                #ifdef DEBUG_MEMMGR_FATAL
                printf("!! Memory allocation failed !!\n");
                #endif
                return nullptr;
            }
        }
    }
}


// Scans the free list, starting at freep, looking the the place to insert the
// free block. This is either between two existing blocks or at the end of the
// list. In any case, if the block being freed is adjacent to either neighbor,
// the adjacent blocks are combined.
//
void MemoryManager::memmgr_free(void* ap)
{
    mem_header_t* block;
    mem_header_t* p;

    // acquire pointer to block header
    block = ((mem_header_t*) ap) - 1;

    // Find the correct place to place the block in (the free list is sorted by
    // address, increasing order)
    //
    for (p = freep; !(block > p && block < p->s.next); p = p->s.next)
    {
        // Since the free list is circular, there is one link where a
        // higher-addressed block points to a lower-addressed block.
        // This condition checks if the block should be actually
        // inserted between them
        //
        if (p >= p->s.next && (block > p || block < p->s.next))
            break;
    }

    // Try to combine with the higher neighbor
    //
    if (block + block->s.size == p->s.next)
    {
        block->s.size += p->s.next->s.size;
        block->s.next = p->s.next->s.next;
    }
    else
    {
        block->s.next = p->s.next;
    }

    // Try to combine with the lower neighbor
    //
    if (p + p->s.size == block)
    {
        p->s.size += block->s.size;
        p->s.next = block->s.next;
    }
    else
    {
        p->s.next = block;
    }

    freep = p;
}

void * MemoryManager::__builtin_memalign(int align, size_t len)
{
    uint8_t *mem, *newmem;
    mem_header_t *mem_block;
    mem_header_t *new_block;

    if ((align & -align) != align) {
        return nullptr;
    }

    if (align <= sizeof(union mem_header_union)) {
        mem = (uint8_t *)_memmgr_alloc(len);
        if (!mem)
            return 0;
        return mem;
    }

    mem = (uint8_t *)_memmgr_alloc(len + align - 1);
    if (!mem)
        return nullptr;

    newmem = (uint8_t *)((uint64_t)mem + align - 1 & -align);   // TODO: uint64_t
    if (newmem == mem) return mem;

    mem_block = ((mem_header_t *)mem) - 1;
    new_block = ((mem_header_t *)newmem) - 1;
    new_block->s.size = len;
    mem_block->s.size = newmem - mem;

    memmgr_free(mem);
    return newmem;
}

void *MemoryManager::memmgr_alloc_with_align(size_t len, int align)
{
    return __builtin_memalign(align, len);
}

void *MemoryManager::memmgr_alloc(size_t nbytes)
{
    return memmgr_alloc_with_align(nbytes, 4);
}


///////////////

// A rudimentary test of the memory manager.
// Runs assuming default flags in memmgr.h:
//
// #define POOL_SIZE 8 * 1024
// #define MIN_POOL_ALLOC_QUANTAS 16
//
// And a 32-bit machine (sizeof(unsigned long) == 4)
//
void MemoryManager::test_memmgr()
{
    uint8_t *p[30] = {nullptr};
    int i;

    memmgr_init();

    // Each header uses 8 bytes, so this allocates
    // 3 * (2048 + 8) = 6168 bytes, leaving us
    // with 8192 - 6168 = 2024
    //
    for (i = 0; i < 3; ++i)
    {
        p[i] = (uint8_t *)memmgr_alloc(2048);
        assert(p[i]);
    }

    // Allocate all the remaining memory
    //
    p[4] = (uint8_t *)memmgr_alloc(2016);
    assert(p[4]);

    // Nothing left...
    //
    p[5] = (uint8_t *)memmgr_alloc(1);
    assert(p[5] == nullptr);

    // Release the second block. This frees 2048 + 8 bytes.
    //
    memmgr_free(p[1]);
    p[1] = nullptr;

    // Now we can allocate several smaller chunks from the
    // free list. There, they can be smaller than the
    // minimal allocation size.
    // Allocations of 100 require 14 quantas (13 for the
    // requested space, 1 for the header). So it allocates
    // 112 bytes. We have 18 allocations to make:
    //
    for (i = 10; i < 28; ++i)
    {
        p[i] = (uint8_t *)memmgr_alloc(100);
        assert(p[i]);
    }

    // Not enough for another one...
    //
    p[28] = (uint8_t *)memmgr_alloc(100);
    assert(p[28] == nullptr);

    // Now free everything
    //
    for (i = 0; i < 30; ++i)
    {
        if (p[i])
            memmgr_free(p[i]);
    }

    memmgr_print_stats();
}

