#ifndef HASHMAP_H

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

    T &find(uint64_t hash)
    {
        uint64_t addr = hashToAddr(hash);

        return pool[addr];
    }

    size_t getSize();
    size_t getCapacity();

    void clear();

    void insert(uint64_t hash, const T &hashValue);

protected:
private:
    size_t capacity;
    size_t size;

    T *pool;

    bool construct();
    
    uint64_t hashToAddr(uint64_t hash);
};


#endif // HASHMAP_H