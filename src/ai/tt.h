#ifndef TT_H
#define TT_H

#include "config.h"
#include "types.h"
#include "position.h"
#include "search.h"
#include "hashmap.h"

using namespace CTSL;

#ifdef TRANSPOSITION_TABLE_ENABLE

extern const hash_t zobrist[SQ_EXPANDED_COUNT][PIECE_TYPE_COUNT];

class TranspositionTable
{
public:
    // 定义哈希值的类型
    enum HashType : uint8_t
    {
        hashfEMPTY = 0,
        hashfALPHA = 1, // 结点的值最多是 value
        hashfBETA = 2,  // 结点的值至少是 value
        hashfEXACT = 3  // 结点值 value 是准确值
    };

    // 定义哈希表的值
    struct HashValue
    {
        value_t value;
        depth_t depth;
        enum HashType type;
        move_t bestMove;
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        uint8_t age;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
    };

    // 查找哈希表
    static bool findHash(hash_t hash, HashValue &hashValue);
    static value_t probeHash(hash_t hash, depth_t depth, value_t alpha, value_t beta, move_t &bestMove, HashType &type);

    // 插入哈希表
    static int recordHash(value_t value, depth_t depth, HashType type, hash_t hash, move_t bestMove);

    // 清空置换表
    static void clear();
};

using TT = TranspositionTable;

extern HashMap<hash_t, TT::HashValue> transpositionTable;

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
extern uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

#endif  // TRANSPOSITION_TABLE_ENABLE

#endif /* TT_H */
