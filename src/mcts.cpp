// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stack>
#include <thread>
#include <vector>
#include <mutex>

#include "mcts.h"
#include "movepick.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "types.h"
#include "uci.h"

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

using namespace std;

// Pre-allocate memory pools for Node and Position objects
template <typename T>
class MemoryPool
{
public:
    // Constructor allocates a block of memory for the specified number of
    // objects
    MemoryPool(size_t pool_size)
        : pool_size_(pool_size)
    {
        pool_ = static_cast<T *>(operator new(pool_size_ * sizeof(T)));
        for (size_t i = 0; i < pool_size_; ++i) {
            free_list_.push_back(pool_ + i);
        }
    }

    ~MemoryPool() { operator delete(pool_); }

    // Acquire an object from the pool
    T *acquire()
    {
        if (free_list_.empty()) {
            // If no object is available, allocate a new one (rare case)
            return new T(); // Error: No matching constructor for initialization
                            // of 'Node'
        }
        T *obj = free_list_.back();
        free_list_.pop_back();
        return obj;
    }

    // Return an object to the pool
    void release(T *obj)
    {
        if (obj >= pool_ && obj < pool_ + pool_size_) {
            obj->~T(); // Call destructor explicitly
            free_list_.push_back(obj);
        } else {
            delete obj; // If not from the pool, delete it
        }
    }

private:
    size_t pool_size_;
    T *pool_;
    std::vector<T *> free_list_;
};

// Thread-safe atomic node visit tracking
class ThreadSafeNodeVisits
{
public:
    explicit ThreadSafeNodeVisits(size_t initial_size)
        : node_visits_(initial_size)
        , node_values_(initial_size, 0.0)
    { }

    // Increment visits using relaxed memory order for reduced synchronization
    void increment_visits(int move_index, uint32_t visits)
    {
        node_visits_[move_index].fetch_add(visits, std::memory_order_relaxed);
    }

    // Add value in a thread-safe manner
    void add_values(int move_index, double value)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        node_values_[move_index] += value;
    }

    // Read the visits count with relaxed memory order
    uint32_t visits(int move_index)
    {
        return node_visits_[move_index].load(std::memory_order_relaxed);
    }

    // Read the total value in a thread-safe manner
    double values(int move_index)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return node_values_[move_index];
    }

private:
    std::vector<std::atomic<uint32_t>> node_visits_;
    std::vector<double> node_values_;
    std::mutex mutex_;
};

// Class representing a node in the MCTS tree
class Node
{
public:
    Node() = default;
    Node(Position *pos, Move m, Node *prt, int idx)
        : position(pos)
        , move(m)
        , parent(prt)
        , move_index(idx)
        , cached_log_parent_visits(-1)
    { }

    void increment_visits() { ++num_visits; }

    void add_value(Value value) { total_value += value; }

    void add_child(Node *child) { children.emplace_back(child); }

    double average_value() const
    {
        return num_visits > 0 ? total_value / num_visits : 0.0;
    }

    Position *position {nullptr};
    Move move;
    Node *parent {nullptr};
    std::vector<Node *> children;
    uint32_t num_visits {0};
    double total_value {0.0};
    int move_index {0};
    mutable double cached_log_parent_visits;
};

// Recursively delete the tree starting from the given node using memory pool
void delete_tree(Node *root, MemoryPool<Node> &node_pool,
                 MemoryPool<Position> &position_pool)
{
    std::stack<Node *> nodes;
    nodes.push(root);

    while (!nodes.empty()) {
        Node *node = nodes.top();
        nodes.pop();

        for (Node *child : node->children) {
            nodes.push(child);
        }

        position_pool.release(node->position);
        node_pool.release(node);
    }
}

