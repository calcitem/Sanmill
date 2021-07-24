/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "mcts.h"
#include "position.h"
#include "search.h"
#include "movegen.h"
#include "mills.h"
#include "thread.h"

#ifdef MCTS_AI

void doRandomMove(Position &pos, Node *node, mt19937_64 *engine)
{
    assert(hasMoves(pos));
    checkInvariant(pos);

    generate<LEGAL>(pos, node->moves, false);
    int movesSize = node->moves.size();

#ifdef MCTS_PLD
    int i = 0;
    if (movesSize > 1) {
        std::vector<int> v { 0, movesSize - 1 };             // Sample values
        std::vector<int> w { movesSize - 1, 0 };                 // Weights for the samples
        std::piecewise_linear_distribution<> index { std::begin(v), std::end(v), std::begin(w) };

        i = (int)index(*engine);
    }
#else
    uniform_int_distribution<int> index(0, movesSize - 1);
    auto i = index(*engine);
#endif // MCTS_PLD

    Move m = node->moves[i];
    pos.do_move(m);
}

bool hasMoves(Position &pos)
{
    checkInvariant(pos);

    Color winner = pos.get_winner();
    if (winner != NOBODY) {
        return false;
    }

    return true;
}

double getResult(Position &pos, Color currentSideToMove)
{
    assert(!hasMoves(pos));
    checkInvariant(pos);

    auto winner = pos.get_winner();

    if (winner == NOBODY) {
        return 0.5;
    }

    if (winner == currentSideToMove) {
        return 0.0;
    } else {
        return 1.0;
    }
}

void checkInvariant(Position &pos)
{
    assert(pos.sideToMove == WHITE || pos.sideToMove == BLACK);
}

////////////////////////////////////////////////////////////////////////////////////////

Node::Node(Position &position)
{
    sideToMove = position.sideToMove;
    generate<LEGAL>(position, moves, true);
}

Node::Node(Position &position, const Move &m, Node *p)
{
    move = m;
    parent = p;
    sideToMove = position.sideToMove;
    generate<LEGAL>(position, moves, true);
}

void deleteChild(Node *node)
{
    for (int i = 0; i < node->childrenSize; i++) {
        deleteChild(node->children[i]);
    }

    node->childrenSize = 0;

    delete node;
    node = nullptr;
}

Node::~Node()
{
    for (int i = 0; i < childrenSize; i++) {
        deleteChild(children[i]);
    }
}

bool Node::hasUntriedMoves() const
{
    return !moves.empty();
}

template<typename RandomEngine>
Move Node::getUntriedMove(RandomEngine *engine) const
{
    assert(!moves.empty());

#ifdef MCTS_PLD
    int i = 0;
    int movesSize = moves.size();
    if (movesSize > 1) {
        std::vector<int> v{ 0, movesSize - 1 };             // Sample values
        std::vector<int> w{ movesSize - 1, 0 };                 // Weights for the samples
        std::piecewise_linear_distribution<> index{ std::begin(v), std::end(v), std::begin(w) };

        i = (int)index(*engine);
    }

    return moves[i];
#else
    uniform_int_distribution<int> movesDistribution(0, moves.size() - 1);

    return moves[movesDistribution(*engine)];
#endif // #ifdef MCTS_PLD
}

bool Node::hasChildren() const
{
    return (childrenSize != 0);
}

Node *Node::bestChildren() const
{
    assert(moves.empty());
    assert(childrenSize > 0);

    int visitsMax = numeric_limits<int>::min();
    Node *nodeMax = nullptr;

    for (int i = 0; i < childrenSize; i++) {
        if (children[i]->visits > visitsMax) {
            visitsMax = children[i]->visits;
            nodeMax = children[i];
        }
    }

    return nodeMax;
}

