// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_init.cpp

#include "config.h"

#include <cassert>

#include "option.h"
#include "perfect_common.h"
#include "perfect_errors.h"
#include "perfect_init.h"
#include "perfect_sector.h"
#include "perfect_wrappers.h"
#include "rule.h"
#include "types.h"

extern int ruleVariant;
extern int maxKsz;

int perfect_init()
{
    if (rule.pieceCount == 9) {
        ruleVariant = (int)Wrappers::Constants::Variants::std;
    } else if (rule.pieceCount == 12) {
        ruleVariant = (int)Wrappers::Constants::Variants::mora;
    } else if (rule.pieceCount == 10) {
        ruleVariant = (int)Wrappers::Constants::Variants::lask;
    } else {
        ruleVariant = (int)Wrappers::Constants::Variants::std;
    }

    switch (ruleVariant) {
    case (int)Wrappers::Constants::Variants::std:
        ruleVariantName = "std";
        maxKsz = 9;
        field2Offset = 12;
        break;
    case (int)Wrappers::Constants::Variants::mora:
        ruleVariantName = "mora";
        maxKsz = 12;
        field2Offset = 14;
        break;
    case (int)Wrappers::Constants::Variants::lask:
        ruleVariantName = "lask";
        maxKsz = 10;
        field2Offset = 14;
        break;
    default:
        assert(false);
        break;
    }

#ifdef FULL_SECTOR_GRAPH
    maxKsz = 12;
#endif

    field1Size = field2Offset;
    field2Size = 8 * eval_struct_size - field2Offset;
    secValMinValue = -(1 << (field1Size - 1));

    sectors.resize(maxKsz + 1);
    for (int i = 0; i <= maxKsz; ++i) {
        sectors[i].resize(maxKsz + 1);
        for (int j = 0; j <= maxKsz; ++j) {
            sectors[i][j].resize(maxKsz + 1);
            for (int k = 0; k <= maxKsz; ++k) {
                sectors[i][j][k].resize(maxKsz + 1);
            }
        }
    }

    return 0;
}

int perfect_exit()
{
    return 0;
}

int perfect_reset()
{
    return perfect_init();
}

Square from_perfect_square(uint32_t sq)
{
    constexpr Square map[] = {SQ_30, SQ_31, SQ_24, SQ_25, SQ_26, SQ_27, SQ_28,
                              SQ_29, SQ_22, SQ_23, SQ_16, SQ_17, SQ_18, SQ_19,
                              SQ_20, SQ_21, SQ_14, SQ_15, SQ_8,  SQ_9,  SQ_10,
                              SQ_11, SQ_12, SQ_13, SQ_0};

    return map[sq];
}

int to_perfect_square(Square sq)
{
    constexpr int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        18, 19, 20, 21, 22, 23, 16, 17, /* 8 - 15 */
        10, 11, 12, 13, 14, 15, 8,  9,  /* 16 - 23 */
        2,  3,  4,  5,  6,  7,  0,  1,  /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}
