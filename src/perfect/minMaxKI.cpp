/*********************************************************************
	minMaxKI.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "minMaxKI.h"

//-----------------------------------------------------------------------------
// Name: minMaxKI()
// Desc: minMaxKI class constructor
//-----------------------------------------------------------------------------
minMaxKI::minMaxKI()
{
	depthOfFullTree = 0;
}

//-----------------------------------------------------------------------------
// Name: ~minMaxKI()
// Desc: minMaxKI class destructor
//-----------------------------------------------------------------------------
minMaxKI::~minMaxKI()
{
}

//-----------------------------------------------------------------------------
// Name: play()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo)
{
	// globals
	field			= theField;
	ownId			= field->curPlayer->id; 
	curSearchDepth	= 0;
	unsigned int	bestChoice;
	unsigned int	searchDepth;

	// automatic depth
	if (depthOfFullTree == 0) {
		if (theField->settingPhase)						searchDepth	=  5;  
		else if (theField->curPlayer->numStones <= 4)	searchDepth =  7;  
		else if (theField->oppPlayer->numStones <= 4)	searchDepth =  7;  
		else											searchDepth =  7;  
	} else {
		searchDepth = depthOfFullTree;
	}

	// Inform user about progress
	cout << "minMaxKI is thinking with a depth of " << searchDepth << " steps!\n\n\n";

	// reserve memory
	possibilities	= new possibilityStruct [ searchDepth + 1];
	oldStates		= new backupStruct		[ searchDepth + 1];
	idPossibilities	= new unsigned int		[(searchDepth + 1) * MAX_NUM_POS_MOVES];

	// start the miniMax-algorithmn
	possibilityStruct *rootPossibilities = (possibilityStruct*) getBestChoice(searchDepth, &bestChoice, MAX_NUM_POS_MOVES);

	// decode the best choice
		 if (field->stoneMustBeRemoved) {	*pushFrom	= bestChoice;	*pushTo		= 0;			}
	else if (field->settingPhase)		{	*pushFrom	= 0;			*pushTo		= bestChoice;	}
	else								{	*pushFrom	= rootPossibilities->from[bestChoice];
											*pushTo		= rootPossibilities->to  [bestChoice];		}

	// release memory
	delete [] oldStates;
	delete [] idPossibilities;
	delete [] possibilities;

	// release memory
	field = NULL;
}

//-----------------------------------------------------------------------------
// Name: setSearchDepth()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::setSearchDepth(unsigned int depth)
{
	depthOfFullTree = depth;
}

//-----------------------------------------------------------------------------
// Name: prepareBestChoiceCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::prepareBestChoiceCalculation()
{
	// calculate current value
	currentValue		= 0;
	gameHasFinished		= false;
}

//-----------------------------------------------------------------------------
// Name: getPossSettingPhase()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int *minMaxKI::getPossSettingPhase(unsigned int *numPossibilities, void **pPossibilities)
{
	// locals
	unsigned int i;
	unsigned int *idPossibility			= &idPossibilities[curSearchDepth * MAX_NUM_POS_MOVES];
	
	// possibilities with cut off
	for ((*numPossibilities) = 0, i=0; i<field->size; i++) {

		// move possible ?
		if (field->field[i] == field->squareIsFree) {

			idPossibility[*numPossibilities] = i;
			(*numPossibilities)++;
		}
	}

	// possibility code is simple
	*pPossibilities = NULL;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossNormalMove()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * minMaxKI::getPossNormalMove(unsigned int *numPossibilities, void **pPossibilities)
{
	// locals
	unsigned int		from, to, dir;
	unsigned int		*idPossibility			= &idPossibilities[curSearchDepth * MAX_NUM_POS_MOVES];
	possibilityStruct	*possibility			= &possibilities  [curSearchDepth];
	
	// if he is not allowed to spring
	if (field->curPlayer->numStones > 3) {

		for ((*numPossibilities) = 0, from=0; from < field->size; from++) { for (dir=0; dir<4; dir++) {

			// destination 
			to = field->connectedSquare[from][dir];

			// move possible ?
			if (to < field->size && field->field[from] == field->curPlayer->id && field->field[to] == field->squareIsFree) {

				// stone is moveable
				idPossibility[*numPossibilities]		= *numPossibilities;
				possibility->from[*numPossibilities]	= from;
				possibility->to[*numPossibilities]		= to;
				(*numPossibilities)++;
	
	// current player is allowed to spring
	}}}} else {

		for ((*numPossibilities) = 0, from=0; from < field->size; from++) { for (to=0; to < field->size; to++) {

			// move possible ?
			if (field->field[from] == field->curPlayer->id &&  field->field[to] == field->squareIsFree && *numPossibilities < MAX_NUM_POS_MOVES) {

				// stone is moveable
				idPossibility[*numPossibilities]		= *numPossibilities;
				possibility->from[*numPossibilities]	= from;
				possibility->to[*numPossibilities]		= to;
				(*numPossibilities)++;
	}}}}

	// pass possibilities
	*pPossibilities = (void*)possibility;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossStoneRemove()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * minMaxKI::getPossStoneRemove(unsigned int *numPossibilities, void **pPossibilities)
{
	// locals
	unsigned int i;
	unsigned int *idPossibility			= &idPossibilities[curSearchDepth * MAX_NUM_POS_MOVES];
	
	// possibilities with cut off
	for ((*numPossibilities) = 0, i=0; i<field->size; i++) {

		// move possible ?
		if (field->field[i] == field->oppPlayer->id && !field->stonePartOfMill[i]) {
			
			idPossibility[*numPossibilities] = i;
			(*numPossibilities)++;
		}
	}
	
	// possibility code is simple
	*pPossibilities = NULL;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossibilities()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * minMaxKI::getPossibilities(unsigned int threadNo, unsigned int *numPossibilities, bool *opponentsMove, void **pPossibilities)
{
	// set opponentsMove
	*opponentsMove = (field->curPlayer->id == ownId) ? false : true;

	// When game has ended of course nothing happens any more
	if (gameHasFinished) {
		*numPossibilities = 0;
		return 0;
	// look what is to do
	} else {
		     if (field->stoneMustBeRemoved) return getPossStoneRemove	(numPossibilities, pPossibilities);
		else if (field->settingPhase)		return getPossSettingPhase	(numPossibilities, pPossibilities);
		else								return getPossNormalMove	(numPossibilities, pPossibilities);
	}
}

//-----------------------------------------------------------------------------
// Name: getValueOfSituation()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::getValueOfSituation(unsigned int threadNo, float &floatValue, twoBit &shortValue)
{
	floatValue = currentValue;
	shortValue = 0;
}

//-----------------------------------------------------------------------------
// Name: deletePossibilities()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::deletePossibilities(unsigned int threadNo, void *pPossibilities)
{
}

//-----------------------------------------------------------------------------
// Name: undo()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::undo(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void *pBackup, void *pPossibilities)
{
	// locals
	backupStruct *oldState				= (backupStruct*)pBackup;

	// reset old value
	currentValue						= oldState->value;
	gameHasFinished						= oldState->gameHasFinished;
	curSearchDepth--;

	field->curPlayer					= oldState->curPlayer;							
	field->oppPlayer					= oldState->oppPlayer;							
	field->curPlayer->numStones			= oldState->curNumStones;						
	field->oppPlayer->numStones			= oldState->oppNumStones;						
	field->curPlayer->numStonesMissing	= oldState->curMissStones;						
	field->oppPlayer->numStonesMissing	= oldState->oppMissStones;						
	field->curPlayer->numPossibleMoves	= oldState->curPosMoves;						
	field->oppPlayer->numPossibleMoves	= oldState->oppPosMoves;						
	field->settingPhase					= oldState->settingPhase;						
	field->stonesSet					= oldState->stonesSet;							
	field->stoneMustBeRemoved			= oldState->stoneMustBeRemoved;					
	field->field[oldState->from]		= oldState->fieldFrom;							
	field->field[oldState->to  ]		= oldState->fieldTo;							

	// very expensive
	for (int i=0; i<field->size; i++) {
		field->stonePartOfMill[i]	= oldState->stonePartOfMill[i];
		field->warnings[i]			= oldState->warnings[i];
	}
}

//-----------------------------------------------------------------------------
// Name: setWarning()
// Desc: 
//-----------------------------------------------------------------------------
inline void minMaxKI::setWarning(unsigned int stoneOne, unsigned int stoneTwo, unsigned int stoneThree)
{
	// if all 3 fields are occupied by current player than he closed a mill
	if (field->field[stoneOne] == field->curPlayer->id && field->field[stoneTwo] == field->curPlayer->id && field->field[stoneThree] == field->curPlayer->id) {

			field->stonePartOfMill[stoneOne  ]++;
			field->stonePartOfMill[stoneTwo  ]++;
			field->stonePartOfMill[stoneThree]++;
			field->stoneMustBeRemoved = 1;
	}

	// is a mill destroyed ?
	if (field->field[stoneOne] == field->squareIsFree && field->stonePartOfMill[stoneOne] && field->stonePartOfMill[stoneTwo] && field->stonePartOfMill[stoneThree]) {

			field->stonePartOfMill[stoneOne  ]--;
			field->stonePartOfMill[stoneTwo  ]--;
			field->stonePartOfMill[stoneThree]--;
	}

	// stone was set
	if (field->field[stoneOne] == field->curPlayer->id) {

		// a warnig was destroyed
		field->warnings[stoneOne] = field->noWarning;

		// a warning is created
		if (field->field[stoneTwo  ] == field->curPlayer->id && field->field[stoneThree] == field->squareIsFree) field->warnings[stoneThree] |= field->curPlayer->warning;
		if (field->field[stoneThree] == field->curPlayer->id && field->field[stoneTwo  ] == field->squareIsFree) field->warnings[stoneTwo  ] |= field->curPlayer->warning;
	
	// stone was removed
	} else if (field->field[stoneOne] == field->squareIsFree) {

		// a warning is created
		if (field->field[stoneTwo  ] == field->curPlayer->id && field->field[stoneThree] == field->curPlayer->id) field->warnings[stoneOne] |= field->curPlayer->warning;
		if (field->field[stoneTwo  ] == field->oppPlayer->id && field->field[stoneThree] == field->oppPlayer->id) field->warnings[stoneOne] |= field->oppPlayer->warning;

		// a warning is destroyed
		if (field->warnings[stoneTwo] && field->field[stoneThree] != field->squareIsFree) {

			// reset warning if necessary
			     if (field->field[field->neighbour[stoneTwo][0][0]] == field->curPlayer->id && field->field[field->neighbour[stoneTwo][0][1]] == field->curPlayer->id)	field->warnings[stoneTwo  ] = field->curPlayer->warning;
			else if (field->field[field->neighbour[stoneTwo][1][0]] == field->curPlayer->id && field->field[field->neighbour[stoneTwo][1][1]] == field->curPlayer->id)	field->warnings[stoneTwo  ] = field->curPlayer->warning;
			else if (field->field[field->neighbour[stoneTwo][0][0]] == field->oppPlayer->id && field->field[field->neighbour[stoneTwo][0][1]] == field->oppPlayer->id)	field->warnings[stoneTwo  ] = field->oppPlayer->warning;
			else if (field->field[field->neighbour[stoneTwo][1][0]] == field->oppPlayer->id && field->field[field->neighbour[stoneTwo][1][1]] == field->oppPlayer->id)	field->warnings[stoneTwo  ] = field->oppPlayer->warning;
			else																															field->warnings[stoneTwo  ] = field->noWarning;

		} else if (field->warnings[stoneThree] && field->field[stoneTwo  ] != field->squareIsFree)  {

			// reset warning if necessary
			     if (field->field[field->neighbour[stoneThree][0][0]] == field->curPlayer->id && field->field[field->neighbour[stoneThree][0][1]] == field->curPlayer->id)	field->warnings[stoneThree] = field->curPlayer->warning;
			else if (field->field[field->neighbour[stoneThree][1][0]] == field->curPlayer->id && field->field[field->neighbour[stoneThree][1][1]] == field->curPlayer->id)	field->warnings[stoneThree] = field->curPlayer->warning;
			else if (field->field[field->neighbour[stoneThree][0][0]] == field->oppPlayer->id && field->field[field->neighbour[stoneThree][0][1]] == field->oppPlayer->id)	field->warnings[stoneThree] = field->oppPlayer->warning;
			else if (field->field[field->neighbour[stoneThree][1][0]] == field->oppPlayer->id && field->field[field->neighbour[stoneThree][1][1]] == field->oppPlayer->id)	field->warnings[stoneThree] = field->oppPlayer->warning;
			else																																field->warnings[stoneThree] = field->noWarning;
		}
	} 
}

//-----------------------------------------------------------------------------
// Name: updateWarning()
// Desc: 
//-----------------------------------------------------------------------------
inline void minMaxKI::updateWarning(unsigned int firstStone, unsigned int secondStone)
{
	// set warnings
	if (firstStone  < field->size) setWarning(firstStone,  field->neighbour[firstStone][0][0],  field->neighbour[firstStone][0][1]);
	if (firstStone  < field->size) setWarning(firstStone,  field->neighbour[firstStone][1][0],  field->neighbour[firstStone][1][1]);

	if (secondStone < field->size) setWarning(secondStone, field->neighbour[secondStone][0][0], field->neighbour[secondStone][0][1]);
	if (secondStone < field->size) setWarning(secondStone, field->neighbour[secondStone][1][0], field->neighbour[secondStone][1][1]);

	// no stone must be removed if each belongs to a mill
	unsigned int	i;
	bool			atLeastOneStoneRemoveAble = false;
	if (field->stoneMustBeRemoved) for (i=0; i<field->size; i++) if (field->stonePartOfMill[i] == 0 && field->field[i] == field->oppPlayer->id) { atLeastOneStoneRemoveAble = true; break; }
	if (!atLeastOneStoneRemoveAble) field->stoneMustBeRemoved = 0;
}

//-----------------------------------------------------------------------------
// Name: updatePossibleMoves()
// Desc: 
//-----------------------------------------------------------------------------
inline void minMaxKI::updatePossibleMoves(unsigned int stone, playerStruct *stoneOwner, bool stoneRemoved, unsigned int ignoreStone)
{
	// locals
	unsigned int	neighbor, direction;

	// look into every direction
	for (direction=0; direction<4; direction++) {

		neighbor = field->connectedSquare[stone][direction];

		// neighbor must exist
		if (neighbor < field->size) {

			// relevant when moving from one square to another connected square
			if (ignoreStone == neighbor) continue;

			// if there is no neighbour stone than it only affects the actual stone
			if (field->field[neighbor] == field->squareIsFree) {
			
				if (stoneRemoved)	stoneOwner->numPossibleMoves--;
				else				stoneOwner->numPossibleMoves++;
			
			// if there is a neighbour stone than it effects only this one
			} else if (field->field[neighbor] == field->curPlayer->id) {
				
				if (stoneRemoved)	field->curPlayer->numPossibleMoves++;
				else				field->curPlayer->numPossibleMoves--;

			} else {
				
				if (stoneRemoved)	field->oppPlayer->numPossibleMoves++;
				else				field->oppPlayer->numPossibleMoves--;
			}
	}}

	// only 3 stones resting
	if (field->curPlayer->numStones <= 3 && !field->settingPhase) field->curPlayer->numPossibleMoves = field->curPlayer->numStones * (field->size - field->curPlayer->numStones - field->oppPlayer->numStones);
	if (field->oppPlayer->numStones <= 3 && !field->settingPhase) field->oppPlayer->numPossibleMoves = field->oppPlayer->numStones * (field->size - field->curPlayer->numStones - field->oppPlayer->numStones);
}

//-----------------------------------------------------------------------------
// Name: setStone()
// Desc: 
//-----------------------------------------------------------------------------
inline void	minMaxKI::setStone(unsigned int to, backupStruct *backup)
{
	// backup
	backup->from			= field->size;
	backup->to				= to;
	backup->fieldFrom		= field->size;
	backup->fieldTo			= field->field[to];

	// set stone into field
	field->field[to]		= field->curPlayer->id;
	field->curPlayer->numStones++;
	field->stonesSet++;

	// setting phase finished ?
	if (field->stonesSet == 18) field->settingPhase = false;

	// update possible moves
	updatePossibleMoves(to, field->curPlayer, false, field->size);

	// update warnings
	updateWarning(to, field->size);
}

//-----------------------------------------------------------------------------
// Name: normalMove()
// Desc: 
//-----------------------------------------------------------------------------
inline void	minMaxKI::normalMove(unsigned int from, unsigned int to, backupStruct *backup)
{
	// backup
	backup->from			= from;
	backup->to				= to;
	backup->fieldFrom		= field->field[from];
	backup->fieldTo			= field->field[to  ];

	// set stone into field
	field->field[from]		= field->squareIsFree;
	field->field[to]		= field->curPlayer->id;

	// update possible moves
	updatePossibleMoves(from, field->curPlayer, true, to);
	updatePossibleMoves(to, field->curPlayer, false, from);

	// update warnings
	updateWarning(from, to);
}

//-----------------------------------------------------------------------------
// Name: removeStone()
// Desc: 
//-----------------------------------------------------------------------------
inline void minMaxKI::removeStone(unsigned int from, backupStruct *backup) 
{
	// backup
	backup->from			= from;
	backup->to				= field->size;
	backup->fieldFrom		= field->field[from];
	backup->fieldTo			= field->size;

	// remove stone
	field->field[from]		= field->squareIsFree;
	field->oppPlayer->numStones--;
	field->oppPlayer->numStonesMissing++;
	field->stoneMustBeRemoved--;
	
	// update possible moves
	updatePossibleMoves(from, field->oppPlayer, true, field->size);

	// update warnings
	updateWarning(from, field->size);
	
	// end of game ?
	if ((field->oppPlayer->numStones < 3) && (!field->settingPhase)) gameHasFinished	= true;
}

//-----------------------------------------------------------------------------
// Name: move()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::move(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void **pBackup, void *pPossibilities)
{
	// locals
	backupStruct		*oldState		= &oldStates[curSearchDepth];
	possibilityStruct	*tmpPossibility = (possibilityStruct*) pPossibilities;
	playerStruct		*tmpPlayer;
	unsigned int		i;

	// calculate place of stone
	*pBackup					= (void*) oldState;
	oldState->value				= currentValue;											
	oldState->gameHasFinished	= gameHasFinished;										
	oldState->curPlayer			= field->curPlayer;										
	oldState->oppPlayer			= field->oppPlayer;										
	oldState->curNumStones		= field->curPlayer->numStones;							
	oldState->oppNumStones		= field->oppPlayer->numStones;							
	oldState->curPosMoves		= field->curPlayer->numPossibleMoves;					
	oldState->oppPosMoves		= field->oppPlayer->numPossibleMoves;					
	oldState->curMissStones		= field->curPlayer->numStonesMissing;					
	oldState->oppMissStones		= field->oppPlayer->numStonesMissing;					
	oldState->settingPhase		= field->settingPhase;									
	oldState->stonesSet			= field->stonesSet;										
	oldState->stoneMustBeRemoved= field->stoneMustBeRemoved;							
	curSearchDepth++;
 
	// very expensive
	for (i=0; i<field->size; i++) {
		oldState->stonePartOfMill[i]	= field->stonePartOfMill[i];
		oldState->warnings[i]			= field->warnings[i];
	}

	// move
	if (field->stoneMustBeRemoved)	{ removeStone(idPossibility, oldState);															}
	else if (field->settingPhase)	{ setStone(idPossibility, oldState);															}
	else							{ normalMove(tmpPossibility->from[idPossibility], tmpPossibility->to[idPossibility], oldState);	}

	// when opponent is unable to move than current player has won
	if ((!field->oppPlayer->numPossibleMoves) && (!field->settingPhase) && (!field->stoneMustBeRemoved) && (field->oppPlayer->numStones > 3)) gameHasFinished = true;

	// calc value
	if (!opponentsMove)						currentValue = (float) field->oppPlayer->numStonesMissing - field->curPlayer->numStonesMissing + field->stoneMustBeRemoved + field->curPlayer->numPossibleMoves * 0.1f - field->oppPlayer->numPossibleMoves * 0.1f;
	else									currentValue = (float) field->curPlayer->numStonesMissing - field->oppPlayer->numStonesMissing - field->stoneMustBeRemoved + field->oppPlayer->numPossibleMoves * 0.1f - field->curPlayer->numPossibleMoves * 0.1f;

	// when game has finished - perfect for the current player
	if (gameHasFinished && !opponentsMove)	currentValue =  VALUE_GAME_WON  - curSearchDepth;
	if (gameHasFinished &&  opponentsMove)	currentValue =  VALUE_GAME_LOST + curSearchDepth;

	// set next player
	if (!field->stoneMustBeRemoved) {
		tmpPlayer			= field->curPlayer;
		field->curPlayer	= field->oppPlayer;
		field->oppPlayer	= tmpPlayer;
	}
}

//-----------------------------------------------------------------------------
// Name: printMoveInformation()
// Desc: 
//-----------------------------------------------------------------------------
void minMaxKI::printMoveInformation(unsigned int threadNo, unsigned int idPossibility, void *pPossibilities)
{
	// locals
	possibilityStruct	*tmpPossibility = (possibilityStruct*) pPossibilities;

	// move
	if (field->stoneMustBeRemoved)	cout << "remove stone from " << (char) (idPossibility + 97);														
	else if (field->settingPhase)	cout << "set stone to "      << (char) (idPossibility + 97);															
	else							cout << "move from " << (char) (tmpPossibility->from[idPossibility] + 97) << " to " << (char) (tmpPossibility->to[idPossibility] + 97);
}
