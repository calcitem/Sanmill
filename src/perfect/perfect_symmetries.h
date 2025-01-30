// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_symmetries.h

#ifndef PERFECT_SYMMETRIES_H_INCLUDED
#define PERFECT_SYMMETRIES_H_INCLUDED

#include "perfect_common.h"

void init_symmetry_lookup_tables();

board sym24_transform(int op, board a);
board sym48_transform(int op, board a);

extern int8_t inv[];

#endif // PERFECT_SYMMETRIES_H_INCLUDED
