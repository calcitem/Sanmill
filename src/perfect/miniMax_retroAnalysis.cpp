/*********************************************************************
	miniMax_retroAnalysis.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
s\*********************************************************************/

#include "miniMax.h"

//-----------------------------------------------------------------------------
// Name: calcKnotValuesByRetroAnalysis()
// Desc: 
// The COUNT-ARRAY is the main element of the algorithmn. It contains the number of succeding states for the drawn gamestates,
// whose short knot value has to be determined. If all succeding states (branches representing possible moves) are for example won than,
// a state can be marked as lost, since no branch will lead to a drawn or won situation any more.
// Each time the short knot value of a game state has been determined, the state will be added to 'statesToProcess'.
// This list is like a queue of states, which still has to be processed.
//-----------------------------------------------------------------------------
bool miniMax::calcKnotValuesByRetroAnalysis(vector<unsigned int> &layersToCalculate)
{
    // locals
	bool					abortCalculation		= false;
	unsigned int			curLayer				= 0;				// Counter variable
	unsigned int			curSubLayer				= 0;				// Counter variable
	unsigned int			plyCounter				= 0;				// Counter variable
	unsigned int			threadNo;
	stringstream			ssLayers;
	retroAnalysisGlobalVars	retroVars;

	// init retro vars
	retroVars.thread.resize(threadManager.getNumThreads());
	for (threadNo=0; threadNo<threadManager.getNumThreads(); threadNo++) {
		retroVars.thread[threadNo].statesToProcess.resize(PLYINFO_EXP_VALUE, NULL);
		retroVars.thread[threadNo].numStatesToProcess	= 0;
		retroVars.thread[threadNo].threadNo				= threadNo;
	}
	retroVars.countArrays.resize(layersToCalculate.size(), NULL);
	retroVars.layerInitialized.resize(skvfHeader.numLayers, false);
	retroVars.layersToCalculate		= layersToCalculate;
	retroVars.pMiniMax				= this;
	for (retroVars.totalNumKnots=0, retroVars.numKnotsToCalc=0, curLayer=0; curLayer<layersToCalculate.size(); curLayer++) {
		retroVars.numKnotsToCalc	+= layerStats[layersToCalculate[curLayer]].knotsInLayer;
		retroVars.totalNumKnots		+= layerStats[layersToCalculate[curLayer]].knotsInLayer;
		retroVars.layerInitialized[layersToCalculate[curLayer]] = true;
		for (curSubLayer=0; curSubLayer<layerStats[layersToCalculate[curLayer]].numSuccLayers; curSubLayer++) {
			if  (retroVars.layerInitialized[layerStats[layersToCalculate[curLayer]].succLayers[curSubLayer]]) continue;
			else retroVars.layerInitialized[layerStats[layersToCalculate[curLayer]].succLayers[curSubLayer]] = true;
			retroVars.totalNumKnots		+= layerStats[layerStats[layersToCalculate[curLayer]].succLayers[curSubLayer]].knotsInLayer;
		}
	}
	retroVars.layerInitialized.assign(skvfHeader.numLayers, false);
	
	// output & filenames
	for (curLayer=0; curLayer<layersToCalculate.size(); curLayer++) ssLayers << " " << layersToCalculate[curLayer];
	PRINT(0, this, "*** Calculate layers" << ssLayers.str() << " by retro analysis ***");

	// initialization
	PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
	if (!initRetroAnalysis(retroVars)) { abortCalculation = true; goto freeMem; }
	
	// prepare count arrays
	PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
	if (!prepareCountArrays(retroVars)) { abortCalculation = true; goto freeMem; }

	// stop here if only preparing layer
	if (onlyPrepareLayer) goto freeMem;

	// iteration
	PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
	if (!performRetroAnalysis(retroVars)) { abortCalculation = true; goto freeMem; }

	// show output
	PRINT(2, this, "  Bytes in memory: " << memoryUsed2);
	for (curLayer=0; curLayer<layersToCalculate.size(); curLayer++) { showLayerStats(layersToCalculate[curLayer]); }
 	PRINT(2, this, "");

	// free memory
freeMem:
	for (threadNo=0; threadNo<threadManager.getNumThreads(); threadNo++) {
		for (plyCounter=0; plyCounter<retroVars.thread[threadNo].statesToProcess.size(); plyCounter++) { 
			SAFE_DELETE(retroVars.thread[threadNo].statesToProcess[plyCounter]);
		}
	}
	for (curLayer=0; curLayer<layersToCalculate.size(); curLayer++) {
		if (retroVars.countArrays[curLayer] != NULL) {
			memoryUsed2 -= layerStats[layersToCalculate[curLayer]].knotsInLayer * sizeof(countArrayVarType); 
			arrayInfos.removeArray(layersToCalculate[curLayer], arrayInfoStruct::arrayType_countArray, layerStats[layersToCalculate[curLayer]].knotsInLayer * sizeof(countArrayVarType), 0);
		}
		SAFE_DELETE_ARRAY(retroVars.countArrays[curLayer]);
	}
	if (!abortCalculation) PRINT(2, this, "  Bytes in memory: " << memoryUsed2);
	return !abortCalculation;
}

