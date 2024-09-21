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

static constexpr size_t CACHE_LINE_SIZE = 64;

struct TTData
{
    Value value;
    Depth depth;
    Bound bound;
};

struct alignas(CACHE_LINE_SIZE) TTEntry
{
    Key key;            // 64-bit Zobrist hash key
    Value value;        // 32-bit evaluation value
    Depth depth;        // 8-bit search depth
    uint8_t generation; // 8-bit generation for aging
    Bound bound;        // 8-bit bound type
    uint8_t padding[2]; // Padding to make the struct size a multiple of 8 bytes

    TTData read() const { return TTData {value, depth, bound}; }

    bool is_occupied() const;
    void save(Key k, Value v, Bound b, Depth d, uint8_t gen);
    uint8_t relative_age(uint8_t current_generation) const;
};

struct TTWriter
{
public:
    void write(Key k, Value v, Bound b, Depth d, uint8_t gen);

private:
    friend class TranspositionTable;
    TTEntry *entry;

    TTWriter(TTEntry *tte);
};

class TranspositionTable
{
public:
    ~TranspositionTable() { aligned_large_pages_free(table); }

    void resize(size_t mbSize);
    void clear();
    int hashfull() const;

    void new_search();
    uint8_t generation() const;
    std::tuple<bool, TTData, TTWriter> probe(const Key key) const;
    TTEntry *first_entry(const Key key) const;

private:
    friend struct TTEntry;

    size_t entryCount; // Number of entries in the table
    TTEntry *table = nullptr;

    uint8_t generation_ = 0;
};

extern TranspositionTable TT;

#endif // TT_H_INCLUDED
