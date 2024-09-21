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

// Save data into the TTEntry
void TTEntry::save(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    // Assuming external synchronization or single-threaded writes
    // For multi-threaded environments, additional synchronization may be
    // required
    key = k;
    value = v;
    depth = d;
    bound = b;
    generation = gen;
}

// Calculate relative age for aging mechanism
uint8_t TTEntry::relative_age(uint8_t current_generation) const
{
    return static_cast<uint8_t>(current_generation - generation);
}

// TTWriter write function
void TTWriter::write(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    // Save data to the TTEntry
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
    table = nullptr;
    entryCount = 0;

    // Calculate the number of entries, ensuring it's a power of two
    size_t desiredEntries = (mbSize * 1024 * 1024) / sizeof(TTEntry);
    size_t power_of_two = 1;
    while (power_of_two < desiredEntries) {
        power_of_two <<= 1;
    }
    entryCount = power_of_two;

    // Allocate memory aligned to cache lines for better performance
    table = static_cast<TTEntry *>(
        aligned_large_pages_alloc(entryCount * sizeof(TTEntry)));

    if (!table) {
        std::cerr << "Failed to allocate " << mbSize
                  << "MB for transposition table." << std::endl;
        std::exit(EXIT_FAILURE);
    }

    // Initialize the TT by clearing all entries
    clear();
}

// Clear all TTEntries by setting them to zero
void TranspositionTable::clear()
{
    if (table) {
        std::memset(table, 0, entryCount * sizeof(TTEntry));
    }
}

// Estimate the fill rate of the TT by sampling
int TranspositionTable::hashfull() const
{
    constexpr size_t sampled = 1000;
    size_t occupied = 0;
    uint8_t current_generation = generation_.load(std::memory_order_relaxed);

    for (size_t i = 0; i < sampled; ++i) {
        size_t index = (i * 1024) & (entryCount - 1); // Use bitmask for
                                                      // power-of-two table size
        const TTEntry &entry = table[index];

        if (entry.is_occupied() && entry.generation == current_generation) {
            ++occupied;
        }
    }

    // Return the percentage of occupied sampled entries
    return static_cast<int>((occupied * 100) / sampled);
}

// Start a new search by incrementing the generation atomically
void TranspositionTable::new_search()
{
    // Atomic increment with wrap-around handled by std::atomic<uint8_t>
    generation_.fetch_add(1, std::memory_order_relaxed);
}

// Get the current generation value atomically
uint8_t TranspositionTable::generation() const
{
    return generation_.load(std::memory_order_relaxed);
}

// Probe the TT for a given key
std::tuple<bool, TTData, TTWriter> TranspositionTable::probe(const Key key)
{
    // Calculate the index using bitmask for power-of-two table size
    size_t index = key & (entryCount - 1);
    TTEntry &entry = table[index];

    // Prefetch the entry to reduce cache miss latency
    __builtin_prefetch(&table[index], 0, 3);

    uint8_t current_generation = generation_.load(std::memory_order_relaxed);

    // Check for a matching key and if the entry is valid for the current
    // generation
    if (entry.key == key && entry.is_occupied() &&
        entry.generation == current_generation) {
        // Read the TTData
        TTData data = entry.read();
        // Return a writer for potential replacement
        TTWriter writer(&entry);
        return {true, data, writer};
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
