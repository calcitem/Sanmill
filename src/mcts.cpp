// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html

#include "evaluate.h"
#include "mcts.h"
#include "position.h"
#include "types.h"
#include "movegen.h"
#include "option.h"
#include "search.h"
#include <algorithm>
#include <vector>
#include <cmath>

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
    {
    }

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

Value heuristic_evaluation(const Node *node)
{
    //Position *pos = node->position;
    //return Eval::evaluate(*pos);
    //return (Value)node->children.size();
    return VALUE_ZERO;
}

double uct_value_tuned(const Node *node, double exploration_parameter,
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

Node *best_uct_child_tuned(Node *node, double exploration_parameter,
                           double progressive_bias_weight)
{
    Node *best_child = nullptr;
    double best_value = std::numeric_limits<double>::lowest();

    for (Node *child : node->children) {
        double value = uct_value_tuned(child, exploration_parameter,
                                       progressive_bias_weight);
        if (value > best_value) {
            best_value = value;
            best_child = child;
        }
    }

    return best_child;
}

Node *select(Node *node, double exploration_parameter,
             double progressive_bias_weight)
{
    while (!node->children.empty()) {
        node = best_uct_child_tuned(node, exploration_parameter,
                                    progressive_bias_weight);
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

bool simulate(Node *node, int alpha_beta_depth)
{
    if (gameOptions.getShufflingEnabled() == false) {
        srand(42);
    }

    Position *pos = node->position;
    Color side_to_move = pos->side_to_move();

    Move bestMove {MOVE_NONE};
    ss.clear();
    Value value = qsearch(pos, ss, alpha_beta_depth, alpha_beta_depth,
                          -VALUE_INFINITE,
                          VALUE_INFINITE,
                         bestMove);

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
    const int max_iterations = 10000;
    const double exploration_parameter = 1.0;
    const int alpha_beta_depth = 7;
    const double progressive_bias_weight = 0.1; 

    Node *root = new Node(new Position(*pos), MOVE_NONE, nullptr);

    for (int i = 0; i < max_iterations; ++i) {
        Node *node = select(root, exploration_parameter,
                            progressive_bias_weight);
        Node *expanded_node = expand(node);
        bool win = simulate(expanded_node, alpha_beta_depth);
        backpropagate(expanded_node, win);
    }

    Node *best_child = best_uct_child_tuned(root, 0.0, progressive_bias_weight);

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
