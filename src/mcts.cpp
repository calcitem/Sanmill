// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html

#include "config.h"
#include "mcts.h"
#include "movegen.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "tt.h"
#include "types.h"
#include <algorithm>
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
    Node(Position *position, Move move, Node *parent,
#ifdef TRANSPOSITION_TABLE_ENABLE
         Key key
#endif
         )
        : position(position)
        , move(move)
        , parent(parent)
#ifdef TRANSPOSITION_TABLE_ENABLE
        , key(key)
#endif
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
#ifdef TRANSPOSITION_TABLE_ENABLE
    Key key;
    TTEntry tt_entry;
#endif
};

void delete_tree(Node *node)
{
    for (Node *child : node->children) {
        delete_tree(child);
    }
    delete node->position;
    delete node;
}

double uct_value_tuned(const Node *node, double exploration_parameter)
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

Node *best_uct_child_tuned(Node *node, double exploration_parameter)
{
    Node *best_child = nullptr;
    double best_value = std::numeric_limits<double>::lowest();

    for (Node *child : node->children) {
        double value = uct_value_tuned(child, exploration_parameter);
        if (value > best_value) {
            best_value = value;
            best_child = child;
        }
    }

    return best_child;
}

Node *select(Node *node, double exploration_parameter)
{
    while (node!= nullptr && !node->children.empty()) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        if (TranspositionTable::search(node->key, node->tt_entry)) {
            // Update node state based on tt_entry
            node->num_visits = node->tt_entry.visits();
            node->num_wins = node->tt_entry.wins();
        }
#endif
        node = best_uct_child_tuned(node, exploration_parameter);
    }
    return node;
}

Node *expand(Node *node)
{
    if (node == nullptr)
        return nullptr;

    Position *pos = node->position;
    std::vector<Move> legal_moves;
    MoveList<LEGAL> ml(*pos);

    for (const ExtMove *it = ml.begin(); it != ml.end(); ++it) {
        legal_moves.emplace_back(it->move);
    }

    for (const Move &move : legal_moves) {
        Position *child_position = new Position(*pos);
        child_position->do_move(move);
#ifdef TRANSPOSITION_TABLE_ENABLE
        Key child_key = child_position->key();
#endif

        Node *child = new Node(child_position, move, node
#ifdef TRANSPOSITION_TABLE_ENABLE
                               ,
                               child_key
#endif
        );
        node->add_child(child);

#ifdef TRANSPOSITION_TABLE_ENABLE
        // Set default values for value, depth, and type
        Value value = VALUE_NONE;
        Depth depth = DEPTH_NONE;
        Bound type = BOUND_NONE;
        uint32_t visits = 0;
        uint32_t wins = 0;

        // Save the child node in the transposition table
        TranspositionTable::save(value, depth, type, child_key, visits, wins);
#endif
    }

    return node->children.empty() ? node : node->children.front();
}

static Sanmill::Stack<Position> ss;

bool simulate(Node *node, int alpha_beta_depth)
{
    if (node == nullptr) {
        return false;
    }

    if (gameOptions.getShufflingEnabled() == false) {
        srand(42);
    }

    Position *pos = node->position;
    Color side_to_move = pos->side_to_move();

    Move bestMove {MOVE_NONE};
    ss.clear();

#ifdef TRANSPOSITION_TABLE_ENABLE
    Bound boiund_type = BOUND_NONE;
    Value value = TranspositionTable::probe(node->key, alpha_beta_depth,
                                            -VALUE_INFINITE, VALUE_INFINITE,
                                            boiund_type);

    if (value == VALUE_NONE) {
        value = qsearch(pos, ss, alpha_beta_depth, alpha_beta_depth,
                        -VALUE_INFINITE, VALUE_INFINITE, bestMove);
    }
#else
    Value value = qsearch(pos, ss, alpha_beta_depth, alpha_beta_depth,
                          -VALUE_INFINITE, VALUE_INFINITE, bestMove);
#endif

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
    const int max_iterations = 10000;
    const double exploration_parameter = 1.0;
    const int alpha_beta_depth = 7;

    Node *root = new Node(new Position(*pos), MOVE_NONE, nullptr
#ifdef TRANSPOSITION_TABLE_ENABLE
                          ,
                          pos->key()
#endif
    );

    for (int i = 0; i < max_iterations; ++i) {
        Node *node = select(root, exploration_parameter);
        Node *expanded_node = expand(node);
        bool win = simulate(expanded_node, alpha_beta_depth);
        backpropagate(expanded_node, win);
    }

    Node *best_child = best_uct_child_tuned(root, 0.0);

    if (best_child == nullptr) {
        bestMove = MOVE_NONE;
        return VALUE_DRAW;
    }

    bestMove = best_child->move;
    Value best_value = static_cast<Value>(best_child->win_score() * 2.0 -
                                          1.0); // Convert win rate to value

    // Free memory
    delete_tree(root);

#ifdef TRANSPOSITION_TABLE_ENABLE
    // Clear transposition table
    TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

    return best_value;
}
