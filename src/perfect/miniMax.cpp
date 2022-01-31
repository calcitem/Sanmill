/*********************************************************************
    MiniMax.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

//-----------------------------------------------------------------------------
// MiniMax()
// MiniMax class constructor
//-----------------------------------------------------------------------------
MiniMax::MiniMax()
{
    // init default values
    hFileShortKnotValues = nullptr;
    hFilePlyInfo = nullptr;
    memoryUsed2 = 0;
    arrayInfos.c = this;
    arrayInfos.arrayInfosToBeUpdated.clear();
    arrayInfos.listArrays.clear();
    onlyPrepareLayer = false;
    curCalculatedLayer = 0;
    osPrint = &cout;
    verbosity = 3;
    stopOnCriticalError = true;
    pDataForUserPrintFunc = nullptr;
    userPrintFunc = nullptr;
    layerStats = nullptr;
    plyInfos = nullptr;
    fileDir.assign("");
    InitializeCriticalSection(&csDatabase);
    InitializeCriticalSection(&csOsPrint);

    // for I/O operations per second measurement
    QueryPerformanceFrequency(&frequency);
    nReadSkvOps = 0;
    nWriteSkvOps = 0;
    nReadPlyOps = 0;
    nWritePlyOps = 0;

    if (MEASURE_ONLY_IO) {
        readSkvInterval.QuadPart = 0;
        writeSkvInterval.QuadPart = 0;
        readPlyInterval.QuadPart = 0;
        writePlyInterval.QuadPart = 0;
    } else {
        QueryPerformanceCounter(&readSkvInterval);
        QueryPerformanceCounter(&writeSkvInterval);
        QueryPerformanceCounter(&readPlyInterval);
        QueryPerformanceCounter(&writePlyInterval);
    }

    // The algorithm assumes that each player does only one move.
    // That means closing a mill and removing a piece should be one move.
    // PL_TO_MOVE_CHANGED   means that in the predecessor state the player to
    // move has changed to the other player. PL_TO_MOVE_UNCHANGED means that the
    // player to move is still the one who shall move.
    const unsigned char skvPerspectiveMatrixTmp[4][2] = {
        //  PL_TO_MOVE_UNCHANGED    PL_TO_MOVE_CHANGED
        SKV_VALUE_INVALID,
        SKV_VALUE_INVALID, // SKV_VALUE_INVALID
        SKV_VALUE_GAME_WON,
        SKV_VALUE_GAME_LOST, // SKV_VALUE_GAME_LOST
        SKV_VALUE_GAME_DRAWN,
        SKV_VALUE_GAME_DRAWN, // SKV_VALUE_GAME_DRAWN
        SKV_VALUE_GAME_LOST,
        SKV_VALUE_GAME_WON // SKV_VALUE_GAME_WON
    };

    memcpy(skvPerspectiveMatrix, skvPerspectiveMatrixTmp, 4 * 2);
}

//-----------------------------------------------------------------------------
// ~MiniMax()
// MiniMax class destructor
//-----------------------------------------------------------------------------
MiniMax::~MiniMax()
{
    closeDatabase();
    DeleteCriticalSection(&csOsPrint);
    DeleteCriticalSection(&csDatabase);
}

//-----------------------------------------------------------------------------
// falseOrStop()
//
//-----------------------------------------------------------------------------
bool MiniMax::falseOrStop() const
{
    if (stopOnCriticalError)
        WaitForSingleObject(GetCurrentProcess(), INFINITE);

    return false;
}

//-----------------------------------------------------------------------------
// getBestChoice()
// Returns the best choice if the database has been opened and
// calculates the best choice for that if database is not open.
//-----------------------------------------------------------------------------
void *MiniMax::getBestChoice(uint32_t tilLevel, uint32_t *choice,
                             uint32_t branchCountMax)
{
    // set global vars
    fullTreeDepth = tilLevel;
    maxNumBranches = branchCountMax;
    layerInDatabase = isCurStateInDatabase(0);
    calcDatabase = false;

    // Locals
    Knot root;
    AlphaBetaGlobalVars alphaBetaVars(this, getLayerNumber(0));
    RunAlphaBetaVars tva(this, &alphaBetaVars, alphaBetaVars.layerNumber);
    srand(static_cast<uint32_t>(time(nullptr)));
    tva.curThreadNo = 0;

    // prepare the situation
    prepareBestChoiceCalc();

    // First make a tree until the desired level
    letTheTreeGrow(&root, &tva, fullTreeDepth, FPKV_MIN_VALUE, FPKV_MAX_VALUE);

    // pass best choice and close database
    *choice = root.bestMoveId;

    // Return the best branch of the root
    return pRootPossibilities;
}

//-----------------------------------------------------------------------------
// calculateDatabase()
// Calculates the database, which must be already open.
//-----------------------------------------------------------------------------
void MiniMax::calculateDatabase(uint32_t maxDepthOfTree, bool onlyPrepLayer)
{
    // locals
    bool abortCalc = false;
    this->onlyPrepareLayer = onlyPrepLayer;
    lastCalculatedLayer.clear();

    PRINT(1, this, "*************************");
    PRINT(1, this, "* Calculate Database    *");
    PRINT(1, this, "*************************");

    // call preparation function of parent class
    prepareDatabaseCalc();

    // when database not completed then do it
    if (hFileShortKnotValues != nullptr && skvfHeader.completed == false) {
        // reserve memory
        lastCalculatedLayer.clear();
        fullTreeDepth = maxDepthOfTree;
        layerInDatabase = false;
        calcDatabase = true;
        threadManager.uncancelExec();
        arrayInfos.vectorArrays.resize(ArrayInfo::arrayTypeCount *
                                           skvfHeader.LayerCount,
                                       arrayInfos.listArrays.end());

        // calculate layer after layer, beginning with the last one
        for (curCalculatedLayer = 0; curCalculatedLayer < skvfHeader.LayerCount;
             curCalculatedLayer++) {
            // layer already calculated?
            if (layerStats[curCalculatedLayer].layerIsCompletedAndInFile)
                continue;

            // don't calculate if neither the layer nor the partner layer has
            // any knots
            if (layerStats[curCalculatedLayer].knotsInLayer == 0 &&
                layerStats[layerStats[curCalculatedLayer].partnerLayer]
                        .knotsInLayer == 0)
                continue;

            // calculate
            abortCalc = !calcLayer(curCalculatedLayer);

            // release memory
            unloadAllLayers();
            unloadAllPlyInfos();

            // don't save layer and header when only preparing layers
            if (onlyPrepLayer)
                return;
            if (abortCalc)
                break;

            // save header
            saveHeader(&skvfHeader, layerStats);
            saveHeader(&plyInfoHeader, plyInfos);
        }

        // don't save layer and header when only preparing layers or when
        if (onlyPrepLayer)
            return;

        if (!abortCalc) {
            // calculate layer statistics
            calcLayerStatistics("statistics.txt");

            // save header
            skvfHeader.completed = true;
            plyInfoHeader.plyInfoCompleted = true;
            saveHeader(&skvfHeader, layerStats);
            saveHeader(&plyInfoHeader, plyInfos);
        }

        // free memory
        curCalcActionId = MM_ACTION_NONE;
    } else {
        PRINT(1, this, "\nThe database is already fully calculated.\n");
    }

    // call warp-up function of parent class
    wrapUpDatabaseCalc(abortCalc);

    PRINT(1, this, "*************************");
    PRINT(1, this, "* Calc finished  *");
    PRINT(1, this, "*************************");
}

//-----------------------------------------------------------------------------
// calcLayer()
//
//-----------------------------------------------------------------------------
bool MiniMax::calcLayer(uint32_t layerNumber)
{
    // locals
    vector<uint32_t> layersToCalc;

    // moves can be done reverse, leading to too depth searching trees
    if (shallRetroAnalysisBeUsed(layerNumber)) {
        // calculate values for all states of layer
        layersToCalc.push_back(layerNumber);
        if (layerNumber != layerStats[layerNumber].partnerLayer)
            layersToCalc.push_back(layerStats[layerNumber].partnerLayer);
        if (!calcKnotValuesByRetroAnalysis(layersToCalc))
            return false;

        // save partner layer
        if (layerStats[layerNumber].partnerLayer != layerNumber) {
            saveLayerToFile(layerStats[layerNumber].partnerLayer);
        }

        // use minimax-algorithm
    } else {
        if (!calcKnotValuesByAlphaBeta(layerNumber))
            return false;
    }

    // save layer
    saveLayerToFile(layerNumber);

    // test layer
    if (!testLayer(layerNumber)) {
        PRINT(0, this, "ERROR: Layer calculation cancelled or failed!" << endl);
        return false;
    }

    // test partner layer if retro-analysis has been used
    if (shallRetroAnalysisBeUsed(layerNumber) &&
        layerStats[layerNumber].partnerLayer != layerNumber) {
        if (!testLayer(layerStats[layerNumber].partnerLayer)) {
            PRINT(0, this,
                  "ERROR: Layer calculation cancelled or failed!" << endl);
            return false;
        }
    }

    // update output info
    EnterCriticalSection(&csOsPrint);
    if (shallRetroAnalysisBeUsed(layerNumber) &&
        layerNumber != layerStats[layerNumber].partnerLayer) {
        lastCalculatedLayer.push_back(layerStats[layerNumber].partnerLayer);
    }
    lastCalculatedLayer.push_back(layerNumber);
    LeaveCriticalSection(&csOsPrint);

    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
