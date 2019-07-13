#include "hashmap.h"

template <typename T>
HashMap<T>::HashMap():
    capacity(0),
    size(0),
    pool(nullptr)
{
    this->capacity = 0x20000000; // TODO
}

template <typename T>
HashMap<T>::HashMap(size_t capacity)
{
    this->capacity = capacity;
    this->size = 0;
    construct();
}

template <typename T>
HashMap<T>::~HashMap()
{
    clear();
}

template <typename T>
bool HashMap<T>::construct()
{
    pool = new T[capacity];

    if (pool ==  nullptr) {
        return false;
    }

    return true;
}

template <typename T>
T& HashMap<T>::at(uint64_t i)
{
    if (i >= capacity) {
        qDebug() << "Error";
        return pool[0];
    }
    return pool[i];
}

template <typename T>
size_t HashMap<T>::getSize()
{
    return size;
}

template <typename T>
size_t HashMap<T>::getCapacity()
{
    return capacity;
}

template <typename T>
uint64_t HashMap<T>::hashToAddr(uint64_t hash)
{
    return hash << 32 >> 32;
}

template <typename T>
void HashMap<T>::insert(uint64_t hash, const T &hashValue)
{
    uint64_t addr = hashToAddr(hash);

    pool[addr] = hashValue;
}

template <typename T>
void HashMap<T>::clear()
{
    delete[] pool;
    pool = nullptr;
}

