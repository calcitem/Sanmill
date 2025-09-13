// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// evaluate_tunable.h - Tunable version of evaluation parameters

#ifndef EVALUATE_TUNABLE_H_INCLUDED
#define EVALUATE_TUNABLE_H_INCLUDED

#include <string>
#include "types.h"
#include "tunable_parameters.h"

class Position;

namespace EvalTunable {

// Use tunable parameters instead of static constants
// These will dynamically get values from ParameterManager

// Base piece value
inline Value get_piece_value()
{
    return static_cast<Value>(TUNABLE_PIECE_VALUE);
}

// In-hand piece value
inline Value get_piece_inhand_value()
{
    return static_cast<Value>(TUNABLE_PIECE_INHAND_VALUE);
}

// On-board piece value
inline Value get_piece_onboard_value()
{
    return static_cast<Value>(TUNABLE_PIECE_ONBOARD_VALUE);
}

// Need-remove piece value
inline Value get_piece_needremove_value()
{
    return static_cast<Value>(TUNABLE_PIECE_NEEDREMOVE_VALUE);
}

// Mobility weight
inline double get_mobility_weight()
{
    return TUNABLE_MOBILITY_WEIGHT;
}

// Tunable evaluation function
Value evaluate(Position &pos);

} // namespace EvalTunable

#endif // EVALUATE_TUNABLE_H_INCLUDED
