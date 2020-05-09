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

#ifndef TT_H
#define TT_H

#include "config.h"
#include "types.h"
#include "position.h"
#include "search.h"
#include "hashmap.h"

using namespace CTSL;

#ifdef TRANSPOSITION_TABLE_ENABLE

extern const hash_t zobrist[SQ_EXPANDED_COUNT][PIECETYPE_COUNT];

class TranspositionTable
{
public:
    // 定义哈希值的类型
    enum bound_t : uint8_t
    {
        BOUND_NONE,
        BOUND_UPPER,
        BOUND_LOWER,
        BOUND_EXACT = BOUND_UPPER | BOUND_LOWER
    };

    // 定义哈希表的值
    struct HashValue
    {
        value_t value;
        depth_t depth;
        enum bound_t type;
#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
        uint8_t age;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN
#ifdef TT_MOVE_ENABLE
        move_t ttMove;
#endif // TT_MOVE_ENABLE
    };

    // 查找哈希表
    static bool findHash(const hash_t &hash, HashValue &hashValue);
    static value_t probeHash(const hash_t &hash,
                             const depth_t &depth,
                             const value_t &alpha,
                             const value_t &beta,
                             bound_t &type
#ifdef TT_MOVE_ENABLE
                             , move_t &ttMove
#endif // TT_MOVE_ENABLE
                             );

    // 插入哈希表
    static int recordHash(const value_t &value,
                          const depth_t &depth,
                          const bound_t &type,
                          const hash_t &hash
#ifdef TT_MOVE_ENABLE
                          , const move_t &ttMove
#endif // TT_MOVE_ENABLE
                         );

    // 清空置换表
    static void clear();

    // 预读取
    static void prefetchHash(const hash_t &hash);
};

using TT = TranspositionTable;

extern HashMap<hash_t, TT::HashValue> transpositionTable;

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
extern uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

#endif  // TRANSPOSITION_TABLE_ENABLE

#endif /* TT_H */
