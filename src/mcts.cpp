#include "mcts.h"
#include "movegen.h"
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

class Node
{
public:
    Node(Position *position, Move move, Node *parent)
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

    void add_child(Node *child) { children.emplace_back(child); }

    Position *position;
    Move move;
    Node *parent;
    std::vector<Node *> children;
    uint32_t num_visits = 0;
    uint32_t num_wins = 0;
};

void delete_tree(Node *node)
{
    for (Node *child : node->children) {
        delete_tree(child);
    }
    delete node->position;
    delete node;
}

bool confident_enough(const Node *node)
{
    if (node->num_visits == 0) {
        return false;
    }

    double mean = node->win_score();
    double delta = confidence_threshold * std::sqrt(std::log(node->parent->num_visits) /
                                 node->num_visits);

    return mean - delta > 0.5;
}

double uct_value_tuned(const Node *node)
{
    if (node->num_visits == 0)
        return std::numeric_limits<double>::max();
    double mean = node->win_score();
    double exploration_term = exploration_parameter *
                              std::sqrt(2 * std::log(node->parent->num_visits) /
                                        node->num_visits);
    double variance_term = std::sqrt((mean * (1 - mean)) / node->num_visits);
    return mean + exploration_term + variance_term;
}

Node *best_uct_child_tuned(Node *node)
{
    Node *best_child = nullptr;
    Node *fallback_child = nullptr;
    double best_value = std::numeric_limits<double>::lowest();
    uint32_t min_visits = std::numeric_limits<uint32_t>::max();

    for (Node *child : node->children) {
        if (!confident_enough(child)) {
            // Fall back to the child with the least visits
            if (child->num_visits < min_visits) {
                min_visits = child->num_visits;
                fallback_child = child;
            }
            continue;
        }

        double value = uct_value_tuned(child);
        if (value > best_value) {
            best_value = value;
            best_child = child;
        }
    }

    // If all children are not confident enough, use the fall back child
    if (best_child == nullptr) {
        return fallback_child;
    }

    return best_child;
}

Node *select(Node *node)
{
    while (!node->children.empty()) {
        node = best_uct_child_tuned(node);
    }
    return node;
}

Node *expand(Node *node)
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

        Node *child = new Node(child_position, move, node);
        node->add_child(child);
    }

    return node->children.empty() ? node : node->children.front();
}

static Sanmill::Stack<Position> ss;

bool simulate(Node *node)
{
    if (gameOptions.getShufflingEnabled() == false) {
        srand(42);
    }

    Position *pos = node->position;

    Move bestMove {MOVE_NONE};
    ss.clear();

    Value value = qsearch(pos, ss, alpha_beta_depth, alpha_beta_depth,
                          -VALUE_INFINITE, VALUE_INFINITE, bestMove);

    return value > 0;
}

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

Value monte_carlo_tree_search(Position *pos, Move &bestMove)
{
    // Adjust these values according to your needs
    const int max_iterations = gameOptions.getSkillLevel() * 1024;

    // Add time limit (no limit if gameOptions.getMoveTime() returns 0)
    const auto start_time = std::chrono::steady_clock::now();
    const auto move_time = gameOptions.getMoveTime();
    const auto time_limit = move_time > 0 ?
                                std::chrono::seconds(move_time) :
                                std::chrono::steady_clock::time_point::max() -
                                    std::chrono::steady_clock::now();

    Node *root = new Node(new Position(*pos), MOVE_NONE, nullptr);

    int iteration = 0;

    // Bit mask for bitwise AND operation
    const int check_time_mask = check_time_frequency - 1;

    while (iteration < max_iterations) {
        Node *node = select(root);
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

    Node *best_child = best_uct_child_tuned(root);

    if (best_child == nullptr) {
        bestMove = MOVE_NONE;
        return VALUE_DRAW;
    }

    bestMove = best_child->move;
    Value best_value = static_cast<Value>(best_child->win_score() * 2.0 -
                                          1.0); // Convert win rate to value

    // Free memory
    delete_tree(root);

    return best_value;
}