//-----------------------------------------------------------------------------
// Name: initRetroAnalysis()
// Desc: The state values for all game situations in the database are marked as invalid, as undecided, as won or as  lost by using the function getValueOfSituation().
//-----------------------------------------------------------------------------
bool miniMax::initRetroAnalysis(retroAnalysisGlobalVars &retroVars)
{
	// locals
	unsigned int				curLayerId;						// current processed layer within 'layersToCalculate'
	unsigned int				layerNumber;					// layer number of the current process layer
	stringstream				ssInitArrayPath;				// path of the working directory
	stringstream				ssInitArrayFilePath;			// filename corresponding to a cyclic array file which is used for storage
	bufferedFileClass*			initArray;						// 
	bool						initAlreadyDone		= false;	// true if the initialization information is already available in a file

	// process each layer
	for (curLayerId=0; curLayerId<retroVars.layersToCalculate.size(); curLayerId++) { 

		// set current processed layer number
		layerNumber = retroVars.layersToCalculate[curLayerId];
		curCalculationActionId = MM_ACTION_INIT_RETRO_ANAL;
		PRINT(1, this, endl << "  *** Initialization of layer " << layerNumber << " (" << (getOutputInformation(layerNumber)) << ") which has " << layerStats[layerNumber].knotsInLayer << " knots ***"); 

		// file names
		ssInitArrayPath.str("");		ssInitArrayPath     << fileDirectory << (fileDirectory.size()?"\\":"") << "initLayer";
		ssInitArrayFilePath.str("");	ssInitArrayFilePath << fileDirectory << (fileDirectory.size()?"\\":"") << "initLayer\\initLayer" << layerNumber << ".dat";

		// does initialization file exist ?
		CreateDirectoryA(ssInitArrayPath.str().c_str(), NULL);
		initArray = new bufferedFileClass(threadManager.getNumThreads(), FILE_BUFFER_SIZE, ssInitArrayFilePath.str().c_str());
		if (initArray->getFileSize() == (LONGLONG) layerStats[layerNumber].knotsInLayer) { 
			PRINT(2, this, "    Loading init states from file: " << ssInitArrayFilePath.str());
			initAlreadyDone = true;
		}

		// don't add layers twice
		if (retroVars.layerInitialized[layerNumber])	continue;
		else											retroVars.layerInitialized[layerNumber] = true;
		
		// prepare parameters
		numStatesProcessed = 0;
		retroVars.statsValueCounter[SKV_VALUE_GAME_WON  ] = 0;
		retroVars.statsValueCounter[SKV_VALUE_GAME_LOST ] = 0;
		retroVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
		retroVars.statsValueCounter[SKV_VALUE_INVALID   ] = 0;
		threadManagerClass::threadVarsArray<initRetroAnalysisVars> tva(threadManager.getNumThreads(), initRetroAnalysisVars(this, &retroVars, layerNumber, initArray, initAlreadyDone));
		
		// process each state in the current layer
		switch (threadManager.executeParallelLoop(initRetroAnalysisThreadProc, tva.getPointerToArray(), tva.getSizeOfArray(), TM_SCHEDULE_STATIC, 0, layerStats[layerNumber].knotsInLayer - 1, 1))
		{
		case TM_RETURN_VALUE_OK: 			
			break;
		case TM_RETURN_VALUE_EXECUTION_CANCELLED:
			PRINT(0,this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
			SAFE_DELETE(initArray);
			return false;
		default:
		case TM_RETURN_VALUE_INVALID_PARAM:
		case TM_RETURN_VALUE_UNEXPECTED_ERROR:
			return falseOrStop();
		}

		// reduce and delete thread specific data
		tva.reduce();
		initAlreadyDone		= false;
		initArray->flushBuffers();
		SAFE_DELETE(initArray);
		if (numStatesProcessed < layerStats[layerNumber].knotsInLayer) return falseOrStop();
					
		// when init file was created new then save it now
		PRINT(2, this, "    Saved initialized states to file: " << ssInitArrayFilePath.str());

		// show statistics
		PRINT(2, this, "    won     states: " << retroVars.statsValueCounter[SKV_VALUE_GAME_WON  ]);	
		PRINT(2, this, "    lost    states: " << retroVars.statsValueCounter[SKV_VALUE_GAME_LOST ]);	
		PRINT(2, this, "    draw    states: " << retroVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);	
		PRINT(2, this, "    invalid states: " << retroVars.statsValueCounter[SKV_VALUE_INVALID   ]);	
	}
	return true;
}

//-----------------------------------------------------------------------------
// Name: initRetroAnalysisParallelSub()
// Desc: 
//-----------------------------------------------------------------------------
DWORD miniMax::initRetroAnalysisThreadProc(void* pParameter, int index)
{
	// locals
	initRetroAnalysisVars *		iraVars		= (initRetroAnalysisVars *) pParameter;
	miniMax *					m			= iraVars->pMiniMax;
	float		  				floatValue;						// dummy variable for calls of getValueOfSituation()
	stateAdressStruct			curState;						// current state counter for loops
	twoBit		  				curStateValue;					// for calls of getValueOfSituation()
	
	curState.layerNumber	= iraVars->layerNumber;
	curState.stateNumber	= index;
	iraVars->statesProcessed++;

	// print status
	if (iraVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) { 
		m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
		PRINT(2, m, "Already initialized " << m->numStatesProcessed << " of " << m->layerStats[curState.layerNumber].knotsInLayer << " states");
	}

	// layer initialization already done ? if so, then read from file
	if (iraVars->initAlreadyDone) {
		if (!iraVars->bufferedFile->readBytes(iraVars->curThreadNo, index * sizeof(twoBit), sizeof(twoBit), (unsigned char*) &curStateValue)) {
			PRINT(0, m, "ERROR: initArray->takeBytes() failed");
			return m->falseOrStop();
		}

	// initialization not done
	} else {

		// set current selected situation
		if (!m->setSituation(iraVars->curThreadNo, curState.layerNumber, curState.stateNumber)) {
			curStateValue = SKV_VALUE_INVALID;
		} else {
			// get value of current situation
			m->getValueOfSituation(iraVars->curThreadNo, floatValue, curStateValue);
		}
	}

	// save init value
	if (curStateValue != SKV_VALUE_INVALID) {

		// save short knot value
		m->saveKnotValueInDatabase(curState.layerNumber, curState.stateNumber, curStateValue);

		// put in list if state is final
		if (curStateValue == SKV_VALUE_GAME_WON || curStateValue == SKV_VALUE_GAME_LOST) {

			// ply info
			m->savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber, 0);

			// add state to list
			m->addStateToProcessQueue(*iraVars->retroVars, iraVars->retroVars->thread[iraVars->curThreadNo], 0, &curState);
		}
	}

	// write data to file
	if (!iraVars->initAlreadyDone) {
		// curStateValue sollte 2 sein bei index == 1329322
		if (!iraVars->bufferedFile->writeBytes(iraVars->curThreadNo, index * sizeof(twoBit), sizeof(twoBit), (unsigned char*) &curStateValue)) {
			PRINT(0, m, "ERROR: bufferedFile->writeBytes failed!");
			return m->falseOrStop();
		}
	}
	iraVars->statsValueCounter[curStateValue]++;

	return TM_RETURN_VALUE_OK;
}

