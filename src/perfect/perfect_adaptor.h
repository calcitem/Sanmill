// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_adaptor.h

#ifndef PERFECT_PERFECT_H_INCLUDED
#define PERFECT_PERFECT_H_INCLUDED

#include "position.h"
#include "types.h"

int perfect_init();
int perfect_exit();
int perfect_reset();
Square from_perfect_square(uint32_t sq);
int to_perfect_square(Square sq);

Value perfect_search(const Position *pos, Move &bestMove);

#endif // PERFECT_H_INCLUDED
