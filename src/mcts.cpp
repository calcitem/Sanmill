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

#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "types.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <vector>

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

using namespace std;

// Class representing a node in the Monte Carlo Tree Search
class Node
{
public:
    Node(Position *position, Move move, Node *parent, int index)
        : position(position)
        , move(move)
        , move_index(index)
        , parent(parent)
    { }

    double win_score() const
    {
        if (num_visits == 0)
            return 0;
        return static_cast<double>(num_wins) / num_visits;
    }

    void increment_visits() { ++num_visits; }

    void increment_wins() { ++num_wins; }

    void add_child(Node *child) { children.emplace_back(child); }

    Position *position {nullptr};
    Move move;
    Node *parent {nullptr};
    std::vector<Node *> children;
    uint32_t num_visits {0};
    uint32_t num_wins {0};
    int move_index {0};
};

// Recursively delete tree starting from the given node
void delete_tree(Node *node)
{
    for (Node *child : node->children) {
        delete_tree(child);
    }
    delete node->position;
    delete node;
}

// Compute the UCT (Upper Confidence Bound for Trees) value tuned for a node
double uct_value_tuned(const Node *node, double exploration_parameter)
{
    if (node->num_visits == 0) {
        return std::numeric_limits<double>::max();
    }

    double mean = node->win_score();
    double exploration_term = exploration_parameter *
                              std::sqrt(2 * std::log(node->parent->num_visits) /
                                        node->num_visits);
    double variance_term = std::sqrt((mean * (1 - mean)) / node->num_visits);
    double bias_term = BIAS_FACTOR *
                       static_cast<double>(MAX_MOVES - node->move_index);

    return mean + exploration_term + variance_term + bias_term;
}

// Return the best child node according to UCT value tuned
Node *best_uct_child_tuned(Node *node, double exploration_parameter)
{
    Node *best_child = nullptr;
    double best_value = std::numeric_limits<double>::lowest();

    // Loop through all child nodes and find the one with the highest UCT value
    for (Node *child : node->children) {
        double value = uct_value_tuned(child, exploration_parameter);
        if (value > best_value) {
            best_value = value;
            best_child = child;
        }
    }

    return best_child;
}

// Select the next node to expand
Node *select(Node *node, double exploration_parameter)
{
    while (!node->children.empty()) {
        node = best_uct_child_tuned(node, exploration_parameter);
    }
    return node;
}

// Expand the current node by adding child nodes for all legal moves
Node *expand(Node *node)
{
    Position *pos = node->position;

    MovePicker mp(*pos);
    mp.next_move(); // Sort moves
    const int moveCount = mp.move_count();

    // Add child nodes for each sorted legal move
    for (int i = 0; i < moveCount; i++) {
        Position *child_position = new Position(*pos);
        const Move move = mp.moves[i].move;
        child_position->do_move(move);

        Node *child = new Node(child_position, move, node, i);
        node->add_child(child);
    }

    return node->children.empty() ? node : node->children.front();
}

static Sanmill::Stack<Position> ss;

// Simulate a game from the given node and return whether it resulted in a win
bool simulate(Node *node)
{
    Position *pos = node->position;

    Move bestMove {MOVE_NONE};
    ss.clear();

    Value value = qsearch(pos, ss, ALPHA_BETA_DEPTH, ALPHA_BETA_DEPTH,
                          -VALUE_INFINITE, VALUE_INFINITE, bestMove);

    return value > 0;
}

// Back propagate the results of the simulation up the tree
void backpropagate(Node *node, bool win)
{
    while (node != nullptr) {
        node->increment_visits();
        if (win)
            node->increment_wins();
        win = !win;
        node = node->parent;
    }
}

// Perform Monte Carlo Tree Search to find the best move and its value
Value monte_carlo_tree_search(Position *pos, Move &bestMove)
{
    // Adjust these values according to your needs
    int max_iterations = gameOptions.getSkillLevel() *
                               ITERATIONS_PER_SKILL_LEVEL;

    // Workaround fix: The first move is slow.
    if (pos->is_board_empty()) {
        max_iterations = 1;
    }

    // Add time limit (no limit if gameOptions.getMoveTime() returns 0)
    const auto start_time = std::chrono::steady_clock::now();
    const auto move_time = gameOptions.getMoveTime();
    const auto time_limit = move_time > 0 ?
                                std::chrono::seconds(move_time) :
                                std::chrono::steady_clock::time_point::max() -
                                    std::chrono::steady_clock::now();

    // Create the root node
    Node *root = new Node(new Position(*pos), MOVE_NONE, nullptr, 0);

    int iteration = 0;

    // Bit mask for bitwise AND operation
    const int check_time_mask = CHECK_TIME_FREQUENCY - 1;

    // Main MCTS loop
    while (iteration < max_iterations) {
        Node *node = select(root, EXPLORATION_PATAMETER);
        Node *expanded_node = expand(node);
        bool win = simulate(expanded_node);
        backpropagate(expanded_node, win);

        iteration++;

        // Check if the time limit has expired, but not for every iteration
        if ((iteration & check_time_mask) == 0) {
            auto current_time = std::chrono::steady_clock::now();
            if (move_time > 0 && current_time - start_time >= time_limit) {
                break;
            }
        }
    }

    // Find the best child node according to UCT value tuned
    // Note:
    // At the end of the search, we use 0.0 as the exploration parameter
    // to focus only on the win rate. This is because,
    // during the search process, we want to find a good balance point,
    // while at the end of the search, we are only concerned with
    // the win rate of each child node.
    Node *best_child = best_uct_child_tuned(root, 0.0);

    if (best_child == nullptr) {
        bestMove = MOVE_NONE;
        return VALUE_DRAW;
    }

    // Set the best move and calculate its value based on the win rate
    bestMove = best_child->move;

    // Convert win rate to value
    Value best_value = static_cast<Value>(best_child->win_score() * 2.0 - 1.0);

    // Free memory
    delete_tree(root);

    return best_value;
}
