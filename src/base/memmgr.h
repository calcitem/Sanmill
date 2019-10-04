//----------------------------------------------------------------
// Statically-allocated memory manager
//
// by Eli Bendersky (eliben@gmail.com)
// Adapted by Calcitem to the Mill Game (Calcitem <calcitem@outlook.com>)
//  
// This code is in the public domain.
//----------------------------------------------------------------
#ifndef MEMMGR_H
#define MEMMGR_H

//
// Memory manager: dynamically allocates memory from 
// a fixed pool that is allocated statically at link-time.
// 
// Usage: after calling memmgr_init() in your 
// initialization routine, just use memmgr_alloc() instead
// of malloc() and memmgr_free() instead of free().
// Naturally, you can use the preprocessor to define 
// malloc() and free() as aliases to memmgr_alloc() and 
// memmgr_free(). This way the manager will be a drop-in 
// replacement for the standard C library allocators, and can
// be useful for debugging memory allocation problems and 
// leaks.
//
// Preprocessor flags you can define to customize the 
// memory manager:
//
// DEBUG_MEMMGR_FATAL
//    Allow printing out a message when allocations fail
//
// DEBUG_MEMMGR_SUPPORT_STATS
//    Allow printing out of stats in function 
//    memmgr_print_stats When this is disabled, 
//    memmgr_print_stats does nothing.
//
// Note that in production code on an embedded system 
// you'll probably want to keep those undefined, because
// they cause printf to be called.
//
// POOL_SIZE
//    Size of the pool for new allocations. This is 
//    effectively the heap size of the application, and can 
//    be changed in accordance with the available memory 
//    resources.
//
// MIN_POOL_ALLOC_QUANTAS
//    Internally, the memory manager allocates memory in
//    quantas roughly the size of two ulong objects. To
//    minimize pool fragmentation in case of multiple allocations
//    and deallocations, it is advisable to not allocate
//    blocks that are too small.
//    This flag sets the minimal ammount of quantas for 
//    an allocation. If the size of a ulong is 4 and you
//    set this flag to 16, the minimal size of an allocation
//    will be 4 * 2 * 16 = 128 bytes
//    If you have a lot of small allocations, keep this value
//    low to conserve memory. If you have mostly large 
//    allocations, it is best to make it higher, to avoid 
//    fragmentation.
//
// Notes:
// 1. This memory manager is *not thread safe*. Use it only
//    for single thread/task applications.
// 

#include <cstdint>

#define DEBUG_MEMMGR_SUPPORT_STATS 1

typedef unsigned long Align;

union mem_header_union
{
    struct
    {
        // Pointer to the next block in the free list
        //
        union mem_header_union *next;

        // Size of the block (in quantas of sizeof(mem_header_t))
        //
        size_t size;
    } s;

    // Used to align headers in memory to a boundary
    //
    Align align_dummy;
};

typedef union mem_header_union mem_header_t;

class MemoryManager
{
public:
    // Initialize the memory manager. This function should be called
    // only once in the beginning of the program.
    void memmgr_init();

    // Exit
    void memmgr_exit();

    // 'malloc' clone
    void *memmgr_alloc(size_t nbytes);

    // 'free' clone
    void memmgr_free(void *ap);

    // Prints statistics about the current state of the memory
    // manager
    void memmgr_print_stats();

    // test
    void test_memmgr();

protected:
private:
    static const int POOL_SIZE = 1024 * 1024;
    static const int MIN_POOL_ALLOC_QUANTAS = 1024;

    // Initial empty list
    mem_header_t base;

    // Start of free list
    mem_header_t *freep = 0;

    // pool for new allocations
    uint8_t *pool;
    size_t pool_free_pos = 0;

    void *_memmgr_alloc(size_t nbytes);
    mem_header_t *get_mem_from_pool(size_t nquantas);
    void *__builtin_memalign(int align, size_t len);
    void *memmgr_alloc_with_align(size_t len, int align);

};

#endif // MEMMGR_H