//-----------------------------------------------------------------------------
// Name: prepareCountArrays()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::prepareCountArrays(retroAnalysisGlobalVars &retroVars)
{
	// locals
	unsigned int			numKnotsInCurLayer;
	stateAdressStruct		curState;									// current state counter for loops
	unsigned int			curLayer				= 0;				// Counter variable
	countArrayVarType		defValue				= 0;				// default counter array value
	DWORD					dwWritten;
	DWORD					dwRead;
	LARGE_INTEGER			fileSize;
	HANDLE					hFileCountArray			= NULL;				// file handle for loading and saving the arrays in 'countArrays'
	stringstream			ssCountArrayPath;			
	stringstream			ssCountArrayFilePath;		
	stringstream			ssLayers;

	// output & filenames
	for (curLayer=0; curLayer<retroVars.layersToCalculate.size(); curLayer++) ssLayers << " " << retroVars.layersToCalculate[curLayer];
	ssCountArrayPath		<< fileDirectory << (fileDirectory.size()?"\\":"") << "countArray";
	ssCountArrayFilePath	<< fileDirectory << (fileDirectory.size()?"\\":"") << "countArray\\countArray" << ssLayers.str() << ".dat";
	PRINT(2, this, "  *** Prepare count arrays for layers " << ssLayers.str() << " ***" << endl);
	curCalculationActionId = MM_ACTION_PREPARE_COUNT_ARRAY;

	// prepare count arrays
	CreateDirectoryA(ssCountArrayPath.str().c_str(), NULL);
	if ((hFileCountArray = CreateFileA(ssCountArrayFilePath.str().c_str(),  GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL)) == INVALID_HANDLE_VALUE) {
		PRINT(0, this, "ERROR: Could not open File " << ssCountArrayFilePath.str() << "!");
		return falseOrStop();
	}

	// allocate memory for count arrays
	for (curLayer=0; curLayer<retroVars.layersToCalculate.size(); curLayer++) {
		numKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]].knotsInLayer;
		retroVars.countArrays[curLayer] = new countArrayVarType[numKnotsInCurLayer];
		memoryUsed2 += numKnotsInCurLayer * sizeof(countArrayVarType);
		arrayInfos.addArray(retroVars.layersToCalculate[curLayer], arrayInfoStruct::arrayType_countArray, numKnotsInCurLayer * sizeof(countArrayVarType), 0);
	}

	// load file if already existend
	if (GetFileSizeEx(hFileCountArray, &fileSize) && fileSize.QuadPart == retroVars.numKnotsToCalc) {
		PRINT(2, this, "  Load number of succedors from file: " << ssCountArrayFilePath.str().c_str());

		for (curLayer=0; curLayer<retroVars.layersToCalculate.size(); curLayer++) {
			numKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]].knotsInLayer;
			if (!ReadFile(hFileCountArray, retroVars.countArrays[curLayer], numKnotsInCurLayer * sizeof(countArrayVarType), &dwRead, NULL)) return falseOrStop();
			if (dwRead != numKnotsInCurLayer * sizeof(countArrayVarType)) return falseOrStop();
		}

	// else calculate number of succedding states
	} else {

		// Set default value 0
		for (curLayer=0; curLayer<retroVars.layersToCalculate.size(); curLayer++) {
			numKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]].knotsInLayer;
			for (curState.stateNumber=0; curState.stateNumber<numKnotsInCurLayer; curState.stateNumber++) {
				retroVars.countArrays[curLayer][curState.stateNumber]	= defValue;
			}
		}

		// calc values
		if (!calcNumSuccedors(retroVars)) {
			CloseHandle(hFileCountArray);
			return false;
		}

		// save to file
		for (curLayer=0, dwWritten=0; curLayer<retroVars.layersToCalculate.size(); curLayer++) {
			numKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]].knotsInLayer;
			if (!WriteFile(hFileCountArray, retroVars.countArrays[curLayer], numKnotsInCurLayer * sizeof(countArrayVarType), &dwWritten, NULL)) return falseOrStop();
			if (dwWritten != numKnotsInCurLayer * sizeof(countArrayVarType)) return falseOrStop();
		}
		PRINT(2, this, "  Count array saved to file: " << ssCountArrayFilePath.str());
	}

	// finish
	CloseHandle(hFileCountArray);
	return true;
}

