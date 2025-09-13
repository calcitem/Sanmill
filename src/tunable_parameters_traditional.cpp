// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tunable_parameters_traditional.cpp - Implementation of traditional algorithm
// parameter checking

#include "tunable_parameters_traditional.h"
#include "option.h"

namespace TunableParams {

bool TraditionalParameterManager::is_traditional_algorithm_selected() const
{
    // Check if current algorithm is a traditional search algorithm (not MCTS)
    return gameOptions.getAlphaBetaAlgorithm() ||
           gameOptions.getPvsAlgorithm() || gameOptions.getMtdfAlgorithm();
}

} // namespace TunableParams