Node *Node::selectChild() const
{
    assert(childrenSize > 0);

    for (int i = 0; i < childrenSize; i++) {
        children[i]->score = double(children[i]->wins) / double(children[i]->visits) +
            sqrt(2.0 * log(double(this->visits)) / children[i]->visits);
    }

    double scoreMax = numeric_limits<double>::min();
    Node *nodeMax = nullptr;

    for (int i = 0; i < childrenSize; i++) {
        if (children[i]->score > scoreMax) {
            scoreMax = children[i]->score;
            nodeMax = children[i];
        }
    }

    return nodeMax;
}

Node *Node::addChild(const Move &m, Position &position)
{
    auto node = new Node(position, m, this); // TODO: memmgr_alloc

    //children.push_back(node);
    children[childrenSize] = node;
    childrenSize++;

    assert(childrenSize > 0);

    int iter = 0;
    for (; &moves[iter] != moves.end() && moves[iter] != m; ++iter);

    assert(&moves[iter] != moves.end());

    moves.erase(iter);

    return node;
}

void Node::update(double result)
{
    visits++;

    wins += result;
    //double my_wins = wins.load();
    //while ( ! wins.compare_exchange_strong(my_wins, my_wins + result));
}

string Node::toString()
{
    stringstream sout;

    sout << "["
        << "P" << 3 - sideToMove << " "
        << "M:" << move << " "
        << "W/V: " << wins << "/" << visits << " "
        << "U: " << moves.size() << "]\n";

    return sout.str();
}

#if 0
string Node::treeToString(int maxDepth, int indent) const
{
    if (indent >= maxDepth) {
        return "";
    }

    string s = indentString(indent) + toString();

    for (auto child : children) {
        s += child->treeToString(maxDepth, indent + 1);
    }

    return s;
}
#endif

string Node::indentString(int indent) const
{
    string s = "";

    for (int i = 1; i <= indent; ++i) {
        s += "| ";
    }

    return s;
}

/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////

Node *computeTree(Position position,
                  const MCTSOptions options,
                  mt19937_64::result_type initialSeed)
{
    mt19937_64 random_engine(initialSeed);

    assert(options.maxIterations >= 0 || options.maxTime >= 0);

    if (options.maxTime >= 0) {
#ifndef USE_OPENMP
        throw runtime_error("ComputeOptions::maxTime requires OpenMP.");
#endif
    }

    // Will support more players later.
    assert(position.sideToMove == WHITE || position.sideToMove == BLACK);

    Node *root = new Node(position);

#ifdef USE_OPENMP
    double start_time = ::omp_get_wtime();
    double print_time = start_time;
#endif

    for (int iter = 1; iter <= options.maxIterations || options.maxIterations < 0; ++iter) {
        //auto node = root.get();
        Node *node = root;

        Position pos = position;
        //memcpy(&pos, &position, sizeof(position));  // TODO

        // Select a path through the tree to a leaf node.
        while (!node->hasUntriedMoves() && node->hasChildren()) {
            node = node->selectChild();
            pos.do_move(node->move);
        }

        // If we are not already at the final game, expand the
        // tree with a new node and move there.
        if (node->hasUntriedMoves()) {
            auto move = node->getUntriedMove(&random_engine);
            pos.do_move(move);
            node = node->addChild(move, pos);
        }

        // We now play randomly until the game ends.
        while (hasMoves(pos)) {
            doRandomMove(pos, root, &random_engine);
        }

        // We have now reached a final game. Back propagate the result
        // up the tree to the root node.
        while (node != nullptr) {
            node->update(getResult(pos, node->sideToMove));
            node = node->parent;
        }

#ifdef USE_OPENMP
        if (options.verbose || options.maxTime >= 0) {
            double time = ::omp_get_wtime();
            if (options.verbose && (time - print_time >= 1.0 || iter == options.maxIterations)) {
                cerr << iter << " games played (" << double(iter) / (time - start_time) << " / second)." << endl;
                print_time = time;
            }

            if (time - start_time >= options.maxTime) {
                break;
            }
        }
#endif
    }

    return root;
}

