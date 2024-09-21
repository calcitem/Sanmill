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

extern UCI::OptionsMap Options; // Global options map

TranspositionTable TT; // Global transposition table

// TTEntry implementation

bool TTEntry::is_occupied() const
{
    return depth8 != 0;
}

void TTEntry::save(Key k, Value v, Bound b, Depth d, uint8_t gen8)
{
    // Overwrite less valuable entries (cheapest checks first)
    if (b == BOUND_EXACT || uint16_t(k) != key16 ||
        d - DEPTH_ENTRY_OFFSET > depth8 || relative_age(gen8)) {
        assert(d > DEPTH_ENTRY_OFFSET);
        assert(d < 256 + DEPTH_ENTRY_OFFSET);

        key16 = uint16_t(k);
        depth8 = uint8_t(d - DEPTH_ENTRY_OFFSET);
        generation8 = gen8;
        bound8 = b;
        value16 = int16_t(v);
    }
}

uint8_t TTEntry::relative_age(uint8_t current_generation) const
{
    // Correctly handle cyclic nature of generation8
    return (current_generation - generation8);
}

// TTWriter implementation

TTWriter::TTWriter(TTEntry *tte)
    : entry(tte)
{ }

void TTWriter::write(Key k, Value v, Bound b, Depth d, uint8_t gen8)
{
    entry->save(k, v, b, d, gen8);
}

// TranspositionTable implementation

void TranspositionTable::resize(size_t mbSize)
{
    Threads.main()->wait_for_search_finished();

    aligned_large_pages_free(table);

    // Calculate the number of hash buckets ensuring it's a power of 2
    size_t desiredBuckets = (mbSize * 1024 * 1024) /
                            (sizeof(TTEntry) * BucketSize);
    size_t power = 1;
    while (power < desiredBuckets && power < MAX_BUCKET_COUNT)
        power <<= 1;
    bucketCount = power;

    // Allocate memory aligned to cache lines for better cache performance
    table = static_cast<TTEntry *>(
        aligned_large_pages_alloc(bucketCount * BucketSize * sizeof(TTEntry)));
    if (!table) {
        std::cerr << "Failed to allocate " << mbSize
                  << "MB for transposition table." << std::endl;
        exit(EXIT_FAILURE);
    }

    clear();
}

void TranspositionTable::clear()
{
    std::vector<std::thread> threads;
    size_t numThreads = Options["Threads"];

    // Launch threads to initialize the table in parallel
    for (size_t idx = 0; idx < numThreads; ++idx) {
        threads.emplace_back([this, idx, numThreads]() {
            // Bind thread to specific CPU core for cache affinity
            if (numThreads > 8)
                WinProcGroup::bindThisThread(idx);

            // Determine the range of buckets this thread will handle
            size_t stride = bucketCount / numThreads;
            size_t start = stride * idx;
            size_t end = (idx == numThreads - 1) ? bucketCount : start + stride;

            // Iterate over assigned buckets and zero-initialize entries
            for (size_t i = start; i < end; ++i) {
                TTEntry *bucket = &table[i * BucketSize];
                // Use memset for contiguous memory initialization
                std::memset(bucket, 0, sizeof(TTEntry) * BucketSize);
            }
        });
    }

    // Wait for all threads to complete initialization
    for (std::thread &th : threads)
        th.join();
}

int TranspositionTable::hashfull() const
{
    int cnt = 0;
    // Sample 1000 random entries to estimate hash table fullness
    for (int i = 0; i < 1000; ++i) {
        size_t index = mul_hi64(i, bucketCount); // Improved distribution
        TTEntry *bucket = &const_cast<TTEntry *>(table)[index * BucketSize];

        for (int j = 0; j < BucketSize; ++j) {
            const TTEntry &entry = bucket[j];
            if (entry.is_occupied() && entry.generation8 == generation8)
                cnt++;
        }
    }

    // Return the count scaled to permille (parts per thousand)
    return (cnt * 1000) / 1000; // Simplified for demonstration
}

void TranspositionTable::new_search()
{
    // Increment generation to age existing entries
    generation8++;
}

uint8_t TranspositionTable::generation() const
{
    return generation8;
}

std::tuple<bool, TTData, TTWriter>
TranspositionTable::probe(const Key key) const
{
    // Calculate the bucket index using bitmasking for power-of-2 bucketCount
    size_t index = mul_hi64(key, bucketCount);
    TTEntry *const bucket = &const_cast<TTEntry *>(table)[index * BucketSize];

    const uint16_t key16 = uint16_t(key); // Use the lower 16 bits of the key

    TTEntry *replace = nullptr;
    int min_replace_value = INT32_MAX;

    // Prefetch the entire bucket to minimize cache misses
    prefetch(reinterpret_cast<void *>(bucket));

    for (int i = 0; i < BucketSize; ++i) {
        TTEntry &entry = bucket[i];

        // Check for a matching key and occupied entry
        if (entry.key16 == key16 && entry.is_occupied()) {
            // Prefetch the next potential bucket to hide latency
            if (i + 1 < BucketSize)
                prefetch(reinterpret_cast<void *>(&bucket[i + 1]));
            return {true, entry.read(), TTWriter(&entry)};
        }

        // Determine the replace value based on depth and age for eviction
        // policy
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
    // Calculate the bucket index using bitmasking for power-of-2 bucketCount
    size_t index = mul_hi64(key, bucketCount);
    return &const_cast<TTEntry *>(table)[index * BucketSize];
}
