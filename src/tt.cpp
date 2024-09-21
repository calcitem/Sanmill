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

extern UCI::OptionsMap Options;

TranspositionTable TT;

bool TTEntry::is_occupied() const
{
    return depth != 0;
}

void TTEntry::save(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    // Always replace the entry
    key = k;
    value = v;
    depth = d;
    generation = gen;
    bound = b;
}

uint8_t TTEntry::relative_age(uint8_t current_generation) const
{
    return current_generation - generation;
}

TTWriter::TTWriter(TTEntry *tte)
    : entry(tte)
{ }

void TTWriter::write(Key k, Value v, Bound b, Depth d, uint8_t gen)
{
    entry->save(k, v, b, d, gen);
}

void TranspositionTable::resize(size_t mbSize)
{
    Threads.main()->wait_for_search_finished();

    aligned_large_pages_free(table);

    // Calculate the number of entries based on megabytes
    entryCount = (mbSize * 1024 * 1024) / sizeof(TTEntry);

    // Allocate memory aligned to cache lines for better performance
    table = static_cast<TTEntry *>(
        aligned_large_pages_alloc(entryCount * sizeof(TTEntry)));

    if (!table) {
        std::cerr << "Failed to allocate " << mbSize
                  << "MB for transposition table." << std::endl;
        exit(EXIT_FAILURE);
    }

    clear();
}

void TranspositionTable::clear()
{
    std::memset(table, 0, entryCount * sizeof(TTEntry));
}

int TranspositionTable::hashfull() const
{
    int cnt = 0;
    for (size_t i = 0; i < 1000; ++i) {
        size_t index = (i * 1024) % entryCount;
        const TTEntry &entry = table[index];

        if (entry.is_occupied() && entry.generation == generation_)
            cnt++;
    }

    return (cnt * 1000) / 1000;
}

void TranspositionTable::new_search()
{
    ++generation_;
}

uint8_t TranspositionTable::generation() const
{
    return generation_;
}

std::tuple<bool, TTData, TTWriter>
TranspositionTable::probe(const Key key) const
{
    // Calculate the index based on the key and size of the table
    size_t index = key % entryCount;
    TTEntry &entry = const_cast<TTEntry &>(table[index]);

    // Check for a matching key
    if (entry.key == key && entry.is_occupied()) {
        return {true, entry.read(), TTWriter(&entry)};
    }

    // No match found
    return {false, TTData(), TTWriter(&entry)};
}

TTEntry *TranspositionTable::first_entry(const Key key) const
{
    size_t index = key % entryCount;
    return &const_cast<TTEntry &>(table[index]);
}
