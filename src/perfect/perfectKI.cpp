/*********************************************************************
	perfectKI.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "perfectKI.h"

unsigned int soTableTurnLeft[] = {        
 2,      14,      23,                     
    5,   13,   20,                        
       8,12,17,                           
 1, 4, 7,   16,19,22,                     
       6,11,15,                           
    3,   10,   18,                        
 0,       9,      21                      
};                                        

unsigned int soTableDoNothing[]= {        
 0,       1,       2,                     
    3,    4,    5,                        
       6, 7, 8,                           
 9,10,11,   12,13,14,                     
      15,16,17,                           
   18,   19,   20,                        
21,      22,      23                      
};                                        

unsigned int soTableMirrorHori[] = {      
21,      22,      23,                     
   18,   19,   20,                        
      15,16,17,                           
 9,10,11,   12,13,14,                     
       6, 7, 8,                           
    3,    4,    5,                        
 0,       1,       2                      
};                                        

unsigned int soTableTurn180[]  = {    
 23,      22,      21,                
    20,   19,   18,                   
       17,16,15,                      
 14,13,12,   11,10, 9,                
        8, 7, 6,                      
     5,    4,    3,                   
  2,       1,       0                 
};                                    

unsigned int soTableInvert[]     = {  
  6,       7,       8,                
     3,    4,    5,                   
        0, 1, 2,                      
 11,10, 9,   14,13,12,                
       21,22,23,                      
    18,   19,   20,                   
 15,      16,      17                 
};

unsigned int soTableInvMirHori[]     = {  
 15,      16,      17,                
    18,   19,   20,                   
       21,22,23,                      
 11,10, 9,   14,13,12,                
        0, 1, 2,                      
     3,    4,    5,                   
  6,       7,       8                 
}; 

unsigned int soTableInvMirVert[]     = {  
  8,       7,       6,                
     5,    4,    3,                   
        2, 1, 0,                      
 12,13,14,    9,10,11,                
       23,22,21,                      
    20,   19,   18,                   
 17,      16,      15                 
}; 

unsigned int soTableInvMirDiag1[]     = {  
 17,      12,       8,                
    20,   13,    5,                   
       23,14, 2,                      
 16,19,22,    1, 4, 7,                
       21, 9, 0,                      
    18,   10,    3,                   
 15,      11,       6                 
}; 

unsigned int soTableInvMirDiag2[]     = {  
  6,      11,      15,                
     3,   10,   18,                   
        0, 9,21,                      
  7, 4, 1,   22,19,16,                
        2,14,23,                      
     5,   13,   20,                   
  8,      12,      17                 
}; 

unsigned int soTableInvLeft[]     = {  
  8,      12,      17,                
     5,   13,   20,                   
        2,14,23,                      
  7, 4, 1,   22,19,16,                
        0, 9,21,                      
     3,   10,   18,                   
  6,      11,      15                 
}; 

unsigned int soTableInvRight[]     = {  
 15,      11,       6,                
    18,   10,    3,                   
       21, 9, 0,                      
 16,19,22,    1, 4, 7,                
       23,14, 2,                      
    20,   13,    5,                   
 17,      12,       8                 
}; 

unsigned int soTableInv180[]     = {  
 17,      16,      15,                
    20,   19,   18,                   
       23,22,21,                      
 12,13,14,    9,10,11,                
        2, 1, 0,                      
     5,    4,    3,                   
  8,       7,       6                 
}; 

unsigned int soTableMirrorDiag1[]  = {
  0,       9,      21,                
     3,   10,   18,                   
        6,11,15,                      
  1, 4, 7,   16,19,22,                
        8,12,17,                      
     5,   13,   20,                   
  2,      14,      23                 
};                                    

unsigned int soTableTurnRight[]= {
  21,       9,       0,
     18,   10,    3,
        15,11, 6,
  22,19,16,    7, 4, 1,
        17,12, 8,
     20,   13,    5,
  23,      14,       2
};

unsigned int soTableMirrorVert[]   = {
   2,       1,       0,
      5,    4,    3,
         8, 7, 6,
  14,13,12,   11,10, 9,
        17,16,15,
     20,   19,   18,
  23,      22,      21
}; 

unsigned int soTableMirrorDiag2[] = {
  23,      14,       2,
     20,   13,    5,
        17,12, 8,
  22,19,16,    7, 4, 1,
        15,11, 6,
     18,   10,    3,
  21,       9,       0
};

// define the four groups
unsigned int squareIndexGroupA[] = {  3,  5, 20, 18 };
unsigned int squareIndexGroupB[] = {  4, 13, 19, 10 };
unsigned int squareIndexGroupC[] = {  0,  2, 23, 21,  6,  8, 17, 15 };
unsigned int squareIndexGroupD[] = {  1,  7, 14, 12, 22, 16,  9, 11 };

unsigned int fieldPosIsOfGroup[] = { GROUP_C,                GROUP_D,                GROUP_C,
                                             GROUP_A,        GROUP_B,        GROUP_A,
                                                     GROUP_C,GROUP_D,GROUP_C,
                                     GROUP_D,GROUP_B,GROUP_D,        GROUP_D,GROUP_B,GROUP_D,
                                                     GROUP_C,GROUP_D,GROUP_C,
                                             GROUP_A,        GROUP_B,        GROUP_A,
                                     GROUP_C,                GROUP_D,                GROUP_C};   

//-----------------------------------------------------------------------------
// Name: perfectKI()
// Desc: perfectKI class constructor
//-----------------------------------------------------------------------------
perfectKI::perfectKI(const char *directory)
{
	// loacls
    unsigned int					i, a, b, c, totalNumStones;
    unsigned int					wCD, bCD, wAB, bAB;
    unsigned int					stateAB, stateCD, symStateCD, layerNum;
    unsigned int					myField[fieldStruct::size];
    unsigned int					symField[fieldStruct::size];
    unsigned int					*originalStateCD_tmp[10][10];
	DWORD							dwBytesRead		= 0;
	DWORD							dwBytesWritten	= 0;
	HANDLE							hFilePreCalcVars;
	stringstream					ssPreCalcVarsFilePath;
	preCalcedVarsFileHeaderStruct	preCalcVarsHeader;

	// 
	threadVars = new threadVarsStruct[getNumThreads()];
	for (unsigned int curThread=0; curThread<getNumThreads(); curThread++) {
		threadVars[curThread].parent			= this;
		threadVars[curThread].field				= &dummyField;
		threadVars[curThread].possibilities		= new possibilityStruct [ MAX_DEPTH_OF_TREE + 1];
		threadVars[curThread].oldStates			= new backupStruct		[ MAX_DEPTH_OF_TREE + 1];
		threadVars[curThread].idPossibilities	= new unsigned int		[(MAX_DEPTH_OF_TREE + 1) * MAX_NUM_POS_MOVES];
	}
	
	// Open File, which contains the precalculated vars
	if (strlen(directory) && PathFileExistsA(directory)) {	ssPreCalcVarsFilePath << directory << "\\"; } ssPreCalcVarsFilePath << "preCalculatedVars.dat";
	hFilePreCalcVars = CreateFileA(ssPreCalcVarsFilePath.str().c_str(), GENERIC_READ /*| GENERIC_WRITE*/, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	ReadFile(hFilePreCalcVars, &preCalcVarsHeader, sizeof (preCalcedVarsFileHeaderStruct), &dwBytesRead, NULL);

	// vars already stored in file?
	if (dwBytesRead) {
		
		// Read from file
		ReadFile(hFilePreCalcVars, layer, 					sizeof(layerStruct) 	*NUM_LAYERS,													&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, layerIndex, 				sizeof(unsigned int)  *2*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, anzahlStellungenAB, 		sizeof(unsigned int)	*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, anzahlStellungenCD, 		sizeof(unsigned int)	*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, indexAB, 				sizeof(unsigned int)	*MAX_ANZ_STELLUNGEN_A*MAX_ANZ_STELLUNGEN_B,						&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, indexCD, 				sizeof(unsigned int)	*MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D,						&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, symmetryOperationCD, 	sizeof(unsigned char)	*MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D,						&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, powerOfThree, 			sizeof(unsigned int)	*(numSquaresGroupC+numSquaresGroupD),							&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, symmetryOperationTable, 	sizeof(unsigned int)	*fieldStruct::size*NUM_SYM_OPERATIONS,							&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, reverseSymOperation, 	sizeof(unsigned int)	*NUM_SYM_OPERATIONS,											&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, concSymOperation, 		sizeof(unsigned int)	*NUM_SYM_OPERATIONS*NUM_SYM_OPERATIONS,							&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, mOverN,					sizeof(unsigned int)	*(fieldStruct::size+1)*(fieldStruct::size+1),					&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, valueOfMove, 			sizeof(unsigned char)	*fieldStruct::size*fieldStruct::size,							&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, plyInfoForOutput,		sizeof(plyInfoVarType)	*fieldStruct::size*fieldStruct::size,							&dwBytesRead, NULL);
		ReadFile(hFilePreCalcVars, incidencesValuesSubMoves,sizeof(unsigned int)  *4*fieldStruct::size*fieldStruct::size,							&dwBytesRead, NULL);

		// process originalStateAB[][]
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupA + numSquaresGroupB) continue;
			originalStateAB[a][b] = new unsigned int[anzahlStellungenAB[a][b]];
			ReadFile(hFilePreCalcVars, originalStateAB[a][b], sizeof(unsigned int) * anzahlStellungenAB[a][b], &dwBytesRead, NULL);		
		}}

		// process originalStateCD[][]
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupC + numSquaresGroupD) continue;
			originalStateCD[a][b]    = new unsigned int[anzahlStellungenCD[a][b]];
			ReadFile(hFilePreCalcVars, originalStateCD[a][b], sizeof(unsigned int) * anzahlStellungenCD[a][b],	&dwBytesRead, NULL);
		}}

	// calculate vars and save into file
	} else {

		// calc mOverN
		for (a=0; a<=fieldStruct::size; a++) { for (b=0; b<=fieldStruct::size; b++) { 
			mOverN[a][b] = (unsigned int) mOverN_Function(a,b);
		}}

		// reset
		for (i=0; i<fieldStruct::size*fieldStruct::size; i++)	{
			plyInfoForOutput[i]										= PLYINFO_VALUE_INVALID;
			valueOfMove[i]											= SKV_VALUE_INVALID;
			incidencesValuesSubMoves[i][SKV_VALUE_INVALID		]	= 0;
			incidencesValuesSubMoves[i][SKV_VALUE_GAME_LOST		]	= 0;
			incidencesValuesSubMoves[i][SKV_VALUE_GAME_DRAWN	]	= 0;
			incidencesValuesSubMoves[i][SKV_VALUE_GAME_WON		]	= 0;
		}

		// power of three
		for (powerOfThree[0]=1, i=1; i<numSquaresGroupC+numSquaresGroupD; i++) powerOfThree[i] = 3 * powerOfThree[i-1];

		// symmetry operation table
		for (i=0; i<fieldStruct::size; i++) {
			symmetryOperationTable[SO_TURN_LEFT     ][i] = soTableTurnLeft   [i];
			symmetryOperationTable[SO_TURN_180      ][i] = soTableTurn180    [i];
			symmetryOperationTable[SO_TURN_RIGHT    ][i] = soTableTurnRight  [i];
			symmetryOperationTable[SO_DO_NOTHING    ][i] = soTableDoNothing  [i];
			symmetryOperationTable[SO_INVERT        ][i] = soTableInvert     [i];
			symmetryOperationTable[SO_MIRROR_VERT   ][i] = soTableMirrorVert [i];
			symmetryOperationTable[SO_MIRROR_HORI   ][i] = soTableMirrorHori [i];
			symmetryOperationTable[SO_MIRROR_DIAG_1 ][i] = soTableMirrorDiag1[i];
			symmetryOperationTable[SO_MIRROR_DIAG_2 ][i] = soTableMirrorDiag2[i];
			symmetryOperationTable[SO_INV_LEFT      ][i] = soTableInvLeft    [i];
			symmetryOperationTable[SO_INV_RIGHT     ][i] = soTableInvRight   [i];
			symmetryOperationTable[SO_INV_180       ][i] = soTableInv180     [i];
			symmetryOperationTable[SO_INV_MIR_VERT  ][i] = soTableInvMirHori [i];
			symmetryOperationTable[SO_INV_MIR_HORI  ][i] = soTableInvMirVert [i];
			symmetryOperationTable[SO_INV_MIR_DIAG_1][i] = soTableInvMirDiag1[i];
			symmetryOperationTable[SO_INV_MIR_DIAG_2][i] = soTableInvMirDiag2[i];
		}

		// reverse symmetrie operation
		reverseSymOperation[SO_TURN_LEFT     ] = SO_TURN_RIGHT;
		reverseSymOperation[SO_TURN_180      ] = SO_TURN_180;
		reverseSymOperation[SO_TURN_RIGHT    ] = SO_TURN_LEFT;
		reverseSymOperation[SO_DO_NOTHING    ] = SO_DO_NOTHING;
		reverseSymOperation[SO_INVERT        ] = SO_INVERT;
		reverseSymOperation[SO_MIRROR_VERT   ] = SO_MIRROR_VERT;
		reverseSymOperation[SO_MIRROR_HORI   ] = SO_MIRROR_HORI;
		reverseSymOperation[SO_MIRROR_DIAG_1 ] = SO_MIRROR_DIAG_1;
		reverseSymOperation[SO_MIRROR_DIAG_2 ] = SO_MIRROR_DIAG_2;
		reverseSymOperation[SO_INV_LEFT      ] = SO_INV_RIGHT;
		reverseSymOperation[SO_INV_RIGHT     ] = SO_INV_LEFT;
		reverseSymOperation[SO_INV_180       ] = SO_INV_180;  
		reverseSymOperation[SO_INV_MIR_VERT  ] = SO_INV_MIR_VERT;
		reverseSymOperation[SO_INV_MIR_HORI  ] = SO_INV_MIR_HORI;
		reverseSymOperation[SO_INV_MIR_DIAG_1] = SO_INV_MIR_DIAG_1;
		reverseSymOperation[SO_INV_MIR_DIAG_2] = SO_INV_MIR_DIAG_2;  
	    
		// concatenated symmetry operations
		for (a=0; a<NUM_SYM_OPERATIONS; a++) { 
			for (b=0; b<NUM_SYM_OPERATIONS; b++) {

				// test each symmetry operation
				for (c=0; c<NUM_SYM_OPERATIONS; c++) {

					// look if b(a(state)) == c(state)
					for (i=0; i<fieldStruct::size; i++) {
						if (symmetryOperationTable[c][i] != symmetryOperationTable[a][symmetryOperationTable[b][i]]) break;
					}   
	                
					// match found?
					if (i == fieldStruct::size) {
						concSymOperation[a][b] = c;
						break;
					}
				}

				// no match found
				if (c == NUM_SYM_OPERATIONS) {
					cout << endl << "ERROR IN SYMMETRY-OPERATIONS!" << endl;
				}
			}
		}

		// group A&B //

		// reserve memory
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {

			if (a + b > numSquaresGroupA + numSquaresGroupB) continue;

			anzahlStellungenAB[a][b] = mOverN[numSquaresGroupA + numSquaresGroupB][a] * mOverN[numSquaresGroupA + numSquaresGroupB - a][b];
			originalStateAB   [a][b] = new unsigned int[anzahlStellungenAB[a][b]];
			anzahlStellungenAB[a][b] = 0;
		}}

		// mark all indexCD as not indexed
		for (stateAB=0; stateAB<MAX_ANZ_STELLUNGEN_A*MAX_ANZ_STELLUNGEN_B; stateAB++) indexAB[stateAB] = NOT_INDEXED;

		for (stateAB=0; stateAB<MAX_ANZ_STELLUNGEN_A*MAX_ANZ_STELLUNGEN_B; stateAB++) {

			// new state ?
			if (indexAB[stateAB] == NOT_INDEXED) {

				// zero field
				for (i=0; i<fieldStruct::size; i++) myField[i] = FREE_SQUARE; 

				// make field
				myField[squareIndexGroupA[0]] = (stateAB / powerOfThree[ 7]) % 3;
				myField[squareIndexGroupA[1]] = (stateAB / powerOfThree[ 6]) % 3;
				myField[squareIndexGroupA[2]] = (stateAB / powerOfThree[ 5]) % 3;
				myField[squareIndexGroupA[3]] = (stateAB / powerOfThree[ 4]) % 3;
				myField[squareIndexGroupB[4]] = (stateAB / powerOfThree[ 3]) % 3;
				myField[squareIndexGroupB[5]] = (stateAB / powerOfThree[ 2]) % 3;
				myField[squareIndexGroupB[6]] = (stateAB / powerOfThree[ 1]) % 3;
				myField[squareIndexGroupB[7]] = (stateAB / powerOfThree[ 0]) % 3;

				// count black and white stones
				for (a=0,i=0; i<fieldStruct::size; i++) if (myField[i] == WHITE_STONE) a++; 
				for (b=0,i=0; i<fieldStruct::size; i++) if (myField[i] == BLACK_STONE) b++; 
	            
				// condition
				if (a + b > numSquaresGroupA + numSquaresGroupB) continue;

				// mark original state
				indexAB         [stateAB]                        = anzahlStellungenAB[a][b];
				originalStateAB [a][b][anzahlStellungenAB[a][b]] = stateAB;

				// state counter
				anzahlStellungenAB[a][b]++;    
			}
		}

		// group C&D //

		// reserve memory
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupC + numSquaresGroupD) continue;
			originalStateCD_tmp[a][b] = new unsigned int[mOverN[numSquaresGroupC+numSquaresGroupD][a] * mOverN[numSquaresGroupC+numSquaresGroupD-a][b]];
			anzahlStellungenCD [a][b] = 0;
		}}

		// mark all indexCD as not indexed
		memset(indexCD, NOT_INDEXED, 4 * MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D);
	    
		for (stateCD=0; stateCD<MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D; stateCD++) {

			// new state ?
			if (indexCD[stateCD] == NOT_INDEXED) {

				// zero field
				for (i=0; i<fieldStruct::size; i++) myField[i] = FREE_SQUARE; 

				// make field
				myField[squareIndexGroupC[0]] = (stateCD / powerOfThree[15]) % 3;  
				myField[squareIndexGroupC[1]] = (stateCD / powerOfThree[14]) % 3;
				myField[squareIndexGroupC[2]] = (stateCD / powerOfThree[13]) % 3;
				myField[squareIndexGroupC[3]] = (stateCD / powerOfThree[12]) % 3;
				myField[squareIndexGroupC[4]] = (stateCD / powerOfThree[11]) % 3;
				myField[squareIndexGroupC[5]] = (stateCD / powerOfThree[10]) % 3;
				myField[squareIndexGroupC[6]] = (stateCD / powerOfThree[ 9]) % 3;
				myField[squareIndexGroupC[7]] = (stateCD / powerOfThree[ 8]) % 3;
				myField[squareIndexGroupD[0]] = (stateCD / powerOfThree[ 7]) % 3;
				myField[squareIndexGroupD[1]] = (stateCD / powerOfThree[ 6]) % 3;
				myField[squareIndexGroupD[2]] = (stateCD / powerOfThree[ 5]) % 3;
				myField[squareIndexGroupD[3]] = (stateCD / powerOfThree[ 4]) % 3;
				myField[squareIndexGroupD[4]] = (stateCD / powerOfThree[ 3]) % 3;
				myField[squareIndexGroupD[5]] = (stateCD / powerOfThree[ 2]) % 3;
				myField[squareIndexGroupD[6]] = (stateCD / powerOfThree[ 1]) % 3;
				myField[squareIndexGroupD[7]] = (stateCD / powerOfThree[ 0]) % 3;

				// count black and white stones
				for (a=0,i=0; i<fieldStruct::size; i++) if (myField[i] == WHITE_STONE) a++; 
				for (b=0,i=0; i<fieldStruct::size; i++) if (myField[i] == BLACK_STONE) b++; 
	            
				// condition
				if (a + b > numSquaresGroupC + numSquaresGroupD) continue;
				if (a	  > NUM_STONES_PER_PLAYER) continue;
				if (b	  > NUM_STONES_PER_PLAYER) continue;

				// mark original state
				indexCD             [stateCD]                        = anzahlStellungenCD[a][b];
				symmetryOperationCD [stateCD]                        = SO_DO_NOTHING;
				originalStateCD_tmp [a][b][anzahlStellungenCD[a][b]] = stateCD;

				// mark all symmetric states
				for (i=0; i<NUM_SYM_OPERATIONS; i++) {
	                
					applySymmetrieOperationOnField(i, myField, symField);

					symStateCD  = symField[squareIndexGroupC[0]] * powerOfThree[15]
								+ symField[squareIndexGroupC[1]] * powerOfThree[14]
								+ symField[squareIndexGroupC[2]] * powerOfThree[13]
								+ symField[squareIndexGroupC[3]] * powerOfThree[12]
								+ symField[squareIndexGroupC[4]] * powerOfThree[11]
								+ symField[squareIndexGroupC[5]] * powerOfThree[10]
								+ symField[squareIndexGroupC[6]] * powerOfThree[ 9]
								+ symField[squareIndexGroupC[7]] * powerOfThree[ 8]
								+ symField[squareIndexGroupD[0]] * powerOfThree[ 7]
								+ symField[squareIndexGroupD[1]] * powerOfThree[ 6]
								+ symField[squareIndexGroupD[2]] * powerOfThree[ 5]
								+ symField[squareIndexGroupD[3]] * powerOfThree[ 4]
								+ symField[squareIndexGroupD[4]] * powerOfThree[ 3]
								+ symField[squareIndexGroupD[5]] * powerOfThree[ 2]
								+ symField[squareIndexGroupD[6]] * powerOfThree[ 1]
								+ symField[squareIndexGroupD[7]] * powerOfThree[ 0];

					if (stateCD != symStateCD) {
						indexCD             [symStateCD] = anzahlStellungenCD[a][b];
						symmetryOperationCD [symStateCD] = reverseSymOperation[i];
					}
				}

				// state counter
				anzahlStellungenCD[a][b]++;    
			}
		}
	    
		// copy from originalStateCD_tmp to originalStateCD
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupC + numSquaresGroupD) continue;
			originalStateCD[a][b]    = new unsigned int[anzahlStellungenCD[a][b]];
			for (i=0; i<anzahlStellungenCD[a][b]; i++) originalStateCD[a][b][i] = originalStateCD_tmp[a][b][i];
			SAFE_DELETE_ARRAY(originalStateCD_tmp[a][b]);
		}}

		// moving phase
		for (totalNumStones=0, layerNum=0; totalNumStones<=18; totalNumStones++) {
			for (a=0; a<=totalNumStones; a++) { for (b=0; b<=totalNumStones-a; b++) { 
				if (a>NUM_STONES_PER_PLAYER) continue;
				if (b>NUM_STONES_PER_PLAYER) continue;
				if (a+b != totalNumStones) continue;

  				layerIndex[LAYER_INDEX_MOVING_PHASE][a][b]	= layerNum;
				layer[layerNum].numWhiteStones	            = a;
				layer[layerNum].numBlackStones	            = b;
				layer[layerNum].numSubLayers                = 0;
	            
				for (wCD=0; wCD<=layer[layerNum].numWhiteStones; wCD++) { for (bCD=0; bCD<=layer[layerNum].numBlackStones; bCD++) {

					// calc number of white and black stones for group A&B
					wAB = layer[layerNum].numWhiteStones - wCD;
					bAB = layer[layerNum].numBlackStones - bCD;

					// conditions
					if (wCD + wAB != layer[layerNum].numWhiteStones)      continue;
					if (bCD + bAB != layer[layerNum].numBlackStones)      continue;
					if (wAB + bAB > numSquaresGroupA + numSquaresGroupB)  continue;
					if (wCD + bCD > numSquaresGroupC + numSquaresGroupD)  continue;

					if (layer[layerNum].numSubLayers > 0) {
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].maxIndex           = layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex + anzahlStellungenAB[wAB][bAB] * anzahlStellungenCD[wCD][bCD];
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].minIndex           = layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex + 1;
					} else {
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].maxIndex           = anzahlStellungenAB[wAB][bAB] * anzahlStellungenCD[wCD][bCD] - 1;
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].minIndex           = 0;
					}
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numBlackStonesGroupAB  = bAB;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numBlackStonesGroupCD  = bCD;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numWhiteStonesGroupAB  = wAB;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numWhiteStonesGroupCD  = wCD;
					layer[layerNum].subLayerIndexAB[wAB][bAB]                                     = layer[layerNum].numSubLayers;
					layer[layerNum].subLayerIndexCD[wCD][bCD]                                     = layer[layerNum].numSubLayers;
					layer[layerNum].numSubLayers++;
				}}
				layerNum++;
			}}
		}

		// setting phase
		for (totalNumStones=0, layerNum=NUM_LAYERS-1; totalNumStones<=2*NUM_STONES_PER_PLAYER; totalNumStones++) {
			for (a=0; a<=totalNumStones; a++) { for (b=0; b<=totalNumStones-a; b++) { 
				if (a	>  NUM_STONES_PER_PLAYER)	continue;
				if (b	>  NUM_STONES_PER_PLAYER)	continue;
				if (a+b != totalNumStones)			continue;
				layer[layerNum].numWhiteStones	                = a;
				layer[layerNum].numBlackStones	                = b;
				layerIndex[LAYER_INDEX_SETTING_PHASE][a][b]		= layerNum;
				layer[layerNum].numSubLayers                    = 0;
	            
				for (wCD=0; wCD<=layer[layerNum].numWhiteStones; wCD++) { for (bCD=0; bCD<=layer[layerNum].numBlackStones; bCD++) {

					// calc number of white and black stones for group A&B
					wAB = layer[layerNum].numWhiteStones - wCD;
					bAB = layer[layerNum].numBlackStones - bCD;

					// conditions
					if (wCD + wAB != layer[layerNum].numWhiteStones)      continue;
					if (bCD + bAB != layer[layerNum].numBlackStones)      continue;
					if (wAB + bAB > numSquaresGroupA + numSquaresGroupB)  continue;
					if (wCD + bCD > numSquaresGroupC + numSquaresGroupD)  continue;

					if (layer[layerNum].numSubLayers > 0) {
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].maxIndex           = layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex + anzahlStellungenAB[wAB][bAB] * anzahlStellungenCD[wCD][bCD];
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].minIndex           = layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex + 1;
					} else {
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].maxIndex           = anzahlStellungenAB[wAB][bAB] * anzahlStellungenCD[wCD][bCD] - 1;
						layer[layerNum].subLayer[layer[layerNum].numSubLayers].minIndex           = 0;
					}
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numBlackStonesGroupAB  = bAB;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numBlackStonesGroupCD  = bCD;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numWhiteStonesGroupAB  = wAB;
					layer[layerNum].subLayer[layer[layerNum].numSubLayers].numWhiteStonesGroupCD  = wCD;
					layer[layerNum].subLayerIndexAB[wAB][bAB]                                     = layer[layerNum].numSubLayers;
					layer[layerNum].subLayerIndexCD[wCD][bCD]                                     = layer[layerNum].numSubLayers;
					layer[layerNum].numSubLayers++;
				}}
				layerNum--;
			}}
		}

		// write vars into file
		preCalcVarsHeader.sizeInBytes = sizeof(preCalcedVarsFileHeaderStruct);

		WriteFile(hFilePreCalcVars, &preCalcVarsHeader,		preCalcVarsHeader.sizeInBytes,															&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, layer, 					sizeof(layerStruct) 	*NUM_LAYERS,													&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, layerIndex, 			sizeof(unsigned int)  *2*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, anzahlStellungenAB, 	sizeof(unsigned int)	*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, anzahlStellungenCD, 	sizeof(unsigned int)	*NUM_STONES_PER_PLAYER_PLUS_ONE*NUM_STONES_PER_PLAYER_PLUS_ONE,	&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, indexAB, 				sizeof(unsigned int)	*MAX_ANZ_STELLUNGEN_A*MAX_ANZ_STELLUNGEN_B,						&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, indexCD, 				sizeof(unsigned int)	*MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D,						&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, symmetryOperationCD, 	sizeof(unsigned char)	*MAX_ANZ_STELLUNGEN_C*MAX_ANZ_STELLUNGEN_D,						&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, powerOfThree, 			sizeof(unsigned int)	*(numSquaresGroupC+numSquaresGroupD),							&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, symmetryOperationTable, sizeof(unsigned int)	*fieldStruct::size*NUM_SYM_OPERATIONS,							&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, reverseSymOperation, 	sizeof(unsigned int)	*NUM_SYM_OPERATIONS,											&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, concSymOperation, 		sizeof(unsigned int)	*NUM_SYM_OPERATIONS*NUM_SYM_OPERATIONS,							&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, mOverN,					sizeof(unsigned int)	*(fieldStruct::size+1)*(fieldStruct::size+1),					&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, valueOfMove, 			sizeof(unsigned char)	*fieldStruct::size*fieldStruct::size,							&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, plyInfoForOutput,		sizeof(plyInfoVarType)	*fieldStruct::size*fieldStruct::size,							&dwBytesWritten, NULL);
		WriteFile(hFilePreCalcVars, incidencesValuesSubMoves,sizeof(unsigned int)  *4*fieldStruct::size*fieldStruct::size,							&dwBytesWritten, NULL);

		// process originalStateAB[][]
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupA + numSquaresGroupB) continue;
			WriteFile(hFilePreCalcVars, originalStateAB[a][b], sizeof(unsigned int)	*anzahlStellungenAB[a][b], &dwBytesWritten, NULL);		
		}}

		// process originalStateCD[][]
		for (a=0; a<=NUM_STONES_PER_PLAYER; a++) { for (b=0; b<=NUM_STONES_PER_PLAYER; b++) {
			if (a + b > numSquaresGroupC + numSquaresGroupD) continue;
			WriteFile(hFilePreCalcVars, originalStateCD[a][b], sizeof(unsigned int)	*anzahlStellungenCD[a][b],	&dwBytesWritten, NULL);
		}}
	}

	// Close File
	CloseHandle(hFilePreCalcVars);
}

