#ifndef HASH_MAP_H_
#define HASH_MAP_H_

#include <cstdint> 
#include <iostream> 
#include <functional>
#include <mutex> 
#include <shared_mutex>

constexpr size_t HASH_SIZE_DEFAULT = 1031; // A prime number as hash size gives a better distribution of values in buckets

namespace CTSL //Concurrent Thread Safe Library
{
// Class representing a templatized hash node
template <typename K, typename V>
class HashNode
{
public:
    HashNode() : next(nullptr)
    {
    }
    HashNode(K key_, V value_) : next(nullptr), key(key_), value(value_)
    {
    }
    ~HashNode()
    {
        next = nullptr;
    }

    const K &getKey() const
    {
        return key;
    }
    void setValue(V value_)
    {
        value = value_;
    }
    const V &getValue() const
    {
        return value;
    }

    HashNode *next; // Pointer to the next node in the same bucket
private:
    K key;   // the hash key
    V value; // the value corresponding to the key
};


// Class representing a hash bucket. The bucket is implemented as a singly linked list.
// A bucket is always constructed with a dummy head node
template <typename K, typename V>
class HashBucket
{
public:
    HashBucket() : head(nullptr)
    {
    }

    ~HashBucket() //delete the bucket
    {
        clear();
    }

    // Function to find an entry in the bucket matching the key
    // If key is found, the corresponding value is copied into the parameter "value" and function returns true.
    // If key is not found, function returns false
    bool find(const K &key, V &value) const;

    // Function to insert into the bucket
    // If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair
    void insert(const K &key, const V &value);

    // Function to remove an entry from the bucket, if found
    void erase(const K &key);

    // Function to clear the bucket
    void clear();

private:
    HashNode<K, V> *head; //The head node of the bucket
    mutable std::shared_timed_mutex mutex_; //The mutex for this bucket
};

// The class represting the hash map.
// It is expected for user defined types, the hash function will be provided.
// By default, the std::hash function will be used
// If the hash size is not provided, then a defult size of 1031 will be used
// The hash table itself consists of an array of hash buckets.
// Each hash bucket is implemented as singly linked list with the head as a dummy node created 
// during the creation of the bucket. All the hash buckets are created during the construction of the map.
// Locks are taken per bucket, hence multiple threads can write simultaneously in different buckets in the hash map
template <typename K, typename V, typename F = std::hash<K> >
class HashMap
{
public:
    HashMap(size_t hashSize_ = HASH_SIZE_DEFAULT) : hashSize(hashSize_)
    {
        hashTable = new HashBucket<K, V>[hashSize]; // create the hash table as an array of hash buckets
    }

    ~HashMap()
    {
        delete[] hashTable;
    }

    // Copy and Move of the HashMap are not supported at this moment
    HashMap(const HashMap &) = delete;
    HashMap(HashMap &&) = delete;
    HashMap &operator=(const HashMap &) = delete;
    HashMap &operator=(HashMap &&) = delete;

    // Function to find an entry in the hash map matching the key.
    // If key is found, the corresponding value is copied into the parameter "value" and function returns true.
    // If key is not found, function returns false.
    bool find(const K &key, V &value) const;

    // Function to insert into the hash map.
    // If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair.
    void insert(const K &key, const V &value);

    // Function to remove an entry from the bucket, if found
    void erase(const K &key);

    // Function to clean up the hasp map, i.e., remove all entries from it
    void clear();

private:
    HashBucket<K, V> *hashTable;
    F hashFn;
    const size_t hashSize;
};
}
#endif /* HASH_MAP_H_ */
