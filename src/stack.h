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

#ifndef STACK_H_INCLUDED
#define STACK_H_INCLUDED

namespace Sanmill {

template <typename T, size_t capacity = 128>
class Stack
{
public:
    Stack() { arr = new T[capacity]; }

    Stack(const Stack &other) { *this = other; }

    ~Stack() { delete[] arr; }

    Stack &operator=(const Stack &other)
    {
        memcpy(arr, other.arr, length());
        p = other.p;
        return *this;
    }

    bool operator==(const T &other) const
    {
        return p == other.p && memcmp(arr, other.arr, size());
    }

    T &operator[](int i) { return arr[i]; }

    const T &operator[](int i) const { return arr[i]; }

    void push(const T &obj)
    {
        p++;
        memcpy(arr + p, &obj, sizeof(T));
    }

    void push_back(const T &obj)
    {
        p++;
        arr[p] = obj;

        assert(p < capacity);
    }

    void pop() { p--; }

    T *top() { return &arr[p]; }

    [[nodiscard]] int size() const { return p + 1; }

    [[nodiscard]] size_t length() const { return sizeof(T) * size(); }

    T *begin() { return &arr[0]; }

    T *end() { return &arr[p + 1]; }

    [[nodiscard]] bool empty() const { return p < 0; }

    void clear() { p = -1; }

    void erase(int index)
    {
        for (int i = index; i < capacity - 1; i++) {
            arr[i] = arr[i + 1];
        }

        p--;
    }

private:
    T *arr;
    int p {-1};
};

} // namespace Sanmill

#endif // STACK_H_INCLUDED
