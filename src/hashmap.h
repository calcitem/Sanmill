// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// hashmap.h

#ifndef HASH_MAP_H_INCLUDED
#define HASH_MAP_H_INCLUDED

#include "config.h"

#include <cstdint>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <string>

#include "hashnode.h"
#include "misc.h"
#include "types.h"

#define HASH_KEY_DISABLE

constexpr size_t HASH_SIZE_DEFAULT = 1031; // A prime number as key size gives a
                                           // better distribution of values in
                                           // buckets

// Concurrent Thread Safe Library
namespace CTSL {
// The class representing the key map.
// It is expected for user defined types, the key function will be provided.
// By default, the std::key function will be used
// If the key size is not provided, then a default size of 1031 will be used
// The key table itself consists of an array of key buckets.
// Each key bucket is implemented as singly linked list with the head as a dummy
// node created during the creation of the bucket. All the key buckets are
// created during the construction of the map. Locks are taken per bucket, hence
// multiple threads can write simultaneously in different buckets in the key map
#ifdef HASH_KEY_DISABLE
#define hashFn Key
template <typename K, typename V>
#else  // HASH_KEY_DISABLE
template <typename K, typename V, typename F = std::key<K>>
#endif // HASH_KEY_DISABLE
class HashMap
{
public:
    explicit HashMap(hashFn hashSize_ = HASH_SIZE_DEFAULT)
        : hashSize(hashSize_)
    {
#ifdef DISABLE_HASHBUCKET
#ifdef ALIGNED_LARGE_PAGES
        hashTable = (HashNode<K, V> *)aligned_large_pages_alloc(
            sizeof(HashNode<K, V>) * hashSize);
#else  // ALIGNED_LARGE_PAGES

        // Create the key table as an array of key nodes
        hashTable = new HashNode<K, V>[hashSize];
#endif // ALIGNED_LARGE_PAGES

        for (size_t i = 0; i < hashSize; i++) {
            hashTable[i].~HashNode<K, V>();
            new (&hashTable[i]) HashNode<K, V>();
        }
#else  // DISABLE_HASHBUCKET
       // create the key table as an array of key buckets
        hashTable = new HashBucket<K, V>[hashSize];
#endif // DISABLE_HASHBUCKET
    }

    ~HashMap()
    {
#ifdef ALIGNED_LARGE_PAGES
        aligned_large_pages_free(hashTable);
#else  // ALIGNED_LARGE_PAGES

        delete[] hashTable;
#endif // ALIGNED_LARGE_PAGES
    }

    // Copy and Move of the HashMap are not supported at this moment
    HashMap(const HashMap &) = delete;
    HashMap(HashMap &&) = delete;
    HashMap &operator=(const HashMap &) = delete;
    HashMap &operator=(HashMap &&) = delete;

    // Function to find an entry in the key map matching the key.
    // If key is found, the corresponding value is copied into the parameter
    // "value" and function returns true. If key is not found, function returns
    // false.
    bool find(const K &key, V &value) const
    {
        K hashValue = static_cast<hashFn>(key) & (hashSize - 1);
#ifdef DISABLE_HASHBUCKET
        // A shared mutex is used to enable multiple concurrent reads
#ifndef HASHMAP_NOLOCK
        std::shared_lock<std::shared_timed_mutex> lock(mutex_);
#endif /* HASHMAP_NOLOCK */

        auto &node = hashTable[hashValue];
        if (node.getKey() == key) {
            value = node.getValue();
            return true;
        }

        return false;
#else  // DISABLE_HASHBUCKET
        return hashTable[hashValue].find(key, value);
#endif // DISABLE_HASHBUCKET
    }

    void prefetchValue(const K &key)
    {
        K hashValue = static_cast<hashFn>(key) & (hashSize - 1);
        V *addr = &(hashTable[hashValue].getValue());

        prefetch(static_cast<void *>(addr));
    }

    // Function to insert into the key map.
    // If key already exists, update the value, else insert a new node in the
    // bucket with the <key, value> pair.
    K insert(const K &key, const V &value)
    {
        K hashValue = static_cast<hashFn>(key) & (hashSize - 1);
#ifdef DISABLE_HASHBUCKET
#ifndef HASHMAP_NOLOCK
        std::unique_lock<std::shared_timed_mutex> lock(mutex_);
#endif /* HASHMAP_NOLOCK */

        auto &node = hashTable[hashValue];
        node.setKey(key);
        node.setValue(value);
#else  // DISABLE_HASHBUCKET
        hashTable[hashValue].insert(key, value);
#endif // DISABLE_HASHBUCKET

        return hashValue;
    }

    // Function to remove an entry from the bucket, if found
    void erase(
#ifndef DISABLE_HASHBUCKET
        const K &key
#endif // DISABLE_HASHBUCKET
    )
    {
#ifdef DISABLE_HASHBUCKET
        // std::unique_lock<std::shared_timed_mutex> lock(mutex_);
#else  // DISABLE_HASHBUCKET
        size_t hashValue = hashFn(key) & (hashSize - 1);
        hashTable[hashValue].erase(key);
#endif // DISABLE_HASHBUCKET
    }