//-----------------------------------------------------------------------------
// Name: ~perfectKI()
// Desc: perfectKI class destructor
//-----------------------------------------------------------------------------
perfectKI::~perfectKI()
{
	// locals
	unsigned int curThread;

	// release memory
	for (curThread=0; curThread<getNumThreads(); curThread++) {
		SAFE_DELETE_ARRAY(threadVars[curThread].oldStates);
		SAFE_DELETE_ARRAY(threadVars[curThread].idPossibilities);
		SAFE_DELETE_ARRAY(threadVars[curThread].possibilities);
		threadVars[curThread].field->deleteField();
	}
	SAFE_DELETE_ARRAY(threadVars);
}

//-----------------------------------------------------------------------------
// Name: play()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo)
{
	// ... trick 17
	theField->copyField(&dummyField);

	// locals
	threadVars[0].field			= theField;
	threadVars[0].ownId			= threadVars[0].field->curPlayer->id; 
	unsigned int	bestChoice, i;
	
	// reset
	for (i=0; i<fieldStruct::size*fieldStruct::size; i++)	{
		valueOfMove[i]										  =	SKV_VALUE_INVALID;
		plyInfoForOutput[i]									  = PLYINFO_VALUE_INVALID;
		incidencesValuesSubMoves[i][SKV_VALUE_INVALID		] = 0;
		incidencesValuesSubMoves[i][SKV_VALUE_GAME_LOST		] = 0;
		incidencesValuesSubMoves[i][SKV_VALUE_GAME_DRAWN	] = 0;
		incidencesValuesSubMoves[i][SKV_VALUE_GAME_WON		] = 0;
	}

	// open database file
	openDatabase(databaseDirectory.c_str(), MAX_NUM_POS_MOVES);
	
	if (theField->settingPhase)	threadVars[0].depthOfFullTree = 2;
	else						threadVars[0].depthOfFullTree = 2;
	
	// current state already calculated?
	if (isCurrentStateInDatabase(0)) {
		cout << "perfectKI is using database!\n\n\n";
		threadVars[0].depthOfFullTree = 3;
	} else {
		cout << "perfectKI is thinking thinking with a depth of " << threadVars[0].depthOfFullTree << " steps!\n\n\n";
	}
	
	// start the miniMax-algorithmn
	possibilityStruct *rootPossibilities = (possibilityStruct*) getBestChoice(threadVars[0].depthOfFullTree, &bestChoice, MAX_NUM_POS_MOVES);

	// decode the best choice
		 if (threadVars[0].field->stoneMustBeRemoved)	{	*pushFrom	= bestChoice;	*pushTo		= 0;			}
	else if (threadVars[0].field->settingPhase)			{	*pushFrom	= 0;			*pushTo		= bestChoice;	}
	else												{	*pushFrom	= rootPossibilities->from[bestChoice];
															*pushTo		= rootPossibilities->to  [bestChoice];		}

	// release memory
	threadVars[0].field = &dummyField;
}

