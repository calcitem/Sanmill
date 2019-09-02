#ifndef HASH_MAP_H_
#define HASH_MAP_H_

#include <cstdint>
#include <iostream>
#include <functional>
#include <mutex>
#include <QFile>
#include <iostream>
#include "HashNode.h"

#include "config.h"

#define HASH_KEY_DISABLE

constexpr size_t HASH_SIZE_DEFAULT = 1031; // A prime number as hash size gives a better distribution of values in buckets
namespace CTSL //Concurrent Thread Safe Library
{
    //The class represting the hash map.
    //It is expected for user defined types, the hash function will be provided.
    //By default, the std::hash function will be used
    //If the hash size is not provided, then a defult size of 1031 will be used
    //The hash table itself consists of an array of hash buckets.
    //Each hash bucket is implemented as singly linked list with the head as a dummy node created
    //during the creation of the bucket. All the hash buckets are created during the construction of the map.
    //Locks are taken per bucket, hence multiple threads can write simultaneously in different buckets in the hash map
#ifdef HASH_KEY_DISABLE
    #define hashFn uint64_t
    template <typename K, typename V>
#else
    template <typename K, typename V, typename F = std::hash<K> >
#endif
    class HashMap
    {
        public:
            HashMap(size_t hashSize_ = HASH_SIZE_DEFAULT) : hashSize(hashSize_)
            {
#ifdef DISABLE_HASHBUCKET
                hashTable = new HashNode<K, V>[hashSize]; //create the hash table as an array of hash nodes
                memset(hashTable, 0, sizeof(HashNode<K, V>) * hashSize);
#else
                hashTable = new HashBucket<K, V>[hashSize]; //create the hash table as an array of hash buckets
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

            //Function to find an entry in the hash map matching the key.
            //If key is found, the corresponding value is copied into the parameter "value" and function returns true.
            //If key is not found, function returns false.
            bool find(const K &key, V &value) const
            {
                size_t hashValue = hashFn(key) & (hashSize - 1) ;
#ifdef DISABLE_HASHBUCKET
                // A shared mutex is used to enable multiple concurrent reads
                std::shared_lock<std::shared_timed_mutex> lock(mutex_);

                if (hashTable[hashValue].getKey() == key) {
                    value = hashTable[hashValue].getValue();
                    return true;
                }

                return false;
#else
                return hashTable[hashValue].find(key, value);
#endif
            }

            //Function to insert into the hash map.
            //If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair.
            void insert(const K &key, const V &value)
            {
                size_t hashValue = hashFn(key) & (hashSize - 1);
#ifdef DISABLE_HASHBUCKET
                std::unique_lock<std::shared_timed_mutex> lock(mutex_);
                hashTable[hashValue].setKey(key);
                hashTable[hashValue].setValue(value);
#else
                hashTable[hashValue].insert(key, value);
#endif
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

            //Function to dump the hash map to file
            void dump(const QString &filename)
            {
#ifdef DISABLE_HASHBUCKET
                QFile file(filename);
                file.open(QIODevice::WriteOnly);
                file.write(static_cast<char *>(hashTable), sizeof(HashNode<K, V>) * hashSize);
                file.close();
#endif
            }

            //Function to load the hash map from file
            void load(const QString &filename)
            {
#ifdef DISABLE_HASHBUCKET
                QFile file(filename);
                file.open(QIODevice::ReadOnly);
                file.read(static_cast<char *>(hashTable), sizeof(HashNode<K, V>) * hashSize);
                file.close();
#endif
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
            const size_t hashSize;
#ifdef DISABLE_HASHBUCKET
            mutable std::shared_timed_mutex mutex_;
#endif
    };
}
#endif

