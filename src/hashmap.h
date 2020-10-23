#ifndef HASH_MAP_H_
#define HASH_MAP_H_

#include <cstdint>
#include <iostream>
#include <functional>
#include <mutex>
#include <fstream>
#include <iostream>
#include <cstring>
#include "HashNode.h"
#include "misc.h"
#include "types.h"
#include "config.h"

#define HASH_KEY_DISABLE

constexpr size_t HASH_SIZE_DEFAULT = 1031; // A prime number as key size gives a better distribution of values in buckets
namespace CTSL //Concurrent Thread Safe Library
{
    //The class represting the key map.
    //It is expected for user defined types, the key function will be provided.
    //By default, the std::key function will be used
    //If the key size is not provided, then a defult size of 1031 will be used
    //The key table itself consists of an array of key buckets.
    //Each key bucket is implemented as singly linked list with the head as a dummy node created
    //during the creation of the bucket. All the key buckets are created during the construction of the map.
    //Locks are taken per bucket, hence multiple threads can write simultaneously in different buckets in the key map
#ifdef HASH_KEY_DISABLE
    #define hashFn Key
    template <typename K, typename V>
#else
    template <typename K, typename V, typename F = std::key<K> >
#endif
    class HashMap
    {
        public:
            HashMap(hashFn hashSize_ = HASH_SIZE_DEFAULT) : hashSize(hashSize_)
            {
#ifdef DISABLE_HASHBUCKET
                hashTable = new HashNode<K, V>[hashSize]; //create the key table as an array of key nodes
                memset(hashTable, 0, sizeof(HashNode<K, V>) * hashSize);
#else
                hashTable = new HashBucket<K, V>[hashSize]; //create the key table as an array of key buckets
#endif
            }

            ~HashMap()
            {
                delete [] hashTable;
            }
            //Copy and Move of the HashMap are not supported at this moment
            HashMap(const HashMap&) = delete;
            HashMap(HashMap&&) = delete;
            HashMap& operator=(const HashMap&) = delete;
            HashMap& operator=(HashMap&&) = delete;

            //Function to find an entry in the key map matching the key.
            //If key is found, the corresponding value is copied into the parameter "value" and function returns true.
            //If key is not found, function returns false.
            bool find(const K &key, V &value) const
            {
                K hashValue = hashFn(key) & (hashSize - 1) ;
#ifdef DISABLE_HASHBUCKET
                // A shared mutex is used to enable multiple concurrent reads
#ifndef HASHMAP_NOLOCK
                std::shared_lock<std::shared_timed_mutex> lock(mutex_);
#endif /* HASHMAP_NOLOCK */

                if (hashTable[hashValue].getKey() == key) {
                    value = hashTable[hashValue].getValue();
                    return true;
                }

                return false;
#else
                return hashTable[hashValue].find(key, value);
#endif
            }

            void prefetchValue(const K &key)
            {
                K hashValue = hashFn(key) & (hashSize - 1);
                V *addr = &(hashTable[hashValue].getValue());

                prefetch((void *)addr);
            }

            //Function to insert into the key map.
            //If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair.
            K insert(const K &key, const V &value)
            {
                K hashValue = hashFn(key) & (hashSize - 1);
#ifdef DISABLE_HASHBUCKET
#ifndef HASHMAP_NOLOCK
                std::unique_lock<std::shared_timed_mutex> lock(mutex_);
#endif /* HASHMAP_NOLOCK */
                hashTable[hashValue].setKey(key);
                hashTable[hashValue].setValue(value);
#else
                hashTable[hashValue].insert(key, value);
#endif
                return hashValue;
            }

            //Function to remove an entry from the bucket, if found
            void erase(
#ifndef DISABLE_HASHBUCKET
                const K &key
#endif
                )
            {
#ifdef DISABLE_HASHBUCKET
                // std::unique_lock<std::shared_timed_mutex> lock(mutex_);
#else
                size_t hashValue = hashFn(key) & (hashSize - 1);
                hashTable[hashValue].erase(key);
#endif
            }


