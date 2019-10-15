/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef STACK_H
#define STACK_H

#include <cstdlib>

template <typename T, size_t capacity = 128>
class Stack
{
public:
    Stack()
    {
    }

    ~Stack()
    {
        memset(arr, 0, sizeof(T) * capacity);
    }

    Stack &operator= (const Stack &other)
    {
        memcpy(arr, other.arr, length());
        p = other.p;
        return *this;
    }

    bool operator== (const T &other) const
    {
        return (p == other.p &&
                memcmp(arr, other.arr, size()));
    }

#if 0
    T operator*(const Stack<T> &obj)
    {
        return (obj.arr);
    };
#endif

    T &operator[](int i)
    {
        return arr[i];
    }

    const T &operator[](int i) const
    {
        return arr[i];
    }

    inline void push(const T &obj)
    {
        p++;
        memcpy(arr + p, &obj, sizeof(T));

        assert(p < capacity);
    }

    inline void push_back(const T &obj)
    {
        p++;
        arr[p] = obj;

        assert(p < capacity);
    }

    inline void pop()
    {
        p--;
    }

    inline T &top()
    {
        return arr[p];
    }

    inline int size()
    {
        return p + 1;
    }

    inline size_t length()
    {
        return (sizeof(T) * size());
    }

    inline T &begin()
    {
        return arr[0];
    }

    inline T &end()
    {
        return arr[p + 1];
    }

    inline bool empty()
    {
        return (p < 0);
    }

    inline void clear()
    {
        p = -1;
    }

private:
    int p { -1 };
    T arr[capacity];
};

#endif // STACK_H
