#ifndef MCTS_H
#define MCTS_H

// Monte Carlo Tree Search for finite games.
//
// Originally based on Python code at
// http://mcts.ai/code/python.html

#include "types.h"
#include "position.h"

Value monte_carlo_tree_search(Position *pos, Move &bestMove);

#endif // MCTS_H
