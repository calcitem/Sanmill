//
// Petter Strandmark 2013
// petter.strandmark@gmail.com
// calcitem@outlook.com
//
// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html
//

#include "mcts.h"
#include "position.h"
#include "search.h"

#ifdef MCTS_AI

void Game::doRandomMove(Node *node, mt19937_64 *engine)
{
    assert(hasMoves());
    checkInvariant();
    
    generateMoves(moves);

    int movesSize = moves.size();
    uniform_int_distribution<int> index(0, movesSize - 1);
    auto i = index(*engine);
    move_t m = moves[i];
    doMove(m);
}

bool Game::hasMoves() const
{
    checkInvariant();

    player_t winner = getWinner();
    if (winner != PLAYER_NOBODY) {
        return false;
    }

    return true;
}

double Game::getResult(player_t currentSideToMove) const
{
    assert(!hasMoves());
    checkInvariant();

    auto winner = getWinner();

    if (winner == PLAYER_NOBODY) {
        return 0.5;
    }

    if (winner == currentSideToMove) {
        return 0.0;
    } else {
        return 1.0;
    }
}

void Game::checkInvariant() const
{
    assert(position->sideToMove == PLAYER_BLACK || position->sideToMove == PLAYER_WHITE);
}

////////////////////////////////////////////////////////////////////////////////////////

Node::Node(Game &game) :
    sideToMove(game.position->sideToMove)
{
    game.generateMoves(moves);
}

Node::Node(Game &game, const move_t &m, Node *p) :
    move(m),
    parent(p),
    sideToMove(game.position->sideToMove)
{
    game.generateMoves(moves);
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
move_t Node::getUntriedMove(RandomEngine *engine) const
{
    assert(!moves.empty());

    uniform_int_distribution<size_t> movesDistribution(0, moves.size() - 1);

    return moves[movesDistribution(*engine)];
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

Node *Node::selectChildUCT() const
{
    assert(childrenSize > 0);

    for (int i = 0; i < childrenSize; i++) {
        children[i]->scoreUCT = double(children[i]->wins) / double(children[i]->visits) +
            sqrt(2.0 * log(double(this->visits)) / children[i]->visits);
    }

    double scoreMax = numeric_limits<double>::min();
    Node *nodeMax = nullptr;

    for (int i = 0; i < childrenSize; i++) {
        if (children[i]->scoreUCT > scoreMax) {
            scoreMax = children[i]->scoreUCT;
            nodeMax = children[i];
        }
    }

    return nodeMax;
}

Node *Node::addChild(const move_t &move, Game &game)
{
    auto node = new Node(game, move, this); // TODO: memmgr_alloc

    //children.push_back(node);
    children[childrenSize] = node;
    childrenSize++;

    assert(childrenSize > 0);

    int iter = 0;
    for (; &moves[iter] != moves.end() && moves[iter] != move; ++iter);

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

Node *AIAlgorithm::computeTree(Game game,
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
    assert(game.position->sideToMove == PLAYER_BLACK || game.position->sideToMove == PLAYER_WHITE);

    Node *root = new Node(game);

#ifdef USE_OPENMP
    double start_time = ::omp_get_wtime();
    double print_time = start_time;
#endif

    for (int iter = 1; iter <= options.maxIterations || options.maxIterations < 0; ++iter) {
        //auto node = root.get();
        Node *node = root;

        Game tempGame = game;

        // Select a path through the tree to a leaf node.
        while (!node->hasUntriedMoves() && node->hasChildren()) {
            node = node->selectChildUCT();
            tempGame.doMove(node->move);
        }

        // If we are not already at the final game, expand the
        // tree with a new node and move there.
        if (node->hasUntriedMoves()) {
            auto move = node->getUntriedMove(&random_engine);
            tempGame.doMove(move);
            node = node->addChild(move, tempGame);
        }

        // We now play randomly until the game ends.
        while (tempGame.hasMoves()) {
            tempGame.doRandomMove(root, &random_engine);
        }

        // We have now reached a final game. Backpropagate the result
        // up the tree to the root node.
        while (node != nullptr) {
            node->update(tempGame.getResult(node->sideToMove));
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

move_t AIAlgorithm::computeMove(Game game,
                   const MCTSOptions options)
{
    // Will support more players later.
    assert(game.position->sideToMove == PLAYER_BLACK || game.position->sideToMove == PLAYER_WHITE);

    Stack<move_t, MOVE_COUNT> moves;
    game.generateMoves(moves);
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
        auto func = [t, &game, &jobOptions, this]() -> Node* {
            return computeTree(game, jobOptions, 1012411 * t + 12515);
        };

        rootFutures[t] = async(launch::async, func);
    }

    // Collect the results.
    Node *roots[THREADS_COUNT] = { nullptr };

    for (int t = 0; t < options.nThreads; ++t) {
        roots[t] = move(rootFutures[t].get());
    }

    // Merge the children of all root nodes.
    map<move_t, int> visits;
    map<move_t, double> wins;
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
    move_t bestMove = move_t();

    for (auto iter : visits) {
        auto move = iter.first;
        double v = iter.second;
        double w = wins[move];
        // Expected success rate assuming a uniform prior (Beta(1, 1)).
        // https://en.wikipedia.org/wiki/Beta_distribution
        double expectedSuccessRate = (w + 1) / (v + 2);
        if (expectedSuccessRate > bestScore) {
            bestMove = move;
            bestScore = expectedSuccessRate;
        }

        if (options.verbose) {
            cerr << "Move: " << iter.first
                << " (" << setw(2) << right << int(100.0 * v / double(gamesPlayed) + 0.5) << "% visits)"
                << " (" << setw(2) << right << int(100.0 * w / v + 0.5) << "% wins)" << endl;
        }
    }

    if (options.verbose) {
        auto best_wins = wins[bestMove];
        auto best_visits = visits[bestMove];
        cerr << "----" << endl;
        cerr << "Best: " << bestMove
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

    return bestMove;
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

ostream &operator << (ostream &out, Game &game)
{
    //game.print(out);
    return out;
}

#endif // MCTS_AI
