// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mcts_tunable.h - Tunable version of MCTS parameters

#ifndef MCTS_TUNABLE_H
#define MCTS_TUNABLE_H

#include "position.h"
#include "types.h"
#include "tunable_parameters.h"

// Use tunable parameters instead of static constants
// These macros will use the dynamic values from ParameterManager

// The role of exploration_parameter in Monte Carlo Tree Search (MCTS) is to
// balance exploration and utilization. During the search,
// MCTS needs to choose between nodes that have not been fully explored
// (nodes that may have high potential) and nodes that have been explored (nodes
// that seem to be better based on their win ratio).
// The exploration_parameter achieves this balance by adjusting the exploration
// term in the UCT (Upper Confidence Bound applied to Trees) formula.
#define EXPLORATION_PARAMETER TUNABLE_EXPLORATION_PARAMETER

// BIAS_FACTOR is a constant factor used to adjust the initial number
// of wins assigned to the child nodes during the expansion phase of the Monte
// Carlo Tree Search (MCTS). This constant introduces a bias towards selecting
// moves with lower index values (i.e., moves that appear earlier in the sorted
// move list) in the search process.
#define BIAS_FACTOR TUNABLE_BIAS_FACTOR

// Depth for alpha-beta search
#define ALPHA_BETA_DEPTH TUNABLE_ALPHA_BETA_DEPTH

// Check time limit every N iterations
#define CHECK_TIME_FREQUENCY TUNABLE_CHECK_TIME_FREQUENCY

// Iterations per skill level
#define ITERATIONS_PER_SKILL_LEVEL TUNABLE_ITERATIONS_PER_SKILL_LEVEL

Value monte_carlo_tree_search(Position *pos, Move &bestMove);

#endif // MCTS_TUNABLE_H
