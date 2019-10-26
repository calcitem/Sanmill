/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

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
    static bool findHash(const hash_t &hash, HashValue &hashValue);
    static value_t probeHash(const hash_t &hash, const depth_t &depth, const value_t &alpha, const value_t &beta, move_t &bestMove, HashType &type);

    // 插入哈希表
    static int recordHash(const value_t &value, const depth_t &depth, const HashType &type, const hash_t &hash, const move_t &bestMove);

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
