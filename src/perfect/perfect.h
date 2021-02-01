#ifndef PERFECT_H
#define PERFECT_H

#include "mill.h"
#include "perfectAI.h"
#include "types.h"

static const char databaseDirectory[] = "D:\\Muehle\\Muehle";

extern Mill *mill;
extern PerfectAI *ai;

// Perfect AI
int perfect_init(void);
int perfect_exit(void);
int perfect_reset(void);
Square from_perfect_sq(unsigned int sq);
Move from_perfect_move(unsigned int from, unsigned int to);
unsigned to_perfect_sq(Square sq);
void to_perfect_move(Move move, unsigned int &from, unsigned int &to);
Move perfect_search();
bool perfect_do_move(Move move);
bool perfect_command(const char *cmd);

#endif