//-----------------------------------------------------------------------------
// Name: prepareDatabaseCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::prepareDatabaseCalculation()
{
	// only prepare layers?
	unsigned int	curThread;

	// create a temporary field
	for (curThread=0; curThread<getNumThreads(); curThread++) {
		threadVars[curThread].field = new fieldStruct();
		threadVars[curThread].field->createField();
		setOpponentLevel(curThread, false);
	}

	// open database file
	openDatabase(databaseDirectory.c_str(), MAX_NUM_POS_MOVES);
}

//-----------------------------------------------------------------------------
// Name: wrapUpDatabaseCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::wrapUpDatabaseCalculation(bool calculationAborted)
{
	// locals
	unsigned int curThread;

	// release memory
	for (curThread=0; curThread<getNumThreads(); curThread++) {
		threadVars[curThread].field->deleteField();
		SAFE_DELETE(threadVars[curThread].field);
		threadVars[curThread].field = &dummyField;
	}
}

//-----------------------------------------------------------------------------
// Name: testLayers()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::testLayers(unsigned int startTestFromLayer, unsigned int endTestAtLayer)
{
	// locals
	unsigned int curLayer;
	bool		 result	= true;

	for (curLayer=startTestFromLayer; curLayer<=endTestAtLayer; curLayer++) {
	    closeDatabase();	
	    if (!openDatabase(databaseDirectory.c_str(), MAX_NUM_POS_MOVES)) result = false;
	    if (!testIfSymStatesHaveSameValue(curLayer)) result = false;
	    if (!testLayer(curLayer)) result = false;
	    unloadAllLayers();
        unloadAllPlyInfos();
		closeDatabase();
	}
	return result;
}

//-----------------------------------------------------------------------------
// Name: setDatabasePath()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::setDatabasePath(const char *directory)
{
	if (directory == NULL) {
		return false;
	} else {
		cout << "Path to database set to: " << directory << endl;
		databaseDirectory.assign(directory);
		return true;
	}
}

//-----------------------------------------------------------------------------
// Name: prepareBestChoiceCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::prepareBestChoiceCalculation()
{
	for (unsigned int curThread=0; curThread<getNumThreads(); curThread++) {
		threadVars[curThread].floatValue		= 0.0f;
		threadVars[curThread].shortValue		= SKV_VALUE_INVALID;
		threadVars[curThread].gameHasFinished	= false;
		threadVars[curThread].curSearchDepth	= 0;
	}
}

//-----------------------------------------------------------------------------
// Name: threadVarsStruct()
// Desc: 
//-----------------------------------------------------------------------------
perfectKI::threadVarsStruct::threadVarsStruct()
{
	field			= NULL;			
	floatValue		= 0;
	shortValue		= 0;		
	gameHasFinished	= false;
	ownId			= 0;			
	curSearchDepth	= 0;	
	depthOfFullTree	= 0;
	idPossibilities	= NULL;
	oldStates		= NULL;		
	possibilities	= NULL;			
	parent			= NULL;
	
}

//-----------------------------------------------------------------------------
// Name: getPossSettingPhase()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * perfectKI::threadVarsStruct::getPossSettingPhase(unsigned int *numPossibilities, void **pPossibilities)
{
	// locals
	unsigned int i;
	unsigned int *idPossibility			= &idPossibilities[curSearchDepth * MAX_NUM_POS_MOVES];
	bool		 stoneCanBeRemoved;
	unsigned int numberOfMillsBeeingClosed;

	// check if an opponent stone can be removed
	for (stoneCanBeRemoved=false, i=0; i<field->size; i++) {
		if (field->field[i] == field->oppPlayer->id && field->stonePartOfMill[i] == 0) {
			stoneCanBeRemoved = true;
			break;
		}
	}
		
	// possibilities with cut off
	for ((*numPossibilities) = 0, i=0; i<field->size; i++) {

		// move possible ?
		if (field->field[i] == field->squareIsFree) {

			// check if a mill is beeing closed
			numberOfMillsBeeingClosed = 0;
			if (field->curPlayer->id == field->field[field->neighbour[i][0][0]] && field->curPlayer->id == field->field[field->neighbour[i][0][1]]) numberOfMillsBeeingClosed++;
			if (field->curPlayer->id == field->field[field->neighbour[i][1][0]] && field->curPlayer->id == field->field[field->neighbour[i][1][1]]) numberOfMillsBeeingClosed++;

			// Version 15: don't allow to close two mills at once
			// Version 25: don't allow to close a mill, although no stone can be removed from the opponent
			if ((numberOfMillsBeeingClosed < 2) && (numberOfMillsBeeingClosed==0 || stoneCanBeRemoved)) {
				idPossibility[*numPossibilities] = i;
				(*numPossibilities)++;
			}

		}
	}

	// possibility code is simple
	if (pPossibilities != NULL) *pPossibilities = NULL;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossNormalMove()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * perfectKI::threadVarsStruct::getPossNormalMove(unsigned int *numPossibilities, void **pPossibilities)
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
	}}}} else if (field->curPlayer->numStones == 3) {

		for ((*numPossibilities) = 0, from=0; from < field->size; from++) { for (to=0; to < field->size; to++) {

			// move possible ?
			if (field->field[from] == field->curPlayer->id &&  field->field[to] == field->squareIsFree && *numPossibilities < MAX_NUM_POS_MOVES) {

				// stone is moveable
				idPossibility[*numPossibilities]		= *numPossibilities;
				possibility->from[*numPossibilities]	= from;
				possibility->to[*numPossibilities]		= to;
				(*numPossibilities)++;
	}}}} else {
		*numPossibilities = 0;
	}

	// pass possibilities
	if (pPossibilities != NULL) *pPossibilities = (void*)possibility;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossStoneRemove()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * perfectKI::threadVarsStruct::getPossStoneRemove(unsigned int *numPossibilities, void **pPossibilities)
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
	if (pPossibilities != NULL) *pPossibilities = NULL;

	return idPossibility;
}

//-----------------------------------------------------------------------------
// Name: getPossibilities()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int * perfectKI::getPossibilities(unsigned int threadNo, unsigned int *numPossibilities, bool *opponentsMove, void **pPossibilities)
{
	// locals
	bool		 aStoneCanBeRemovedFromCurPlayer	= 0;
	unsigned int numberOfMillsCurrentPlayer			= 0;
	unsigned int numberOfMillsOpponentPlayer		= 0;
	unsigned int i;

	// set opponentsMove
	threadVarsStruct * tv = &threadVars[threadNo];
	*opponentsMove = (tv->field->curPlayer->id == tv->ownId) ? false : true;

	// count completed mills
	for (i=0; i<fieldStruct::size; i++) {
		if (tv->field->field[i] == tv->field->curPlayer->id) numberOfMillsCurrentPlayer  += tv->field->stonePartOfMill[i];
		else												 numberOfMillsOpponentPlayer += tv->field->stonePartOfMill[i];
        if (tv->field->stonePartOfMill[i] == 0 && tv->field->field[i] == tv->field->curPlayer->id) aStoneCanBeRemovedFromCurPlayer = true;
	}
	numberOfMillsCurrentPlayer  /= 3;
	numberOfMillsOpponentPlayer /= 3;

	// When game has ended of course nothing happens any more
	if (tv->gameHasFinished || !tv->fieldIntegrityOK(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, aStoneCanBeRemovedFromCurPlayer)) {
		*numPossibilities = 0;
		return 0;
	// look what is to do
	} else {
		     if (tv->field->stoneMustBeRemoved) return tv->getPossStoneRemove	(numPossibilities, pPossibilities);
		else if (tv->field->settingPhase)		return tv->getPossSettingPhase	(numPossibilities, pPossibilities);
		else									return tv->getPossNormalMove	(numPossibilities, pPossibilities);
	}
}

