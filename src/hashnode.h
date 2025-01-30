// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// hashnode.h

#ifndef HASH_NODE_H_INCLUDED
#define HASH_NODE_H_INCLUDED

#include "config.h"

#include <mutex>
#include <shared_mutex>

namespace CTSL // Concurrent Thread Safe Library
{
// Class representing a template key node
template <typename K, typename V>
class HashNode
{
public:
    HashNode()
#ifndef DISABLE_HASHBUCKET
        : next(nullptr)
#endif
        = default;

    HashNode(K key_, V value_)
        :
#ifndef DISABLE_HASHBUCKET
        next(nullptr)
        ,
#endif
        key(key_)
        , value(value_)
    { }

    ~HashNode()
    {
#ifndef DISABLE_HASHBUCKET
        next = nullptr;
#endif
    }

    const K &getKey() const { return key; }
    void setValue(V value_) { value = value_; }
    V &getValue() { return value; }
    void setKey(K key_) { key = key_; }

#ifndef DISABLE_HASHBUCKET
    HashNode *next; // Pointer to the next node in the same bucket
#endif

private:
    K key {0}; // the key key
    V value;   // the value corresponding to the key
};

// Class representing a key bucket. The bucket is implemented as a singly linked
// list. A bucket is always constructed with a dummy head node
template <typename K, typename V>
class HashBucket
{
public:
    HashBucket()
        : head(nullptr)
    { }

    ~HashBucket() // delete the bucket
    {
        clear();
    }

    // Function to find an entry in the bucket matching the key
    // If key is found, the corresponding value is copied into the parameter
    // "value" and function returns true. If key is not found, function returns
    // false
    bool find(const K &key, V &value) const
    {
        // A shared mutex is used to enable multiple concurrent reads
        std::shared_lock lock(mutex_);
        HashNode<K, V> *node = head;

#ifdef DISABLE_HASHBUCKET
        if (node == nullptr) {
            return false;
        }

        if (node->getKey() == key) {
            value = node->getValue();
            return true;
        }
#else  // DISABLE_HASHBUCKET
        while (node != nullptr) {
            if (node->getKey() == key) {
                value = node->getValue();
                return true;
            }
            node = node->next;
        }
#endif //  DISABLE_HASHBUCKET

        return false;
    }

    // Function to insert into the bucket
    // If key already exists, update the value, else insert a new node in the
    // bucket with the <key, value> pair
    void insert(const K &key, const V &value)
    {
        // Exclusive lock to enable single write in the bucket
        std::unique_lock lock(mutex_);

#ifdef DISABLE_HASHBUCKET
        if (head == nullptr) {
            head = new HashNode<K, V>(key, value);
            return;
        }

        head->setValue(value);
#else  // DISABLE_HASHBUCKET
        HashNode<K, V> *prev = nullptr;
        HashNode<K, V> *node = head;

        while (node != nullptr && node->getKey() != key) {
            prev = node;
            node = node->next;
        }

        if (nullptr == node) { // New entry, create a node and add to bucket
            if (nullptr == head) {
                head = new HashNode<K, V>(key, value);
            } else {
                prev->next = new HashNode<K, V>(key, value);
            }
        } else {
            node->setValue(value); // Key found in bucket, update the value
        }
#endif // DISABLE_HASHBUCKET
    }

    // Function to remove an entry from the bucket, if found
    void erase(const K &key)
    {
        // Exclusive lock to enable single write in the bucket
        std::unique_lock lock(mutex_);

#ifdef DISABLE_HASHBUCKET
        if (head == nullptr) {
            // Key not found, nothing to be done
            return;
        }

        if (head->getKey() == key) {
            delete head;
            head = nullptr;
        }
#else  // DISABLE_HASHBUCKET
        HashNode<K, V> *prev = nullptr;
        HashNode<K, V> *node = head;

        while (node != nullptr && node->getKey() != key) {
            prev = node;
            node = node->next;
        }

        if (nullptr == node) { // Key not found, nothing to be done
            return;
        } else {
            // Remove the node from the bucket
            if (head == node) {
                head = node->next;
            } else {
                prev->next = node->next;
            }
            delete node; // Free up the memory
        }
#endif // DISABLE_HASHBUCKET
    }

    // Function to clear the bucket
    void clear()
    {
        // Exclusive lock to enable single write in the bucket
        std::unique_lock lock(mutex_);

#ifdef DISABLE_HASHBUCKET
        if (head != nullptr) {
            delete head;
        }
#else  // DISABLE_HASHBUCKET

        HashNode<K, V> *prev = nullptr;
        HashNode<K, V> *node = head;

        while (node != nullptr) {
            prev = node;
            node = node->next;
            delete prev;
        }
#endif // DISABLE_HASHBUCKET

        head = nullptr;
    }

private:
    HashNode<K, V> *head;                   // The head node of the bucket
    mutable std::shared_timed_mutex mutex_; // The mutex for this bucket
};
} // namespace CTSL

#endif // HASH_NODE_H_INCLUDED
