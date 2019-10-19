#include "tt.h"

#ifdef TRANSPOSITION_TABLE_ENABLE
static constexpr int TRANSPOSITION_TABLE_SIZE = 0x2000000; // 8-128M:102s, 4-64M:93s 2-32M:91s 1-16M: 冲突
HashMap<hash_t, TT::HashValue> transpositionTable(TRANSPOSITION_TABLE_SIZE);

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

value_t TT::probeHash(const hash_t &hash,
                      const depth_t &depth,
                      const value_t &alpha,
                      const value_t &beta,
                      move_t &bestMove, HashType &type)
{
    HashValue hashValue{};

    if (!transpositionTable.find(hash, hashValue)) {
        return VALUE_UNKNOWN;
    }

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    if (hashValue.age != transpositionTableAge)
    {
        return VALUE_UNKNOWN;
    }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    if (depth > hashValue.depth) {
        goto out;
    }

    type = hashValue.type;

    if (hashValue.type == hashfEXACT) {
        return hashValue.value;
    }

    if ((hashValue.type == hashfALPHA) && // 最多是 hashValue.value
        (hashValue.value <= alpha)) {
        return alpha;   // TODO: https://github.com/calcitem/NineChess/issues/25
    }

    if ((hashValue.type == hashfBETA) && // 至少是 hashValue.value
        (hashValue.value >= beta)) {
        return beta;
    }

out:
    bestMove = hashValue.bestMove;
    return VALUE_UNKNOWN;
}

bool TT::findHash(const hash_t &hash, TT::HashValue &hashValue)
{
    return transpositionTable.find(hash, hashValue);

    // TODO: 变换局面
#if 0
    if (iter != hashmap.end())
        return iter;

    // 变换局面，查找 hash (废弃)
    tempGameShift = tempGame;
    for (int i = 0; i < 2; i++) {
        if (i)
            tempGameShift.mirror(false);

        for (int j = 0; j < 2; j++) {
            if (j)
                tempGameShift.turn(false);
            for (int k = 0; k < 4; k++) {
                tempGameShift.rotate(k * 90, false);
                iter = hashmap.find(tempGameShift.getHash());
                if (iter != hashmap.end())
                    return iter;
            }
        }
    }
#endif
}

int TT::recordHash(const value_t &value,
                   const depth_t &depth,
                   const TT::HashType &type,
                   const hash_t &hash,
                   const move_t &bestMove)
{
    // 同样深度或更深时替换
    // 注意: 每走一步以前都必须把散列表中所有的标志项置为 hashfEMPTY

    //hashMapMutex.lock();
    HashValue hashValue {};

    if (findHash(hash, hashValue)) {
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        if (hashValue.age == transpositionTableAge) {
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
            if (hashValue.type != hashfEMPTY &&
                hashValue.depth > depth) {
                return -1;
            }
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        }
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
    }

    hashValue.value = value;
    hashValue.depth = depth;
    hashValue.type = type;
    hashValue.bestMove = bestMove;

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    hashValue.age = transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

    transpositionTable.insert(hash, hashValue);

    //hashMapMutex.unlock();

    return 0;
}

void TT::clear()
{
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
    if (transpositionTableAge == UINT8_MAX)
    {
        loggerDebug("Clean TT\n");
        transpositionTable.clear();
        transpositionTableAge = 0;
    } else {
        transpositionTableAge++;
    }
#else
    transpositionTable.clear();
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
}

#endif /* TRANSPOSITION_TABLE_ENABLE */
