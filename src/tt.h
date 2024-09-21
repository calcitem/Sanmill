#ifndef TT_H_INCLUDED
#define TT_H_INCLUDED

#include <cstddef>
#include <cstdint>
#include <tuple>
#include <atomic>
#include <memory>

#include "memory.h"
#include "misc.h"
#include "types.h"

class ThreadPool;

// Constants
static constexpr size_t CACHE_LINE_SIZE = 64;
static constexpr size_t DEFAULT_TT_MB_SIZE = 256; // Default TT size in MB

// Struct to hold the data retrieved from the TT
struct TTData
{
    Value value;
    Depth depth;
    Bound bound;
};

// Aligned TTEntry to prevent false sharing and improve cache performance
struct alignas(CACHE_LINE_SIZE) TTEntry
{
    Key key;            // 64-bit Zobrist hash key
    Value value;        // 32-bit evaluation value
    Depth depth;        // 8-bit search depth
    Bound bound;        // 8-bit bound type
    uint8_t generation; // 8-bit generation for aging
    uint8_t padding; // Padding to align the structure to a multiple of 8 bytes

    // Read-only access to TTData
    TTData read() const { return TTData {value, depth, bound}; }

    // Check if the TTEntry is occupied based on depth
    bool is_occupied() const;

    // Save data into the TTEntry atomically
    void save(Key k, Value v, Bound b, Depth d, uint8_t gen);

    // Calculate relative age for aging mechanism
    uint8_t relative_age(uint8_t current_generation) const;
};

// Writer class to encapsulate writing operations to a TTEntry
struct TTWriter
{
public:
    // Write data to the associated TTEntry
    void write(Key k, Value v, Bound b, Depth d, uint8_t gen);

private:
    friend class TranspositionTable;
    TTEntry *entry;

    // Private constructor to ensure controlled access
    TTWriter(TTEntry *tte)
        : entry(tte)
    { }
};

// TranspositionTable class managing the TTEntries
class TranspositionTable
{
public:
    TranspositionTable()
        : entryCount(0)
        , table(nullptr)
        , generation_(0)
    { }
    ~TranspositionTable();

    // Initialize or resize the TT with the specified size in megabytes
    void resize(size_t mbSize = DEFAULT_TT_MB_SIZE);

    // Clear all entries in the TT
    void clear();

    // Estimate the fill rate of the TT
    int hashfull() const;

    // Start a new search by incrementing the generation
    void new_search();

    // Get the current generation value
    uint8_t generation() const;

    // Probe the TT for a given key
    std::tuple<bool, TTData, TTWriter> probe(const Key key);

    // Retrieve the first TTEntry for a given key
    TTEntry *first_entry(const Key key) const;

private:
    friend struct TTEntry;

    size_t entryCount; // Total number of TTEntries
    TTEntry *table;    // Pointer to the TTEntries array

    // Use atomic for thread-safe generation updates
    uint8_t generation_;
};

// Externally accessible TT instance
extern TranspositionTable TT;

#endif // TT_H_INCLUDED
