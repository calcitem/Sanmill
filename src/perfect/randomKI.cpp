/*********************************************************************
	randomKI.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "randomKI.h"

//-----------------------------------------------------------------------------
// Name: randomKI()
// Desc: randomKI class constructor
//-----------------------------------------------------------------------------
randomKI::randomKI()
{
	// Init
	srand( (unsigned)time( NULL ) );
}

//-----------------------------------------------------------------------------
// Name: ~randomKI()
// Desc: randomKI class destructor
//-----------------------------------------------------------------------------
randomKI::~randomKI()
{
	// Locals

}

//-----------------------------------------------------------------------------
// Name: play()
// Desc: 
//-----------------------------------------------------------------------------
void randomKI::play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo)
{
	// locals
	unsigned int	from, to, direction;
	bool			allowedToSpring = (theField->curPlayer->numStones == 3) ? true : false;

	// must stone be removed ?
	if (theField->stoneMustBeRemoved) {

		// search a stone from the enemy
		do {
			from	= rand() % theField->size;
			to		= theField->size;
		} while (theField->field[from] != theField->oppPlayer->id || theField->stonePartOfMill[from]);
	
	// still in setting phase ?
	} else if (theField->settingPhase) {

		// search a free square
		do {
			from	= theField->size;
			to		= rand() % theField->size;
		} while (theField->field[to] != theField->squareIsFree);
	
	// try to push randomly
	} else {

		do {
		// search an own stone
			do {
				from = rand() % theField->size;
			} while (theField->field[from] != theField->curPlayer->id);

			// select a free square
			if (allowedToSpring) {
				do {
					to	= rand() % theField->size;
				} while (theField->field[to] != theField->squareIsFree);
				
			// select a connected square
			} else { 
				do {
					direction	= rand() % 4; 
					to			= theField->connectedSquare[from][direction];
				} while (to == theField->size);
			}

		} while (theField->field[to] != theField->squareIsFree);
	}
	
	*pushFrom	= from;
	*pushTo		= to;
}
