// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html

#include "mcts.h"
#include "evaluate.h"
#include "movegen.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "types.h"
#include <algorithm>
#include <cmath>
#include <mutex>
#include <thread>
#include <vector>

using namespace std;

std::mutex mtx;

Value MTDF(Position *pos, Sanmill::Stack<Position> &ss, Value firstguess,
           Depth depth, Depth originDepth, Move &bestMove);

Value qsearch(Position *pos, Sanmill::Stack<Position> &ss, Depth depth,
              Depth originDepth, Value alpha, Value beta, Move &bestMove);

class Node
{
public:
    Node(Position *position, Move move, shared_ptr<Node> parent)
        : position(position)
        , move(move)
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

    void add_child(shared_ptr<Node> child) { children.emplace_back(child); }

    Position *position;
    Move move;
    shared_ptr<Node> parent;
    std::vector<shared_ptr<Node>> children;
    uint32_t num_visits = 0;
    uint32_t num_wins = 0;
};

void delete_tree(shared_ptr<Node> node)
{
    for (auto &child : node->children) {
        delete_tree(child);
    }
    delete node->position;
}

Value heuristic_evaluation(const shared_ptr<Node> &node)
{
    // Position *pos = node->position;
    // return Eval::evaluate(*pos);
    // return (Value)node->children.size();
    return VALUE_ZERO;
}

double uct_value_tuned(const shared_ptr<Node> &node,
                       double exploration_parameter,
                       double progressive_bias_weight)
{
    if (node->num_visits == 0)
        return std::numeric_limits<double>::max();
    double mean = node->win_score();
    double exploration_term = exploration_parameter *
                              std::sqrt(2 * std::log(node->parent->num_visits) /
                                        node->num_visits);
    double variance_term = std::sqrt((mean * (1 - mean)) / node->num_visits);
    double progressive_bias_term = progressive_bias_weight *
                                   (double)heuristic_evaluation(node);
    return mean + exploration_term + variance_term + progressive_bias_term;
}

shared_ptr<Node> best_uct_child_tuned(shared_ptr<Node> node,
                                      double exploration_parameter,
                                      double progressive_bias_weight)
{
    shared_ptr<Node> best_child = nullptr;
    double best_value = std::numeric_limits<double>::lowest();

    for (auto &child : node->children) {
        double value = uct_value_tuned(child, exploration_parameter,
                                       progressive_bias_weight);
        if (value > best_value) {
            best_value = value;
            best_child = child;
        }
    }

    return best_child;
}

shared_ptr<Node> select(shared_ptr<Node> node, double exploration_parameter,
                        double progressive_bias_weight)
{
    while (!node->children.empty()) {
        node = best_uct_child_tuned(node, exploration_parameter,
                                    progressive_bias_weight);
    }
    return node;
}

shared_ptr<Node> expand(shared_ptr<Node> node)
{
    Position *pos = node->position;
    std::vector<Move> legal_moves;
    MoveList<LEGAL> ml(*pos);

    for (const ExtMove *it = ml.begin(); it != ml.end(); ++it) {
        legal_moves.emplace_back(it->move);
    }

    for (const Move &move : legal_moves) {
        Position *child_position = new Position(*pos);
        child_position->do_move(move);

        shared_ptr<Node> child = make_shared<Node>(child_position, move, node);
        node->add_child(child);
    }

    return node->children.empty() ? node : node->children.front();
}

bool simulate(const shared_ptr<Node> &node, int alpha_beta_depth,
              Sanmill::Stack<Position> &ss)
{
    if (gameOptions.getShufflingEnabled() == false) {
        srand(42);
    }

    Position *pos = node->position;
    Color side_to_move = pos->side_to_move();

    Move bestMove {MOVE_NONE};
    ss.clear();
    Value value = qsearch(pos, ss, alpha_beta_depth, alpha_beta_depth,
                          -VALUE_INFINITE, VALUE_INFINITE, bestMove);

    return value > 0;
}

void backpropagate(shared_ptr<Node> node, bool win)
{
    while (node != nullptr) {
        node->increment_visits();
        if (win)
            node->increment_wins();
        win = !win;
        node = node->parent;
    }
}

class ThreadResult
{
public:
    shared_ptr<Node> best_child = nullptr;
    uint32_t num_visits = 0;
};

void monte_carlo_tree_search_worker(shared_ptr<Node> root, int iterations,
                                    double exploration_parameter,
                                    int alpha_beta_depth,
                                    double progressive_bias_weight,
                                    ThreadResult *result, int thread_index)
{
    Sanmill::Stack<Position> ss;
    for (int i = 0; i < iterations; ++i) {
        shared_ptr<Node> node = select(root, exploration_parameter,
                                       progressive_bias_weight);
        shared_ptr<Node> expanded_node = expand(node);
        bool win = simulate(expanded_node, alpha_beta_depth, ss);
        backpropagate(expanded_node, win);
    }
    result->best_child = best_uct_child_tuned(root, 0.0,
                                              progressive_bias_weight);
    result->num_visits = root->num_visits;
}

Value monte_carlo_tree_search(Position *pos, Move &bestMove)
{
    const int max_iterations = 10000;
    const double exploration_parameter = 1.0;
    const int alpha_beta_depth = 7;
    const double progressive_bias_weight = 0.1;
    const int num_threads = std::thread::hardware_concurrency();

    std::vector<shared_ptr<Node>> roots(num_threads);
    for (int i = 0; i < num_threads; ++i) {
        roots[i] = make_shared<Node>(new Position(*pos), MOVE_NONE, nullptr);
    }

    std::vector<ThreadResult> thread_results(num_threads);
    std::vector<std::thread> threads;

    int iterations_per_thread = max_iterations / num_threads;

    for (int i = 0; i < num_threads; ++i) {
        threads.emplace_back(std::thread(
            monte_carlo_tree_search_worker, roots[i], iterations_per_thread,
            exploration_parameter, alpha_beta_depth, progressive_bias_weight,
            &thread_results[i], i));
    }

    for (auto &t : threads) {
        t.join();
    }

    shared_ptr<Node> root = roots[0];
    for (int i = 1; i < num_threads; ++i) {
        root->num_visits += thread_results[i].num_visits;
        for (const shared_ptr<Node> &child : roots[i]->children) {
            root->children.push_back(child);
        }
    }

    shared_ptr<Node> best_child = best_uct_child_tuned(root, 0.0,
                                                       progressive_bias_weight);

    if (best_child == nullptr) {
        bestMove = MOVE_NONE;
        return VALUE_DRAW;
    }

    bestMove = best_child->move;
    Value best_value = static_cast<Value>(best_child->win_score() * 2.0 - 1.0);

    delete_tree(root);

    return best_value;
}

