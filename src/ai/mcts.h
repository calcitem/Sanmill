#ifndef MCTS_HEADER_PETTER
#define MCTS_HEADER_PETTER
//
// Petter Strandmark 2013
// petter.strandmark@gmail.com
//
// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html
//
// Uses the "root parallelization" technique [1].
//
// This game engine can play any game defined by a game like this:
/*

class GameState
{
public:
	typedef int move_t;
	static const move_t noMove = ...

	void doMove(Move move);
	template<typename RandomEngine>
	void doRandomMove(*engine);
	bool hasMoves() const;
	vector<move_t> MoveList_Generate() const;

	// Returns a value in {0, 0.5, 1}.
	// This should not be an evaluation function, because it will only be
	// called for finished games. Return 0.5 to indicate a draw.
	double getResult(int currentSideToMove) const;

	int sideToMove;

	// ...
private:
	// ...
};

*/
//
// See the examples for more details. Given a suitable State, the
// following function (tries to) compute the best move for the
// player to move.
//

#include <algorithm>
#include <cstdlib>
#include <future>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>
#include <cassert>

#include "stack.h"

#ifdef _DEBUG
#define USE_OPENMP
#endif

#ifdef USE_OPENMP
#include <omp.h>
#endif

#include "config.h"

using namespace std;

typedef int move_t;

class MCTSGame
{
public:
    typedef int move_t;
    static const move_t noMove = -1;

    static const char playerMarkers[3];

    MCTSGame()
        : sideToMove(1),
        lastCol(-1),
        lastRow(-1)
    {
		for (int r = 0; r < numRows; r++) {
			for (int c = 0; c < numCols; c++) {
				board[r][c] = playerMarkers[0];
			}
		}
    }

    void doMove(move_t move);

    template<typename RandomEngine>
    void doRandomMove(RandomEngine *engine);

    bool hasMoves() const;

    void generateMoves(Stack<move_t, 8> &moves) const;

    char getWinner() const;

    double getResult(int currentSideToMove) const;

	void print(ostream &out) const;

    int sideToMove;
private:

	void checkInvariant() const;

	static const int numRows = 6;
	static const int numCols = 7;

	char board[numRows][numCols];
	
    int lastCol;
    int lastRow;
};

static const int THREADS_COUNT = 2;

class MCTSOptions
{
public:
	int nThreads { THREADS_COUNT };
	int maxIterations { 10000 };
	double maxTime { -1.0 };
	bool verbose { false };
};

//
//
// [1] Chaslot, G. M. B., Winands, M. H., & van Den Herik, H. J. (2008).
//     Parallel monte-carlo tree search. In Computers and Games (pp.
//     60-71). Springer Berlin Heidelberg.
//

//
// This class is used to build the game tree. The root is created by the users and
// the rest of the tree is created by add_node.
//

class Node
{
public:
	Node(const MCTSGame &game);
	~Node();

	bool hasUntriedMoves() const;

	template<typename RandomEngine>
	move_t getUntriedMove(RandomEngine *engine) const;

	Node *bestChildren() const;

	bool hasChildren() const;

	Node *selectChildUCT() const;

	Node *addChild(const move_t &move, const MCTSGame &game);

	void update(double result);

	string toString();
	string treeToString(int max_depth = 1000000, int indent = 0) const;

	static const int NODE_CHILDREN_SIZE = 8;

	const move_t move { MCTSGame::noMove };
	Node *const parent {nullptr};
	const int sideToMove;

	//atomic<double> wins;
	//atomic<int> visits;
	double wins { 0 };
	int visits { 0 };

	Stack<move_t, 8> moves;
	Node *children[NODE_CHILDREN_SIZE];
	int childrenSize { 0 };

private:
	Node(const MCTSGame &game, const move_t &move, Node *parent);

	string indentString(int indent) const;

	Node(const Node &);
	Node &operator = (const Node &);

	double scoreUCT { 0 };
};

move_t computeMove(const MCTSGame game,
                   const MCTSOptions options = MCTSOptions());


#endif // MCTS_HEADER_PETTER
