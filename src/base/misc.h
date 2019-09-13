#ifndef MISC_H
#define MISC_H

using TimePoint = std::chrono::milliseconds::rep; // A value in milliseconds

static_assert(sizeof(TimePoint) == sizeof(int64_t), "TimePoint should be 64 bits");

inline TimePoint now()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>
        (std::chrono::steady_clock::now().time_since_epoch()).count();
}

inline uint64_t rand64()
{
    return static_cast<uint64_t>(rand()) ^
        (static_cast<uint64_t>(rand()) << 15) ^
        (static_cast<uint64_t>(rand()) << 30) ^
        (static_cast<uint64_t>(rand()) << 45) ^
        (static_cast<uint64_t>(rand()) << 60);
}

inline uint64_t rand56()
{
    return rand64() << 8;
}

#endif /* MISC_H */
