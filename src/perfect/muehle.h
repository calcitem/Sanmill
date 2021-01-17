/*********************************************************************\
	muehle.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#ifndef MUEHLE_H
#define MUEHLE_H

#include <iostream>
#include <cstdio>
#include <time.h>
#include <stdlib.h>
#include "muehleKI.h"

using namespace std;

/*** Konstanten ******************************************************/
#define	MAX_NUM_MOVES	10000

/*** Makros ******************************************************/
#define SAFE_DELETE(p)			{ if(p) { delete (p);     (p)=NULL; } }
#define SAFE_DELETE_ARRAY(p)	{ if(p) { delete[] (p);   (p)=NULL; } }

/*** Klassen *********************************************************/

class muehle
{
private: 
	// Variables
	unsigned int	*moveLogFrom, *moveLogTo, movesDone;			// array containing the history of moves done
	muehleKI		*playerOneKI;									// class-pointer to the AI of player one
	muehleKI		*playerTwoKI;									// class-pointer to the AI of player two
	fieldStruct		field;											// current field
	fieldStruct		initialField;									// undo of the last move is done by setting the initial field und performing all moves saved in history
	int				winner;											// playerId of the player who has won the game. zero if game is still running.
	int				beginningPlayer;								// playerId of the player who makes the first move

	// Functions
	void			deleteArrays				();
	void			setNextPlayer				();
	void			calcPossibleMoves			(playerStruct *player);
	void			updateMillsAndWarnings		(unsigned int newStone);
	bool			isNormalMovePossible		(unsigned int from, unsigned int to, playerStruct *player);
	void			setWarningAndMill			(unsigned int stone, unsigned int firstNeighbour, unsigned int secondNeighbour, bool isNewStone);
	
public:
    // Constructor / destructor
					muehle						();
					~muehle						();

	// Functions
	void			undoLastMove				();
	void			beginNewGame				(muehleKI *firstPlayerKI, muehleKI *secondPlayerKI, int currentPlayer);
	void			setKI						(int player, muehleKI *KI);
	bool			moveStone					(unsigned int  pushFrom, unsigned int  pushTo);
	void			getComputersChoice			(unsigned int *pushFrom, unsigned int *pushTo);
	bool			setCurrentGameState			(fieldStruct  *curState);
	bool			compareWithField			(fieldStruct  *compareField);
	bool			comparePlayers				(playerStruct *playerA, playerStruct *playerB);
	void			printField					();
    bool            startSettingPhase			(muehleKI *firstPlayerKI, muehleKI *secondPlayerKI, int currentPlayer, bool settingPhase);
    bool            putStone					(unsigned int pos, int player);
    bool            settingPhaseHasFinished		();
	void			getChoiceOfSpecialKI		(muehleKI *KI, unsigned int *pushFrom, unsigned int *pushTo);
    void			setUpCalcPossibleMoves		(playerStruct *player);
    void			setUpSetWarningAndMill		(unsigned int stone, unsigned int firstNeighbour, unsigned int secondNeighbour);
	void			calcNumberOfRestingStones	(int &numWhiteStonesResting, int &numBlackStonesResting);
		
	// getter
	void			getLog						(unsigned int &numMovesDone, unsigned int *from, unsigned int *to);
	bool			getField					(int *pField);
	bool			isCurrentPlayerHuman		();
	bool			isOpponentPlayerHuman		();	
	bool			inSettingPhase				()	{	return field.settingPhase;									}
	unsigned int	mustStoneBeRemoved			()	{	return field.stoneMustBeRemoved;							}
	int				getWinner					()	{   return winner;												}
	int				getCurrentPlayer			()	{	return field.curPlayer->id;									}		
	unsigned int	getLastMoveFrom				()	{	return (movesDone ? moveLogFrom[movesDone-1] : field.size);	}
	unsigned int	getLastMoveTo				()	{	return (movesDone ? moveLogTo  [movesDone-1] : field.size);	}
	unsigned int    getMovesDone				()	{	return movesDone;											}
	unsigned int    getNumStonesSet				()	{	return field.stonesSet;										}
	int				getBeginningPlayer			()	{	return beginningPlayer;										}
	unsigned int	getNumStonOfCurPlayer		()	{	return field.curPlayer->numStones;							}
    unsigned int	getNumStonOfOppPlayer		()	{	return field.oppPlayer->numStones;							}
};

#endif

