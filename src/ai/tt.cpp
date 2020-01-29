/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

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
                      HashType &type
#ifdef BEST_MOVE_ENABLE
                      , move_t &bestMove
#endif // BEST_MOVE_ENABLE
                      )
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

    switch (hashValue.type) {
    case hashfEXACT:
        return hashValue.value;
        break;
    case hashfALPHA:     // 最多是 hashValue.value
        if (hashValue.value <= alpha) {
            return alpha;   // TODO: https://github.com/calcitem/NineChess/issues/25
        }
        break;
    case hashfBETA:     // 至少是 hashValue.value
        if (hashValue.value >= beta) {
            return beta;
        }
        break;
    }

out:

#ifdef BEST_MOVE_ENABLE
    bestMove = hashValue.bestMove;
#endif // BEST_MOVE_ENABLE

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
                   const hash_t &hash
#ifdef BEST_MOVE_ENABLE
                   , const move_t &bestMove
#endif // BEST_MOVE_ENABLE
                  )
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

#ifdef BEST_MOVE_ENABLE
    hashValue.bestMove = bestMove;
#endif // BEST_MOVE_ENABLE

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
    if (transpositionTableAge == std::numeric_limits<uint8_t>::max())
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
