#ifndef HASHMAP_H
#define HASHMAP_H

#include <limits>
#include <qDebug>

template <typename T>
class HashMap
{
public:
    HashMap();
    HashMap(size_t capacity);
    ~HashMap();

    enum FindResult
    {
        HASHMAP_NOTFOUND = INT32_MAX,
    };

    T& at(uint64_t i);

    T& operator[](uint64_t hash)
    {
        uint64_t addr = hashToAddr(hash);
        
        return pool[addr];
    }

    uint64_t hashToAddr(uint64_t hash);

    T &find(uint64_t hash)
    {
        uint64_t addr = hashToAddr(hash);

        return pool[addr];
    }

    size_t getSize();
    size_t getCapacity();

    void clear();

    void insert(uint64_t hash, const T &hashValue);

    bool construct();

private:
    size_t capacity;
    size_t size;

    T *pool;   

};


#endif // HASHMAP_H
