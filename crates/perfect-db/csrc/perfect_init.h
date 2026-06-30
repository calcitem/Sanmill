// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_init.h
//
// Standalone init / square-mapping helpers extracted from the legacy
// perfect_adaptor (which depended on the removed C++ Position engine).

#ifndef PERFECT_INIT_H_INCLUDED
#define PERFECT_INIT_H_INCLUDED

#include "types.h"

int perfect_init();
int perfect_exit();
int perfect_reset();
Square from_perfect_square(uint32_t sq);
int to_perfect_square(Square sq);

#endif // PERFECT_INIT_H_INCLUDED
