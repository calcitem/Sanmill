// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// test_stack.cpp

#include <gtest/gtest.h>
#include "stack.h"
#include <string>

namespace {

using namespace Sanmill;

// A helper struct to test with a non-primitive type
// so we can check if copying/erasing works for objects
struct SimpleObject
{
    int x;
    float y;

    // For '==' to work in remove(T entry)
    bool operator==(const SimpleObject &other) const
    {
        return (x == other.x && y == other.y);
    }
};

class StackTest : public ::testing::Test
{
protected:
    // You can define any shared objects here
    // They will be instantiated for each test in the fixture
    void SetUp() override
    {
        // Code here will be called immediately after the constructor
        // right before each test
    }

    void TearDown() override
    {
        // Code here will be called immediately after each test
        // right before the destructor
    }
};

// Test push and pop for integers
TEST_F(StackTest, PushPopInt)
{
    Stack<int> st;

    // Initially empty
    EXPECT_TRUE(st.empty()) << "Stack should start empty";

    // Push some elements
    st.push(10);
    st.push(20);
    st.push(30);

    EXPECT_EQ(st.size(), 3) << "After 3 pushes, size should be 3";
    EXPECT_FALSE(st.empty()) << "Stack should no longer be empty";

    // Check top element
    EXPECT_EQ(*st.top(), 30) << "Top element should be the last pushed value";

    // Pop one
    st.pop();
    EXPECT_EQ(st.size(), 2) << "After one pop, size should be 2";
    EXPECT_EQ(*st.top(), 20) << "Top element should be the new last value";
}

// Test push_back with objects
TEST_F(StackTest, PushBackObjects)
{
    Stack<SimpleObject> st;

    SimpleObject a {1, 2.5f};
    SimpleObject b {2, 3.14f};

    st.push_back(a);
    st.push_back(b);

    EXPECT_EQ(st.size(), 2);
    EXPECT_EQ(st[0].x, 1) << "First object's x should match 'a'";
    EXPECT_EQ(st[1].y, 3.14f) << "Second object's y should match 'b'";
}

// Test copy constructor
TEST_F(StackTest, CopyConstructor)
{
    Stack<int> st1;
    st1.push_back(5);
    st1.push_back(10);

    Stack<int> st2(st1); // Use copy constructor
    EXPECT_EQ(st2.size(), 2);
    EXPECT_EQ(*st2.top(), 10);
    st2.pop();
    EXPECT_EQ(st2.size(), 1);

    // Make sure st1 is not affected
    EXPECT_EQ(st1.size(), 2) << "Original stack should remain unchanged";
}

// Test assignment operator
TEST_F(StackTest, AssignmentOperator)
{
    Stack<int> st1;
    st1.push_back(100);
    st1.push_back(200);

    Stack<int> st2;
    st2.push_back(999);

    st2 = st1; // Use operator=
    EXPECT_EQ(st2.size(), 2);
    EXPECT_EQ(*st2.top(), 200);

    // Modify st2 to ensure st1 not mutated
    st2.pop();
    EXPECT_EQ(st2.size(), 1);
    EXPECT_EQ(*st1.top(), 200) << "st1 should remain unaffected";
}

// Test erase
TEST_F(StackTest, Erase)
{
    Stack<int> st;
    for (int i = 1; i <= 5; i++) {
        st.push_back(i); // stack: 1,2,3,4,5
    }

    // Erase middle element (index 2 => value 3)
    st.erase(2);
    EXPECT_EQ(st.size(), 4);
    EXPECT_EQ(st[2], 4) << "After erasing index 2, the new index 2 should be "
                           "old value 4";

    // Erase first element
    st.erase(0);
    EXPECT_EQ(st.size(), 3);
    EXPECT_EQ(st[0], 2) << "After erasing index 0, new index 0 should be old "
                           "value 2";
}

// Test remove
TEST_F(StackTest, Remove)
{
    Stack<int> st;
    st.push_back(10);
    st.push_back(20);
    st.push_back(30);

    st.remove(20); // remove the value 20
    EXPECT_EQ(st.size(), 2);
    EXPECT_EQ(st[0], 10);
    EXPECT_EQ(st[1], 30);

    // Attempt removing a value that doesn't exist
    st.remove(999);
    EXPECT_EQ(st.size(), 2) << "Size should not change after removing a "
                               "nonexistent value";
}

// Test indexOf
TEST_F(StackTest, IndexOf)
{
    Stack<SimpleObject> st;
    SimpleObject a {10, 1.0f};
    SimpleObject b {20, 2.0f};
    SimpleObject c {30, 3.0f};
    st.push_back(a);
    st.push_back(b);
    st.push_back(c);

    // We rely on the memcmp logic to find matching struct
    int indexB = st.indexOf(b);
    EXPECT_EQ(indexB, 1) << "Object b should be at index 1";

    SimpleObject notExists {40, 4.0f};
    int indexNotExists = st.indexOf(notExists);
    EXPECT_EQ(indexNotExists, -1) << "Object not in stack should return -1";
}

// Test clear
TEST_F(StackTest, Clear)
{
    Stack<int> st;
    st.push_back(1);
    st.push_back(2);

    st.clear();
    EXPECT_EQ(st.size(), 0);
    EXPECT_TRUE(st.empty());
}

} // namespace