            //Function to clean up the hasp map, i.e., remove all entries from it
            void clear()
            {
#ifdef DISABLE_HASHBUCKET
                memset(hashTable, 0, sizeof(HashNode<K, V>) * hashSize);
#else
                for(size_t i = 0; i < hashSize; i++)
                {
                    (hashTable[i]).clear();
                }
#endif
            }

            void resize(size_t o)
            {
                // TODO
                o = o;
                return;
            }

            //Function to dump the key map to file
            void dump(const std::string &filename)
            {
#ifdef DISABLE_HASHBUCKET
                std::ofstream file;
                file.open(filename, std::ios::out);
                file.write((char *)(hashTable), sizeof(HashNode<K, V>) * hashSize);
                file.close();
#endif
            }

            //Function to load the key map from file
            void load(const std::string &filename)
            {
#ifdef DISABLE_HASHBUCKET
                std::ifstream file;
                file.open(filename, std::ios::in);
                file.read((char *)(hashTable), sizeof(HashNode<K, V>) * hashSize);
                file.close();

                stat();
#endif
            }

            void merge(const HashMap &other)
            {
                size_t ksize = sizeof(K);
                size_t nsize = sizeof(HashNode<K, V>);

                size_t nProcessed = 0;
                size_t nMerged = 0;
                size_t nSkip = 0;
                size_t nAllSame = 0;
                size_t nOnlyKeySame = 0;
                size_t nDiff = 0;

                char empty[sizeof(HashNode<K, V>)];
                memset(empty, 0, nsize);

                size_t nBefore = stat();

                for (size_t i = 0; i < hashSize; i++) {
                    size_t offset = i * nsize;
                    if (memcmp((char *)other.hashTable + offset, empty, ksize)) {
                        nProcessed++;
                        if (!memcmp((char *)hashTable + offset, empty, ksize)) {
                            memcpy((char *)hashTable + offset, (char *)other.hashTable + offset, nsize);
                            nMerged++;
                        } else {
                            nSkip++;
                            if (!memcmp((char *)other.hashTable + offset, (char *)hashTable + offset, nsize)) {
                                nAllSame++;
                            } else if (!memcmp((char *)other.hashTable + offset, (char *)hashTable + offset, ksize)) {
                                nOnlyKeySame++;
                            } else {
                                nDiff++;
                            }
                        }
                    }
                }

                size_t nAfter = stat();

                loggerDebug("[key merge]\nnProcessed = %lld, nMerged = %lld,\n"
                            "nSkip = %lld (nAllSame = %lld, nOnlyKeySame = %lld, nDiff = %lld)\n"
                            "hashSize = %d, nBefore = %lld (%f%%), nAfter = %lld (%f%%)\n",
                            nProcessed, nMerged, nSkip, nAllSame, nOnlyKeySame, nDiff,
                            hashSize, nBefore, (double)nBefore * 100 / hashSize, nAfter, (double)nAfter * 100 / hashSize);
            }

            size_t stat()
            {
                size_t nEntries = 0;

                size_t size = sizeof(HashNode<K, V>);
                char empty[sizeof(HashNode<K, V>)];
                memset(empty, 0, size);

                for (size_t i = 0; i < hashSize; i++) {
                    if (memcmp((char *)hashTable + i * size, empty, size)) {
                        nEntries++;
                    }
                }

                loggerDebug("Hash map loaded from file (%lld/%d entries)\n", nEntries, hashSize);

                return nEntries;
            }

        private:
#ifdef DISABLE_HASHBUCKET
            HashNode<K, V> *hashTable;
#else
            HashBucket<K, V> * hashTable;
#endif
#ifdef HASH_KEY_DISABLE
#else
            F hashFn;
#endif
            const hashFn hashSize;
#ifdef DISABLE_HASHBUCKET
#ifndef HASHMAP_NOLOCK
            mutable std::shared_timed_mutex mutex_;
#endif /* HASHMAP_NOLOCK */
#endif
    };
}
#endif

