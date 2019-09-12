#include "tt.h"

#ifdef TRANSPOSITION_TABLE_ENABLE
static constexpr int TRANSPOSITION_TABLE_SIZE = 0x2000000; // 8-128M:102s, 4-64M:93s 2-32M:91s 1-16M: 冲突
HashMap<hash_t, TranspositionTable::HashValue> transpositionTable(TRANSPOSITION_TABLE_SIZE);

value_t TranspositionTable::probeHash(hash_t hash,
                                 depth_t depth, value_t alpha, value_t beta,
                                 move_t &bestMove, HashType &type)
{
    HashValue hashValue{};

    if (!transpositionTable.find(hash, hashValue)) {
        return VALUE_UNKNOWN;
    }

    if (depth > hashValue.depth) {
        goto out;
    }

    type = hashValue.type;

    if (hashValue.type == hashfEXACT) {
        return hashValue.value;
    }

    if ((hashValue.type == hashfALPHA) && // 最多是 hashValue.value
        (hashValue.value <= alpha)) {
        return alpha;
    }

    if ((hashValue.type == hashfBETA) && // 至少是 hashValue.value
        (hashValue.value >= beta)) {
        return beta;
    }

out:
    bestMove = hashValue.bestMove;
    return VALUE_UNKNOWN;
}

bool TranspositionTable::findHash(hash_t hash, TranspositionTable::HashValue &hashValue)
{
    return transpositionTable.find(hash, hashValue);

    // TODO: 变换局面
#if 0
    if (iter != hashmap.end())
        return iter;

    // 变换局面，查找 hash (废弃)
    dummyPositionShift = dummyPosition;
    for (int i = 0; i < 2; i++) {
        if (i)
            dummyPositionShift.mirror(false);

        for (int j = 0; j < 2; j++) {
            if (j)
                dummyPositionShift.turn(false);
            for (int k = 0; k < 4; k++) {
                dummyPositionShift.rotate(k * 90, false);
                iter = hashmap.find(dummyPositionShift.getHash());
                if (iter != hashmap.end())
                    return iter;
            }
        }
    }
#endif
}

int TranspositionTable::recordHash(value_t value, depth_t depth, TranspositionTable::HashType type, hash_t hash, move_t bestMove)
{
    // 同样深度或更深时替换
    // 注意: 每走一步以前都必须把散列表中所有的标志项置为 hashfEMPTY

    //hashMapMutex.lock();
    HashValue hashValue{};
    memset(&hashValue, 0, sizeof(HashValue));

    if (findHash(hash, hashValue) &&
        hashValue.type != hashfEMPTY &&
        hashValue.depth > depth) {
        return -1;
    }

    hashValue.value = value;
    hashValue.depth = depth;
    hashValue.type = type;
    hashValue.bestMove = bestMove;

    transpositionTable.insert(hash, hashValue);

    //hashMapMutex.unlock();

    return 0;
}

void TranspositionTable::clearTranspositionTable()
{
    transpositionTable.clear();
}

#endif /* TRANSPOSITION_TABLE_ENABLE */
