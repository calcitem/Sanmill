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

extern const key_t zobrist[SQ_EXPANDED_COUNT][PIECETYPE_COUNT];

enum bound_t : uint8_t
{
    BOUND_NONE,
    BOUND_UPPER,
    BOUND_LOWER,
    BOUND_EXACT = BOUND_UPPER | BOUND_LOWER
};

struct TTEntry
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

class TranspositionTable
{
public:
    // 查找哈希表
    static bool search(const key_t &key, TTEntry &tte);
    static value_t probe(const key_t &key,
                            const depth_t &depth,
                            const value_t &alpha,
                            const value_t &beta,
                            bound_t &type
    #ifdef TT_MOVE_ENABLE
                            , move_t &ttMove
    #endif // TT_MOVE_ENABLE
                            );

    // 插入哈希表
    static int save(const value_t &value,
                          const depth_t &depth,
                          const bound_t &type,
                          const key_t &key
#ifdef TT_MOVE_ENABLE
                          , const move_t &ttMove
#endif // TT_MOVE_ENABLE
                         );

    // 清空置换表
    static void clear();

    // 预读取
    static void prefetch(const key_t &key);

private:
    friend struct TTEntry;
};

extern HashMap<key_t, TTEntry> TT;

#ifdef TRANSPOSITION_TABLE_FAKE_CLEAN
extern uint8_t transpositionTableAge;
#endif // TRANSPOSITION_TABLE_FAKE_CLEAN

#endif  // TRANSPOSITION_TABLE_ENABLE

#endif /* TT_H */
