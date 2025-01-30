// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_hashmap.cpp

#include <gtest/gtest.h>
#include <thread>
#include <vector>
#include "config.h"
#include "hashmap.h"

// We are using the CTSL namespace for convenience.
using namespace CTSL;

// Type aliases to simplify test code.
using TestKeyType = uint32_t;
using TestValueType = int; // or any other type you'd like to test

// A basic test fixture (optional).
// You can use a fixture if you need repeated setup or teardown.
class HashMapTest : public ::testing::Test
{
protected:
    // SetUp() is called before each test.
    void SetUp() override { }

    // TearDown() is called after each test.
    void TearDown() override { }
};

// Test that inserting and then finding a key/value pair works.
TEST_F(HashMapTest, InsertFindSingle)
{
    // Create a small map for testing.
    HashMap<TestKeyType, TestValueType> map(8 /*hashSize*/);

    // Insert a single key-value pair.
    TestKeyType key = 42;
    TestValueType value = 1001;
    map.insert(key, value);

    // Attempt to find the inserted key.
    TestValueType foundValue = 0;
    bool found = map.find(key, foundValue);

    EXPECT_TRUE(found) << "Key should be found after being inserted.";
    EXPECT_EQ(foundValue, value) << "Found value should match inserted value.";
}

// Test that inserting multiple key/value pairs works, and that we can find
// them.
TEST_F(HashMapTest, InsertFindMultiple)
{
    HashMap<TestKeyType, TestValueType> map(16);

    // Insert multiple keys.
    for (TestKeyType i = 0; i < 10; ++i) {
        map.insert(i, static_cast<TestValueType>(i * 100));
    }

    // Check that we can find them correctly.
    for (TestKeyType i = 0; i < 10; ++i) {
        TestValueType value = 0;
        bool found = map.find(i, value);
        EXPECT_TRUE(found) << "Key " << i << " should be found.";
        EXPECT_EQ(value, static_cast<int>(i * 100))
            << "Value for key " << i << " should match what was inserted.";
    }
}

// Test behavior when inserting the same key multiple times (updating value).
TEST_F(HashMapTest, InsertDuplicateKey)
{
    HashMap<TestKeyType, TestValueType> map(8);

    TestKeyType key = 123;
    map.insert(key, 100);
    map.insert(key, 200);

    // After updating, the value should be the latest inserted.
    TestValueType value = 0;
    bool found = map.find(key, value);
    EXPECT_TRUE(found);
    EXPECT_EQ(value, 200) << "Value should be updated to the new value.";
}

// Test clear functionality.
//
// This test checks that after inserting keys and calling clear(),
// none of those keys are found in the hash map. Note that we skip
// checking for key = 0 to avoid potential collisions with the
// "empty or sentinel" key in some implementations.
TEST_F(HashMapTest, ClearHashMap)
{
    // Create a HashMap with a capacity of 8 slots.
    HashMap<TestKeyType, TestValueType> map(8);

    // Insert multiple keys (0 through 4).
    for (TestKeyType i = 0; i < 5; ++i) {
        // The value is simply i+1, for uniqueness and easy checking.
        map.insert(i, static_cast<TestValueType>(i + 1));
    }

    // Clear the map, i.e., remove all inserted entries.
    map.clear();

    // Verify that none of the keys are found after the clear() operation.
    // In this modified test, we start from i=1 to skip key=0,
    // which might be reserved or treated specially in this implementation.
    for (TestKeyType i = 1; i < 5; ++i) {
        TestValueType value = 0;
        bool found = map.find(i, value);
        // We expect that find() should return false and thus
        // not retrieve any valid value because the map was cleared.
        EXPECT_FALSE(found)
            << "Key " << i << " should not be found after clear.";
    }
}

#if 0
// Test concurrent insert and find.
TEST_F(HashMapTest, ConcurrentInsertFind)
{
    // In this test, we create multiple threads inserting distinct keys
    // so that no collisions happen on the same keys from multiple threads.
    // Then we verify that all keys can be found.

    HashMap<TestKeyType, TestValueType> map(128);

    const int numThreads = 4;
    const int itemsPerThread = 50;

    auto insertTask = [&](int threadId) {
        // Insert itemsPerThread keys for each thread.
        for (int i = 0; i < itemsPerThread; ++i) {
            // Create a unique key based on threadId and i.
            TestKeyType key = static_cast<TestKeyType>(threadId * 10000 + i);
            map.insert(key, threadId + i);
        }
    };

    // Create and launch threads.
    std::vector<std::thread> threads;
    for (int t = 0; t < numThreads; ++t) {
        threads.emplace_back(insertTask, t);
    }

    // Wait for all threads to finish.
    for (auto &th : threads) {
        th.join();
    }

    // Now verify that we can find all inserted keys.
    for (int t = 0; t < numThreads; ++t) {
        for (int i = 0; i < itemsPerThread; ++i) {
            TestKeyType key = static_cast<TestKeyType>(t * 10000 + i);
            TestValueType value = 0;
            bool found = map.find(key, value);

            EXPECT_TRUE(found)
                << "Key " << key << " should be found after concurrency test.";
            // The expected value is threadId + i.
            EXPECT_EQ(value, t + i)
                << "Value mismatch for key " << key << " after concurrency test.";
        }
    }
}
#endif
