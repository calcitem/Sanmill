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

#ifndef MCTS_HEADER_PETTER
#define MCTS_HEADER_PETTER

/*
class GameState
{
public:
	typedef int Move;
	static const Move noMove = ...

	void doMove(Move move);
	template<typename RandomEngine>
	void doRandomMove(*engine);
	bool hasMoves() const;
	vector<Move> MoveList_Generate() const;

	// Returns a value in {0, 0.5, 1}.
	// This should not be an evaluation function, because it will only be
	// called for finished games. Return 0.5 to indicate a draw.
	double getResult(Position &pos, int currentSideToMove) const;

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
#include "types.h"
#include "position.h"
#include "config.h"

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
    int maxIterations { 10000 }; // 40G: 40000000
    double maxTime { 6000 };
    bool verbose { true };
};

class Node
{
public:
    Node();
    ~Node();

#ifdef MCTS_AI
    Node(Position &position);
    Node(Position &position, const Move &move, Node *parent);
#endif // MCTS_AI

    bool hasChildren() const;

#ifdef MCTS_AI
    bool hasUntriedMoves() const;
    template<typename RandomEngine>
    Move getUntriedMove(RandomEngine *engine) const;
    Node *bestChildren() const;
    Node *selectChild() const;
    Node *addChild(const Move &move, Position &position);
    void update(double result);
    string toString();
    string treeToString(int max_depth = 1000000, int indent = 0) const;
    string indentString(int indent) const;
#endif // MCTS_AI

    static const int NODE_CHILDREN_SIZE = MAX_MOVES;

    Node *children[NODE_CHILDREN_SIZE];
    Node *parent{ nullptr };

#ifdef MCTS_AI
    //atomic<double> wins;
    //atomic<int> visits;
    double wins{ 0 };
    double score{ 0 };
    //ExtMove moves[NODE_CHILDREN_SIZE] { {MOVE_NONE, 0} };
    Sanmill::Stack<Move, NODE_CHILDREN_SIZE> moves;
    int visits{ 0 };
#else
    Move moves[NODE_CHILDREN_SIZE];
#endif // MCTS_AI

    Move move { MOVE_NONE };
    int childrenSize { 0 };

    Color sideToMove { NOCOLOR };
};

Node *computeTree(Position &position,
                  const MCTSOptions options,
                  mt19937_64::result_type initialSeed);

void doRandomMove(Position &position, Node *node, mt19937_64 *engine);
void checkInvariant(Position &pos);
bool hasMoves(Position &pos);

//template<typename RandomEngine>
//void doRandomMove(RandomEngine *engine);

double getResult(Position &pos, Color currentSideToMove);

#endif // MCTS_HEADER_PETTER
