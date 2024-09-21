#include "tt.h"

#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>
#include <thread>

#include "memory.h"
#include "misc.h"
#include "thread.h"
#include "uci.h"

extern UCI::OptionsMap Options; // Global object

TranspositionTable TT; // Our global transposition table

// TTEntry struct is the 11 bytes transposition table entry, defined as below:
//
// key        16 bit
// value      16 bit
// depth       8 bit
// generation   8 bit
// bound       8 bit
//
// These fields are in the same order as accessed by TT::probe(), since memory
// is fastest sequentially. Equally, the store order in save() matches this
// order.

struct TTEntry
{
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
    // The returned age is a multiple of TranspositionTable::GENERATION_DELTA
    uint8_t relative_age(uint8_t current_generation) const;

private:
    friend class TranspositionTable;

    uint16_t key16;
    int16_t value16;
    uint8_t depth8;
    uint8_t generation8;
    Bound bound8;
};

// DEPTH_ENTRY_OFFSET exists because 1) we use `bool(depth8)` as the occupancy
// check, but 2) we need to store negative depths for QS. (`depth8` is the only
// field with "spare bits": we sacrifice the ability to store depths greater
// than 1<<8 less the offset, as asserted in `save`.)
bool TTEntry::is_occupied() const
{
    return depth8 != 0;
}

// Populates the TTEntry with a new node's data, possibly
// overwriting an old position. The update is not atomic and can be racy.
void TTEntry::save(Key k, Value v, Bound b, Depth d, uint8_t generation8)
{
    // Overwrite less valuable entries (cheapest checks first)
    if (b == BOUND_EXACT || uint16_t(k) != key16 ||
        d - DEPTH_ENTRY_OFFSET > depth8 || relative_age(generation8)) {
        assert(d > DEPTH_ENTRY_OFFSET);
        assert(d < 256 + DEPTH_ENTRY_OFFSET);

        key16 = uint16_t(k);
        depth8 = uint8_t(d - DEPTH_ENTRY_OFFSET);
        this->generation8 = generation8;
        bound8 = b;
        value16 = int16_t(v);
    }
}

uint8_t TTEntry::relative_age(uint8_t current_generation) const
{
    // Due to the cyclic nature of generation8, calculate the relative age
    // correctly
    return (current_generation - generation8);
}

// TTWriter is a thin wrapper around the pointer
TTWriter::TTWriter(TTEntry *tte)
    : entry(tte)
{ }

void TTWriter::write(Key k, Value v, Bound b, Depth d, uint8_t generation8)
{
    entry->save(k, v, b, d, generation8);
}

// A TranspositionTable is a flat array of TTEntry.
// Each TTEntry contains information on exactly one position.
// The size of the TranspositionTable should be a power of 2 for optimal
// hashing.

/// TranspositionTable::resize() sets the size of the transposition table,
/// measured in megabytes. Transposition table consists of a power of 2 number
/// of TTEntry * BucketSize.

void TranspositionTable::resize(size_t mbSize)
{
    Threads.main()->wait_for_search_finished();

    aligned_large_pages_free(table);

    // Calculate the number of hash buckets
    bucketCount = (mbSize * 1024 * 1024) / (sizeof(TTEntry) * BucketSize);

    // Ensure bucketCount is a power of 2 for optimal hashing
    // If not, adjust it to the next power of 2
    size_t originalBucketCount = bucketCount;
    size_t power = 1;
    while (power < bucketCount)
        power <<= 1;
    bucketCount = power;

    table = static_cast<TTEntry *>(
        aligned_large_pages_alloc(bucketCount * BucketSize * sizeof(TTEntry)));
    if (!table) {
        std::cerr << "Failed to allocate " << mbSize
                  << "MB for transposition table." << std::endl;
        exit(EXIT_FAILURE);
    }

    clear();
}

/// TranspositionTable::clear() initializes the entire transposition table to
/// zero, in a multi-threaded way.

void TranspositionTable::clear()
{
    std::vector<std::thread> threads;

    for (size_t idx = 0; idx < Options["Threads"]; ++idx) {
        threads.emplace_back([this, idx]() {
            // Thread binding gives faster search on systems with a first-touch
            // policy
            if (Options["Threads"] > 8)
                WinProcGroup::bindThisThread(idx);

            // Each thread will zero its part of the hash table
            const size_t stride = bucketCount / Options["Threads"];
            const size_t start = stride * idx;
            const size_t end = (idx == Options["Threads"] - 1) ? bucketCount :
                                                                 start + stride;

            for (size_t i = start; i < end; ++i) {
                for (int j = 0; j < BucketSize; ++j) {
                    std::memset(&table[i * BucketSize + j], 0, sizeof(TTEntry));
                }
            }
        });
    }

    for (std::thread &th : threads)
        th.join();
}

// Returns an approximation of the hashtable
// occupation during a search. The hash is x permille full, as per UCI protocol.
// Only counts entries which match the current generation.
int TranspositionTable::hashfull() const
{
    int cnt = 0;
    for (int i = 0; i < 1000; ++i) {
        size_t index = i % bucketCount; // Ensure index is within bucketCount
        for (int j = 0; j < BucketSize; ++j) {
            const TTEntry &entry = table[index * BucketSize + j];
            if (entry.is_occupied() && entry.generation8 == generation8)
                cnt++;
        }
    }

    return cnt / BucketSize;
}

void TranspositionTable::new_search()
{
    // Increment generation to track aging
    generation8++;
}

uint8_t TranspositionTable::generation() const
{
    return generation8;
}

// Looks up the current position in the transposition
// table. It returns true if the position is found.
// Otherwise, it returns false and a pointer to an empty or least valuable
// TTEntry to be replaced later. The replace value of an entry is calculated as
// its depth minus its age. TTEntry t1 is considered more
// valuable than TTEntry t2 if its replace value is greater than that of t2.
std::tuple<bool, TTData, TTWriter>
TranspositionTable::probe(const Key key) const
{
    TTEntry *const tte = first_entry(key);
    const uint16_t key16 = uint16_t(key); // Use the low 16 bits as key

    TTEntry *replace = nullptr;
    int min_replace_value = INT32_MAX;

    for (int i = 0; i < BucketSize; ++i) {
        TTEntry &entry = tte[i];
        if (entry.key16 == key16 && entry.is_occupied()) {
            // This gap is the main place for read races.
            // After `read()` completes that copy is final, but may be
            // self-inconsistent.
            return {true, entry.read(), TTWriter(&entry)};
        }

        // Calculate replace value based on depth and age
        int replace_value = entry.depth8 - entry.relative_age(generation8) * 2;
        if (replace_value < min_replace_value) {
            min_replace_value = replace_value;
            replace = &entry;
        }
    }

    // If no exact match found, return the least valuable entry to replace
    return {false, TTData(), TTWriter(replace)};
}

TTEntry *TranspositionTable::first_entry(const Key key) const
{
    // Simple modulo-based hashing using higher bits for better distribution
    size_t index = mul_hi64(key, bucketCount);
    return &const_cast<TTEntry *>(table)[index * BucketSize];
}
