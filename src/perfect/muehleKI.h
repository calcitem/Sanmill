/*********************************************************************\
	muehleKI.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef MUEHLE_KI_H
#define MUEHLE_KI_H

#include <iostream>
#include <cstdio>

//using namespace std;

/*** Konstanten ******************************************************/
#define	MAX_NUM_POS_MOVES		(3 * 18)						// not (9 * 4) = 36 since the possibilities with 3 stones are more
#define SAFE_DELETE(p)			{ if(p) { delete (p); (p)=NULL; } }

/*** Klassen *********************************************************/

class playerStruct
{
public:
	int			 				id;								// static
	unsigned int 				warning;						// static
	unsigned int 				numStones;						// number of stones of this player on the field
	unsigned int 				numStonesMissing;				// number of stones, which where stolen by the opponent
	unsigned int 				numPossibleMoves;				// amount of possible moves
	unsigned int 				posTo  [MAX_NUM_POS_MOVES];		// target field position of a possible move
	unsigned int 				posFrom[MAX_NUM_POS_MOVES];		// source field position of a possible move

	void						copyPlayer						(playerStruct *destination);
};

class fieldStruct
{
public:
	// constants
	static const int 			squareIsFree					=  0;		// trivial
	static const int 			playerOne						= -1;		// so rowOwner can be calculated easy
	static const int 			playerTwo						=  1;
	static const int 			playerBlack						= -1;		// so rowOwner can be calculated easy
	static const int 			playerWhite						=  1;
	static const unsigned int 	noWarning						=  0;		// so the bitwise or-operation can be applied, without interacting with playerOne & Two
	static const unsigned int 	playerOneWarning				=  2;		
	static const unsigned int 	playerTwoWarning				=  4;
	static const unsigned int 	playerBothWarning				=  6;
	static const unsigned int	numStonesPerPlayer				=  9;
	static const unsigned int	size							= 24;		// number of squares
	static const int			gameDrawn						=  3;		// only a nonzero value

	// variables
	int			 				field[size];					// one of the values above for each field position
	unsigned int 				warnings[size];					// array containing the warnings for each field position
	bool						stoneMoveAble[size][4];			// true if stone can be moved in this direction
	unsigned int 				stonePartOfMill[size];			// the number of mills, of which this stone is part of
	unsigned int 				connectedSquare[size][4];		// static array containg the index of the neighbour or "size"
	unsigned int				neighbour[size][2][2];			// static array containing the two neighbours of each squares
	unsigned int 				stonesSet;						// number of stones set in the setting phase
	bool		 				settingPhase;					// true if stonesSet < 18
	unsigned int 				stoneMustBeRemoved;				// number of stones which must be removed by the current player
	playerStruct				*curPlayer, *oppPlayer;			// pointers to the current and opponent player

	// useful functions
	void						printField						();
	void						copyField						(fieldStruct  *destination);
	void						createField						();
	void						deleteField						();

private:

	// helper functions
	char						GetCharFromStone				(int stone);
	void						setConnection					(unsigned int index, int firstDirection, int secondDirection, int thirdDirection, int fourthDirection);
	void						setNeighbour					(unsigned int index, unsigned int firstNeighbour0, unsigned int secondNeighbour0, unsigned int firstNeighbour1, unsigned int secondNeighbour1);
};

class muehleKI abstract
{
protected:
	fieldStruct					dummyField;

public:
    // Constructor / destructor
								muehleKI()						{ dummyField.createField(); };
								~muehleKI()						{ dummyField.deleteField(); };

	// Functions
	virtual void				play							(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo) = 0;
};

#endif
