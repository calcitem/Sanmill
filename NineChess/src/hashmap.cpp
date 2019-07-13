#include "hashmap.h"


// template <typename T>
// HashMap<T>(uint64_t capacity, uint64_t size, T *pool)
// {
//     this->capacity = capacity;
//     size = size;
//     //HashMap<T>::construct();
// }


template <typename T>
bool HashMap<T>::construct()
{
    HashMap<T>::pool = new T[capacity];

    if (HashMap<T>::pool ==  nullptr) {
        return false;
    }

    return true;
}



template <typename T>
T& HashMap<T>::at(uint64_t i)
{
    if (i >= capacity) {
        qDebug() << "Error";
        return HashMap<T>::pool[0];
    }
    return HashMap<T>::pool[i];
}

template <typename T>
size_t HashMap<T>::getSize()
{
    return size;
}

template <typename T>
uint64_t HashMap<T>::getCapacity()
{
    return capacity;
}

template <typename T>
uint64_t HashMap<T>::hashToAddr(uint64_t hash)
{
    return hash << 32 >> 32;
}

template <typename T>
void HashMap<T>::insert(uint64_t hash, T &hashValue)
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

template <typename T>
HashMap<T>* HashMap<T>::instance = new HashMap<T>(capacity = 1024, size =  0);

