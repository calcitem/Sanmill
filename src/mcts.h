// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mcts.h

#ifndef MCTS_H
#define MCTS_H

#include "position.h"
#include "types.h"

// #define MCTS_PRINT_STAT

// The role of exploration_parameter in Monte Carlo Tree Search (MCTS) is to
// balance exploration and utilization. During the search,
// MCTS needs to choose between nodes that have not been fully explored
// (nodes that may have high potential) and nodes that have been explored (nodes
// that seem to be better based on their win ratio).
// The exploration_parameter achieves this balance by adjusting the exploration
// term in the UCT (Upper Confidence Bound applied to Trees) formula.
// Larger values for exploration_parameter will make the algorithm more biased
// towards exploring nodes that haven't been visited yet, while smaller values
// will make the algorithm focus more on known good nodes. In other words,
// larger exploration_parameter values will make the algorithm more
// exploration-oriented when selecting nodes, while smaller values will make
// the algorithm more exploit-oriented.
// Appropriate values for exploration_parameter depend on the particular problem
// and application scenario. In general, experimentation can be used to tune the
// exploration_parameter value for best results. Sometimes, some rules of thumb
// can be used, such as the common values of 0.5 or sqrt(2), but this may not
// work in all cases. Therefore, it is recommended that you adjust the
// exploration_parameter according to your actual needs.
static constexpr double EXPLORATION_PARAMETER = 0.5;

// BIAS_FACTOR is a constant factor used to adjust the initial number
// of wins assigned to the child nodes during the expansion phase of the Monte
// Carlo Tree Search (MCTS). This constant introduces a bias towards selecting
// moves with lower index values (i.e., moves that appear earlier in the sorted
// move list) in the search process. A higher value for BIAS_FACTOR
// will result in a stronger preference for earlier moves, while a lower value
// will reduce this preference. Be cautious when adjusting this value, as
// introducing excessive bias may negatively impact the search quality.
static constexpr double BIAS_FACTOR = 0.05;

// Depth for alpha-beta search
static constexpr int ALPHA_BETA_DEPTH = 6;

// The SEARCH_PRUNING_FACTOR is used to reduce the number of moves
// considered during the search process. A larger value results in
// fewer moves being considered, potentially speeding up the search
// at the cost of search accuracy. The value should be adjusted
// according to the specific problem and performance requirements.
// static constexpr int SEARCH_PRUNING_FACTOR = 1;

// Check time limit every N iterations
static constexpr int CHECK_TIME_FREQUENCY = 128;

// Iterations per skill level
static constexpr int ITERATIONS_PER_SKILL_LEVEL = 2048;

Value monte_carlo_tree_search(Position *pos, Move &bestMove);

#endif // MCTS_H
