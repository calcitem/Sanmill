#ifndef HASHMAP_H
#define HASHMAP_H

#include <limits>
#include <memory>
#include <mutex>
#include <qDebug>

template <typename T>
class HashMap
{
public:
    //HashMap(size_t capacity, size_t size, T* pool);
    //~HashMap();
    HashMap() = default;

    static HashMap *getInstance()
    {
#if 0
        static std::once_flag s_flag;
        std::call_once(s_flag, [&]() {
            instance.reset(new HashMap);
        });
#endif
        if (instance)

        return *instance;
    }

    static void lock()
    {
        hashMapMutex.lock();
    }

    static void unlock()
    {
        hashMapMutex.unlock();
    }

    static T& at(uint64_t i);

#if 0
    T& operator[](uint64_t hash)
    {
        uint64_t addr = hashToAddr(hash);
        
        return pool[addr];
    }
#endif

    static uint64_t hashToAddr(uint64_t hash);

    static char* find(uint64_t hash)
    {
       // uint64_t addr = hashToAddr(hash);

        return pool[hash <<32 >>32];
    }

    static size_t getSize();
    static size_t getCapacity();

    static void clear();

    static void insert(uint64_t hash, T &hashValue);

    static bool construct();

public:
    static const  uint64_t capacity;
    static uint64_t size;

    static char *pool;

    static std::mutex hashMapMutex;
    
    //static std::auto_ptr<HashMap<T>> instance;
    static HashMap<T>* instance;
public:
    // 防止外部构造。
    //HashMap() = default;
    // 防止拷贝和赋值。
    HashMap &operator=(const HashMap &) = delete; HashMap(const HashMap &another) = delete;
};



#endif // HASHMAP_H
