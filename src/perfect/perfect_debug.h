// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_debug.h

#ifndef PERFECT_DEBUG_H_INCLUDED
#define PERFECT_DEBUG_H_INCLUDED

#include "perfect_common.h"

#include <string>

const char *to_clp(board b);

std::string to_clp2(board b);

std::string to_clp3(board b, Id Id);

#endif // PERFECT_DEBUG_H_INCLUDED
