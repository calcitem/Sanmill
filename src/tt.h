#ifndef TT_H_INCLUDED
#define TT_H_INCLUDED

#include <cstddef>
#include <cstdint>
#include <tuple>

#include "memory.h"
#include "misc.h"
#include "types.h"

class ThreadPool;
struct TTEntry;

// Fixed number of TTEntry per hash bucket
static constexpr int BucketSize = 4;

// Align TTEntry to cache lines (typically 64 bytes) to prevent false sharing
static constexpr size_t CACHE_LINE_SIZE = 64;

// Ensure bucketCount is a power of 2 for optimal hashing and masking
static constexpr size_t MAX_BUCKET_COUNT = 1 << 30; // Example maximum

// There is only one global hash table for the engine and all its threads. For
// chess in particular, we even allow racy updates between threads to and from
// the TT, as taking the time to synchronize access would cost thinking time and
// thus elo. As a hash table, collisions are possible and may cause chess
// playing issues (bizarre blunders, faulty mate reports, etc). Fixing these
// also loses elo; however such risk decreases quickly with larger TT size.
//
// `probe` is the primary method: given a board position, we lookup its entry in
// the table, and return a tuple of:
//   1) whether the entry already has this position
//   2) a copy of the prior data (if any) (may be inconsistent due to read
//   races) 3) a writer object to this entry
// The copied data and the writer are separated to maintain clear boundaries
// between local vs global objects.

// A copy of the data already in the entry (possibly collided). `probe` may be
// racy, resulting in inconsistent data.
struct TTData
{
    Value value;
    Depth depth;
    Bound bound;
};

// Transposition table entry structure optimized for cache alignment and minimal
// padding
struct alignas(CACHE_LINE_SIZE) TTEntry
{
    uint16_t key16;      // 16-bit key for position identification
    uint8_t depth8;      // 8-bit search depth
    uint8_t generation8; // 8-bit generation for aging
    Bound bound8;        // 8-bit bound type
    int16_t value16;     // 16-bit evaluation value
    uint8_t padding[2]; // Padding to make the struct size a multiple of 8 bytes

    // Convert internal bitfields to external types
    TTData read() const
    {
        return TTData {
            Value(value16),
            Depth(depth8 + DEPTH_ENTRY_OFFSET),
            Bound(bound8),
        };
    }

    bool is_occupied() const;
    void save(Key k, Value v, Bound b, Depth d, uint8_t generation8);
    uint8_t relative_age(uint8_t current_generation) const;
};

// Wrapper for writing to a TTEntry, ensuring separation of concerns
struct TTWriter
{
public:
    void write(Key k, Value v, Bound b, Depth d, uint8_t generation8);

private:
    friend class TranspositionTable;
    TTEntry *entry;

    // Constructor is private to control access
    TTWriter(TTEntry *tte);
};

// TranspositionTable class optimized for cache-friendly access patterns
class TranspositionTable
{
public:
    ~TranspositionTable() { aligned_large_pages_free(table); }

    void resize(size_t mbSize); // Set TT size
    void clear();               // Re-initialize memory, multithreaded
    int hashfull() const;       // Approximate fraction of entries used

    void new_search();          // Initialize a new search
    uint8_t generation() const; // Current generation for aging
    std::tuple<bool, TTData, TTWriter> probe(const Key key) const; // Main
                                                                   // lookup
                                                                   // method
    TTEntry *first_entry(const Key key) const; // Get the first entry in the
                                               // bucket

private:
    friend struct TTEntry;

    size_t bucketCount; // Number of hash buckets, must be a power of 2
    TTEntry *table = nullptr;

    uint8_t generation8 = 0; // Current generation for aging
};

extern TranspositionTable TT; // Global transposition table

#endif // TT_H_INCLUDED
