// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// stack.h

#ifndef STACK_H_INCLUDED
#define STACK_H_INCLUDED

#include <cstddef>

namespace Sanmill {

template <typename T, int capacity = 128>
class Stack
{
public:
    Stack() { arr = new T[capacity]; }

    Stack(const Stack &other)
        : arr(new T[capacity])
        , p(-1)
    {
        *this = other;
    }

    ~Stack() { delete[] arr; }

    Stack &operator=(const Stack &other)
    {
        if (this == &other) {
            return *this;
        }

        clear();

        for (int i = 0; i <= other.p; i++) {
            push_back(other.arr[i]);
        }

        return *this;
    }

    T &operator[](int i) { return arr[i]; }

    const T &operator[](int i) const { return arr[i]; }

    void push(const T &obj)
    {
        p++;
        arr[p] = obj;
    }

    void pop() { p--; }

    T *top() { return &arr[p]; }

    int size() const { return p + 1; }

    size_t length() const { return sizeof(T) * size(); }

    T *begin() { return &arr[0]; }

    T *end() { return &arr[p + 1]; }

    bool empty() const { return p < 0; }

    void clear() { p = -1; }

    void erase(int index)
    {
        for (int i = index; i < p; i++) {
            arr[i] = arr[i + 1];
        }

        p--;
    }

    void remove(T entry)
    {
        for (int i = 0; i <= p; i++) {
            if (arr[i] == entry) {
                erase(i);
                return;
            }
        }
    }

    int indexOf(T entry)
    {
        for (int i = 0; i <= p; i++) {
            if (arr[i] == entry) {
                return i;
            }
        }
        return -1;
    }

private:
    T *arr;
    int p {-1};
};

} // namespace Sanmill

#endif // STACK_H_INCLUDED
