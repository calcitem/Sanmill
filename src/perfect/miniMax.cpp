/*********************************************************************
	miniMax.cpp													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "miniMax.h"

//-----------------------------------------------------------------------------
// Name: miniMax()
// Desc: miniMax class constructor
//-----------------------------------------------------------------------------
miniMax::miniMax()
{
	// init default values
	hFileShortKnotValues		= NULL;
	hFilePlyInfo				= NULL;
	memoryUsed2					= 0;
	arrayInfos.c				= this;
	arrayInfos.arrayInfosToBeUpdated.clear();
	arrayInfos.listArrays.clear();
	onlyPrepareLayer			= false;
	curCalculatedLayer			= 0;
	osPrint						= &cout;
	verbosity					= 3;
	stopOnCriticalError			= true;
	pDataForUserPrintFunc		= NULL;
	userPrintFunc				= NULL;
	layerStats					= NULL;
	plyInfos					= NULL;
	fileDirectory.assign("");
	InitializeCriticalSection(&csDatabase);
	InitializeCriticalSection(&csOsPrint);

	// Tausender-Trennzeichen
	locale locale("German_Switzerland"); 
    cout.imbue(locale); 

	// for io operations per second measurement
	QueryPerformanceFrequency(&frequency);
	numReadSkvOperations		= 0;
	numWriteSkvOperations		= 0;
	numReadPlyOperations		= 0;			
	numWritePlyOperations		= 0;
	if (MEASURE_ONLY_IO) {
		readSkvInterval.QuadPart  = 0;
		writeSkvInterval.QuadPart = 0;
		readPlyInterval.QuadPart  = 0;
		writePlyInterval.QuadPart = 0;
	} else {
		QueryPerformanceCounter(&readSkvInterval );
		QueryPerformanceCounter(&writeSkvInterval);
		QueryPerformanceCounter(&readPlyInterval );
		QueryPerformanceCounter(&writePlyInterval);
	}

	// The algorithm assumes that each player does only one move.
	// That means closing a mill and removing a stone should be one move.
	// PL_TO_MOVE_CHANGED   means that in the predecessor state the player to move has changed to the other player.
	// PL_TO_MOVE_UNCHANGED means that the player to move is still the one who shall move.
	unsigned char skvPerspectiveMatrixTmp[4][2] = {
	//  PL_TO_MOVE_UNCHANGED    PL_TO_MOVE_CHANGED           
		SKV_VALUE_INVALID,       SKV_VALUE_INVALID,       // SKV_VALUE_INVALID    
		SKV_VALUE_GAME_WON,      SKV_VALUE_GAME_LOST,     // SKV_VALUE_GAME_LOST	
		SKV_VALUE_GAME_DRAWN,    SKV_VALUE_GAME_DRAWN,    // SKV_VALUE_GAME_DRAWN 
		SKV_VALUE_GAME_LOST,     SKV_VALUE_GAME_WON       // SKV_VALUE_GAME_WON	
	};

	memcpy(skvPerspectiveMatrix, skvPerspectiveMatrixTmp, 4 * 2);
}

//-----------------------------------------------------------------------------
// Name: ~miniMax()
// Desc: miniMax class destructor
//-----------------------------------------------------------------------------
miniMax::~miniMax()
{
	closeDatabase();
	DeleteCriticalSection(&csOsPrint);
	DeleteCriticalSection(&csDatabase);
}

//-----------------------------------------------------------------------------
// Name: falseOrStop()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::falseOrStop()
{
	if (stopOnCriticalError) WaitForSingleObject(GetCurrentProcess(), INFINITE);
	return false;
}

//-----------------------------------------------------------------------------
// Name: getBestChoice()
// Desc: Returns the best choice if the database has been opened and calculates the best choice for that if database is not open.
//-----------------------------------------------------------------------------
void *miniMax::getBestChoice(unsigned int tilLevel, unsigned int *choice, unsigned int maximumNumberOfBranches)
{
	// set global vars
	depthOfFullTree				= tilLevel;
	maxNumBranches				= maximumNumberOfBranches;
	layerInDatabase				= isCurrentStateInDatabase(0);
	calcDatabase				= false;

	// Locals
	knotStruct				root;
	alphaBetaGlobalVars		alphaBetaVars(this, getLayerNumber(0));
	runAlphaBetaVars		tva(this, &alphaBetaVars, alphaBetaVars.layerNumber);
	srand((unsigned int)time(NULL));
	tva.curThreadNo			= 0;

	// prepare the situation
	prepareBestChoiceCalculation();

	// First make a tree until the desired level
	letTheTreeGrow(&root, &tva, depthOfFullTree, FPKV_MIN_VALUE, FPKV_MAX_VALUE);

	// pass best choice and close database
	*choice = root.bestMoveId;
	
	// Return the best branch of the root
	return pRootPossibilities;
}

//-----------------------------------------------------------------------------
// Name: calculateDatabase()
// Desc: Calculates the database, which must be already open.
//-----------------------------------------------------------------------------
void miniMax::calculateDatabase(unsigned int maxDepthOfTree, bool onlyPrepareLayer)
{
   	// locals
	bool			abortCalculation = false;
	this->onlyPrepareLayer	= onlyPrepareLayer;
	lastCalculatedLayer.clear();

    PRINT(1, this, "*************************");
    PRINT(1, this, "* Calculate Database    *");
    PRINT(1, this, "*************************");

	// call preparation function of parent class
	prepareDatabaseCalculation();

	// when database not completed then do it
    if (hFileShortKnotValues != NULL && skvfHeader.completed == false) {

        // reserve memory
		lastCalculatedLayer.clear();
        depthOfFullTree 		= maxDepthOfTree;
		layerInDatabase			= false;
		calcDatabase			= true;
		threadManager.uncancelExecution();
		arrayInfos.vectorArrays.resize(arrayInfoStruct::numArrayTypes*skvfHeader.numLayers, arrayInfos.listArrays.end());

		// calc layer after layer, beginning with the last one
		for (curCalculatedLayer=0; curCalculatedLayer<skvfHeader.numLayers; curCalculatedLayer++) {

			// layer already calculated?
			if (layerStats[curCalculatedLayer].layerIsCompletedAndInFile) continue;

			// don't calc if neither the layer nor the partner layer has any knots
			if (layerStats[curCalculatedLayer].knotsInLayer == 0 && layerStats[layerStats[curCalculatedLayer].partnerLayer].knotsInLayer == 0) continue;

			// calc
			abortCalculation  = (!calcLayer(curCalculatedLayer));

			// relase memory
			unloadAllLayers();
			unloadAllPlyInfos();

			// don't save layer and header when only preparing layers
			if (onlyPrepareLayer) return;
			if (abortCalculation) break;

			// save header
			saveHeader(&skvfHeader, layerStats);
			saveHeader(&plyInfoHeader, plyInfos);
		}

		// don't save layer and header when only preparing layers or when 
		if (onlyPrepareLayer) return;
		if (!abortCalculation) {

			// calc layer statistics
			calcLayerStatistics("statistics.txt");

			// save header
			skvfHeader.completed			= true;
			plyInfoHeader.plyInfoCompleted	= true;
			saveHeader(&skvfHeader, layerStats);
			saveHeader(&plyInfoHeader, plyInfos);
		}

        // free mem
		curCalculationActionId	= MM_ACTION_NONE;
	} else {
		PRINT(1, this, "\nThe database is already fully calculated.\n");
	}

	// call warp-up function of parent class
	wrapUpDatabaseCalculation(abortCalculation);

	PRINT(1, this, "*************************");
    PRINT(1, this, "* Calculation finished  *");
    PRINT(1, this, "*************************");
}

//-----------------------------------------------------------------------------
// Name: calcLayer()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::calcLayer(unsigned int layerNumber)
{
	// locals
	vector <unsigned int> layersToCalculate;

	// moves can be done reverse, leading to too depth searching trees
	if (shallRetroAnalysisBeUsed(layerNumber)) {

		// calc values for all states of layer
		layersToCalculate.push_back(layerNumber);
		if (layerNumber != layerStats[layerNumber].partnerLayer) layersToCalculate.push_back(layerStats[layerNumber].partnerLayer);
		if (!calcKnotValuesByRetroAnalysis(layersToCalculate)) return false;

		// save partner layer
		if (layerStats[layerNumber].partnerLayer != layerNumber) {
			saveLayerToFile(layerStats[layerNumber].partnerLayer);
		}

	// use minimax-algorithm
	} else {
		if (!calcKnotValuesByAlphaBeta(layerNumber)) return false;
	}

	// save layer
	saveLayerToFile(layerNumber);

	// test layer
	if (!testLayer(layerNumber)) {
		PRINT(0, this, "ERROR: Layer calculation cancelled or failed!" << endl);
		return false;
	}

	// test partner layer if retro-analysis has been used
	if (shallRetroAnalysisBeUsed(layerNumber) && layerStats[layerNumber].partnerLayer != layerNumber) {
		if (!testLayer(layerStats[layerNumber].partnerLayer)) {
			PRINT(0, this, "ERROR: Layer calculation cancelled or failed!" << endl);
			return false;
		}
	}

	// update output information
	EnterCriticalSection(&csOsPrint);
	if (shallRetroAnalysisBeUsed(layerNumber) && layerNumber != layerStats[layerNumber].partnerLayer) {
		lastCalculatedLayer.push_back(layerStats[layerNumber].partnerLayer);
	}
	lastCalculatedLayer.push_back(layerNumber);
	LeaveCriticalSection(&csOsPrint);

	return true;
}

//-----------------------------------------------------------------------------
// Name: pauseDatabaseCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void miniMax::pauseDatabaseCalculation()
{
	threadManager.pauseExecution();
}

//-----------------------------------------------------------------------------
// Name: cancelDatabaseCalculation()
// Desc: 
//-----------------------------------------------------------------------------
void miniMax::cancelDatabaseCalculation()
{
	// when returning from executeParallelLoop() all function shall quit immediatelly up to calculateDatabase()
	threadManager.cancelExecution();
}

//-----------------------------------------------------------------------------
// Name: wasDatabaseCalculationCancelled()
// Desc: 
//-----------------------------------------------------------------------------
bool miniMax::wasDatabaseCalculationCancelled()
{
	return threadManager.wasExecutionCancelled();
}