//-----------------------------------------------------------------------------
// Name: calcNumSuccedors()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::calcNumSuccedors(retroAnalysisGlobalVars &retroVars)
{
	// locals
	unsigned int			curLayerId;											// current processed layer within 'layersToCalculate'
	unsigned int			layerNumber;										// layer number of the current process layer
	stateAdressStruct		curState;											// current state counter for loops
	stateAdressStruct		succState;											// current succeding state counter for loops
	vector<bool>			succCalculated(skvfHeader.numLayers, false);		// 

	// process each layer
	for (curLayerId=0; curLayerId<retroVars.layersToCalculate.size(); curLayerId++) { 

		// set current processed layer number
		layerNumber = retroVars.layersToCalculate[curLayerId];
		PRINT(0, this, "  *** Calculate number of succeding states for each state of layer " << layerNumber << " ***");

		// process layer ... 
		if (!succCalculated[layerNumber]) {

			// prepare parameters for multithreading
			succCalculated[layerNumber] = true;
			numStatesProcessed			= 0;
			threadManagerClass::threadVarsArray<addNumSuccedorsVars> tva(threadManager.getNumThreads(), addNumSuccedorsVars(this, &retroVars, layerNumber));

			// process each state in the current layer
			switch (threadManager.executeParallelLoop(addNumSuccedorsThreadProc, tva.getPointerToArray(), tva.getSizeOfArray(), TM_SCHEDULE_STATIC, 0, layerStats[layerNumber].knotsInLayer - 1, 1))
			{
			case TM_RETURN_VALUE_OK: 			
				break;
			case TM_RETURN_VALUE_EXECUTION_CANCELLED:
				PRINT(0,this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
				return false;
			default:
			case TM_RETURN_VALUE_INVALID_PARAM:
			case TM_RETURN_VALUE_UNEXPECTED_ERROR:
				return falseOrStop();
			}

			// reduce and delete thread specific data
			tva.reduce();
			if (numStatesProcessed < layerStats[layerNumber].knotsInLayer) return falseOrStop();

		// don't calc layers twice
		} else {						  
			return falseOrStop();
		}

		// ... and process succeding layers
		for (curState.layerNumber=0; curState.layerNumber<layerStats[layerNumber].numSuccLayers; curState.layerNumber++) {
	        
			// get current pred. layer
			succState.layerNumber = layerStats[layerNumber].succLayers[curState.layerNumber];

			// don't add layers twice
			if (succCalculated[succState.layerNumber]) continue;
			else									   succCalculated[succState.layerNumber] = true;
			
			// don't process layers without states
			if (!layerStats[succState.layerNumber].knotsInLayer) continue;

			// check all states of pred. layer
  			PRINT(2, this, "    - Do the same for the succeding layer " << (int) succState.layerNumber);

			// prepare parameters for multithreading
			numStatesProcessed	= 0;
			threadManagerClass::threadVarsArray<addNumSuccedorsVars> tva(threadManager.getNumThreads(), addNumSuccedorsVars(this, &retroVars, succState.layerNumber));

			// process each state in the current layer
			switch (threadManager.executeParallelLoop(addNumSuccedorsThreadProc, tva.getPointerToArray(), tva.getSizeOfArray(), TM_SCHEDULE_STATIC, 0, layerStats[succState.layerNumber].knotsInLayer - 1, 1))
			{
			case TM_RETURN_VALUE_OK: 			
				break;
			case TM_RETURN_VALUE_EXECUTION_CANCELLED:
				PRINT(0,this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
				return false;
			default:
			case TM_RETURN_VALUE_INVALID_PARAM:
			case TM_RETURN_VALUE_UNEXPECTED_ERROR:
				return falseOrStop();
			}

			// reduce and delete thread specific data
			tva.reduce();
			if (numStatesProcessed < layerStats[succState.layerNumber].knotsInLayer) return falseOrStop();
		}
	}

	// everything fine
	return true;
}

//-----------------------------------------------------------------------------
// Name: addNumSuccedorsThreadProc()
// Desc: 
//-----------------------------------------------------------------------------
DWORD miniMax::addNumSuccedorsThreadProc(void* pParameter, int index)
{
	// locals
	addNumSuccedorsVars *		ansVars					= (addNumSuccedorsVars *) pParameter;
	miniMax *					m						= ansVars->pMiniMax;
	unsigned int				numLayersToCalculate	= (unsigned int) ansVars->retroVars->layersToCalculate.size();
	unsigned int				curLayerId;				// current processed layer within 'layersToCalculate'
	unsigned int				amountOfPred;
	unsigned int				curPred;
	countArrayVarType 			countValue;
	stateAdressStruct			predState;
	stateAdressStruct			curState;
	twoBit						curStateValue;
	plyInfoVarType				numPlies;							// number of plies of the current considered succeding state
	bool						cuStateAddedToProcessQueue	= false;

	curState.layerNumber	= ansVars->layerNumber;
	curState.stateNumber	= (stateNumberVarType) index;

	// print status
	ansVars->statesProcessed++;
	if (ansVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) { 
		m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
		PRINT(2, m, "    Already processed " << m->numStatesProcessed << " of " << m->layerStats[curState.layerNumber].knotsInLayer << " states");
	}

	// invalid state ?
	m->readKnotValueFromDatabase(curState.layerNumber, curState.stateNumber, curStateValue);
	if (curStateValue == SKV_VALUE_INVALID) return TM_RETURN_VALUE_OK;

    // set current selected situation
	if (!m->setSituation(ansVars->curThreadNo, curState.layerNumber, curState.stateNumber)) {
		PRINT(0, m, "ERROR: setSituation() returned false!");
		return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
	}

    // get list with statenumbers of predecessors
    m->getPredecessors(ansVars->curThreadNo, &amountOfPred, ansVars->predVars);

	// iteration
	for (curPred=0; curPred<amountOfPred; curPred++) {

        // current predecessor
        predState.layerNumber = ansVars->predVars[curPred].predLayerNumbers;
        predState.stateNumber = ansVars->predVars[curPred].predStateNumbers;

		// don't calculate states from layers above yet
		for (curLayerId=0; curLayerId<numLayersToCalculate; curLayerId++) { 
			if (ansVars->retroVars->layersToCalculate[curLayerId] == predState.layerNumber) break;
		}
		if (curLayerId == numLayersToCalculate) continue;

		// put in list (with states to be processed) if state is final
		if (!cuStateAddedToProcessQueue && (curStateValue == SKV_VALUE_GAME_WON || curStateValue == SKV_VALUE_GAME_LOST)) {
			m->readPlyInfoFromDatabase(curState.layerNumber, curState.stateNumber, numPlies);
			m->addStateToProcessQueue(*ansVars->retroVars, ansVars->retroVars->thread[ansVars->curThreadNo], numPlies, &curState);
			cuStateAddedToProcessQueue = true;
		}

		// add this state as possible move
		long *					pCountValue		= ((long*) ansVars->retroVars->countArrays[curLayerId]) + predState.stateNumber / (sizeof(long) / sizeof(countArrayVarType));
		long					numBitsToShift	= sizeof(countArrayVarType) * 8 * (predState.stateNumber % (sizeof(long) / sizeof(countArrayVarType)));	// little-endian byte-order
		long					mask			= 0x000000ff << numBitsToShift;
		long					curCountLong, newCountLong;
			
		do {
			curCountLong	= *pCountValue;
			countValue		= (countArrayVarType) ((curCountLong & mask) >> numBitsToShift);
			if (countValue == 255) {
				PRINT(0, m, "ERROR: maximum value for Count[] reached!");
				return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
			} else {
				countValue++;
				newCountLong = (curCountLong & (~mask)) + (countValue << numBitsToShift);
			}
		} while (InterlockedCompareExchange(pCountValue, newCountLong, curCountLong) != curCountLong);
	}

	// everything is fine
	return TM_RETURN_VALUE_OK;
}

//-----------------------------------------------------------------------------
// Name: performRetroAnalysis()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::performRetroAnalysis(retroAnalysisGlobalVars &retroVars)
{
	// locals
	stateAdressStruct		curState;									// current state counter for loops
	twoBit		  			curStateValue;								// current state value
	unsigned int			curLayerId;									// current processed layer within 'layersToCalculate'

	PRINT(2, this, "  *** Begin Iteration ***");
	numStatesProcessed = 0;
	curCalculationActionId = MM_ACTION_PERFORM_RETRO_ANAL;
	
	// process each state in the current layer
	switch (threadManager.executeInParallel(performRetroAnalysisThreadProc, (void**) &retroVars, 0)) 
	{
	case TM_RETURN_VALUE_OK: 			
		break;
	case TM_RETURN_VALUE_EXECUTION_CANCELLED:
		PRINT(0,this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
		return false;
	default:
	case TM_RETURN_VALUE_INVALID_PARAM:
	case TM_RETURN_VALUE_UNEXPECTED_ERROR:
		return falseOrStop();
	}
	
	// if there are still states to process, than something went wrong
	for (unsigned int curThreadNo=0; curThreadNo<threadManager.getNumThreads(); curThreadNo++) {
		if (retroVars.thread[curThreadNo].numStatesToProcess) {
			PRINT(0, this, "ERROR: There are still states to process after performing retro analysis!");
			return falseOrStop();
		}
	}
	
	// copy drawn and invalid states to ply info
	PRINT(2, this, "    Copy drawn and invalid states to ply info database...");
	for (curLayerId=0; curLayerId<retroVars.layersToCalculate.size(); curLayerId++) { 
		for (curState.layerNumber=retroVars.layersToCalculate[curLayerId], curState.stateNumber=0; curState.stateNumber<layerStats[curState.layerNumber].knotsInLayer; curState.stateNumber++) {
			 readKnotValueFromDatabase(curState.layerNumber, curState.stateNumber, curStateValue);
			 if (curStateValue == SKV_VALUE_GAME_DRAWN) savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber, PLYINFO_VALUE_DRAWN);
			 if (curStateValue == SKV_VALUE_INVALID)    savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber, PLYINFO_VALUE_INVALID);
		}
	}
	PRINT(1, this, "  *** Iteration finished! ***");

	// every thing ok
	return true;
}

//-----------------------------------------------------------------------------
// Name: performRetroAnalysisThreadProc()
// Desc: 
//-----------------------------------------------------------------------------
DWORD miniMax::performRetroAnalysisThreadProc(void* pParameter)
{
	// locals
	retroAnalysisGlobalVars *	retroVars					= (retroAnalysisGlobalVars *) pParameter;
	miniMax *					m							= retroVars->pMiniMax;
	unsigned int				threadNo					= m->threadManager.getThreadNumber();
	retroAnalysisThreadVars *	threadVars					= &retroVars->thread[threadNo];

	twoBit						predStateValue;
	unsigned int				curLayerId;									// current processed layer within 'layersToCalculate'
	unsigned int  				amountOfPred;								// total numbers of predecessors and current considered one
	unsigned int				curPred;
	unsigned int				threadCounter;
	long long					numStatesProcessed;
	long long					totalNumStatesToProcess;
	plyInfoVarType				curNumPlies;
	plyInfoVarType				numPliesTillCurState;
	plyInfoVarType				numPliesTillPredState;
	countArrayVarType			countValue;
	stateAdressStruct			predState;
	stateAdressStruct			curState;									// current state counter for while-loop
	twoBit		  				curStateValue;								// current state value
	retroAnalysisPredVars		predVars[MAX_NUM_PREDECESSORS];

	for (numStatesProcessed	= 0, curNumPlies=0; curNumPlies<threadVars->statesToProcess.size(); curNumPlies++) {

		// skip empty and uninitialized cyclic arrays
		if (threadVars->statesToProcess[curNumPlies] != NULL) {
		
			if (threadNo==0) {
				PRINT(0, m, "    Current number of plies: " << (unsigned int) curNumPlies << "/" << threadVars->statesToProcess.size());
				for (threadCounter=0; threadCounter<m->threadManager.getNumThreads(); threadCounter++) {
					PRINT(0, m, "      States to process for thread " << threadCounter << ": " << retroVars->thread[threadCounter].numStatesToProcess);
				}
			}

			while (threadVars->statesToProcess[curNumPlies]->takeBytes(sizeof(stateAdressStruct), (unsigned char*) &curState)) {

				// execution cancelled by user?
				if (m->threadManager.wasExecutionCancelled()) {
					PRINT(0,m, "\n****************************************\nSub-thread no. " << threadNo << ": Execution cancelled by user!\n****************************************\n");
					return TM_RETURN_VALUE_EXECUTION_CANCELLED;
				}

				// get value of current state
				m->readKnotValueFromDatabase(curState.layerNumber, curState.stateNumber, curStateValue);
				m->readPlyInfoFromDatabase  (curState.layerNumber, curState.stateNumber, numPliesTillCurState);

				if (numPliesTillCurState != curNumPlies) {
					PRINT(0,m,"ERROR: numPliesTillCurState != curNumPlies");
					return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
				}
				
				// console output
				numStatesProcessed++;
				threadVars->numStatesToProcess--;
				if (numStatesProcessed % OUTPUT_EVERY_N_STATES == 0) { 
					m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
					for (totalNumStatesToProcess=0, threadCounter=0; threadCounter<m->threadManager.getNumThreads(); threadCounter++) {
						totalNumStatesToProcess += retroVars->thread[threadCounter].numStatesToProcess;
					}
					PRINT(2, m, "    states already processed: " << m->numStatesProcessed << " \t states still in list: " << totalNumStatesToProcess);
				}

				// set current selected situation
				if (!m->setSituation(threadNo, curState.layerNumber, curState.stateNumber)) {
					PRINT(0,m,"ERROR: setSituation() returned false!");
					return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
				}

				// get list with statenumbers of predecessors
				m->getPredecessors(threadNo, &amountOfPred, predVars);

				// iteration
				for (curPred=0; curPred<amountOfPred; curPred++) {

					// current predecessor
					predState.layerNumber = predVars[curPred].predLayerNumbers;
					predState.stateNumber = predVars[curPred].predStateNumbers;

					// don't calculate states from layers above yet
					for (curLayerId=0; curLayerId<retroVars->layersToCalculate.size(); curLayerId++) { 
						if (retroVars->layersToCalculate[curLayerId] == predState.layerNumber) break;
					}
					if (curLayerId == retroVars->layersToCalculate.size()) continue;

					// get value of predecessor
					m->readKnotValueFromDatabase(predState.layerNumber, predState.stateNumber, predStateValue);

					// only drawn states are relevant here, since the other are already calculated
					if (predStateValue == SKV_VALUE_GAME_DRAWN) {

						// if current considered state is a lost game then all predecessors are a won game
						if (curStateValue == m->skvPerspectiveMatrix[SKV_VALUE_GAME_LOST][predVars[curPred].playerToMoveChanged ? PL_TO_MOVE_CHANGED : PL_TO_MOVE_UNCHANGED]) {
							m->saveKnotValueInDatabase(predState.layerNumber, predState.stateNumber, SKV_VALUE_GAME_WON);
							m->savePlyInfoInDatabase  (predState.layerNumber, predState.stateNumber, numPliesTillCurState + 1);	// (requirement: curNumPlies == numPliesTillCurState)
							if (numPliesTillCurState + 1 < curNumPlies) {
								PRINT(0,m,"ERROR: Current number of plies is bigger than numPliesTillCurState + 1!");
								return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
							}
							m->addStateToProcessQueue(*retroVars, *threadVars, numPliesTillCurState + 1, &predState);
						// if current state is a won game, then this state is not an option any more for all predecessors
						} else {
							// reduce count value by one
							long *					pCountValue		= ((long*) retroVars->countArrays[curLayerId]) + predState.stateNumber / (sizeof(long) / sizeof(countArrayVarType));
							long					numBitsToShift	= sizeof(countArrayVarType) * 8 * (predState.stateNumber % (sizeof(long) / sizeof(countArrayVarType)));	// little-endian byte-order
							long					mask			= 0x000000ff << numBitsToShift;
							long					curCountLong, newCountLong;
			
							do {
								curCountLong	= *pCountValue;
								countValue		= (countArrayVarType) ((curCountLong & mask) >> numBitsToShift);
								if (countValue > 0) {
									countValue--;
									newCountLong = (curCountLong & (~mask)) + (countValue << numBitsToShift);
								} else {
									PRINT(0,m,"ERROR: Count is already zero!");
									return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
								}
							} while (InterlockedCompareExchange(pCountValue, newCountLong, curCountLong) != curCountLong);

							// ply info (requirement: curNumPlies == numPliesTillCurState)
							m->readPlyInfoFromDatabase(predState.layerNumber, predState.stateNumber, numPliesTillPredState);
							if (numPliesTillPredState == PLYINFO_VALUE_UNCALCULATED || numPliesTillCurState + 1 > numPliesTillPredState) {
								m->savePlyInfoInDatabase(predState.layerNumber, predState.stateNumber, numPliesTillCurState + 1);
							}
								
							// when all successor are won states then this is a lost state (this should only be the case for one thread)
							if (countValue == 0) {
								m->saveKnotValueInDatabase(predState.layerNumber, predState.stateNumber, SKV_VALUE_GAME_LOST);
								if (numPliesTillCurState + 1 < curNumPlies) {
									PRINT(0,m,"ERROR: Current number of plies is bigger than numPliesTillCurState + 1!");
									return TM_RETURN_VALUE_TERMINATE_ALL_THREADS;
								}
								m->addStateToProcessQueue(*retroVars, *threadVars, numPliesTillCurState + 1, &predState);
							}
						} 
					}
				}
			}
		}

		// there might be other threads still processing states with this ply number
		m->threadManager.waitForOtherThreads(threadNo);
	}

	// every thing ok
	return TM_RETURN_VALUE_OK;
}

//-----------------------------------------------------------------------------
// Name: addStateToProcessQueue()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::addStateToProcessQueue(retroAnalysisGlobalVars &retroVars, retroAnalysisThreadVars &threadVars, unsigned int plyNumber, stateAdressStruct* pState)
{
	// resize vector if too small
	if (plyNumber >= threadVars.statesToProcess.size()) {
		threadVars.statesToProcess.resize(max(plyNumber+1, 10*threadVars.statesToProcess.size()), NULL);
		PRINT(4, this, "    statesToProcess resized to " << threadVars.statesToProcess.size());
	}

	// initialize cyclic array if necessary
	if (threadVars.statesToProcess[plyNumber] == NULL) {
		stringstream	ssStatesToProcessFilePath;
		stringstream	ssStatesToProcessPath;		
		ssStatesToProcessPath	<< fileDirectory << (fileDirectory.size()?"\\":"") << "statesToProcess";
		CreateDirectoryA(ssStatesToProcessPath.str().c_str(), NULL);
		ssStatesToProcessFilePath.str("");
		ssStatesToProcessFilePath << ssStatesToProcessPath.str() << "\\statesToProcessWithPlyCounter=" << plyNumber << "andThread=" << threadVars.threadNo << ".dat";
		threadVars.statesToProcess[plyNumber] = new cyclicArray(BLOCK_SIZE_IN_CYCLIC_ARRAY * sizeof(stateAdressStruct), (unsigned int)(retroVars.totalNumKnots / BLOCK_SIZE_IN_CYCLIC_ARRAY) + 1, ssStatesToProcessFilePath.str().c_str());
		PRINT(4, this, "    Created cyclic array: " << ssStatesToProcessFilePath.str());
	}

	// add state
	if (!threadVars.statesToProcess[plyNumber]->addBytes(sizeof(stateAdressStruct), (unsigned char*) pState)) {
		PRINT(0, this, "ERROR: Cyclic list to small! numStatesToProcess:" << threadVars.numStatesToProcess);
		return falseOrStop();
	}

	// everything was fine
	threadVars.numStatesToProcess++;
	return true;
}
