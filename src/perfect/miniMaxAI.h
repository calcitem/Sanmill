/*********************************************************************\
	MiniMaxAI.h
	Copyright (c) Thomas Weber. All rights reserved.
	Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#ifndef MINIMAXAI_H
#define MINIMAXAI_H

#include <iostream>
#include <cstdio>
#include <math.h>
#include "millAI.h"
#include "miniMax.h"

//using namespace std;

#define VALUE_GAME_LOST		-1000.0f
#define VALUE_GAME_WON	     1000.0f

/*** Klassen *********************************************************/
class MiniMaxAI : public MillAI, MiniMax
{
protected:

	// structs
	struct Possibility
	{
		unsigned int from[MAX_NUM_POS_MOVES];
		unsigned int to[MAX_NUM_POS_MOVES];
	};

	struct Backup
	{
		float			value;
		bool			gameHasFinished;
		bool			settingPhase;
		int				fieldFrom, fieldTo;				// value of board
		unsigned int	from, to;						// index of board
		unsigned int	curNumStones, oppNumStones;
		unsigned int	curPosMoves, oppPosMoves;
		unsigned int	curMissStones, oppMissStones;
		unsigned int	stonesSet;
		unsigned int	stoneMustBeRemoved;
		unsigned int	stonePartOfMill[fieldStruct::size];
		unsigned int	warnings[fieldStruct::size];
		Player *curPlayer, *oppPlayer;
	};

	// Variables
	fieldStruct *field;							// pointer of the current board [changed by move()]
	float			currentValue;					// value of current situation for board->currentPlayer
	bool			gameHasFinished;				// someone has won or current board is full

	int				ownId;							// id of the player who called the play()-function
	unsigned int	curSearchDepth;					// current level
	unsigned int	depthOfFullTree;				// search depth where the whole tree is explored
	unsigned int *idPossibilities;				// returned pointer of getPossibilities()-function
	Backup *oldStates;						// for undo()-function	
	Possibility *possibilities;				// for getPossNormalMove()-function

	// Functions
	unsigned int *getPossSettingPhase(unsigned int *numPossibilities, void **pPossibilities);
	unsigned int *getPossNormalMove(unsigned int *numPossibilities, void **pPossibilities);
	unsigned int *getPossStoneRemove(unsigned int *numPossibilities, void **pPossibilities);

	// move functions
	inline void		updatePossibleMoves(unsigned int stone, Player *stoneOwner, bool stoneRemoved, unsigned int ignoreStone);
	inline void		updateWarning(unsigned int firstStone, unsigned int secondStone);
	inline void		setWarning(unsigned int stoneOne, unsigned int stoneTwo, unsigned int stoneThree);
	inline void		removeStone(unsigned int from, Backup *backup);
	inline void		setStone(unsigned int to, Backup *backup);
	inline void		normalMove(unsigned int from, unsigned int to, Backup *backup);

	// Virtual Functions
	void			prepareBestChoiceCalculation();
	unsigned int *getPossibilities(unsigned int threadNo, unsigned int *numPossibilities, bool *opponentsMove, void **pPossibilities);
	void			deletePossibilities(unsigned int threadNo, void *pPossibilities);
	void			move(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void **pBackup, void *pPossibilities);
	void			undo(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void *pBackup, void *pPossibilities);
	void			getValueOfSituation(unsigned int threadNo, float &floatValue, TwoBit &shortValue);
	void			printMoveInformation(unsigned int threadNo, unsigned int idPossibility, void *pPossibilities);

	unsigned int	getNumberOfLayers()
	{
		return 0;
	};
	unsigned int	getNumberOfKnotsInLayer(unsigned int layerNum)
	{
		return 0;
	};
	void            getSuccLayers(unsigned int layerNum, unsigned int *amountOfSuccLayers, unsigned int *succLayers)
	{
	};
	unsigned int	getPartnerLayer(unsigned int layerNum)
	{
		return 0;
	};
	string			getOutputInformation(unsigned int layerNum)
	{
		return string("");
	};
	void			setOpponentLevel(unsigned int threadNo, bool isOpponentLevel)
	{
	};
	bool			setSituation(unsigned int threadNo, unsigned int layerNum, unsigned int stateNumber)
	{
		return false;
	};
	bool			getOpponentLevel(unsigned int threadNo)
	{
		return false;
	};
	unsigned int	getLayerAndStateNumber(unsigned int threadNo, unsigned int &layerNum, unsigned int &stateNumber)
	{
		return 0;
	};
	unsigned int	getLayerNumber(unsigned int threadNo)
	{
		return 0;
	};
	void			getSymStateNumWithDoubles(unsigned int threadNo, unsigned int *numSymmetricStates, unsigned int **symStateNumbers)
	{
	};
	void            getPredecessors(unsigned int threadNo, unsigned int *amountOfPred, RetroAnalysisPredVars *predVars)
	{
	};
	void			printField(unsigned int threadNo, unsigned char value)
	{
	};
	void			prepareDatabaseCalculation()
	{
	};
	void			wrapUpDatabaseCalculation(bool calculationAborted)
	{
	};

public:
	// Constructor / destructor
	MiniMaxAI();
	~MiniMaxAI();

	// Functions
	void			play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo);
	void			setSearchDepth(unsigned int depth);
};

#endif