// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef MCTS_H
#define MCTS_H

#include "position.h"
#include "types.h"

// The role of exploration_parameter in Monte Carlo Tree Search (MCTS) is to
// balance exploration (exploration) and utilization (exploitation). During the
// search, MCTS needs to choose between nodes that have not been fully explored
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
static constexpr double exploration_parameter = 1.0;

// If c is set to a very large value, the confidence interval bounds will
// become very large, which will cause all nodes to be considered to be in
// the confidence interval, so that the behavior of the algorithm is
// basically the same as the version without these codes. same. Therefore,
// the default value of c can be set to a large value, such as
// std::numeric_limits<double>::max().
// The value range of c can theoretically be [0, +INF), but in practice,
// you may want to limit it to a smaller range, such as [0, 5].
// Smaller values of c will cause the algorithm to pay more attention to
// promising nodes within the confidence interval, thus doing more pruning,
// while larger values of c will lead to less pruning.
// There is no fixed standard for typical values,
// as it depends on the specific problem and application scenario.
// In practice, it is often necessary to tune the value of c experimentally
// for best results. A possible starting point is to start with a small
// value (such as 0.1 or 1.0), then gradually increase and watch the
// performance of the algorithm change. In this way, you can find the value
// of c that suits your problem and application scenario.
// (The above c refers to confidence_threshold.)
static constexpr double confidence_threshold =
    std::numeric_limits<double>::max();

// Depth for alpha-beta search
static constexpr int alpha_beta_depth = 7;

// Check time limit every N iterations
static constexpr int check_time_frequency = 128;

Value monte_carlo_tree_search(Position *pos, Move &bestMove);

#endif // MCTS_H
