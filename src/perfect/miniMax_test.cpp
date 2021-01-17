/*********************************************************************
	miniMax_test.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "miniMax.h"

//-----------------------------------------------------------------------------
// Name: testLayer()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::testLayer(unsigned int layerNumber)
{
	// Locals
	unsigned int	curThreadNo;
	unsigned int	returnValue;

	// database open?
	if (hFileShortKnotValues == NULL || hFilePlyInfo == NULL) {
		PRINT(0, this, "ERROR: Database file not open!");
		return falseOrStop();
	}

	// output
	PRINT(1, this, endl << "*** Test each state in layer: " << layerNumber << " ***");
    PRINT(1, this, (getOutputInformation(layerNumber)));

	// prepare parameters for multithreading
	skvfHeader.completed	= false;
	layerInDatabase			= false;
	numStatesProcessed		= 0;
	curCalculatedLayer		= layerNumber;
	curCalculationActionId	= MM_ACTION_TESTING_LAYER;
	testLayersVars *tlVars	= new testLayersVars[threadManager.getNumThreads()];
	for (curThreadNo=0; curThreadNo<threadManager.getNumThreads(); curThreadNo++) {
		tlVars[curThreadNo].curThreadNo			= curThreadNo;
		tlVars[curThreadNo].pMiniMax			= this;
		tlVars[curThreadNo].layerNumber			= layerNumber;
		tlVars[curThreadNo].statesProcessed		= 0;
		tlVars[curThreadNo].subValueInDatabase	= new twoBit         [maxNumBranches];
		tlVars[curThreadNo].subPlyInfos         = new plyInfoVarType [maxNumBranches];
		tlVars[curThreadNo].hasCurPlayerChanged = new bool           [maxNumBranches];
	}

	// process each state in the current layer
	returnValue = threadManager.executeParallelLoop(testLayerThreadProc, (void*) tlVars, sizeof(testLayersVars), TM_SCHEDULE_STATIC, 0, layerStats[layerNumber].knotsInLayer - 1,1);
	switch (returnValue)
	{
	case TM_RETURN_VALUE_OK: 			
	case TM_RETURN_VALUE_EXECUTION_CANCELLED:
		// reduce and delete thread specific data
		for (numStatesProcessed=0, curThreadNo=0; curThreadNo<threadManager.getNumThreads(); curThreadNo++) {
			numStatesProcessed	+= tlVars[curThreadNo].statesProcessed;
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].subValueInDatabase);
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].hasCurPlayerChanged);
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].subPlyInfos);
		}
		SAFE_DELETE_ARRAY(tlVars);
		if (returnValue == TM_RETURN_VALUE_EXECUTION_CANCELLED) {
			PRINT(0,this, "Main thread: Execution cancelled by user");
			return false;	// ... better would be to return a cancel-specific value
		} else {
			break;
		}
	default:
	case TM_RETURN_VALUE_INVALID_PARAM:
	case TM_RETURN_VALUE_UNEXPECTED_ERROR:
		return falseOrStop();
	}
	
	// layer is not ok
	if (numStatesProcessed < layerStats[layerNumber].knotsInLayer) {
		PRINT(0, this, "DATABASE ERROR IN LAYER " << layerNumber);
		return falseOrStop();
	// layer is ok
	} else {
		PRINT(1, this, " TEST PASSED !" << endl << endl);
		return true;
	}
}

//-----------------------------------------------------------------------------
// Name: testLayerThreadProc()
// Desc: 
//-----------------------------------------------------------------------------
DWORD miniMax::testLayerThreadProc(void* pParameter, int index)
{
	// locals
	testLayersVars *			tlVars				= (testLayersVars*) pParameter;
	miniMax *					m					= tlVars->pMiniMax;
	unsigned int				layerNumber			= tlVars->layerNumber;
	unsigned int				stateNumber			= index;
	unsigned int				threadNo			= tlVars->curThreadNo;
	twoBit *					subValueInDatabase	= tlVars->subValueInDatabase;
	plyInfoVarType *			subPlyInfos			= tlVars->subPlyInfos;
	bool *						hasCurPlayerChanged	= tlVars->hasCurPlayerChanged;
	twoBit						shortValueInDatabase;
    plyInfoVarType				numPliesTillCurState;
	twoBit						shortValueInGame;
	float						floatValueInGame;
	plyInfoVarType				min, max;
	unsigned int				numPossibilities;
	unsigned int				i, j;
	unsigned int				tmpStateNumber, tmpLayerNumber;
	unsigned int *				idPossibility;
	void *						pPossibilities;
	void *						pBackup;
	bool						isOpponentLevel;
	bool						invalidLayerOrStateNumber;
	bool						layerInDatabaseAndCompleted;

	// output
	tlVars->statesProcessed++;
	if (tlVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) { 
		m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
		PRINT(0, m, m->numStatesProcessed << " states of " << m->layerStats[layerNumber].knotsInLayer << " tested");
	}

	// situation already existend in database ?
	m->readKnotValueFromDatabase(layerNumber, stateNumber, shortValueInDatabase);
    m->readPlyInfoFromDatabase  (layerNumber, stateNumber, numPliesTillCurState);

	// prepare the situation
	if (!m->setSituation(threadNo, layerNumber, stateNumber)) {
			
		// when situation cannot be constructed then state must be marked as invalid in database
		if (shortValueInDatabase != SKV_VALUE_INVALID || numPliesTillCurState != PLYINFO_VALUE_INVALID) { 
			PRINT(0, m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Could not set situation, but value is not invalid."); 	
			goto errorInDatabase; 
		} else {
			return TM_RETURN_VALUE_OK;
		}
	}

	// debug information
	if (m->verbosity > 5) {
		PRINT(5, m, "layer: " << layerNumber << " state: " << stateNumber);
		m->printField(threadNo, shortValueInDatabase);
	}

	// get number of possiblities
	m->setOpponentLevel(threadNo, false);
	idPossibility = m->getPossibilities(threadNo, &numPossibilities, &isOpponentLevel, &pPossibilities);

	// unable to move
	if (numPossibilities == 0)  {
			
		// get ingame value
		m->getValueOfSituation(threadNo, floatValueInGame, shortValueInGame);

		// compare database with game
		if (shortValueInDatabase != shortValueInGame || numPliesTillCurState != 0) { PRINT(0,m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Number of possibilities is zero, but knot value is not invalid or ply info equal zero."); goto errorInDatabase; }
        if (shortValueInDatabase == SKV_VALUE_INVALID)							   { PRINT(0,m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Number of possibilities is zero, but knot value is invalid."); goto errorInDatabase; }

	} else {

		// check each possible move
        for (i=0; i<numPossibilities; i++) {
				
			// move
			m->move(threadNo, idPossibility[i], isOpponentLevel, &pBackup, pPossibilities);

			// get database value
			m->readKnotValueFromDatabase(threadNo, tmpLayerNumber, tmpStateNumber, subValueInDatabase[i], invalidLayerOrStateNumber, layerInDatabaseAndCompleted);
            m->readPlyInfoFromDatabase  (tmpLayerNumber, tmpStateNumber, subPlyInfos[i]);
			hasCurPlayerChanged[i] = (m->getOpponentLevel(threadNo) == true); 

			// debug information
			if (m->verbosity > 5) {
				PRINT(5, m, "layer: " << tmpLayerNumber << " state: " << tmpStateNumber << " value: " << (int) subValueInDatabase[i]);
				m->printField(threadNo, subValueInDatabase[i]);
			}

			// if layer or state number is invalid then value of testes state must be invalid
			if (invalidLayerOrStateNumber && shortValueInDatabase != SKV_VALUE_INVALID) { PRINT(0,m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Succeding state  has invalid layer (" << tmpLayerNumber << ")or state number (" << tmpStateNumber << "), but tested state is not marked as invalid."); goto errorInDatabase; }
			// BUG: Does not work because, layer 101 is calculated before 105, although removing a stone does need this jump.
			// if (!layerInDatabaseAndCompleted)										{ PRINT(0,m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Succeding state " << tmpStateNumber << " in an uncalculated layer " << tmpLayerNumber << "! Calc layer first!"); goto errorInDatabase; }

            // undo move
			m->undo(threadNo, idPossibility[i], isOpponentLevel, pBackup, pPossibilities);
		}

		// value possible?
		switch (shortValueInDatabase) {
			case SKV_VALUE_GAME_LOST : 
					
				// all possible moves must be lost for the current player or won for the opponent
				for (i=0; i<numPossibilities; i++) { if (subValueInDatabase[i] != ((hasCurPlayerChanged[i]) ? SKV_VALUE_GAME_WON : SKV_VALUE_GAME_LOST) && subValueInDatabase[i] != SKV_VALUE_INVALID) {
					PRINT(0,m, "ERROR: DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": All possible moves must be lost for the current player or won for the opponent");
					goto errorInDatabase;
				}}
				// not all options can be invalid
				for (j=0, i=0; i<numPossibilities; i++) { if (subValueInDatabase[i] == SKV_VALUE_INVALID) {
					j++;
				}}
				if (j == numPossibilities) {
					PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ". Not all options can be invalid");
				}
                // ply info must be max(subPlyInfos[]+1)
                max = 0;
				for (i=0; i<numPossibilities; i++) { 
                    if (subValueInDatabase[i] == ((hasCurPlayerChanged[i]) ? SKV_VALUE_GAME_WON : SKV_VALUE_GAME_LOST))   {
                        if (subPlyInfos[i] + 1 > max) {
                            max = subPlyInfos[i] + 1;
                        }
                    }
                }
				if (numPliesTillCurState>PLYINFO_VALUE_DRAWN) { 
                    PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Knot value is LOST, but numPliesTillCurState is bigger than PLYINFO_MAX_VALUE."); 
                    goto errorInDatabase; 
                }
                if (numPliesTillCurState!=max) { 
                    PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Number of needed plies is not maximal for LOST state."); 
                    goto errorInDatabase; 
                }
				break;

			case SKV_VALUE_GAME_WON  : 
					
				// at least one possible move must be lost for the opponent or won for the current player
				for (i=0; i<numPossibilities; i++) { 
                    // if (subValueInDatabase[i] == SKV_VALUE_INVALID)                                                      { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": At least one possible move must be lost for the opponent or won for the current player. But subValueInDatabase[i] == SKV_VALUE_INVALID.");	goto errorInDatabase; }
                    if (subValueInDatabase[i] == ((hasCurPlayerChanged[i]) ? SKV_VALUE_GAME_LOST : SKV_VALUE_GAME_WON))   i = numPossibilities;
                }
                if (i==numPossibilities) { 
                    PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": At least one possible move must be lost for the opponent or won for the current player."); 
                    goto errorInDatabase; 
                }

                // ply info must be min(subPlyInfos[]+1)
                min = PLYINFO_VALUE_DRAWN;
				for (i=0; i<numPossibilities; i++) { 
                    if (subValueInDatabase[i] == ((hasCurPlayerChanged[i]) ? SKV_VALUE_GAME_LOST : SKV_VALUE_GAME_WON))   {
                        if (subPlyInfos[i] + 1 < min) {
                            min = subPlyInfos[i] + 1;
                        }
                    }
                }
				if (numPliesTillCurState>PLYINFO_VALUE_DRAWN) { 
                    PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Knot value is WON, but numPliesTillCurState is bigger than PLYINFO_MAX_VALUE."); 
                    goto errorInDatabase; 
                }
                if (numPliesTillCurState!=min) { 
                    PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Number of needed plies is not minimal for WON state."); 
                    goto errorInDatabase; 
                }
				break;

			case SKV_VALUE_GAME_DRAWN: 

				// all possible moves must be won for the opponent, lost for the current player or drawn
				for (j=0,i=0; i<numPossibilities; i++) { 
                    // if (subValueInDatabase[i] == SKV_VALUE_INVALID)                                                      { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": All possible moves must be won for the opponent, lost for the current player or drawn. But subValueInDatabase[i] == SKV_VALUE_INVALID."); goto errorInDatabase; }
                    if (subValueInDatabase[i] != ((hasCurPlayerChanged[i]) ? SKV_VALUE_GAME_WON : SKV_VALUE_GAME_LOST) 
                        &&  subValueInDatabase[i] != SKV_VALUE_GAME_DRAWN
						&&  subValueInDatabase[i] != SKV_VALUE_INVALID)		                                             { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": All possible moves must be won for the opponent, lost for the current player or drawn."); goto errorInDatabase; }
                    if (subValueInDatabase[i] == SKV_VALUE_GAME_DRAWN)                                                   j = 1;
				}

                // at least one succeding state must be drawn
                if (j == 0) { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": At least one succeding state must be drawn."); goto errorInDatabase; }

                // ply info must also be drawn
                if (numPliesTillCurState != PLYINFO_VALUE_DRAWN) { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Knot value is drawn but ply info is not!"); goto errorInDatabase; }
				break;

			case SKV_VALUE_INVALID: 
				// if setSituation() returned true but state value is invalid, then all following states must be invalid
				for (i=0; i<numPossibilities; i++) { 
					if (subValueInDatabase[i] != SKV_VALUE_INVALID) break;
				}
				if (i!=numPossibilities) {
					PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": If setSituation() returned true but state value is invalid, then all following states must be invalid."); goto errorInDatabase;
				}
                // ply info must also be invalid
                if (numPliesTillCurState != PLYINFO_VALUE_INVALID) { PRINT(0,m, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber << ": Knot value is invalid but ply info is not!"); goto errorInDatabase; }
				break;
		}
	}
	return TM_RETURN_VALUE_OK;

errorInDatabase:
	// terminate all threads
	return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
}

//-----------------------------------------------------------------------------
// Name: testState()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::testState(unsigned int layerNumber, unsigned int stateNumber)
{
	// locals
	testLayersVars 	tlVars;
	bool			result;

	// prepare parameters for multithreading
	tlVars.curThreadNo			= 0;
	tlVars.pMiniMax				= this;
	tlVars.layerNumber			= layerNumber;
	tlVars.statesProcessed		= 0;
	tlVars.subValueInDatabase	= new twoBit         [maxNumBranches];
	tlVars.subPlyInfos			= new plyInfoVarType [maxNumBranches];
	tlVars.hasCurPlayerChanged	= new bool           [maxNumBranches];

	if (testLayerThreadProc(&tlVars, stateNumber) != TM_RETURN_VALUE_OK) result = false;

	delete [] tlVars.subValueInDatabase;
	delete [] tlVars.subPlyInfos;
	delete [] tlVars.hasCurPlayerChanged;

	return result;
}

//-----------------------------------------------------------------------------
// Name: testSetSituationAndGetPoss()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::testSetSituationAndGetPoss(unsigned int layerNumber)
{
	// Locals
	unsigned int	curThreadNo;
	unsigned int	returnValue;

	// output
	PRINT(1, this, endl << "*** Test each state in layer: " << layerNumber << " ***");
    PRINT(1, this, (getOutputInformation(layerNumber)));

	// prepare parameters for multithreading
	numStatesProcessed		= 0;
	curCalculationActionId	= MM_ACTION_TESTING_LAYER;
	testLayersVars *tlVars	= new testLayersVars[threadManager.getNumThreads()];
	for (curThreadNo=0; curThreadNo<threadManager.getNumThreads(); curThreadNo++) {
		tlVars[curThreadNo].curThreadNo			= curThreadNo;
		tlVars[curThreadNo].pMiniMax			= this;
		tlVars[curThreadNo].layerNumber			= layerNumber;
		tlVars[curThreadNo].statesProcessed		= 0;
		tlVars[curThreadNo].subValueInDatabase	= new twoBit         [maxNumBranches];
		tlVars[curThreadNo].subPlyInfos         = new plyInfoVarType [maxNumBranches];
		tlVars[curThreadNo].hasCurPlayerChanged = new bool           [maxNumBranches];
	}

	// process each state in the current layer
	returnValue = threadManager.executeParallelLoop(testSetSituationThreadProc, (void*) tlVars, sizeof(testLayersVars), TM_SCHEDULE_STATIC, 0, layerStats[layerNumber].knotsInLayer - 1,1);
	switch (returnValue)
	{
	case TM_RETURN_VALUE_OK: 			
	case TM_RETURN_VALUE_EXECUTION_CANCELLED:
		// reduce and delete thread specific data
		for (numStatesProcessed=0, curThreadNo=0; curThreadNo<threadManager.getNumThreads(); curThreadNo++) {
			numStatesProcessed	+= tlVars[curThreadNo].statesProcessed;
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].subValueInDatabase);
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].hasCurPlayerChanged);
			SAFE_DELETE_ARRAY(tlVars[curThreadNo].subPlyInfos);
		}
		SAFE_DELETE_ARRAY(tlVars);
		if (returnValue == TM_RETURN_VALUE_EXECUTION_CANCELLED) {
			PRINT(0,this, "Main thread: Execution cancelled by user");
			return false;	// ... better would be to return a cancel-specific value
		} else {
			break;
		}
	default:
	case TM_RETURN_VALUE_INVALID_PARAM:
	case TM_RETURN_VALUE_UNEXPECTED_ERROR:
		return falseOrStop();
	}
	
	// layer is not ok
	if (numStatesProcessed < layerStats[layerNumber].knotsInLayer) {
		PRINT(0, this, "DATABASE ERROR IN LAYER " << layerNumber);
		return falseOrStop();
	// layer is ok
	} else {
		PRINT(1, this, " TEST PASSED !" << endl << endl);
		return true;
	}
}

//-----------------------------------------------------------------------------
// Name: testSetSituationThreadProc()
// Desc: 
//-----------------------------------------------------------------------------
DWORD miniMax::testSetSituationThreadProc(void* pParameter, int index)
{
	// locals
	testLayersVars *			tlVars				= (testLayersVars*) pParameter;
	miniMax *					m					= tlVars->pMiniMax;
	unsigned int	*			idPossibility;
	void			*			pPossibilities;
	void			*			pBackup;
	unsigned int				curPoss;
	float						floatValue;
	stateAdressStruct			curState;						
	stateAdressStruct			subState;						
	knotStruct					knot;
	twoBit						shortKnotValue		= SKV_VALUE_GAME_DRAWN;
	curState.layerNumber		= tlVars->layerNumber;
	curState.stateNumber		= index;

	// output
	tlVars->statesProcessed++;
	if (tlVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) { 
		m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
		PRINT(0, m, m->numStatesProcessed << " states of " << m->layerStats[curState.layerNumber].knotsInLayer << " tested");
	}

	// set state
	if (m->setSituation(tlVars->curThreadNo, curState.layerNumber, curState.stateNumber)) {
		m->getValueOfSituation(tlVars->curThreadNo, floatValue, shortKnotValue);
	} else {
		shortKnotValue = SKV_VALUE_INVALID;
	}

	// get number of possiblities
	idPossibility = m->getPossibilities(tlVars->curThreadNo, &knot.numPossibilities, &knot.isOpponentLevel, &pPossibilities);

	// unable to move
	if (knot.numPossibilities == 0)  {
		if (shortKnotValue == SKV_VALUE_GAME_DRAWN) {
			PRINT(0, m, "ERROR: Layer " << curState.layerNumber << " and state " << curState.stateNumber << ". setSituation() returned true, although getPossibilities() yields no possible moves."); 	
			return m->falseOrStop();
		}
	// moving is possible
	} else {
		if (shortKnotValue == SKV_VALUE_INVALID) {
			PRINT(0, m, "ERROR: Moved from layer " << curState.layerNumber << " and state " << curState.stateNumber << " setSituation() returned false, although getPossibilities() yields some possible moves."); 	
			return m->falseOrStop();
		}

		// check each possibility
		for (curPoss=0; curPoss<knot.numPossibilities; curPoss++) {

			// move
			m->move(tlVars->curThreadNo, idPossibility[curPoss], knot.isOpponentLevel, &pBackup, pPossibilities);

			// get state number of succeding state
			unsigned int i;
			m->getLayerAndStateNumber(tlVars->curThreadNo, i, subState.stateNumber);
			subState.layerNumber = i;

			// undo move
			m->undo(tlVars->curThreadNo, idPossibility[curPoss], knot.isOpponentLevel, pBackup, pPossibilities);

			// state reached by move() must not be invalid
			if (!m->setSituation(tlVars->curThreadNo, subState.layerNumber, subState.stateNumber)) {
				PRINT(0, m, "ERROR: Moved from layer " << curState.layerNumber << " and state " << curState.stateNumber << " to invalid situation layer " << curState.layerNumber << " and state " << curState.stateNumber); 	
				return m->falseOrStop();
			}
			// set back to current state
			m->setSituation(tlVars->curThreadNo, curState.layerNumber, curState.stateNumber);
		}
	}
	return TM_RETURN_VALUE_OK;

//errorInDatabase:
	// terminate all threads
	return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
}

//-----------------------------------------------------------------------------
// Name: testIfSymStatesHaveSameValue()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::testIfSymStatesHaveSameValue(unsigned int layerNumber)
{
	// Locals
	unsigned int	threadNo	= 0;
	twoBit			shortValueInDatabase;
	twoBit			shortValueOfSymState;
    plyInfoVarType  numPliesTillCurState;
    plyInfoVarType  numPliesTillSymState;
	unsigned int	stateNumber				= 0;
	unsigned int  * symStateNumbers			= NULL;
	unsigned int	numSymmetricStates;
	unsigned int	i;

	// database open?
	if (hFileShortKnotValues == NULL || hFilePlyInfo == NULL) {
		PRINT(0, this, "ERROR: Database files not open!");
		layerNumber = 0;
		goto errorInDatabase;
	}

	// layer completed ?
	if (!layerStats[layerNumber].layerIsCompletedAndInFile) {
		PRINT(0, this, "ERROR: Layer not in file!");
		layerNumber = 0;
		goto errorInDatabase;
	}

	// test if each state has symmetric states with the same value
	PRINT(1, this, endl << "testIfSymmetricStatesHaveSameValue - TEST EACH STATE IN LAYER: " << layerNumber);
    PRINT(1, this, (getOutputInformation(layerNumber)));
	skvfHeader.completed = false;
	
	for (layerInDatabase=false, stateNumber=0; stateNumber<layerStats[layerNumber].knotsInLayer; stateNumber++) {

		// output
		if (stateNumber % OUTPUT_EVERY_N_STATES == 0) PRINT(1, this, stateNumber << " states of " << layerStats[layerNumber].knotsInLayer << " tested");

		// situation already existend in database ?
		readKnotValueFromDatabase(layerNumber, stateNumber, shortValueInDatabase);
        readPlyInfoFromDatabase(layerNumber, stateNumber, numPliesTillCurState);

		// prepare the situation
		if (!setSituation(threadNo, layerNumber, stateNumber)) {
			
			// when situation cannot be constructed then state must be marked as invalid in database
			if (shortValueInDatabase != SKV_VALUE_INVALID || numPliesTillCurState != PLYINFO_VALUE_INVALID) goto errorInDatabase;
			else continue;
		}

		// get numbers of symmetric states
		getSymStateNumWithDoubles(threadNo, &numSymmetricStates, &symStateNumbers);

		// save value for all symmetric states
		for (i=0; i<numSymmetricStates; i++) {

			readKnotValueFromDatabase(layerNumber, symStateNumbers[i], shortValueOfSymState);
            readPlyInfoFromDatabase(layerNumber, symStateNumbers[i], numPliesTillSymState);

			if (shortValueOfSymState != shortValueInDatabase || numPliesTillCurState != numPliesTillSymState) {
				
				PRINT(2, this, "current tested state " << stateNumber << " has value " << (int) shortValueInDatabase);
				setSituation(threadNo, layerNumber, stateNumber);
				printField(threadNo, shortValueInDatabase);
				
				PRINT(1, this, "");
				PRINT(1, this, "symmetric state " << symStateNumbers[i] << " has value " << (int) shortValueOfSymState);
				setSituation(threadNo, layerNumber, symStateNumbers[i]);
				printField(threadNo, shortValueOfSymState);

				setSituation(threadNo, layerNumber, stateNumber);
			}
		}
	}

	// layer is ok
	PRINT(0, this, "TEST PASSED !");
	return true;

errorInDatabase:

	// layer is not ok
	if (layerNumber) PRINT(0, this, "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE " << stateNumber);
	return falseOrStop();
}