//-----------------------------------------------------------------------------
// Name: getValueOfSituation()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getValueOfSituation(unsigned int threadNo, float &floatValue, twoBit &shortValue)
{
	threadVarsStruct * tv = &threadVars[threadNo];
	floatValue = tv->floatValue;
	shortValue = tv->shortValue;
}

//-----------------------------------------------------------------------------
// Name: deletePossibilities()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::deletePossibilities(unsigned int threadNo, void *pPossibilities)
{
}

//-----------------------------------------------------------------------------
// Name: undo()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::undo(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void *pBackup, void *pPossibilities)
{
	// locals
	threadVarsStruct * tv = &threadVars[threadNo];
	backupStruct *oldState				= (backupStruct*)pBackup;

	// reset old value
	tv->floatValue							= oldState->floatValue;
	tv->shortValue							= oldState->shortValue;
	tv->gameHasFinished						= oldState->gameHasFinished;
	tv->curSearchDepth--;

	tv->field->curPlayer					= oldState->curPlayer;							
	tv->field->oppPlayer					= oldState->oppPlayer;							
	tv->field->curPlayer->numStones			= oldState->curNumStones;						
	tv->field->oppPlayer->numStones			= oldState->oppNumStones;						
	tv->field->curPlayer->numStonesMissing	= oldState->curMissStones;						
	tv->field->oppPlayer->numStonesMissing	= oldState->oppMissStones;						
	tv->field->curPlayer->numPossibleMoves	= oldState->curPosMoves;						
	tv->field->oppPlayer->numPossibleMoves	= oldState->oppPosMoves;						
	tv->field->settingPhase					= oldState->settingPhase;						
	tv->field->stonesSet					= oldState->stonesSet;							
	tv->field->stoneMustBeRemoved			= oldState->stoneMustBeRemoved;					
	tv->field->field[oldState->from]		= oldState->fieldFrom;							
	tv->field->field[oldState->to  ]		= oldState->fieldTo;							

	// very expensive
	for (int i=0; i<tv->field->size; i++) {
		tv->field->stonePartOfMill[i]	= oldState->stonePartOfMill[i];
	}
}

//-----------------------------------------------------------------------------
// Name: setWarning()
// Desc: 
//-----------------------------------------------------------------------------
inline void perfectKI::threadVarsStruct::setWarning(unsigned int stoneOne, unsigned int stoneTwo, unsigned int stoneThree)
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
}

//-----------------------------------------------------------------------------
// Name: updateWarning()
// Desc: 
//-----------------------------------------------------------------------------
inline void perfectKI::threadVarsStruct::updateWarning(unsigned int firstStone, unsigned int secondStone)
{
	// set warnings
	if (firstStone  < field->size) this->setWarning(firstStone,  field->neighbour[firstStone][0][0],  field->neighbour[firstStone][0][1]);
	if (firstStone  < field->size) this->setWarning(firstStone,  field->neighbour[firstStone][1][0],  field->neighbour[firstStone][1][1]);

	if (secondStone < field->size) this->setWarning(secondStone, field->neighbour[secondStone][0][0], field->neighbour[secondStone][0][1]);
	if (secondStone < field->size) this->setWarning(secondStone, field->neighbour[secondStone][1][0], field->neighbour[secondStone][1][1]);

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
inline void perfectKI::threadVarsStruct::updatePossibleMoves(unsigned int stone, playerStruct *stoneOwner, bool stoneRemoved, unsigned int ignoreStone)
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
inline void	perfectKI::threadVarsStruct::setStone(unsigned int to, backupStruct *backup)
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
inline void	perfectKI::threadVarsStruct::normalMove(unsigned int from, unsigned int to, backupStruct *backup)
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
inline void perfectKI::threadVarsStruct::removeStone(unsigned int from, backupStruct *backup) 
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
void perfectKI::move(unsigned int threadNo, unsigned int idPossibility, bool opponentsMove, void **pBackup, void *pPossibilities)
{
	// locals
	threadVarsStruct *	tv = &threadVars[threadNo];
	backupStruct		*oldState		= &tv->oldStates[tv->curSearchDepth];
	possibilityStruct	*tmpPossibility = (possibilityStruct*) pPossibilities;
	playerStruct		*tmpPlayer;
	unsigned int		i;

	// calculate place of stone
	*pBackup					= (void*) oldState;
	oldState->floatValue		= tv->floatValue;											
	oldState->shortValue		= tv->shortValue;											
	oldState->gameHasFinished	= tv->gameHasFinished;										
	oldState->curPlayer			= tv->field->curPlayer;										
	oldState->oppPlayer			= tv->field->oppPlayer;										
	oldState->curNumStones		= tv->field->curPlayer->numStones;							
	oldState->oppNumStones		= tv->field->oppPlayer->numStones;							
	oldState->curPosMoves		= tv->field->curPlayer->numPossibleMoves;					
	oldState->oppPosMoves		= tv->field->oppPlayer->numPossibleMoves;					
	oldState->curMissStones		= tv->field->curPlayer->numStonesMissing;					
	oldState->oppMissStones		= tv->field->oppPlayer->numStonesMissing;					
	oldState->settingPhase		= tv->field->settingPhase;									
	oldState->stonesSet			= tv->field->stonesSet;										
	oldState->stoneMustBeRemoved= tv->field->stoneMustBeRemoved;							
	tv->curSearchDepth++;
 
	// very expensive
	for (i=0; i<tv->field->size; i++) {
		oldState->stonePartOfMill[i]	= tv->field->stonePartOfMill[i];
	}

	// move
	if (tv->field->stoneMustBeRemoved)	{ tv->removeStone(idPossibility, oldState);															}
	else if (tv->field->settingPhase)	{ tv->setStone(idPossibility, oldState);															}
	else								{ tv->normalMove(tmpPossibility->from[idPossibility], tmpPossibility->to[idPossibility], oldState);	}

	// when opponent is unable to move than current player has won
	if ((!tv->field->oppPlayer->numPossibleMoves) && (!tv->field->settingPhase) && (!tv->field->stoneMustBeRemoved) && (tv->field->oppPlayer->numStones > 3)) tv->gameHasFinished = true;

	// when game has finished - perfect for the current player
	if (tv->gameHasFinished && !opponentsMove) tv->shortValue = SKV_VALUE_GAME_WON;
	if (tv->gameHasFinished &&  opponentsMove) tv->shortValue = SKV_VALUE_GAME_LOST;

    tv->floatValue = tv->shortValue;

	// calc value
	if (!opponentsMove)						tv->floatValue = (float) tv->field->oppPlayer->numStonesMissing - tv->field->curPlayer->numStonesMissing + tv->field->stoneMustBeRemoved + tv->field->curPlayer->numPossibleMoves * 0.1f - tv->field->oppPlayer->numPossibleMoves * 0.1f;
	else									tv->floatValue = (float) tv->field->curPlayer->numStonesMissing - tv->field->oppPlayer->numStonesMissing - tv->field->stoneMustBeRemoved + tv->field->oppPlayer->numPossibleMoves * 0.1f - tv->field->curPlayer->numPossibleMoves * 0.1f;

	// when game has finished - perfect for the current player
	if (tv->gameHasFinished && !opponentsMove)	tv->floatValue =  VALUE_GAME_WON  - tv->curSearchDepth;
	if (tv->gameHasFinished &&  opponentsMove)	tv->floatValue =  VALUE_GAME_LOST + tv->curSearchDepth;

	// set next player
	if (!tv->field->stoneMustBeRemoved) {
		tmpPlayer				= tv->field->curPlayer;
		tv->field->curPlayer	= tv->field->oppPlayer;
		tv->field->oppPlayer	= tmpPlayer;
	}
}

//-----------------------------------------------------------------------------
// Name: storeValueOfMove()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::storeValueOfMove(unsigned int threadNo, unsigned int idPossibility, void *pPossibilities, unsigned char value, unsigned int *freqValuesSubMoves, plyInfoVarType plyInfo)
{	
	// locals
	threadVarsStruct * tv = &threadVars[threadNo];
	unsigned int		index;
	possibilityStruct	*tmpPossibility = (possibilityStruct*) pPossibilities;

	if (tv->field->stoneMustBeRemoved)	index = idPossibility;
	else if (tv->field->settingPhase)	index = idPossibility;
	else								index = tmpPossibility->from[idPossibility] * fieldStruct::size + tmpPossibility->to[idPossibility];

	plyInfoForOutput[index]									= plyInfo;
	valueOfMove[index]										= value;
	incidencesValuesSubMoves[index][SKV_VALUE_INVALID	]	= freqValuesSubMoves[SKV_VALUE_INVALID		];
	incidencesValuesSubMoves[index][SKV_VALUE_GAME_LOST	]	= freqValuesSubMoves[SKV_VALUE_GAME_LOST	];
	incidencesValuesSubMoves[index][SKV_VALUE_GAME_DRAWN]	= freqValuesSubMoves[SKV_VALUE_GAME_DRAWN	];
	incidencesValuesSubMoves[index][SKV_VALUE_GAME_WON	]	= freqValuesSubMoves[SKV_VALUE_GAME_WON		];
}

//-----------------------------------------------------------------------------
// Name: getValueOfMoves()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getValueOfMoves(unsigned char *moveValue, unsigned int *freqValuesSubMoves, plyInfoVarType *plyInfo, unsigned int *moveQuality, unsigned char &knotValue, plyInfoVarType &bestAmountOfPlies)
{
	// locals
	unsigned int	moveQualities[fieldStruct::size * fieldStruct::size];	// 0 is bad, 1 is good
	unsigned int	i, j;

	// set an invalid default value
	knotValue = SKV_NUM_VALUES;

	// calc knotValue
	for (i=0; i<fieldStruct::size; i++) { 
		for (j=0; j<fieldStruct::size; j++) { 
			if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_WON) {
				knotValue	= SKV_VALUE_GAME_WON;
				i			= fieldStruct::size;
				j			= fieldStruct::size;
			} else if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_DRAWN) {
				knotValue	= SKV_VALUE_GAME_DRAWN;
			} else if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_LOST && knotValue != SKV_VALUE_GAME_DRAWN) {
				knotValue	= SKV_VALUE_GAME_LOST;
			}
		}
	}

	// calc move bestAmountOfPlies	
	if (knotValue == SKV_VALUE_GAME_WON) {
		bestAmountOfPlies = PLYINFO_VALUE_INVALID;

		for (i=0; i<fieldStruct::size; i++) { 
			for (j=0; j<fieldStruct::size; j++) { 
				if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_WON) {
					if (bestAmountOfPlies >= plyInfoForOutput[i*fieldStruct::size+j]) {
						bestAmountOfPlies = plyInfoForOutput[i*fieldStruct::size+j];
					}
				}
			}
		}
		
	} else if (knotValue == SKV_VALUE_GAME_LOST) {
		bestAmountOfPlies = 0;

		for (i=0; i<fieldStruct::size; i++) { 
			for (j=0; j<fieldStruct::size; j++) { 
				if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_LOST) {
					if (bestAmountOfPlies <= plyInfoForOutput[i*fieldStruct::size+j]) {
						bestAmountOfPlies = plyInfoForOutput[i*fieldStruct::size+j];
					}
				}
			}
		}
	} else if (knotValue == SKV_VALUE_GAME_DRAWN) {
		bestAmountOfPlies = 0;

		for (i=0; i<fieldStruct::size; i++) { 
			for (j=0; j<fieldStruct::size; j++) { 
				if (valueOfMove[i*fieldStruct::size+j] == SKV_VALUE_GAME_DRAWN) {
					if (bestAmountOfPlies <= incidencesValuesSubMoves[i*fieldStruct::size+j][SKV_VALUE_GAME_WON]) {
						bestAmountOfPlies = incidencesValuesSubMoves[i*fieldStruct::size+j][SKV_VALUE_GAME_WON];
					}
				}
			}
		}
	} 

	// zero move qualities
	for (i=0; i<fieldStruct::size; i++) { 
		for (j=0; j<fieldStruct::size; j++) {
			if ((valueOfMove[i*fieldStruct::size+j] == knotValue && bestAmountOfPlies == plyInfoForOutput[i*fieldStruct::size+j]						     && knotValue != SKV_VALUE_GAME_DRAWN) 
			||  (valueOfMove[i*fieldStruct::size+j] == knotValue && bestAmountOfPlies == incidencesValuesSubMoves[i*fieldStruct::size+j][SKV_VALUE_GAME_WON] && knotValue == SKV_VALUE_GAME_DRAWN)) {
				moveQualities[i*fieldStruct::size+j] = 1;
			} else {
				moveQualities[i*fieldStruct::size+j] = 0;
			}
		}
	}

	// copy
	memcpy(moveQuality,			moveQualities,				sizeof(unsigned int)  * fieldStruct::size * fieldStruct::size);	
	memcpy(plyInfo,				plyInfoForOutput,			sizeof(plyInfoVarType)* fieldStruct::size * fieldStruct::size);	
	memcpy(moveValue,			valueOfMove,				sizeof(unsigned char) * fieldStruct::size * fieldStruct::size);	
	memcpy(freqValuesSubMoves,	incidencesValuesSubMoves,	sizeof(unsigned int ) * fieldStruct::size * fieldStruct::size * 4);	
}

