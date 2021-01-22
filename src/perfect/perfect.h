#ifndef PERFECT_H
#define PERFECT_H


#include "mill.h"
#include "perfectAI.h"
#include "types.h"

extern Mill *mill;
extern PerfectAI *ai;

// Perfect AI
int perfect_init(void);
Square perfect_sq_to_sq(unsigned int sq);
Move perfect_move_to_move(unsigned int from, unsigned int to);
unsigned sq_to_perfect_sq(Square sq);
void move_to_perfect_move(Move move, unsigned int &from, unsigned int &to);
Move perfect_search();
bool perfect_do_move(Move move);

#endif