//
// Petter Strandmark 2013
// petter.strandmark@gmail.com
//
// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html
//

#include "mcts.h"

void MCTSGame::doMove(move_t move)
{
    assert(0 <= move && move < numCols);
    assert(board[0][move] == playerMarkers[0]);
    checkInvariant();

    int row = numRows - 1;
    while (board[row][move] != playerMarkers[0]) row--;
    board[row][move] = playerMarkers[sideToMove];
    lastCol = move;
    lastRow = row;

    sideToMove = 3 - sideToMove;
}

template<typename RandomEngine>
void MCTSGame::doRandomMove(RandomEngine *engine)
{
    assert(hasMoves());
    checkInvariant();

    uniform_int_distribution<move_t> moves(0, numCols - 1);

    while (true) {
        auto move = moves(*engine);
        if (board[0][move] == playerMarkers[0]) {
            doMove(move);
            return;
        }
    }
}

bool MCTSGame::hasMoves() const
{
    checkInvariant();

    char winner = getWinner();
    if (winner != playerMarkers[0]) {
        return false;
    }

    for (int col = 0; col < numCols; ++col) {
        if (board[0][col] == playerMarkers[0]) {
            return true;
        }
    }

    return false;
}

vector<move_t> MCTSGame::generateMoves() const
{
    checkInvariant();

    vector<move_t> moves;

    if (getWinner() != playerMarkers[0]) {
        return moves;
    }

    moves.reserve(numCols);

    for (int col = 0; col < numCols; ++col) {
        if (board[0][col] == playerMarkers[0]) {
            moves.push_back(col);
        }
    }
    return moves;
}

char MCTSGame::getWinner() const
{
    if (lastCol < 0) {
        return playerMarkers[0];
    }

    // We only need to check around the last piece played.
    auto piece = board[lastRow][lastCol];

    // X X X X
    int left = 0, right = 0;
    for (int col = lastCol - 1; col >= 0 && board[lastRow][col] == piece; --col) left++;
    for (int col = lastCol + 1; col < numCols && board[lastRow][col] == piece; ++col) right++;
    if (left + 1 + right >= 4) {
        return piece;
    }

    // X
    // X
    // X
    // X
    int up = 0, down = 0;
    for (int row = lastRow - 1; row >= 0 && board[row][lastCol] == piece; --row) up++;
    for (int row = lastRow + 1; row < numRows && board[row][lastCol] == piece; ++row) down++;
    if (up + 1 + down >= 4) {
        return piece;
    }

    // X
    //  X
    //   X
    //    X
    up = 0;
    down = 0;
    for (int row = lastRow - 1, col = lastCol - 1; row >= 0 && col >= 0 && board[row][col] == piece; --row, --col) up++;
    for (int row = lastRow + 1, col = lastCol + 1; row < numRows && col < numCols && board[row][col] == piece; ++row, ++col) down++;
    if (up + 1 + down >= 4) {
        return piece;
    }

    //    X
    //   X
    //  X
    // X
    up = 0;
    down = 0;
    for (int row = lastRow + 1, col = lastCol - 1; row < numRows && col >= 0 && board[row][col] == piece; ++row, --col) up++;
    for (int row = lastRow - 1, col = lastCol + 1; row >= 0 && col < numCols && board[row][col] == piece; --row, ++col) down++;
    if (up + 1 + down >= 4) {
        return piece;
    }

    return playerMarkers[0];
}

double MCTSGame::getResult(int currentSideToMove) const
{
    assert(!hasMoves());
    checkInvariant();

    auto winner = getWinner();

    if (winner == playerMarkers[0]) {
        return 0.5;
    }

    if (winner == playerMarkers[currentSideToMove]) {
        return 0.0;
    } else {
        return 1.0;
    }
}

void MCTSGame::print(ostream &out) const
{
    out << endl;
    out << " ";
    for (int col = 0; col < numCols - 1; ++col) {
        out << col << ' ';
    }
    out << numCols - 1 << endl;
    for (int row = 0; row < numRows; ++row) {
        out << "|";
        for (int col = 0; col < numCols - 1; ++col) {
            out << board[row][col] << ' ';
        }
        out << board[row][numCols - 1] << "|" << endl;
    }
    out << "+";
    for (int col = 0; col < numCols - 1; ++col) {
        out << "--";
    }
    out << "-+" << endl;
    out << playerMarkers[sideToMove] << " to move " << endl << endl;
}

void MCTSGame::checkInvariant() const
{
    assert(sideToMove == 1 || sideToMove == 2);
}

////////////////////////////////////////////////////////////////////////////////////////

Node::Node(const MCTSGame &game) :
    sideToMove(game.sideToMove),
    moves(game.generateMoves())
{
}

Node::Node(const MCTSGame &game, const move_t &m, Node *p) :
    move(m),
    parent(p),
    sideToMove(game.sideToMove),
    moves(game.generateMoves())
{
}