//-----------------------------------------------------------------------------
// Name: printMoveInformation()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::printMoveInformation(unsigned int threadNo, unsigned int idPossibility, void *pPossibilities)
{
	// locals
	threadVarsStruct * tv = &threadVars[threadNo];
	possibilityStruct	*tmpPossibility = (possibilityStruct*) pPossibilities;

	// move
	if (tv->field->stoneMustBeRemoved)	cout << "remove stone from " << (char) (idPossibility + 97);														
	else if (tv->field->settingPhase)	cout << "set stone to "      << (char) (idPossibility + 97);															
	else								cout << "move from "		 << (char) (tmpPossibility->from[idPossibility] + 97) << " to " << (char) (tmpPossibility->to[idPossibility] + 97);
}

//-----------------------------------------------------------------------------
// Name: getNumberOfLayers()
// Desc: called one time
//-----------------------------------------------------------------------------
unsigned int perfectKI::getNumberOfLayers()
{
	return NUM_LAYERS;
}

//-----------------------------------------------------------------------------
// Name: shallRetroAnalysisBeUsed()
// Desc: called one time for each layer time
//-----------------------------------------------------------------------------
bool perfectKI::shallRetroAnalysisBeUsed(unsigned int layerNum)
{
    if (layerNum < 100) 
	    return true;
    else 
        return false;
}

//-----------------------------------------------------------------------------
// Name: getNumberOfKnotsInLayer()
// Desc: called one time
//-----------------------------------------------------------------------------
unsigned int perfectKI::getNumberOfKnotsInLayer(unsigned int layerNum)
{
    // locals
    unsigned int numberOfKnots = layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex + 1;

    // times two since either an own stone must be moved or an opponent stone must be removed
    numberOfKnots *= MAX_NUM_STONES_REMOVED_MINUS_1;

	// return zero if layer is not reachable
	if (((layer[layerNum].numBlackStones  < 2 || layer[layerNum].numWhiteStones  < 2) && layerNum  < 100)	// moving phase
	||   (layer[layerNum].numBlackStones == 2 && layer[layerNum].numWhiteStones == 2  && layerNum  < 100)
    ||																				    (layerNum == 100))
		return 0;

    // another way
    return (unsigned int) numberOfKnots;
}

//-----------------------------------------------------------------------------
// Name: nOverN()
// Desc: called seldom
//-----------------------------------------------------------------------------
long long perfectKI::mOverN_Function(unsigned int m, unsigned int n)
{
	// locals
	long long result	= 1;
	long long fakN		= 1;	
	unsigned int i;

	// invalid parameters ?
	if (n > m) return 0;

	// flip, since then the result value won't get so high
	if (n > m/2) n = m-n;

	// calc number of possibilities one can put n different stones in m holes
	for (i=m-n+1; i<=m; i++) result *= i;

	// calc number of possibilities one can sort n different stones
	for (i=    1; i<=n; i++) fakN *= i;

	// divide
	result /= fakN;

    return result;
}

//-----------------------------------------------------------------------------
// Name: applySymmetrieOperationOnField()
// Desc: called very often
//-----------------------------------------------------------------------------
void perfectKI::applySymmetrieOperationOnField(unsigned char symmetryOperationNumber, unsigned int *sourceField, unsigned int *destField)
{
    for (unsigned int i=0; i<fieldStruct::size; i++) {
        destField[i] = sourceField[symmetryOperationTable[symmetryOperationNumber][i]];
    }
}

//-----------------------------------------------------------------------------
// Name: getLayerNumber()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int perfectKI::getLayerNumber(unsigned int threadNo)
{
	threadVarsStruct * tv = &threadVars[threadNo];
	unsigned int numBlackStones		= tv->field->oppPlayer->numStones;
	unsigned int numWhiteStones		= tv->field->curPlayer->numStones;
	unsigned int phaseIndex			= (tv->field->settingPhase == true) ? LAYER_INDEX_SETTING_PHASE : LAYER_INDEX_MOVING_PHASE;
	return layerIndex[phaseIndex][numWhiteStones][numBlackStones];
}

//-----------------------------------------------------------------------------
// Name: getLayerAndStateNumber()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int perfectKI::getLayerAndStateNumber(unsigned int threadNo, unsigned int &layerNum, unsigned int &stateNumber)
{
	threadVarsStruct * tv = &threadVars[threadNo];
	return tv->getLayerAndStateNumber(layerNum, stateNumber);
}

//-----------------------------------------------------------------------------
// Name: getLayerAndStateNumber()
// Desc: Current player has white stones, the opponent the black ones.
//-----------------------------------------------------------------------------
unsigned int perfectKI::threadVarsStruct::getLayerAndStateNumber(unsigned int &layerNum, unsigned int &stateNumber)
{
    // locals
	unsigned int myField [fieldStruct::size];
    unsigned int symField[fieldStruct::size];
	unsigned int numBlackStones		= field->oppPlayer->numStones;
	unsigned int numWhiteStones		= field->curPlayer->numStones;
	unsigned int phaseIndex			= (field->settingPhase == true) ? LAYER_INDEX_SETTING_PHASE : LAYER_INDEX_MOVING_PHASE;
    unsigned int wCD = 0, bCD = 0;
    unsigned int stateAB, stateCD;
	unsigned int i;

	// layer number
	layerNum = parent->layerIndex[phaseIndex][numWhiteStones][numBlackStones];

	// make white and black fields
    for(i=0; i<fieldStruct::size; i++) {
        if (field->field[i] == fieldStruct::squareIsFree) {
            myField[i] = FREE_SQUARE;
        } else if (field->field[i] == field->curPlayer->id) {
            myField[i] = WHITE_STONE;
            if (fieldPosIsOfGroup[i] == GROUP_C) wCD++;
            if (fieldPosIsOfGroup[i] == GROUP_D) wCD++;
        } else {
            myField[i] = BLACK_STONE;
            if (fieldPosIsOfGroup[i] == GROUP_C) bCD++;
            if (fieldPosIsOfGroup[i] == GROUP_D) bCD++;
        }
	}

    // calc stateCD
    stateCD = myField[squareIndexGroupC[0]] * parent->powerOfThree[15]
            + myField[squareIndexGroupC[1]] * parent->powerOfThree[14]
            + myField[squareIndexGroupC[2]] * parent->powerOfThree[13]
            + myField[squareIndexGroupC[3]] * parent->powerOfThree[12]
            + myField[squareIndexGroupC[4]] * parent->powerOfThree[11]
            + myField[squareIndexGroupC[5]] * parent->powerOfThree[10]
            + myField[squareIndexGroupC[6]] * parent->powerOfThree[ 9]
            + myField[squareIndexGroupC[7]] * parent->powerOfThree[ 8]
            + myField[squareIndexGroupD[0]] * parent->powerOfThree[ 7]
            + myField[squareIndexGroupD[1]] * parent->powerOfThree[ 6]
            + myField[squareIndexGroupD[2]] * parent->powerOfThree[ 5]
            + myField[squareIndexGroupD[3]] * parent->powerOfThree[ 4]
            + myField[squareIndexGroupD[4]] * parent->powerOfThree[ 3]
            + myField[squareIndexGroupD[5]] * parent->powerOfThree[ 2]
            + myField[squareIndexGroupD[6]] * parent->powerOfThree[ 1]
            + myField[squareIndexGroupD[7]] * parent->powerOfThree[ 0];

    // apply symmetry operation on group A&B
    parent->applySymmetrieOperationOnField(parent->symmetryOperationCD[stateCD], myField, symField);

    // calc stateAB
    stateAB = symField[squareIndexGroupA[0]] * parent->powerOfThree[7]
            + symField[squareIndexGroupA[1]] * parent->powerOfThree[6]
            + symField[squareIndexGroupA[2]] * parent->powerOfThree[5]
            + symField[squareIndexGroupA[3]] * parent->powerOfThree[4]
            + symField[squareIndexGroupB[0]] * parent->powerOfThree[3]
            + symField[squareIndexGroupB[1]] * parent->powerOfThree[2]
            + symField[squareIndexGroupB[2]] * parent->powerOfThree[1]
            + symField[squareIndexGroupB[3]] * parent->powerOfThree[0];

    // calc index
    stateNumber = parent->layer[layerNum].subLayer[parent->layer[layerNum].subLayerIndexCD[wCD][bCD]].minIndex    * MAX_NUM_STONES_REMOVED_MINUS_1
                + parent->indexAB[stateAB] * parent->anzahlStellungenCD[wCD][bCD]                                 * MAX_NUM_STONES_REMOVED_MINUS_1
                + parent->indexCD[stateCD]																		  * MAX_NUM_STONES_REMOVED_MINUS_1
                + field->stoneMustBeRemoved;

	return parent->symmetryOperationCD[stateCD];
}

