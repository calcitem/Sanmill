// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "gtest/gtest.h"

#include "stack.h"
using namespace Sanmill;

namespace {

TEST(stackPushTest, stackTest)
{
    Stack<int> stack;

    EXPECT_TRUE(stack.empty());

    stack.push(0);
    EXPECT_EQ(stack.size(), 1);
    EXPECT_EQ(stack[0], 0);
    EXPECT_EQ(stack.top()[0], 0);
    EXPECT_EQ(stack.begin()[0], 0);
    EXPECT_EQ(stack.end()[-1], 0);
    EXPECT_FALSE(stack.empty());

    stack.push_back(1);
    EXPECT_EQ(stack.size(), 2);
    EXPECT_EQ(stack.length(), sizeof(int) * 2);
    EXPECT_EQ(stack[1], 1);
    EXPECT_EQ(stack.top()[0], 1);
    EXPECT_EQ(stack.begin()[0], 0);
    EXPECT_EQ(stack.end()[-1], 1);
    EXPECT_FALSE(stack.empty());

    stack.pop();
    EXPECT_EQ(stack.size(), 1);
    EXPECT_EQ(stack[1], 1);
    EXPECT_EQ(stack.top()[0], 0);
    EXPECT_EQ(stack.begin()[0], 0);
    EXPECT_EQ(stack.end()[-1], 0);
    EXPECT_FALSE(stack.empty());

    stack.pop();
    EXPECT_EQ(stack.size(), 0);
    EXPECT_TRUE(stack.empty());

    stack.push_back(0);
    stack.push_back(1);
    stack.push_back(2);
    stack.push_back(3);
    stack.push_back(4);
    EXPECT_EQ(stack.size(), 5);
    stack.erase(2);
    EXPECT_EQ(stack.size(), 4);
    EXPECT_EQ(stack[0], 0);
    EXPECT_EQ(stack[1], 1);
    EXPECT_EQ(stack[2], 3);
    EXPECT_EQ(stack[3], 4);
    stack.erase(0);
    EXPECT_EQ(stack.size(), 3);
    EXPECT_EQ(stack[0], 1);
    EXPECT_EQ(stack[1], 3);
    EXPECT_EQ(stack[2], 4);
    stack.erase(2);
    EXPECT_EQ(stack.size(), 2);
    EXPECT_EQ(stack[0], 1);
    EXPECT_EQ(stack[1], 3);
    stack.erase(0);
    stack.erase(0);

    //stack.erase(0);
    // EXPECT_EQ(stack.size(), -1); // TODO(calcitem)

    stack.push_back(0);
    stack.push_back(1);
    stack.push_back(2);
    stack.push_back(3);
    stack.push_back(4);
    EXPECT_EQ(stack.size(), 5);
    stack.clear();
    EXPECT_EQ(stack.size(), 0);

    stack.push_back(0);
    stack.push_back(1);
    Stack<int>& stackRef = stack;
    EXPECT_EQ(stack.size(), 2);

    // TODO(calcitem)
    //Stack<int> anotherStack = stack;
    //EXPECT_EQ(stack == anotherStack, true);
}

} // namespace
