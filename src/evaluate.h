// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// evaluate.h

#ifndef EVALUATE_H_INCLUDED
#define EVALUATE_H_INCLUDED

#include <string>

#include "types.h"

class Position;

namespace Eval {

Value evaluate(Position &pos);

// NNUE evaluation
Value evaluate_nnue(Position &pos);

// Hybrid evaluation (traditional + NNUE)
Value evaluate_hybrid(Position &pos);

}

#endif // #ifndef EVALUATE_H_INCLUDED
