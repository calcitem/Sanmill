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

#ifdef _WIN32
#define USE_OPENMP
#endif

#ifdef USE_OPENMP
#include <omp.h>
#endif

#include "config.h"

using namespace std;

static const int THREADS_COUNT = 2;

class MCTSOptions
{
public:
    int nThreads { THREADS_COUNT };
    int maxIterations { 40000000 };
    double maxTime { 6000 };
    bool verbose { true };
};

#endif // MCTS_HEADER_PETTER