// Compute the UCT (Upper Confidence Bound for Trees) value tuned for a node
double uct_value_tuned(const Node *node, double exploration_parameter)
{
    if (node->num_visits == 0) {
        return std::numeric_limits<double>::max();
    }

    if (node->cached_log_parent_visits < 0) {
        node->cached_log_parent_visits = std::log(node->parent->num_visits);
    }

    double mean = node->average_value();
    double exploration_term = exploration_parameter *
                              std::sqrt(2 * node->cached_log_parent_visits /
                                        node->num_visits);
    // Optional: Add variance and bias terms to the UCT value
    // double variance_term = std::sqrt((mean * (1 - mean)) / node->num_visits);
    // double bias_term = BIAS_FACTOR * static_cast<double>(MAX_MOVES -
    // node->move_index);

    return mean + exploration_term; // + variance_term + bias_term;
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

// Select the best child node based on UCT value
Node *select(Node *node, double exploration_parameter)
{
    while (!node->children.empty()) {
        node = best_uct_child_tuned(node, exploration_parameter);
    }
    return node;
}

// Expand the node by creating a new child node for the most promising move
Node *expand(Node *node, MemoryPool<Node> &node_pool,
             MemoryPool<Position> &position_pool)
{
    Position *pos = node->position;

    MovePicker mp(*pos, MOVE_NONE);
    mp.next_move(); // Get the first move

    // Find the first unexpanded move
    for (int i = 0; i < mp.move_count(); ++i) {
        bool already_expanded = false;
        for (Node *child : node->children) {
            if (child->move == mp.moves[i].move) {
                already_expanded = true;
                break;
            }
        }
        if (!already_expanded) {
            // Extend this move
            Position *child_position = position_pool.acquire();
            *child_position = *pos;

            const Move move = mp.moves[i].move;
            child_position->do_move(move);

            Node *child = node_pool.acquire();
            new (child) Node(child_position, move, node, i);
            node->add_child(child);
            return child;
        }
    }

    // If all moves are expanded, return the node itself
    return node;
}

// Simulate a game from the given node
Value simulate(Node *node, Sanmill::Stack<Position> &ss)
{
    Position *pos = node->position;

    Move bestMove {MOVE_NONE};

    Value value = qsearch(pos, ss, ALPHA_BETA_DEPTH, ALPHA_BETA_DEPTH,
                          -VALUE_INFINITE, VALUE_INFINITE, bestMove);

    return value;
}

// Backpropagate the simulation result up the tree
void backpropagate(Node *node, Value value)
{
    while (node != nullptr) {
        node->increment_visits();
        node->add_value(value);
        value = -value;
        node = node->parent;
    }
}

// Worker function for running MCTS on a separate thread
void mcts_worker(Position *pos, int max_iterations,
                 ThreadSafeNodeVisits &shared_visits,
                 MemoryPool<Node> &node_pool,
                 MemoryPool<Position> &position_pool)
{
    Sanmill::Stack<Position> ss;

    Node *root = node_pool.acquire();
    new (root) Node(position_pool.acquire(), MOVE_NONE, nullptr, 0);

    int iteration = 0;

    const int check_time_mask = CHECK_TIME_FREQUENCY - 1;

    // Add time limit (no limit if gameOptions.getMoveTime() returns 0)
    const auto start_time = std::chrono::steady_clock::now();
    const auto move_time = gameOptions.getMoveTime();
    const auto time_limit = move_time > 0 ?
                                std::chrono::seconds(move_time) :
                                std::chrono::steady_clock::time_point::max() -
                                    std::chrono::steady_clock::now();

    while (iteration < max_iterations) {
        Node *node = select(root, EXPLORATION_PARAMETER);
        Node *expanded_node = expand(node, node_pool, position_pool);
        Value sim_value = simulate(expanded_node, ss);
        backpropagate(expanded_node, sim_value);
        iteration++;

        if ((iteration & check_time_mask) == 0) {
            auto current_time = std::chrono::steady_clock::now();
            if (move_time > 0 && current_time - start_time >= time_limit) {
                break;
            }
        }
    }

    for (Node *child : root->children) {
        shared_visits.increment_visits(child->move_index, child->num_visits);
        shared_visits.add_values(child->move_index, child->total_value);
    }

    delete_tree(root, node_pool, position_pool);
}

// MCTS function to find the best move
Value monte_carlo_tree_search(Position *pos, Move &bestMove)
{
    // Adjust these values according to your needs
    int max_iterations = gameOptions.getSkillLevel() *
                         ITERATIONS_PER_SKILL_LEVEL;

    // WAR fix: The first move is slow.
    if (pos->is_board_empty()) {
        max_iterations = 1;
    }

    ThreadSafeNodeVisits shared_visits(MAX_MOVES);

    int num_threads = std::thread::hardware_concurrency();
    if (num_threads == 0) {
        num_threads = 1;
    }

    MemoryPool<Node> node_pool(num_threads * MAX_MOVES);
    MemoryPool<Position> position_pool(num_threads * MAX_MOVES);

    std::vector<std::thread> threads(num_threads);

    for (int i = 0; i < num_threads; ++i) {
        threads[i] = std::thread(mcts_worker, pos, max_iterations / num_threads,
                                 std::ref(shared_visits), std::ref(node_pool),
                                 std::ref(position_pool));
    }

    for (auto &t : threads) {
        if (t.joinable()) {
            t.join();
        }
    }

    MovePicker mp(*pos, MOVE_NONE);
    mp.next_move();

    int best_move_index = 0;
    uint32_t max_visits = 0;

    for (int i = 0; i < mp.move_count(); ++i) {
        uint32_t visits = shared_visits.visits(i);
        if (visits > max_visits) {
            max_visits = visits;
            best_move_index = i;
        }
    }

    bestMove = mp.moves[best_move_index].move;

    Value best_value = (pos->piece_on_board_count(pos->sideToMove) +
                        pos->piece_in_hand_count(pos->sideToMove) -
                        pos->piece_on_board_count(~pos->sideToMove) -
                        pos->piece_in_hand_count(~pos->sideToMove)) *
                       VALUE_EACH_PIECE;
    return best_value;
}
