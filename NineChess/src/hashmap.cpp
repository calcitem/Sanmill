#include "hashmap.h"

using namespace CTSL;

namespace CTSL //Concurrent Thread Safe Library
{
// Function to find an entry in the bucket matching the key
// If key is found, the corresponding value is copied into the parameter "value" and function returns true.
// If key is not found, function returns false
template <typename K, typename V>
bool HashBucket<K, V>::find(const K &key, V &value) const
{
    // A shared mutex is used to enable mutiple concurrent reads
    std::shared_lock<std::shared_timed_mutex> lock(mutex_);
    HashNode<K, V> *node = head;

    while (node != nullptr) {
        if (node->getKey() == key) {
            value = node->getValue();
            return true;
        }
        node = node->next;
    }
    return false;
}

// Function to insert into the bucket
// If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair
template <typename K, typename V>
void HashBucket<K, V>::insert(const K &key, const V &value)
{
    // Exclusive lock to enable single write in the bucket
    std::unique_lock<std::shared_timed_mutex> lock(mutex_);
    HashNode<K, V> *prev = nullptr;
    HashNode<K, V> *node = head;

    while (node != nullptr && node->getKey() != key) {
        prev = node;
        node = node->next;
    }

    if (nullptr == node) // New entry, create a node and add to bucket
    {
        if (nullptr == head) {
            head = new HashNode<K, V>(key, value);
        } else {
            prev->next = new HashNode<K, V>(key, value);
        }
    } else {
        node->setValue(value); // Key found in bucket, update the value
    }
}

// Function to remove an entry from the bucket, if found
template <typename K, typename V>
void HashBucket<K, V>::erase(const K &key)
{
    // Exclusive lock to enable single write in the bucket
    std::unique_lock<std::shared_timed_mutex> lock(mutex_);
    HashNode<K, V> *prev = nullptr;
    HashNode<K, V> *node = head;

    while (node != nullptr && node->getKey() != key) {
        prev = node;
        node = node->next;
    }

    if (nullptr == node) //Key not found, nothing to be done
    {
        return;
    } else  //Remove the node from the bucket
    {
        if (head == node) {
            head = node->next;
        } else {
            prev->next = node->next;
        }
        delete node; //Free up the memory
    }
}

// Function to clear the bucket
template <typename K, typename V>
void HashBucket<K, V>::clear()
{
    // Exclusive lock to enable single write in the bucket
    std::unique_lock<std::shared_timed_mutex> lock(mutex_);
    HashNode<K, V> *prev = nullptr;
    HashNode<K, V> *node = head;
    while (node != nullptr) {
        prev = node;
        node = node->next;
        delete prev;
    }
    head = nullptr;
}

////////////////////////////////////////////////////////////////////////////////////////////////////

// Function to find an entry in the hash map matching the key.
// If key is found, the corresponding value is copied into the parameter "value" and function returns true.
// If key is not found, function returns false.
template <typename K, typename V, typename F>
bool HashMap<K, V, F>::find(const K &key, V &value) const
{
    size_t hashValue = hashFn(key) % hashSize;
    return hashTable[hashValue].find(key, value);
}

// Function to insert into the hash map.
// If key already exists, update the value, else insert a new node in the bucket with the <key, value> pair.
template <typename K, typename V, typename F>
void HashMap<K, V, F>::insert(const K &key, const V &value)
{
    size_t hashValue = hashFn(key) % hashSize;
    hashTable[hashValue].insert(key, value);
}

// Function to remove an entry from the bucket, if found
template <typename K, typename V, typename F>
void HashMap<K, V, F>::erase(const K &key)
{
    size_t hashValue = hashFn(key) % hashSize;
    hashTable[hashValue].erase(key);
}

// Function to clean up the hasp map, i.e., remove all entries from it
template <typename K, typename V, typename F>
void HashMap<K, V, F>::clear()
{
    for (size_t i = 0; i < hashSize; i++) {
        (hashTable[i]).clear();
    }
}
}
