/*********************************************************************
	randomAI.cpp
	Copyright (c) Thomas Weber. All rights reserved.
	Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "randomAI.h"

//-----------------------------------------------------------------------------
// Name: randomAI()
// Desc: randomAI class constructor
//-----------------------------------------------------------------------------
randomAI::randomAI()
{
	// Init
	srand((unsigned)time(nullptr));
}

//-----------------------------------------------------------------------------
// Name: ~randomAI()
// Desc: randomAI class destructor
//-----------------------------------------------------------------------------
randomAI::~randomAI()
{
	// Locals

}

//-----------------------------------------------------------------------------
// Name: play()
// Desc: 
//-----------------------------------------------------------------------------
void randomAI::play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo)
{
	// locals
	unsigned int	from, to, direction;
	bool			allowedToSpring = (theField->curPlayer->numStones == 3) ? true : false;

	// must stone be removed ?
	if (theField->stoneMustBeRemoved) {

		// search a stone from the enemy
		do {
			from = rand() % theField->size;
			to = theField->size;
		} while (theField->board[from] != theField->oppPlayer->id || theField->stonePartOfMill[from]);

		// still in setting phase ?
	} else if (theField->settingPhase) {

		// search a free square
		do {
			from = theField->size;
			to = rand() % theField->size;
		} while (theField->board[to] != theField->squareIsFree);

		// try to push randomly
	} else {

		do {
			// search an own stone
			do {
				from = rand() % theField->size;
			} while (theField->board[from] != theField->curPlayer->id);

			// select a free square
			if (allowedToSpring) {
				do {
					to = rand() % theField->size;
				} while (theField->board[to] != theField->squareIsFree);

				// select a connected square
			} else {
				do {
					direction = rand() % 4;
					to = theField->connectedSquare[from][direction];
				} while (to == theField->size);
			}

		} while (theField->board[to] != theField->squareIsFree);
	}

	*pushFrom = from;
	*pushTo = to;
}