    // Function to clean up the hasp map, i.e., remove all entries from it
    void clear() const
    {
#ifdef DISABLE_HASHBUCKET
        for (size_t i = 0; i < hashSize; i++) {
            hashTable[i].~HashNode<K, V>();
            new (&hashTable[i]) HashNode<K, V>();
        }
#else  // DISABLE_HASHBUCKET
        for (size_t i = 0; i < hashSize; i++) {
            (hashTable[i]).clear();
        }
#endif // DISABLE_HASHBUCKET
    }

    void resize(size_t size)
    {
        // TODO(calcitem): Resize
        if (size < 0x1000000) {
            // New size is too small, do not resize
            return;
        }

#ifdef TRANSPOSITION_TABLE_64BIT_KEY
        hashSize = size;
#else  // TRANSPOSITION_TABLE_64BIT_KEY
        hashSize = static_cast<uint32_t>(size);
#endif // TRANSPOSITION_TABLE_64BIT_KEY
    }

    // Function to dump the key map to file
    void dump(const std::string &filename) const
    {
#ifdef DISABLE_HASHBUCKET
        std::ofstream file;
        file.open(filename, std::ios::out);
        file.write(static_cast<char *>(hashTable),
                   sizeof(HashNode<K, V>) * hashSize);
        file.close();
#endif // DISABLE_HASHBUCKET
    }

    // Function to load the key map from file
    void load(const std::string &filename) const
    {
#ifdef DISABLE_HASHBUCKET
        std::ifstream file;
        file.open(filename, std::ios::in);
        file.read(static_cast<char *>(hashTable),
                  sizeof(HashNode<K, V>) * hashSize);
        file.close();

        stat();
#endif // DISABLE_HASHBUCKET
    }

    void merge(const HashMap &other)
    {
        const size_t ksize = sizeof(K);
        const size_t nsize = sizeof(HashNode<K, V>);

        size_t nProcessed = 0;
        size_t nMerged = 0;
        size_t nSkip = 0;
        size_t nAllSame = 0;
        size_t nOnlyKeySame = 0;
        size_t nDiff = 0;

        char empty[sizeof(HashNode<K, V>)];
        memset(empty, 0, nsize);

        const size_t nBefore = stat();

        for (size_t i = 0; i < hashSize; i++) {
            const size_t offset = i * nsize;
            if (memcmp(static_cast<char *>(other.hashTable) + offset, empty,
                       ksize)) {
                nProcessed++;
                if (!memcmp(static_cast<char *>(hashTable) + offset, empty,
                            ksize)) {
                    memcpy(static_cast<char *>(hashTable) + offset,
                           static_cast<char *>(other.hashTable) + offset,
                           nsize);
                    nMerged++;
                } else {
                    nSkip++;
                    if (!memcmp(static_cast<char *>(other.hashTable) + offset,
                                static_cast<char *>(hashTable) + offset,
                                nsize)) {
                        nAllSame++;
                    } else if (!memcmp(static_cast<char *>(other.hashTable) +
                                           offset,
                                       static_cast<char *>(hashTable) + offset,
                                       ksize)) {
                        nOnlyKeySame++;
                    } else {
                        nDiff++;
                    }
                }
            }
        }

        const size_t nAfter = stat();

        debugPrintf("[key merge]\nnProcessed = %lld, nMerged = %lld,\n"
                    "nSkip = %lld (nAllSame = %lld, nOnlyKeySame = %lld, nDiff "
                    "= "
                    "%lld)\n"
                    "hashSize = %d, nBefore = %lld (%f%%), nAfter = %lld "
                    "(%f%%)\n",
                    nProcessed, nMerged, nSkip, nAllSame, nOnlyKeySame, nDiff,
                    hashSize, nBefore,
                    static_cast<double>(nBefore) * 100 / hashSize, nAfter,
                    static_cast<double>(nAfter) * 100 / hashSize);
    }

    size_t stat() const
    {
        size_t nEntries = 0;

        const size_t size = sizeof(HashNode<K, V>);
        char empty[sizeof(HashNode<K, V>)];
        memset(empty, 0, size);

        for (size_t i = 0; i < hashSize; i++) {
            if (memcmp(static_cast<char *>(hashTable) + i * size, empty,
                       size)) {
                nEntries++;
            }
        }

        debugPrintf("Hash map loaded from file (%lld/%d entries)\n", nEntries,
                    hashSize);

        return nEntries;
    }

private:
#ifdef DISABLE_HASHBUCKET
    HashNode<K, V> *hashTable;
#else  // DISABLE_HASHBUCKET
    HashBucket<K, V> *hashTable;
#endif // DISABLE_HASHBUCKET

#ifdef HASH_KEY_DISABLE
#else  // HASH_KEY_DISABLE
    F hashFn;
#endif // HASH_KEY_DISABLE

    hashFn hashSize;
#ifdef DISABLE_HASHBUCKET
#ifndef HASHMAP_NOLOCK
    mutable std::shared_timed_mutex mutex_;
#endif /* HASHMAP_NOLOCK */

#endif
};
} // namespace CTSL
#endif // HASH_MAP_H_INCLUDED
