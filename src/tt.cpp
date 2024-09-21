#include "tt.h"

#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <thread>

#include "memory.h"
#include "misc.h"
#include "thread.h"
#include "uci.h"

// External UCI options map
extern UCI::OptionsMap Options;

// Global TranspositionTable instance
TranspositionTable TT;

// Check if a TTEntry is occupied based on depth
bool TTEntry::is_occupied() const
{
    return depth != 0;
}

// Save data into the TTEntry atomically
void TTEntry::save(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    // Assuming single-threaded writes or external synchronization
    key = k;
    value = v;
    depth = d;
    bound = b;
    generation = gen;
}

// Calculate relative age for aging mechanism
uint8_t TTEntry::relative_age(uint8_t current_generation) const
{
    return current_generation - generation;
}

// TTWriter write function
void TTWriter::write(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    entry->save(k, v, b, d, gen);
}

// Destructor to free allocated memory
TranspositionTable::~TranspositionTable()
{
    aligned_large_pages_free(table);
}

// Resize the TT to the specified size in megabytes
void TranspositionTable::resize(size_t mbSize)
{
    // Wait for all threads to finish current search to avoid data races
    Threads.main()->wait_for_search_finished();

    // Free existing TT memory
    aligned_large_pages_free(table);

    // Ensure the TT size is a power of two for efficient indexing
    size_t power_of_two = 1;
    while (power_of_two < (mbSize * 1024 * 1024) / sizeof(TTEntry)) {
        power_of_two <<= 1;
    }
    entryCount = power_of_two;

    // Allocate memory aligned to cache lines for better performance
    table = static_cast<TTEntry *>(
        aligned_large_pages_alloc(entryCount * sizeof(TTEntry)));

    if (!table) {
        std::cerr << "Failed to allocate " << mbSize
                  << "MB for transposition table." << std::endl;
        exit(EXIT_FAILURE);
    }

    // Initialize the TT by clearing all entries
    clear();
}

// Clear all TTEntries by setting them to zero
void TranspositionTable::clear()
{
    std::memset(table, 0, entryCount * sizeof(TTEntry));
}

// Estimate the fill rate of the TT by sampling
int TranspositionTable::hashfull() const
{
    size_t sampled = 1000;
    size_t occupied = 0;

    for (size_t i = 0; i < sampled; ++i) {
        size_t index = (i * 1024) & (entryCount - 1); // Use bitmask for
                                                      // power-of-two
        const TTEntry &entry = table[index];

        if (entry.is_occupied() && entry.generation == generation_) {
            ++occupied;
        }
    }

    // Return the percentage of occupied sampled entries
    return static_cast<int>((occupied * 100) / sampled);
}

// Start a new search by incrementing the generation atomically
void TranspositionTable::new_search()
{
    generation_++;
}

// Get the current generation value atomically
uint8_t TranspositionTable::generation() const
{
    return generation_;
}

// Probe the TT for a given key
std::tuple<bool, TTData, TTWriter> TranspositionTable::probe(const Key key)
{
    // Calculate the index using bitmask for power-of-two table size
    size_t index = key & (entryCount - 1);
    TTEntry &entry = table[index];

    // Prefetch the entry to reduce cache miss latency
    __builtin_prefetch(&table[index], 0, 3);

    // Check for a matching key and if the entry is valid for the current
    // generation
    if (entry.key == key && entry.is_occupied() &&
        entry.generation == generation_) {
        return {true, entry.read(), TTWriter(&entry)};
    }

    // No match found; return a writer for potential replacement
    return {false, TTData(), TTWriter(&entry)};
}

// Retrieve the first TTEntry for a given key
TTEntry *TranspositionTable::first_entry(const Key key) const
{
    size_t index = key & (entryCount - 1);
    return const_cast<TTEntry *>(&table[index]);
}