//-----------------------------------------------------------------------------
// Name: setSituation()
// Desc: Current player has white stones, the opponent the black ones.
//		 Sets up the game situation corresponding to the passed layer number and state.
//-----------------------------------------------------------------------------
bool perfectKI::setSituation(unsigned int threadNo, unsigned int layerNum, unsigned int stateNumber)
{
	// parameters ok ?
	if (getNumberOfLayers()				  <= layerNum   ) return false;
	if (getNumberOfKnotsInLayer(layerNum) <= stateNumber) return false;
	
	// locals
 	threadVarsStruct * tv = &threadVars[threadNo];
    unsigned int stateNumberWithInSubLayer;
    unsigned int stateNumberWithInAB;
    unsigned int stateNumberWithInCD;
    unsigned int stateAB, stateCD;
	unsigned int myField [fieldStruct::size];
    unsigned int symField[fieldStruct::size];
	unsigned int numWhiteStones					= layer[layerNum].numWhiteStones;
	unsigned int numBlackStones					= layer[layerNum].numBlackStones;
	unsigned int numberOfMillsCurrentPlayer		= 0;
	unsigned int numberOfMillsOpponentPlayer	= 0;
	unsigned int wCD, bCD, wAB, bAB;
    unsigned int i;
    bool         aStoneCanBeRemovedFromCurPlayer;
	
    // get wCD, bCD, wAB, bAB
    for (i=0; i<=layer[layerNum].numSubLayers; i++) { 
        if (layer[layerNum].subLayer[i].minIndex <= stateNumber / MAX_NUM_STONES_REMOVED_MINUS_1 
         && layer[layerNum].subLayer[i].maxIndex >= stateNumber / MAX_NUM_STONES_REMOVED_MINUS_1) {
            wCD = layer[layerNum].subLayer[i].numWhiteStonesGroupCD;
            bCD = layer[layerNum].subLayer[i].numBlackStonesGroupCD;
            wAB = layer[layerNum].subLayer[i].numWhiteStonesGroupAB;
            bAB = layer[layerNum].subLayer[i].numBlackStonesGroupAB;
            break;
        }
    }

	// reset values
    tv->curSearchDepth                      = 0;
	tv->floatValue		                    = 0.0f;
	tv->shortValue		                    = SKV_VALUE_GAME_DRAWN;
	tv->gameHasFinished	                    = false;

	tv->field->settingPhase					= (layerNum >= NUM_LAYERS / 2) ? LAYER_INDEX_SETTING_PHASE : LAYER_INDEX_MOVING_PHASE;
	tv->field->stoneMustBeRemoved			= stateNumber % MAX_NUM_STONES_REMOVED_MINUS_1;
	tv->field->curPlayer->numStones			= numWhiteStones;
	tv->field->oppPlayer->numStones			= numBlackStones;

    // reconstruct field->field[]
    stateNumberWithInSubLayer = (stateNumber / MAX_NUM_STONES_REMOVED_MINUS_1) - layer[layerNum].subLayer[layer[layerNum].subLayerIndexCD[wCD][bCD]].minIndex;
    stateNumberWithInAB       = stateNumberWithInSubLayer / anzahlStellungenCD[wCD][bCD];
    stateNumberWithInCD       = stateNumberWithInSubLayer % anzahlStellungenCD[wCD][bCD];

    // get stateCD
    stateCD = originalStateCD[wCD][bCD][stateNumberWithInCD];
    stateAB = originalStateAB[wAB][bAB][stateNumberWithInAB];

    // set myField from stateCD and stateAB
    myField[squareIndexGroupA[0]] = (stateAB / powerOfThree[7]) % 3;  
    myField[squareIndexGroupA[1]] = (stateAB / powerOfThree[6]) % 3;
    myField[squareIndexGroupA[2]] = (stateAB / powerOfThree[5]) % 3;
    myField[squareIndexGroupA[3]] = (stateAB / powerOfThree[4]) % 3;
    myField[squareIndexGroupB[0]] = (stateAB / powerOfThree[3]) % 3;
    myField[squareIndexGroupB[1]] = (stateAB / powerOfThree[2]) % 3;
    myField[squareIndexGroupB[2]] = (stateAB / powerOfThree[1]) % 3;
    myField[squareIndexGroupB[3]] = (stateAB / powerOfThree[0]) % 3;

    myField[squareIndexGroupC[0]] = (stateCD / powerOfThree[15]) % 3;  
    myField[squareIndexGroupC[1]] = (stateCD / powerOfThree[14]) % 3;
    myField[squareIndexGroupC[2]] = (stateCD / powerOfThree[13]) % 3;
    myField[squareIndexGroupC[3]] = (stateCD / powerOfThree[12]) % 3;
    myField[squareIndexGroupC[4]] = (stateCD / powerOfThree[11]) % 3;
    myField[squareIndexGroupC[5]] = (stateCD / powerOfThree[10]) % 3;
    myField[squareIndexGroupC[6]] = (stateCD / powerOfThree[ 9]) % 3;
    myField[squareIndexGroupC[7]] = (stateCD / powerOfThree[ 8]) % 3;
    myField[squareIndexGroupD[0]] = (stateCD / powerOfThree[ 7]) % 3;
    myField[squareIndexGroupD[1]] = (stateCD / powerOfThree[ 6]) % 3;
    myField[squareIndexGroupD[2]] = (stateCD / powerOfThree[ 5]) % 3;
    myField[squareIndexGroupD[3]] = (stateCD / powerOfThree[ 4]) % 3;
    myField[squareIndexGroupD[4]] = (stateCD / powerOfThree[ 3]) % 3;
    myField[squareIndexGroupD[5]] = (stateCD / powerOfThree[ 2]) % 3;
    myField[squareIndexGroupD[6]] = (stateCD / powerOfThree[ 1]) % 3;
    myField[squareIndexGroupD[7]] = (stateCD / powerOfThree[ 0]) % 3;
    
    // apply symmetry operation on group A&B
    applySymmetrieOperationOnField(reverseSymOperation[symmetryOperationCD[stateCD]], myField, symField);

    // translate symField[] to field->field[]
    for (i=0; i<fieldStruct::size; i++) {
             if (symField[i] == FREE_SQUARE) tv->field->field[i] = fieldStruct::squareIsFree;
        else if (symField[i] == WHITE_STONE) tv->field->field[i] = tv->field->curPlayer->id;
        else                                 tv->field->field[i] = tv->field->oppPlayer->id;
    }

  	// calc possible moves
	tv->calcPossibleMoves(tv->field->curPlayer);
	tv->calcPossibleMoves(tv->field->oppPlayer);

	// zero
	for (i=0; i<fieldStruct::size; i++) {
		tv->field->stonePartOfMill[i]	= 0;
	}

	// go in every direction
	for (i=0; i<fieldStruct::size; i++) {
		tv->setWarningAndMill(i, tv->field->neighbour[i][0][0], tv->field->neighbour[i][0][1]);
		tv->setWarningAndMill(i, tv->field->neighbour[i][1][0], tv->field->neighbour[i][1][1]);
	}
	
	// since every mill was detected 3 times
	for (i=0; i<fieldStruct::size; i++) tv->field->stonePartOfMill[i] /= 3;

	// count completed mills
	for (i=0; i<fieldStruct::size; i++) {
		if (tv->field->field[i] == tv->field->curPlayer->id) numberOfMillsCurrentPlayer  += tv->field->stonePartOfMill[i];
		else												 numberOfMillsOpponentPlayer += tv->field->stonePartOfMill[i];
	}

	numberOfMillsCurrentPlayer  /= 3;
	numberOfMillsOpponentPlayer /= 3;

	// stonesSet & numStonesMissing
	if (tv->field->settingPhase) {
		// BUG: ... This calculation is not correct! It is possible that some mills did not cause a stone removal.
		tv->field->curPlayer->numStonesMissing	= numberOfMillsOpponentPlayer;
		tv->field->oppPlayer->numStonesMissing	= numberOfMillsCurrentPlayer - tv->field->stoneMustBeRemoved;
		tv->field->stonesSet					= tv->field->curPlayer->numStones + tv->field->oppPlayer->numStones + tv->field->curPlayer->numStonesMissing + tv->field->oppPlayer->numStonesMissing;
	} else {
		tv->field->stonesSet					= 18;
		tv->field->curPlayer->numStonesMissing	= 9 - tv->field->curPlayer->numStones;
		tv->field->oppPlayer->numStonesMissing	= 9 - tv->field->oppPlayer->numStones;
	}

	// when opponent is unable to move than current player has won
    if ((!tv->field->curPlayer->numPossibleMoves) && (!tv->field->settingPhase) && (!tv->field->stoneMustBeRemoved) && (tv->field->curPlayer->numStones > 3))	{ tv->gameHasFinished = true; tv->shortValue = SKV_VALUE_GAME_LOST; }
    if ((tv->field->curPlayer->numStones < 3) && (!tv->field->settingPhase))																					{ tv->gameHasFinished = true; tv->shortValue = SKV_VALUE_GAME_LOST; }
    if ((tv->field->oppPlayer->numStones < 3) && (!tv->field->settingPhase))																					{ tv->gameHasFinished = true; tv->shortValue = SKV_VALUE_GAME_WON;  }

   tv-> floatValue = tv->shortValue;

    // precalc aStoneCanBeRemovedFromCurPlayer
    for (aStoneCanBeRemovedFromCurPlayer=false, i=0; i<tv->field->size; i++) { 
        if (tv->field->stonePartOfMill[i] == 0 && tv->field->field[i] == tv->field->curPlayer->id) {
            aStoneCanBeRemovedFromCurPlayer = true;
            break; 
    }}

	// test if field is ok
	return tv->fieldIntegrityOK(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, aStoneCanBeRemovedFromCurPlayer);
}

//-----------------------------------------------------------------------------
// Name: calcPossibleMoves()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::threadVarsStruct::calcPossibleMoves(playerStruct *player)
{
	// locals
	unsigned int i, j , k, movingDirection;	

	for (player->numPossibleMoves=0, i=0; i<fieldStruct::size; i++) { for (j=0; j<fieldStruct::size; j++) {	

		// is stone from player ?
		if (field->field[i] != player->id)					continue;
		
		// is destination free ?
		if (field->field[j] != field->squareIsFree)			continue;

		// when current player has only 3 stones he is allowed to spring his stone
		if (player->numStones > 3 || field->settingPhase) {

			// determine moving direction
			for (k=0, movingDirection=4; k<4; k++) if (field->connectedSquare[i][k] == j) movingDirection = k;

			// are both squares connected ?
			if (movingDirection == 4)	continue;
		}

		// everything is ok
		player->numPossibleMoves++;
	}}
}

//-----------------------------------------------------------------------------
// Name: setWarningAndMill()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::threadVarsStruct::setWarningAndMill(unsigned int stone, unsigned int firstNeighbour, unsigned int secondNeighbour)
{
	// locals
	int				rowOwner		= field->field[stone];

	// mill closed ?
	if (rowOwner != field->squareIsFree && field->field[firstNeighbour] == rowOwner && field->field[secondNeighbour] == rowOwner) {
					
		field->stonePartOfMill[stone]++;
		field->stonePartOfMill[firstNeighbour]++;
		field->stonePartOfMill[secondNeighbour]++;
	}
}

//-----------------------------------------------------------------------------
// Name: getOutputInformation()
// Desc: 
//-----------------------------------------------------------------------------
string perfectKI::getOutputInformation(unsigned int layerNum)
{
	stringstream ss;
	ss << " white stones : " << layer[layerNum].numWhiteStones << "  \tblack stones  : " << layer[layerNum].numBlackStones;
	return ss.str();
}

//-----------------------------------------------------------------------------
// Name: printField()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::printField(unsigned int threadNo, unsigned char value)
{
	threadVarsStruct * tv = &threadVars[threadNo];
    char  wonStr[]  = "WON";
    char  lostStr[] = "LOST";
    char  drawStr[] = "DRAW";
    char  invStr[]  = "INVALID";
    char* table[4]  = {invStr, lostStr, drawStr, wonStr};

	cout << "\nstate value             : " << table[value];
	cout << "\nstones set              : " << tv->field->stonesSet << "\n";
	tv->field->printField();
}

//-----------------------------------------------------------------------------
// Name: getField()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getField(unsigned int layerNum, unsigned int stateNumber, fieldStruct *field, bool *gameHasFinished)
{
	// set current desired state on thread zero
	setSituation(0, layerNum, stateNumber);

	// copy content of fieldStruct
	threadVars[0].field->copyField(field);
	if (gameHasFinished != NULL) *gameHasFinished = threadVars[0].gameHasFinished;
}


//-----------------------------------------------------------------------------
// Name: getLayerAndStateNumber()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getLayerAndStateNumber(unsigned int& layerNum, unsigned int& stateNumber/*, unsigned int& symmetryOperation*/)
{
	/*symmetryOperation = */threadVars[0].getLayerAndStateNumber(layerNum, stateNumber);
}

//-----------------------------------------------------------------------------
// Name: setOpponentLevel()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::setOpponentLevel(unsigned int threadNo, bool isOpponentLevel)
{
	threadVarsStruct * tv = &threadVars[threadNo];
	tv->ownId = isOpponentLevel ? tv->field->oppPlayer->id : tv->field->curPlayer->id;
}

//-----------------------------------------------------------------------------
// Name: getOpponentLevel()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::getOpponentLevel(unsigned int threadNo)
{
	threadVarsStruct * tv = &threadVars[threadNo];
	return (tv->ownId == tv->field->oppPlayer->id);
}

//-----------------------------------------------------------------------------
// Name: getPartnerLayer()
// Desc: 
//-----------------------------------------------------------------------------
unsigned int perfectKI::getPartnerLayer(unsigned int layerNum)
{
	if (layerNum < 100) 
		for (int i=0; i<100; i++) {
			if (layer[layerNum].numBlackStones == layer[i].numWhiteStones
			&&  layer[layerNum].numWhiteStones == layer[i].numBlackStones) {
				return i;
			}
		}
	return layerNum;
}

//-----------------------------------------------------------------------------
// Name: getSuccLayers()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getSuccLayers(unsigned int layerNum, unsigned int *amountOfSuccLayers, unsigned int *succLayers)
{   
    // locals
    unsigned int i;
	unsigned int shift = (layerNum >= 100) ? 100 :  0;
			 int diff  = (layerNum >= 100) ?   1 : -1;
    
    // search layer with one white stone less
    for (*amountOfSuccLayers=0, i=0+shift; i<100+shift; i++) {
        if (layer[i].numWhiteStones == layer[layerNum].numBlackStones + diff
        &&  layer[i].numBlackStones == layer[layerNum].numWhiteStones    ) {
            succLayers[*amountOfSuccLayers] = i;
            *amountOfSuccLayers             = *amountOfSuccLayers + 1;
            break;
        }
    }

    // search layer with one black stone less
    for (i=0+shift; i<100+shift; i++) {
        if (layer[i].numWhiteStones == layer[layerNum].numBlackStones
        &&  layer[i].numBlackStones == layer[layerNum].numWhiteStones + diff) {
            succLayers[*amountOfSuccLayers] = i;
            *amountOfSuccLayers             = *amountOfSuccLayers + 1;
            break;
        }
    }
}

//-----------------------------------------------------------------------------
// Name: getSymStateNumWithDoubles()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::getSymStateNumWithDoubles(unsigned int threadNo, unsigned int *numSymmetricStates, unsigned int **symStateNumbers)
{
	// locals
	threadVarsStruct * tv = &threadVars[threadNo];
	int			 originalField	   [fieldStruct::size];
	unsigned int originalPartOfMill[fieldStruct::size];
	unsigned int i, symmetryOperation;
	unsigned int layerNum, stateNum;
				 
	*numSymmetricStates = 0;
	*symStateNumbers	= symmetricStateNumberArray;

	// save current field
	for (i=0; i<fieldStruct::size; i++) {
		originalField[i]	  = tv->field->field[i];
		originalPartOfMill[i] = tv->field->stonePartOfMill[i];
	}

	// add all symmetric states
	for (symmetryOperation=0; symmetryOperation<NUM_SYM_OPERATIONS; symmetryOperation++) {

		// appy symmetry operation
		applySymmetrieOperationOnField(symmetryOperation, (unsigned int*) originalField,	  (unsigned int*) tv->field->field);
		applySymmetrieOperationOnField(symmetryOperation, (unsigned int*) originalPartOfMill, (unsigned int*) tv->field->stonePartOfMill);

		getLayerAndStateNumber(threadNo, layerNum, stateNum);
		symmetricStateNumberArray[*numSymmetricStates]		= stateNum;										
		(*numSymmetricStates)++;
	}

	// restore original field
	for (i=0; i<fieldStruct::size; i++) {
		tv->field->field[i]			  = originalField[i];
		tv->field->stonePartOfMill[i] = originalPartOfMill[i];
	}
}