Node::~Node()
{
    for (auto child : children) {
        delete child;
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
    return !children.empty();
}


Node *Node::bestChildren() const
{
    assert(moves.empty());
    assert(!children.empty());

    return *max_element(children.begin(), children.end(),
                             [](Node *a, Node *b) { return a->visits < b->visits; });;
}

Node *Node::selectChildUCT() const
{
    assert(!children.empty());

    for (auto child : children) {
        child->scoreUCT = double(child->wins) / double(child->visits) +
                          sqrt(2.0 * log(double(this->visits)) / child->visits);
    }

    return *max_element(children.begin(), children.end(),
                             [](Node *a, Node *b) { return a->scoreUCT < b->scoreUCT; });
}

Node *Node::addChild(const move_t &move, const MCTSGame &game)
{
    auto node = new Node(game, move, this);
    children.push_back(node);

    assert(!children.empty());

    auto iter = moves.begin();
    for (; iter != moves.end() && *iter != move; ++iter);

    assert(iter != moves.end());

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

string Node::toString() const
{
    stringstream sout;

    sout << "["
        << "P" << 3 - sideToMove << " "
        << "M:" << move << " "
        << "W/V: " << wins << "/" << visits << " "
        << "U: " << moves.size() << "]\n";

    return sout.str();
}

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

unique_ptr<Node> computeTree(const MCTSGame rootState,
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
    assert(rootState.sideToMove == 1 || rootState.sideToMove == 2);

    auto root = unique_ptr<Node>(new Node(rootState));

#ifdef USE_OPENMP
    double start_time = ::omp_get_wtime();
    double print_time = start_time;
#endif

    for (int iter = 1; iter <= options.maxIterations || options.maxIterations < 0; ++iter) {
        auto node = root.get();
        MCTSGame game = rootState;

        // Select a path through the tree to a leaf node.
        while (!node->hasUntriedMoves() && node->hasChildren()) {
            node = node->selectChildUCT();
            game.doMove(node->move);
        }

        // If we are not already at the final game, expand the
        // tree with a new node and move there.
        if (node->hasUntriedMoves()) {
            auto move = node->getUntriedMove(&random_engine);
            game.doMove(move);
            node = node->addChild(move, game);
        }

        // We now play randomly until the game ends.
        while (game.hasMoves()) {
            game.doRandomMove(&random_engine);
        }

        // We have now reached a final game. Backpropagate the result
        // up the tree to the root node.
        while (node != nullptr) {
            node->update(game.getResult(node->sideToMove));
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

move_t computeMove(const MCTSGame rootState,
                   const MCTSOptions options)
{
    // Will support more players later.
    assert(rootState.sideToMove == 1 || rootState.sideToMove == 2);

    auto moves = rootState.generateMoves();
    assert(moves.size() > 0);
    if (moves.size() == 1) {
        return moves[0];
    }

#ifdef USE_OPENMP
    double start_time = ::omp_get_wtime();
#endif

    // Start all jobs to compute trees.
    vector<future<unique_ptr<Node>>> rootFutures;
    MCTSOptions jobOptions = options;

    jobOptions.verbose = false;

    for (int t = 0; t < options.nThreads; ++t) {
        auto func = [t, &rootState, &jobOptions]() -> unique_ptr<Node> {
            return computeTree(rootState, jobOptions, 1012411 * t + 12515);
        };

        rootFutures.push_back(async(launch::async, func));
    }

    // Collect the results.
    vector<unique_ptr<Node>> roots;

    for (int t = 0; t < options.nThreads; ++t) {
        roots.push_back(move(rootFutures[t].get()));
    }

    // Merge the children of all root nodes.
    map<move_t, int> visits;
    map<move_t, double> wins;
    long long gamesPlayed = 0;

    for (int t = 0; t < options.nThreads; ++t) {
        auto root = roots[t].get();
        gamesPlayed += root->visits;
        for (auto child = root->children.cbegin(); child != root->children.cend(); ++child) {
            visits[(*child)->move] += (*child)->visits;
            wins[(*child)->move] += (*child)->wins;
        }
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

ostream &operator << (ostream &out, const MCTSGame &game)
{
    game.print(out);
    return out;
}

const char MCTSGame::playerMarkers[3] = { '.', 'X', 'O' };

///////////////////////////////////////////////////////////////////////////////////////////////////////


void runConnectFour()
{
    bool humanPlayer = false;

    MCTSOptions optionsPlayer1, optionsPlayer2;
    optionsPlayer1.maxIterations = 2000000;
    optionsPlayer1.verbose = true;
    optionsPlayer2.maxIterations = 2000000;
    optionsPlayer2.verbose = true;

    MCTSGame game;

    while (game.hasMoves()) {
        cout << endl << "State: " << game << endl;

        move_t move = MCTSGame::noMove;
        if (game.sideToMove == 1) {
            move = computeMove(game, optionsPlayer1);
            game.doMove(move);
        } else {
            if (humanPlayer) {
                while (true) {
                    cout << "Input your move: ";
                    move = MCTSGame::noMove;
                    cin >> move;
                    try {
                        game.doMove(move);
                        break;
                    } catch (exception &) {
                        cout << "Invalid move." << endl;
                    }
                }
            } else {
                move = computeMove(game, optionsPlayer2);
                game.doMove(move);
            }
        }
    }

    cout << endl << "Final game: " << game << endl;

    if (game.getResult(2) == 1.0) {
        cout << "Player 1 wins!" << endl;
    } else if (game.getResult(1) == 1.0) {
        cout << "Player 2 wins!" << endl;
    } else {
        cout << "Nobody wins!" << endl;
    }
}

#ifdef UCT_DEMO
int main()
{
    try {
        runConnectFour();
    } catch (runtime_error & error) {
        cerr << "ERROR: " << error.what() << endl;
        return 1;
    }
}
#endif // UCT_DEMO