Move Thread::computeMove(Position position,
                         const MCTSOptions options)
{
    // Will support more players later.
    assert(position.sideToMove == WHITE || position.sideToMove == BLACK);

    Mills::move_priority_list_shuffle();

#if 0
    ExtMove moves[MAX_MOVES] { {MOVE_NONE, 0} };
    ExtMove *endMoves = generate<LEGAL>(position, moves);
    int movesSize = int(endMoves - moves);

    assert(movesSize > 0);
    if (movesSize == 1) {
        return moves[0];
    }
#endif

    Sanmill::Stack<Move, MAX_MOVES> moves;
    generate<LEGAL>(position, moves, false);
    assert(moves.size() > 0);
    if (moves.size() == 1) {
        return moves[0];
    }

#ifdef USE_OPENMP
    double start_time = ::omp_get_wtime();
#endif

    // Start all jobs to compute trees.
    future<Node *> rootFutures[THREADS_COUNT];
    MCTSOptions jobOptions = options;

    jobOptions.verbose = true;

    for (int t = 0; t < options.nThreads; ++t) {
        auto func = [t, &position, &jobOptions, this]() -> Node* {
            return computeTree(position, jobOptions, 1012411 * t + 12515);
        };

        rootFutures[t] = async(launch::async, func);
    }

    // Collect the results.
    Node *roots[THREADS_COUNT] = { nullptr };

    for (int t = 0; t < options.nThreads; ++t) {
        roots[t] = move(rootFutures[t].get());
    }

    // Merge the children of all root nodes.
    map<Move, int> visits;
    map<Move, double> wins;
    long long gamesPlayed = 0;

    for (int t = 0; t < options.nThreads; ++t) {
        Node *root = roots[t];
        gamesPlayed += root->visits;

#if 0
        for (auto child = root->children.cbegin(); child != root->children.cend(); ++child) {
            visits[(*child)->move] += (*child)->visits;
            wins[(*child)->move] += (*child)->wins;
        }
#endif

        for (int i = 0; i < root->childrenSize; i++) {
            visits[root->children[i]->move] += root->children[i]->visits;
            wins[root->children[i]->move] += root->children[i]->wins;
        }

        deleteChild(root);
        root = nullptr;
    }

    // Find the node with the highest score.
    double bestScore = -1;
    Move ttMove = Move();

    for (auto iter : visits) {
        auto move = iter.first;
        double v = iter.second;
        double w = wins[move];
        // Expected success rate assuming a uniform prior (Beta(1, 1)).
        // https://en.wikipedia.org/wiki/Beta_distribution
        double expectedSuccessRate = (w + 1) / (v + 2);
        if (expectedSuccessRate > bestScore) {
            ttMove = move;
            bestScore = expectedSuccessRate;
        }

        if (options.verbose) {
            cerr << "Move: " << iter.first
                << " (" << setw(2) << right << int(100.0 * v / double(gamesPlayed) + 0.5) << "% visits)"
                << " (" << setw(2) << right << int(100.0 * w / v + 0.5) << "% wins)" << endl;
        }
    }

    if (options.verbose) {
        auto best_wins = wins[ttMove];
        auto best_visits = visits[ttMove];
        cerr << "----" << endl;
        cerr << "Best: " << ttMove
            << " (" << 100.0 * best_visits / double(gamesPlayed) << "% visits)"
            << " (" << 100.0 * best_wins / best_visits << "% wins)" << endl;
    }

#ifdef USE_OPENMP
    if (options.verbose) {
        double time = ::omp_get_wtime();
        cerr << gamesPlayed << " games played in " << double(time - start_time) << " s. "
            << "(" << double(gamesPlayed) / (time - start_time) << " / second, "
            << options.nThreads << " parallel jobs)." << endl;
    }
#endif

    return ttMove;
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if 0
ostream &operator << (ostream &out, Position &pos)
{
    //state.position->print(out);
    return out;
}
#endif

#endif // MCTS_AI