//-----------------------------------------------------------------------------
// Name: fieldIntegrityOK()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::threadVarsStruct::fieldIntegrityOK(unsigned int numberOfMillsCurrentPlayer, unsigned int numberOfMillsOpponentPlayer, bool aStoneCanBeRemovedFromCurPlayer) 
{
	// locals
	int  i, j;
	bool noneFullFilled;

	// when stone is going to be removed than at least one opponent stone mustn't be part of a mill
	if (numberOfMillsOpponentPlayer > 0 && field->stoneMustBeRemoved) {
		for (i=0; i<field->size; i++) if (field->stonePartOfMill[i] == 0 && field->oppPlayer->id == field->field[i]) break;
		if (i == field->size) return false;
	}

	// when no mill is closed than no stone can be removed
	if (field->stoneMustBeRemoved && numberOfMillsCurrentPlayer == 0) {
		return false;

	// when in setting phase and difference in number of stones between the two players is not
	} else if (field->settingPhase) {

		// Version 8: added for-loop
		noneFullFilled = true;

		for (i=0; noneFullFilled && i<=(int)numberOfMillsOpponentPlayer && i<=(int)numberOfMillsCurrentPlayer; i++) {
			for (j=0; noneFullFilled && j<=(int)numberOfMillsOpponentPlayer && j<=(int)numberOfMillsCurrentPlayer-(int)field->stoneMustBeRemoved; j++) {
				if (field->curPlayer->numStones + numberOfMillsOpponentPlayer + 0 - field->stoneMustBeRemoved - j == field->oppPlayer->numStones + numberOfMillsCurrentPlayer - field->stoneMustBeRemoved - i) noneFullFilled = false;
				if (field->curPlayer->numStones + numberOfMillsOpponentPlayer + 1 - field->stoneMustBeRemoved - j == field->oppPlayer->numStones + numberOfMillsCurrentPlayer - field->stoneMustBeRemoved - i) noneFullFilled = false;
			}
		}

		if (noneFullFilled || field->stonesSet >= 18) {
			return false;
		}
	
	// moving phase
	} else if (!field->settingPhase && (field->curPlayer->numStones < 2 || field->oppPlayer->numStones < 2)) {
		return false;
	}

	return true;
}

//-----------------------------------------------------------------------------
// Name: isSymOperationInvariantOnGroupCD()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::isSymOperationInvariantOnGroupCD(unsigned int symmetryOperation, int *theField)
{
	// locals
	unsigned int i;

	i = squareIndexGroupC[0]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[1]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[2]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[3]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[4]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[5]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[6]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupC[7]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[0]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[1]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[2]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[3]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[4]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[5]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[6]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;
	i = squareIndexGroupD[7]; 	if (theField[i] != theField[symmetryOperationTable[symmetryOperation][i]]) return false;

	return true;
}

//-----------------------------------------------------------------------------
// Name: storePredecessor()
// Desc: 
//-----------------------------------------------------------------------------
void perfectKI::threadVarsStruct::storePredecessor(unsigned int numberOfMillsCurrentPlayer, unsigned int numberOfMillsOpponentPlayer, unsigned int *amountOfPred, retroAnalysisPredVars *predVars)
{
	// locals
	int			 originalField[fieldStruct::size];
	unsigned int i, symmetryOperation, symOpApplied;
	unsigned int predLayerNum, predStateNum;
	unsigned int originalAmountOfPred = *amountOfPred;

	// store only if state is valid
	if (fieldIntegrityOK(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, false)) {

		// save current field
		for (i=0; i<fieldStruct::size; i++) originalField[i] = field->field[i];

		// add all symmetric states
		for (symmetryOperation=0; symmetryOperation<NUM_SYM_OPERATIONS; symmetryOperation++) {

			// ...
			if (symmetryOperation == SO_DO_NOTHING || parent->isSymOperationInvariantOnGroupCD(symmetryOperation, originalField)) {

				// appy symmetry operation
				parent->applySymmetrieOperationOnField(symmetryOperation, (unsigned int*) originalField, (unsigned int*) field->field);

                symOpApplied								= getLayerAndStateNumber(predLayerNum, predStateNum);
				predVars[*amountOfPred].predSymOperation	= parent->concSymOperation[symmetryOperation][symOpApplied]; 
				predVars[*amountOfPred].predLayerNumbers	= predLayerNum;
				predVars[*amountOfPred].predStateNumbers	= predStateNum;										
				predVars[*amountOfPred].playerToMoveChanged	= predVars[originalAmountOfPred].playerToMoveChanged;
		
				// add only if not already in list
				for (i=0; i<(*amountOfPred); i++) if (predVars[i].predLayerNumbers == predLayerNum && predVars[i].predStateNumbers == predStateNum) break;
				if (i == *amountOfPred) (*amountOfPred)++;
			}
		}

		// restore original field
		for (i=0; i<fieldStruct::size; i++) field->field[i] = originalField[i];
	}
}

//-----------------------------------------------------------------------------
// Name: getPredecessors()
// Desc: CAUTION: States musn't be returned twice.
//-----------------------------------------------------------------------------
void perfectKI::getPredecessors(unsigned int threadNo, unsigned int *amountOfPred, retroAnalysisPredVars *predVars)
{
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // the important variables, which much be updated for the getLayerAndStateNumber function are the following ones:
    // - field->curPlayer->numStones
    // - field->oppPlayer->numStones
    // - field->curPlayer->id
    // - field->field
    // - field->stoneMustBeRemoved
    // - field->settingPhase
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // locals
  	threadVarsStruct * tv = &threadVars[threadNo];
	bool         aStoneCanBeRemovedFromCurPlayer;
    bool         millWasClosed;
    unsigned int from, to, dir, i;
    playerStruct *tmpPlayer;
	unsigned int numberOfMillsCurrentPlayer			= 0;
	unsigned int numberOfMillsOpponentPlayer		= 0;

    // zero
    *amountOfPred        = 0;

	// count completed mills
	for (i=0; i<fieldStruct::size; i++) {
		if (tv->field->field[i] == tv->field->curPlayer->id) numberOfMillsCurrentPlayer  += tv->field->stonePartOfMill[i];
		else												 numberOfMillsOpponentPlayer += tv->field->stonePartOfMill[i];
	}

	numberOfMillsCurrentPlayer  /= 3;
	numberOfMillsOpponentPlayer /= 3;

    // precalc aStoneCanBeRemovedFromCurPlayer
    for (aStoneCanBeRemovedFromCurPlayer=false, i=0; i<tv->field->size; i++) { 
        if (tv->field->stonePartOfMill[i] == 0 && tv->field->field[i] == tv->field->curPlayer->id) {
            aStoneCanBeRemovedFromCurPlayer = true;
            break; 
    }}

    // was a mill closed?
    if (tv->field->stoneMustBeRemoved) millWasClosed = true;
    else							   millWasClosed = false;

    // in moving phase
    if (!tv->field->settingPhase && tv->field->curPlayer->numStones >= 3 && tv->field->oppPlayer->numStones >= 3) {

        // normal move
	    if (( tv->field->stoneMustBeRemoved && tv->field->curPlayer->numStones > 3)
        ||  (!tv->field->stoneMustBeRemoved && tv->field->oppPlayer->numStones > 3)) {

            // when game has finished then because current player can't move anymore or has less then 3 stones
            if (!tv->gameHasFinished || (tv->gameHasFinished && tv->field->curPlayer->numPossibleMoves == 0)) {

                // test each destination
		        for (to=0; to < tv->field->size; to++) { 

                    // was opponent player stone owner?
                    if (tv->field->field[to] != (tv->field->stoneMustBeRemoved ? tv->field->curPlayer->id : tv->field->oppPlayer->id)) continue;

					// when stone is going to be removed than a mill must be closed
					if (tv->field->stoneMustBeRemoved && tv->field->stonePartOfMill[to] == 0) continue;

					// when stone is part of a mill then a stone must be removed
					if (aStoneCanBeRemovedFromCurPlayer && tv->field->stoneMustBeRemoved == 0 && tv->field->stonePartOfMill[to]) continue;

                    // test each direction
                    for (dir=0; dir<4; dir++) {

			            // origin 
			            from = tv->field->connectedSquare[to][dir];

			            // move possible ?
			            if (from < tv->field->size && tv->field->field[from] == tv->field->squareIsFree) {

							if (millWasClosed) {
								numberOfMillsCurrentPlayer -= tv->field->stonePartOfMill[to];
                                tv->field->stoneMustBeRemoved				 = 0;
                                predVars[*amountOfPred].playerToMoveChanged  = false;
                            } else {
                                predVars[*amountOfPred].playerToMoveChanged  = true;
                                tmpPlayer					= tv->field->curPlayer;
		                        tv->field->curPlayer		= tv->field->oppPlayer;
		                        tv->field->oppPlayer		= tmpPlayer;
								i							= numberOfMillsCurrentPlayer;
								numberOfMillsCurrentPlayer	= numberOfMillsOpponentPlayer;
								numberOfMillsOpponentPlayer	= i;
								numberOfMillsCurrentPlayer -= tv->field->stonePartOfMill[to];
                            }

	    			        // make move
                            tv->field->field[from]      = tv->field->field[to];
                            tv->field->field[to]        = tv->field->squareIsFree;

							// store predecessor
							tv->storePredecessor(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, amountOfPred, predVars);

                            // undo move
                            tv->field->field[to]        = tv->field->field[from];
                            tv->field->field[from]      = tv->field->squareIsFree;

                            if (millWasClosed) {
								numberOfMillsCurrentPlayer += tv->field->stonePartOfMill[to];
                                tv->field->stoneMustBeRemoved  = 1;
                            } else {
                                tmpPlayer					= tv->field->curPlayer;
		                        tv->field->curPlayer		= tv->field->oppPlayer;
		                        tv->field->oppPlayer		= tmpPlayer;
								numberOfMillsCurrentPlayer += tv->field->stonePartOfMill[to];
								i							= numberOfMillsCurrentPlayer;
								numberOfMillsCurrentPlayer	= numberOfMillsOpponentPlayer;
								numberOfMillsOpponentPlayer	= i;
                            }
        	
	    // current or opponent player were allowed to spring
        }}}}} else if (!tv->gameHasFinished) {

            // test each destination
		    for (to=0; to < tv->field->size; to++) { 

                // when stone must be removed than current player closed a mill, otherwise the opponent did a common spring move
                if (tv->field->field[to] != (tv->field->stoneMustBeRemoved ? tv->field->curPlayer->id : tv->field->oppPlayer->id)) continue;

				// when stone is going to be removed than a mill must be closed
				if (tv->field->stoneMustBeRemoved && tv->field->stonePartOfMill[to] == 0) continue;

				// when stone is part of a mill then a stone must be removed
				if (aStoneCanBeRemovedFromCurPlayer && tv->field->stoneMustBeRemoved == 0 && tv->field->stonePartOfMill[to]) continue;

				// test each direction
                for (from=0; from<tv->field->size; from++) {

			        // move possible ?
			        if (tv->field->field[from] == tv->field->squareIsFree) {

                        // was a mill closed?
                        if (millWasClosed) {
							numberOfMillsCurrentPlayer -= tv->field->stonePartOfMill[to];
                            tv->field->stoneMustBeRemoved				= 0;
                            predVars[*amountOfPred].playerToMoveChanged = false;
                        } else {
                            predVars[*amountOfPred].playerToMoveChanged	= true;
                            tmpPlayer					= tv->field->curPlayer;
		                    tv->field->curPlayer		= tv->field->oppPlayer;
		                    tv->field->oppPlayer		= tmpPlayer;
							i							= numberOfMillsCurrentPlayer;
							numberOfMillsCurrentPlayer	= numberOfMillsOpponentPlayer;
							numberOfMillsOpponentPlayer	= i;
							numberOfMillsCurrentPlayer -= tv->field->stonePartOfMill[to];
                        }

	    			    // make move
                        tv->field->field[from]  = tv->field->field[to];
                        tv->field->field[to]    = tv->field->squareIsFree;

						// store predecessor
						tv->storePredecessor(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, amountOfPred, predVars);

                        // undo move
                        tv->field->field[to]    = tv->field->field[from];
                        tv->field->field[from]  = tv->field->squareIsFree;

                        if (millWasClosed) {
							numberOfMillsCurrentPlayer += tv->field->stonePartOfMill[to];
                            tv->field->stoneMustBeRemoved   = 1;
                        } else {
                            tmpPlayer					= tv->field->curPlayer;
		                    tv->field->curPlayer		= tv->field->oppPlayer;
		                    tv->field->oppPlayer		= tmpPlayer;
							numberOfMillsCurrentPlayer += tv->field->stonePartOfMill[to];
							i							= numberOfMillsCurrentPlayer;
							numberOfMillsCurrentPlayer	= numberOfMillsOpponentPlayer;
							numberOfMillsOpponentPlayer	= i;
                        }
        }}}}
    }

    // was a stone removed ?
    if (tv->field->curPlayer->numStones < 9 && tv->field->curPlayer->numStonesMissing > 0 && tv->field->stoneMustBeRemoved == 0) { 

        // has opponent player a closed mill ?
        if (numberOfMillsOpponentPlayer) {
                
            // from each free position the opponent could have removed a stone from the current player
            for (from=0; from<tv->field->size; from++) {

                // square free?
                if (tv->field->field[from] == tv->field->squareIsFree) {

                    // stone mustn't be part of mill
                    if ((!(tv->field->field[tv->field->neighbour[from][0][0]] == tv->field->curPlayer->id && tv->field->field[tv->field->neighbour[from][0][1]] == tv->field->curPlayer->id))
                    &&  (!(tv->field->field[tv->field->neighbour[from][1][0]] == tv->field->curPlayer->id && tv->field->field[tv->field->neighbour[from][1][1]] == tv->field->curPlayer->id))) {

						// put back stone
						tv->field->stoneMustBeRemoved   = 1;
						tv->field->field[from]          = tv->field->curPlayer->id;
						tv->field->curPlayer->numStones++;
						tv->field->curPlayer->numStonesMissing--;

						// it was an opponent move
                        predVars[*amountOfPred].playerToMoveChanged	= true;
                        tmpPlayer									= tv->field->curPlayer;
		                tv->field->curPlayer						= tv->field->oppPlayer;
		                tv->field->oppPlayer						= tmpPlayer;

						// store predecessor
						tv->storePredecessor(numberOfMillsOpponentPlayer, numberOfMillsCurrentPlayer, amountOfPred, predVars);

						tmpPlayer									= tv->field->curPlayer;
		                tv->field->curPlayer						= tv->field->oppPlayer;
		                tv->field->oppPlayer						= tmpPlayer;

						// remove stone again
						tv->field->stoneMustBeRemoved   = 0;
						tv->field->field[from]          = tv->field->squareIsFree;
						tv->field->curPlayer->numStones--;
						tv->field->curPlayer->numStonesMissing++;
    }}}}}
}

//-----------------------------------------------------------------------------
// Name: checkMoveAndSetSituation()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::checkMoveAndSetSituation()
{
	// locals
	bool			aStoneCanBeRemovedFromCurPlayer;
	unsigned int	numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer;
	unsigned int	stateNum, layerNum, curMove, i;
	unsigned int *	idPossibility;
	unsigned int	numPossibilities;
	bool			isOpponentLevel;
	void *			pPossibilities;
	void *			pBackup;
	unsigned int    threadNo = 0;
	threadVarsStruct * tv = &threadVars[threadNo];

	// output 
	cout << endl << "checkMoveAndSetSituation()" << endl;

	// test if each successor from getPossibilities() leads to the original state using getPredecessors()
	for (layerNum=0; layerNum<NUM_LAYERS; layerNum++) {

		// generate random state
		cout << endl << "TESTING LAYER: " << layerNum;
		if (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex == 0) continue;

		// test each state of layer 
		for (stateNum=0; stateNum<(layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1; stateNum++) {

			// set situation
            if (stateNum % OUTPUT_EVERY_N_STATES == 0) cout << endl << "TESTING STATE " << stateNum << " OF " << (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1;
			if (!setSituation(threadNo, layerNum, stateNum)) continue;

			// get all possible moves
			idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities); 

			// go to each successor state
			for (curMove=0; curMove<numPossibilities; curMove++) {
					
				// move
				move(threadNo, idPossibility[curMove], isOpponentLevel, &pBackup, pPossibilities);

				// count completed mills
				numberOfMillsCurrentPlayer  = 0;
				numberOfMillsOpponentPlayer = 0;
				for (i=0; i<fieldStruct::size; i++) {
					if (tv->field->field[i] == tv->field->curPlayer->id)	numberOfMillsCurrentPlayer  += tv->field->stonePartOfMill[i];
					else													numberOfMillsOpponentPlayer += tv->field->stonePartOfMill[i];
				}
				numberOfMillsCurrentPlayer  /= 3;
				numberOfMillsOpponentPlayer /= 3;

				// precalc aStoneCanBeRemovedFromCurPlayer
				for (aStoneCanBeRemovedFromCurPlayer=false, i=0; i<tv->field->size; i++) { 
					if (tv->field->stonePartOfMill[i] == 0 && tv->field->field[i] == tv->field->curPlayer->id) {
						aStoneCanBeRemovedFromCurPlayer = true;
						break; 
				}}

				// 
				if (tv->fieldIntegrityOK(numberOfMillsCurrentPlayer, numberOfMillsOpponentPlayer, aStoneCanBeRemovedFromCurPlayer) == false) {
					cout << endl << "ERROR: STATE " << stateNum << " REACHED WITH move(), BUT IS INVALID!";
					//return false;
				}
				
				// undo move
				undo(threadNo, idPossibility[curMove], isOpponentLevel, pBackup, pPossibilities);
			}
		}
		cout << endl << "LAYER OK: " << layerNum << endl;
	}

	// free mem
	return true;
}

//-----------------------------------------------------------------------------
// Name: checkGetPossThanGetPred()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::checkGetPossThanGetPred()
{
	// locals
	unsigned int			stateNum, layerNum, i, j;
	unsigned int *			idPossibility;
	unsigned int			numPossibilities;
	unsigned int			amountOfPred;
	bool					isOpponentLevel;
	void *					pPossibilities;
	void *					pBackup;
	retroAnalysisPredVars	predVars[MAX_NUM_PREDECESSORS];
	unsigned int			threadNo = 0;
	threadVarsStruct *		tv = &threadVars[threadNo];

	// test if each successor from getPossibilities() leads to the original state using getPredecessors()
	for (layerNum=0; layerNum<NUM_LAYERS; layerNum++) {

		// generate random state
		cout << endl << "TESTING LAYER: " << layerNum;
		if (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex == 0) continue;

		// test each state of layer 
		for (stateNum=0; stateNum<(layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1; stateNum++) {

			// set situation
            if (stateNum % 10000 == 0) cout << endl << "TESTING STATE " << stateNum << " OF " << (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1;
			if (!setSituation(threadNo, layerNum, stateNum)) continue;

			// get all possible moves
			idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities); 

			// go to each successor state
			for (i=0; i<numPossibilities; i++) {
					
				// move
				move(threadNo, idPossibility[i], isOpponentLevel, &pBackup, pPossibilities);

				// get predecessors1
                getPredecessors(threadNo, &amountOfPred, predVars);

				// does it match ?
				for (j=0; j<amountOfPred; j++) { if (predVars[j].predStateNumbers == stateNum && predVars[j].predLayerNumbers == layerNum) break; }

				// error?
				if (j==amountOfPred) {

					cout << endl << "ERROR: STATE " << stateNum << " NOT FOUND IN PREDECESSOR LIST";
					return false;

					// perform several commands to see in debug mode where the error occurs
					undo(threadNo, idPossibility[i], isOpponentLevel, pBackup, pPossibilities);
					setSituation(threadNo, layerNum, stateNum);
					cout << "current state" << endl;
					cout << "   layerNum: " << layerNum <<"\tstateNum: " << stateNum << endl;
					printField(threadNo, 0);
					move(threadNo, idPossibility[i], isOpponentLevel, &pBackup, pPossibilities);
					cout << "successor" << endl;
					printField(threadNo, 0);
					getPredecessors(threadNo, &amountOfPred, predVars);
					getPredecessors(threadNo, &amountOfPred, predVars);
				}

				// undo move
				undo(threadNo, idPossibility[i], isOpponentLevel, pBackup, pPossibilities);
			}
		}
		cout << endl << "LAYER OK: " << layerNum << endl;
	}

	// everything fine
	return true;
}

//-----------------------------------------------------------------------------
// Name: checkGetPredThanGetPoss()
// Desc: 
//-----------------------------------------------------------------------------
bool perfectKI::checkGetPredThanGetPoss()
{
	// locals
	unsigned int			threadNo = 0;
	threadVarsStruct *		tv = &threadVars[threadNo];
	unsigned int			stateNum, layerNum, i, j, k;
	unsigned int			stateNumB, layerNumB;
	unsigned int *			idPossibility;
	unsigned int			numPossibilities;
	unsigned int			amountOfPred;
	bool					isOpponentLevel;
	void *					pPossibilities;
	void *					pBackup;
	int						symField[fieldStruct::size];
	retroAnalysisPredVars	predVars[MAX_NUM_PREDECESSORS];

	// test if each predecessor from getPredecessors() leads to the original state using getPossibilities()
	for (layerNum=0; layerNum<NUM_LAYERS; layerNum++) {

		// generate random state
        cout << endl << "TESTING LAYER: " << layerNum;
		if (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex == 0) continue;
		
		// test each state of layer 
        for (stateNum=0; stateNum<(layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1; stateNum++) {

			// set situation
            if (stateNum % 10000000 == 0) cout << endl << "TESTING STATE " << stateNum << " OF " << (layer[layerNum].subLayer[layer[layerNum].numSubLayers - 1].maxIndex+1)*MAX_NUM_STONES_REMOVED_MINUS_1;
			if (!setSituation(threadNo, layerNum, stateNum)) continue;

			// get predecessors
			getPredecessors(threadNo, &amountOfPred, predVars);
			
			// test each returned predecessor
            for (j=0; j<amountOfPred; j++) { 

				// set situation	
				if (!setSituation(threadNo, predVars[j].predLayerNumbers, predVars[j].predStateNumbers)) {

					cout << endl << "ERROR SETTING SITUATION";
					return false;

					// perform several commands to see in debug mode where the error occurs
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->field[k];			applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->field); 
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->stonePartOfMill[k];	applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->stonePartOfMill); 
					cout << "predecessor" << endl;
					cout << "   layerNum: " << predVars[j].predLayerNumbers << "\tstateNum: " << predVars[j].predStateNumbers << endl;
					printField(threadNo, 0);
					if (predVars[j].playerToMoveChanged) {
						k							= tv->field->curPlayer->id;
						tv->field->curPlayer->id	= tv->field->oppPlayer->id;
						tv->field->oppPlayer->id	= k;
						for (k=0; k<tv->field->size; k++) tv->field->field[k] = -1 * tv->field->field[k];
					}
					idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities);
					setSituation(threadNo, layerNum, stateNum);
					cout << "current state" << endl;
					cout << "   layerNum: " << layerNum <<"\tstateNum: " << stateNum << endl;
					printField(threadNo, 0);
					getPredecessors(threadNo, &amountOfPred, predVars);
				}

				// regard used symmetry operation
				for (k=0; k<tv->field->size; k++) symField[k] = tv->field->field[k];			applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->field); 
				for (k=0; k<tv->field->size; k++) symField[k] = tv->field->stonePartOfMill[k];	applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->stonePartOfMill); 
				if (predVars[j].playerToMoveChanged) {
					k							= tv->field->curPlayer->id;
					tv->field->curPlayer->id	= tv->field->oppPlayer->id;
					tv->field->oppPlayer->id	= k;
					for (k=0; k<tv->field->size; k++) tv->field->field[k] = -1 * tv->field->field[k];
				}

				// get all possible moves
				idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities); 

				// go to each successor state
				for (i=0; i<numPossibilities; i++) {
						
					// move
					move(threadNo, idPossibility[i], isOpponentLevel, &pBackup, pPossibilities);

					// get numbers
					getLayerAndStateNumber(threadNo, layerNumB, stateNumB);

					// does states match ?
					if (stateNum == stateNumB && layerNum == layerNumB) break;

					// undo move
					undo(threadNo, idPossibility[i], isOpponentLevel, pBackup, pPossibilities);
				}

				// error?
				if (i==numPossibilities) {

					cout << endl << "ERROR: Not all predecessors lead to state " << stateNum << " calling move()" << endl;
					//return false;

					// perform several commands to see in debug mode where the error occurs
					setSituation(threadNo, predVars[j].predLayerNumbers, predVars[j].predStateNumbers);
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->field[k];			applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->field); 
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->stonePartOfMill[k];	applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->stonePartOfMill); 
					cout << "predecessor" << endl;
					cout << "   layerNum: " << predVars[j].predLayerNumbers <<"\tstateNum: " << predVars[j].predStateNumbers << endl;
					printField(threadNo, 0);
					if (predVars[j].playerToMoveChanged) {
						k							= tv->field->curPlayer->id;
						tv->field->curPlayer->id	= tv->field->oppPlayer->id;
						tv->field->oppPlayer->id	= k;
						for (k=0; k<tv->field->size; k++) tv->field->field[k] = -1 * tv->field->field[k];
					}
					idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities);
					setSituation(threadNo, layerNum, stateNum);
					cout << "current state" << endl;
					cout << "   layerNum: " << layerNum <<"\tstateNum: " << stateNum << endl;
					printField(threadNo, 0);
					getPredecessors(threadNo, &amountOfPred, predVars);

					k							= tv->field->curPlayer->id;
					tv->field->curPlayer->id	= tv->field->oppPlayer->id;
					tv->field->oppPlayer->id	= k;
					for (k=0; k<tv->field->size; k++) tv->field->field[k] = -1 * tv->field->field[k];
					setSituation(threadNo, predVars[j].predLayerNumbers, predVars[j].predStateNumbers);
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->field[k];			applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->field); 
					for (k=0; k<tv->field->size; k++) symField[k] = tv->field->stonePartOfMill[k];	applySymmetrieOperationOnField(reverseSymOperation[predVars[j].predSymOperation], (unsigned int*) symField, (unsigned int*)tv->field->stonePartOfMill); 
					printField(threadNo, 0);
					idPossibility = getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities); 
					move(threadNo, idPossibility[1], isOpponentLevel, &pBackup, pPossibilities);
					printField(threadNo, 0);
					getLayerAndStateNumber(threadNo, layerNumB, stateNumB);
				}
			}
		}
		cout << endl << "LAYER OK: " << layerNum << endl;
	}

	// free mem
	return true;
}

/*** To Do's ***************************************
- Womöglich alle cyclicArrays in einer Datei speichern. Besser sogar noch kompromieren (auf Windows oder Programm-Ebene?), was gut gehen sollte da ja eh blockweise gearbeitet wird.
  Da Größe vorher unbekannt muss eine table her. Möglicher Klassenname "compressedCyclicArray(blockSize, numBlocks, numArrays, filePath)".
- initFileReader implementieren
***************************************************/
