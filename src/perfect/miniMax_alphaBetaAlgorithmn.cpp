/*********************************************************************
    miniMax_alphaBetaAlgorithmn.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

//-----------------------------------------------------------------------------
// calcKnotValuesByAlphaBeta()
// return value is true if calculation is stopped either by user or by an error
//-----------------------------------------------------------------------------
bool MiniMax::calcKnotValuesByAlphaBeta(unsigned int layerNumber)
{
    // locals
    AlphaBetaGlobalVars alphaBetaVars(this, layerNumber); // multi-thread vars

    // Version 10:
    PRINT(1, this, "*** Calculate layer " << layerNumber << " by alpha-beta-algorithmn ***" << endl);
    curCalculationActionId = MM_ACTION_PERFORM_ALPHA_BETA;

    // initialization
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    if (!initAlphaBeta(alphaBetaVars)) {
        return false;
    }

    // run alpha-beta algorithm
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    if (!runAlphaBeta(alphaBetaVars)) {
        return false;
    }

    // update layerStats[].numWonStates, etc.
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    showLayerStats(layerNumber);

    return true;
}

//-----------------------------------------------------------------------------
// saveKnotValueInDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaSaveInDatabase(unsigned int threadNo,
    unsigned int layerNumber,
    unsigned int stateNumber,
    TwoBit knotValue,
    PlyInfoVarType plyValue,
    bool invertValue)
{
    // locals
    unsigned int* symStateNumbers = nullptr;
    unsigned int numSymmetricStates;
    unsigned int sysStateNumber;
    unsigned int i;

    // invert value ?
    if (knotValue > SKV_VALUE_GAME_WON) {
        while (true) {
        }
    }
    if (invertValue)
        knotValue = skvPerspectiveMatrix[knotValue][PL_TO_MOVE_UNCHANGED];

    // get numbers of symmetric states
    getSymStateNumWithDoubles(threadNo, &numSymmetricStates, &symStateNumbers);

    // save
    saveKnotValueInDatabase(layerNumber, stateNumber, knotValue);
    savePlyInfoInDatabase(layerNumber, stateNumber, plyValue);

    // save value for all symmetric states
    for (i = 0; i < numSymmetricStates; i++) {
        // get state number
        sysStateNumber = symStateNumbers[i];

        // don't save original state twice
        if (sysStateNumber == stateNumber)
            continue;

        // save
        saveKnotValueInDatabase(layerNumber, sysStateNumber, knotValue);
        savePlyInfoInDatabase(layerNumber, sysStateNumber, plyValue);
    }
}

//-----------------------------------------------------------------------------
// initAlphaBeta()
// The function setSituation is called for each state to mark the invalid ones.
//-----------------------------------------------------------------------------
bool MiniMax::initAlphaBeta(AlphaBetaGlobalVars& alphaBetaVars)
{
#ifndef __clang__ // TODO(calcitem)
    // locals
    BufferedFile* invalidArray; //
    bool initAlreadyDone = false; // true if the initialization information is already available in a file
    stringstream ssInvArrayDirectory; //
    stringstream ssInvArrayFilePath; //

    // set current processed layer number
    PRINT(1, this,
        endl << "  *** Signing of invalid states for layer " << alphaBetaVars.layerNumber << " (" << (getOutputInformation(alphaBetaVars.layerNumber)) << ") which has " << layerStats[alphaBetaVars.layerNumber].knotsInLayer << " knots ***");

    // file names
    ssInvArrayDirectory.str("");
    ssInvArrayDirectory << fileDirectory << (fileDirectory.size() ? "\\" : "") << "invalidStates";
    ssInvArrayFilePath.str("");
    ssInvArrayFilePath << fileDirectory << (fileDirectory.size() ? "\\" : "") << "invalidStates\\invalidStatesOfLayer" << alphaBetaVars.layerNumber << ".dat";

    // does initialization file exist ?
    CreateDirectoryA(ssInvArrayDirectory.str().c_str(), nullptr);
    invalidArray = new BufferedFile(threadManager.getNumThreads(), FILE_BUFFER_SIZE, ssInvArrayFilePath.str().c_str());

    if (invalidArray->getFileSize() == (LONGLONG)layerStats[alphaBetaVars.layerNumber].knotsInLayer) {
        PRINT(2, this, "  Loading invalid states from file: " << ssInvArrayFilePath.str());
        initAlreadyDone = true;
    }

    // prepare parameters
    numStatesProcessed = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID] = 0;
    ThreadManager::ThreadVarsArray<InitAlphaBetaVars> tva(threadManager.getNumThreads(),
        (InitAlphaBetaVars&)InitAlphaBetaVars(this,
            &alphaBetaVars,
            alphaBetaVars.layerNumber,
            invalidArray,
            initAlreadyDone));

    // process each state in the current layer
    switch (threadManager.executeParallelLoop(initAlphaBetaThreadProc,
        tva.getPointerToArray(),
        tva.getSizeOfArray(),
        TM_SCHEDULE_STATIC,
        0,
        layerStats[alphaBetaVars.layerNumber].knotsInLayer - 1,
        1)) {
    case TM_RETURN_VALUE_OK:
        break;
    case TM_RETURN_VALUE_EXECUTION_CANCELLED:
        PRINT(0, this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
        SAFE_DELETE(invalidArray);
        return false;
    default:
    case TM_RETURN_VALUE_INVALID_PARAM:
    case TM_RETURN_VALUE_UNEXPECTED_ERROR:
        PRINT(0, this, "\n****************************************\nMain thread: Invalid or unexpected param!\n****************************************\n");
        return falseOrStop();
    }

    // reduce and delete thread specific data
    tva.reduce();
    if (numStatesProcessed < layerStats[alphaBetaVars.layerNumber].knotsInLayer) {
        SAFE_DELETE(invalidArray);
        return falseOrStop();
    }
    invalidArray->flushBuffers();
    SAFE_DELETE(invalidArray);

    // when init file was created new then save it now
    PRINT(2, this, "    Saved initialized states to file: " << ssInvArrayFilePath.str());

    // show statistics
    PRINT(2, this, "    won     states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON]);
    PRINT(2, this, "    lost    states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST]);
    PRINT(2, this, "    draw    states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);
    PRINT(2, this, "    invalid states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID]);
#endif // __clang__
    return true;
}

//-----------------------------------------------------------------------------
// initAlphaBetaThreadProc()
// set short knot value to SKV_VALUE_INVALID, ply info to PLYINFO_VALUE_INVALID and knotAlreadyCalculated to true or false, whether setSituation() returns true or false
//-----------------------------------------------------------------------------
DWORD MiniMax::initAlphaBetaThreadProc(void* pParameter, unsigned int index)
{
    // locals
    InitAlphaBetaVars* iabVars = (InitAlphaBetaVars*)pParameter;
    MiniMax* m = iabVars->pMiniMax;
    float floatValue; // dummy variable for calls of getValueOfSituation()
    StateAdress curState; // current state counter for loops
    TwoBit curStateValue = 0; // for calls of getValueOfSituation()
    PlyInfoVarType plyInfo; // depends on the curStateValue

    curState.layerNumber = iabVars->layerNumber;
    curState.stateNumber = index;
    iabVars->statesProcessed++;

    // print status
    if (iabVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
        PRINT(2, m, "Already initialized " << m->numStatesProcessed << " of " << m->layerStats[curState.layerNumber].knotsInLayer << " states");
    }

    // layer initialization already done ? if so, then read from file
    if (iabVars->initAlreadyDone) {
        if (!iabVars->bufferedFile->readBytes(iabVars->curThreadNo,
                index * sizeof(TwoBit),
                sizeof(TwoBit),
                (unsigned char*)&curStateValue)) {
            PRINT(0, m, "ERROR: initArray->takeBytes() failed");
            return m->falseOrStop();
        }
        // initialization not done
    } else {
        // set current selected situation
        if (!m->setSituation(iabVars->curThreadNo, curState.layerNumber, curState.stateNumber)) {
            curStateValue = SKV_VALUE_INVALID;
        } else {
            // get value of current situation
            m->getValueOfSituation(iabVars->curThreadNo, floatValue, curStateValue);
        }
    }

    // calc ply info
    if (curStateValue == SKV_VALUE_GAME_WON || curStateValue == SKV_VALUE_GAME_LOST) {
        plyInfo = 0;
    } else if (curStateValue == SKV_VALUE_INVALID) {
        plyInfo = PLYINFO_VALUE_INVALID;
    } else {
        plyInfo = PLYINFO_VALUE_UNCALCULATED;
    }

    // save short knot value & ply info (m->alphaBetaSaveInDatabase(iabVars->curThreadNo, curStateValue, plyInfo, false); ???)
    m->saveKnotValueInDatabase(curState.layerNumber, curState.stateNumber, curStateValue);
    m->savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber, plyInfo);

    // write data to file
    if (!iabVars->initAlreadyDone) {
        if (!iabVars->bufferedFile->writeBytes(iabVars->curThreadNo,
                index * sizeof(TwoBit),
                sizeof(TwoBit),
                (unsigned char*)&curStateValue)) {
            PRINT(0, m, "ERROR: bufferedFile->writeBytes failed!");
            return m->falseOrStop();
        }
    }

    iabVars->statsValueCounter[curStateValue]++;

    return TM_RETURN_VALUE_OK;
}

//-----------------------------------------------------------------------------
// runAlphaBeta()
//
//-----------------------------------------------------------------------------
bool MiniMax::runAlphaBeta(AlphaBetaGlobalVars& alphaBetaVars)
{
#ifndef __clang__ // TODO(calcitem)
    // prepare parameters
    PRINT(1, this, "  Calculate layer " << alphaBetaVars.layerNumber << " with function letTheTreeGrow():");
    numStatesProcessed = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID] = 0;
    ThreadManager::ThreadVarsArray<RunAlphaBetaVars> tva(threadManager.getNumThreads(),
        (RunAlphaBetaVars&)RunAlphaBetaVars(this,
            &alphaBetaVars,
            alphaBetaVars.layerNumber));

    // so far no multi-threading implemented
    threadManager.setNumThreads(1);

    // process each state in the current layer
    switch (threadManager.executeParallelLoop(runAlphaBetaThreadProc,
        tva.getPointerToArray(),
        tva.getSizeOfArray(),
        TM_SCHEDULE_STATIC,
        0,
        layerStats[alphaBetaVars.layerNumber].knotsInLayer - 1, 1)) {
    case TM_RETURN_VALUE_OK:
        break;
    case TM_RETURN_VALUE_EXECUTION_CANCELLED:
        PRINT(0, this, "\n****************************************\nMain thread: Execution cancelled by user!\n****************************************\n");
        return false;
    default:
    case TM_RETURN_VALUE_INVALID_PARAM:
    case TM_RETURN_VALUE_UNEXPECTED_ERROR:
        return falseOrStop();
    }

    threadManager.setNumThreads(4);

    // reduce and delete thread specific data
    tva.reduce();
    if (numStatesProcessed < layerStats[alphaBetaVars.layerNumber].knotsInLayer)
        return falseOrStop();

    // show statistics
    PRINT(2, this, "    won     states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON]);
    PRINT(2, this, "    lost    states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST]);
    PRINT(2, this, "    draw    states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);
    PRINT(2, this, "    invalid states: " << alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID]);
#endif // __clang__
    return true;
}

//-----------------------------------------------------------------------------
// runAlphaBetaThreadProc()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::runAlphaBetaThreadProc(void* pParameter, unsigned int index)
{
    // locals
    RunAlphaBetaVars* rabVars = (RunAlphaBetaVars*)pParameter;
    MiniMax* m = rabVars->pMiniMax;
    StateAdress curState; // current state counter for loops
    Knot root; //
    PlyInfoVarType plyInfo; // depends on the curStateValue

    curState.layerNumber = rabVars->layerNumber;
    curState.stateNumber = index;
    rabVars->statesProcessed++;

    // print status
    if (rabVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->numStatesProcessed += OUTPUT_EVERY_N_STATES;
        PRINT(2, m,
            "  Processed " << m->numStatesProcessed << " of " << m->layerStats[curState.layerNumber].knotsInLayer << " states");
    }

    // Version 10: state already calculated? if so leave.
    m->readPlyInfoFromDatabase(curState.layerNumber, curState.stateNumber, plyInfo);

    if (plyInfo != PLYINFO_VALUE_UNCALCULATED)
        return TM_RETURN_VALUE_OK;

    // set current selected situation
    if (m->setSituation(rabVars->curThreadNo, curState.layerNumber, curState.stateNumber)) {
        // calc value of situation
        m->letTheTreeGrow(&root, rabVars, m->depthOfFullTree, SKV_VALUE_GAME_LOST, SKV_VALUE_GAME_WON);
    } else {
        // should not occur, because already tested by plyInfo == PLYINFO_VALUE_UNCALCULATED
        MessageBoxW(nullptr, L"This event should never occur. if (!m->setSituation())", L"ERROR", MB_OK);
    }
    return TM_RETURN_VALUE_OK;
}

//-----------------------------------------------------------------------------
// letTheTreeGrow()
//
//-----------------------------------------------------------------------------
void MiniMax::letTheTreeGrow(Knot* knot, RunAlphaBetaVars* rabVars, unsigned int tilLevel, float alpha, float beta)
{
    // Locals
    void* pPossibilities;
    unsigned int* idPossibility;
    unsigned int layerNumber = 0; // layer number of current state
    unsigned int stateNumber = 0; // state number of current state
    unsigned int maxWonfreqValuesSubMoves = 0;

    // standard values
    knot->branches = &rabVars->branchArray[(depthOfFullTree - tilLevel) * maxNumBranches];
    knot->numPossibilities = 0;
    knot->bestBranch = 0;
    knot->bestMoveId = 0;
    knot->isOpponentLevel = getOpponentLevel(rabVars->curThreadNo);
    knot->plyInfo = PLYINFO_VALUE_UNCALCULATED;
    knot->shortValue = SKV_VALUE_GAME_DRAWN;
    knot->floatValue = (float)knot->shortValue;

    // evaluate situation, mustn't occur while calculating database
    if (tilLevel == 0) {
        if (calcDatabase) {
            // if tilLevel is equal zero it means that memory is gone out, since each recursive step needs memory
            PRINT(0, this, "ERROR: tilLevel == 0");
            knot->shortValue = SKV_VALUE_INVALID;
            knot->plyInfo = PLYINFO_VALUE_INVALID;
            knot->floatValue = (float)knot->shortValue;
            falseOrStop();
        } else {
            getValueOfSituation(rabVars->curThreadNo, knot->floatValue, knot->shortValue);
        }
        // investigate branches
    } else {
        // get layer and state number of current state and look if short knot value can be found in database or in an array
        if (alphaBetaTryDataBase(knot, rabVars, tilLevel, layerNumber, stateNumber))
            return;

        // get number of possibilities
        idPossibility = getPossibilities(rabVars->curThreadNo,
            &knot->numPossibilities,
            &knot->isOpponentLevel,
            &pPossibilities);

        // unable to move
        if (knot->numPossibilities == 0) {
            // if unable to move a final state is reached
            knot->plyInfo = 0;
            getValueOfSituation(rabVars->curThreadNo, knot->floatValue, knot->shortValue);
            if (tilLevel == depthOfFullTree - 1)
                rabVars->freqValuesSubMoves[knot->shortValue]++;

            // if unable to move an invalid state was reached if nobody has won
            if (calcDatabase && knot->shortValue == SKV_VALUE_GAME_DRAWN) {
                knot->shortValue = SKV_VALUE_INVALID;
                knot->plyInfo = PLYINFO_VALUE_INVALID;
                knot->floatValue = (float)knot->shortValue;
            }

            // movement is possible
        } else {
            // move, letTreeGrow, undo
            alphaBetaTryPossibilities(knot,
                rabVars,
                tilLevel,
                idPossibility,
                pPossibilities,
                maxWonfreqValuesSubMoves,
                alpha,
                beta);

            // calculate value of knot - its the value of the best branch
            alphaBetaCalcKnotValue(knot);

            // calculate ply info
            alphaBetaCalcPlyInfo(knot);

            // select randomly one of the best moves, if they are equivalent
            alphaBetaChooseBestMove(knot, rabVars, tilLevel, idPossibility, maxWonfreqValuesSubMoves);
        }

        // save value and best branch into database and set value as valid
        if (calcDatabase && hFileShortKnotValues && hFilePlyInfo)
            alphaBetaSaveInDatabase(rabVars->curThreadNo,
                layerNumber,
                stateNumber,
                knot->shortValue,
                knot->plyInfo,
                knot->isOpponentLevel);
    }
}

//-----------------------------------------------------------------------------
// alphaBetaTryDataBase()
//
// 1 - Determines layerNumber and stateNumber for the given game situation.
// 2 - Look into database if knot value and ply info are already calculated. If so sets knot->shortValue, knot->floatValue and knot->plyInfo.
// CAUTION: knot->isOpponentLevel must be set and valid.
//-----------------------------------------------------------------------------
bool MiniMax::alphaBetaTryDataBase(Knot* knot,
    RunAlphaBetaVars* rabVars,
    unsigned int tilLevel,
    unsigned int& layerNumber,
    unsigned int& stateNumber)
{
    // locals
    bool invalidLayerOrStateNumber;
    bool subLayerInDatabaseAndCompleted;
    TwoBit shortKnotValue = SKV_VALUE_INVALID;
    PlyInfoVarType plyInfo = PLYINFO_VALUE_UNCALCULATED;

    // use database ?
    if (hFilePlyInfo != nullptr && hFileShortKnotValues != nullptr && (calcDatabase || layerInDatabase)) {
        // situation already existed in database ?
        readKnotValueFromDatabase(rabVars->curThreadNo,
            layerNumber,
            stateNumber,
            shortKnotValue,
            invalidLayerOrStateNumber,
            subLayerInDatabaseAndCompleted);
        readPlyInfoFromDatabase(layerNumber, stateNumber, plyInfo);

        // it was possible to achieve an invalid state using move(),
        // so the original state was an invalid one
        if ((tilLevel < depthOfFullTree && invalidLayerOrStateNumber) || (tilLevel < depthOfFullTree && shortKnotValue == SKV_VALUE_INVALID && subLayerInDatabaseAndCompleted) || (tilLevel < depthOfFullTree && shortKnotValue == SKV_VALUE_INVALID && plyInfo != PLYINFO_VALUE_UNCALCULATED)) { // version 22: replaced:  curCalculatedLayer == layerNumber && knot->plyInfo != PLYINFO_VALUE_UNCALCULATED)) {
            knot->shortValue = SKV_VALUE_INVALID;
            knot->plyInfo = PLYINFO_VALUE_INVALID;
            knot->floatValue = (float)knot->shortValue;
            return true;
        }

        // print out put, if not calculating database, but requesting a knot value
        if (shortKnotValue != SKV_VALUE_INVALID && tilLevel == depthOfFullTree && !calcDatabase && subLayerInDatabaseAndCompleted) {
            PRINT(2, this, "This state is marked as " << ((shortKnotValue == SKV_VALUE_GAME_WON) ? "WON" : ((shortKnotValue == SKV_VALUE_GAME_LOST) ? "LOST" : ((shortKnotValue == SKV_VALUE_GAME_DRAWN) ? "DRAW" : "INVALID"))) << endl);
        }

        // when knot value is valid then return best branch
        if ((calcDatabase && tilLevel < depthOfFullTree && shortKnotValue != SKV_VALUE_INVALID && plyInfo != PLYINFO_VALUE_UNCALCULATED) || (!calcDatabase && tilLevel < depthOfFullTree - 1 && shortKnotValue != SKV_VALUE_INVALID)) {
            // switch if is not opponent level
            if (knot->isOpponentLevel)
                knot->shortValue = skvPerspectiveMatrix[shortKnotValue][PL_TO_MOVE_UNCHANGED];
            else
                knot->shortValue = skvPerspectiveMatrix[shortKnotValue][PL_TO_MOVE_CHANGED];
            knot->floatValue = (float)knot->shortValue;
            knot->plyInfo = plyInfo;
            return true;
        }
    }
    return false;
}

//-----------------------------------------------------------------------------
// alphaBetaTryPossibilities()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaTryPossibilities(Knot* knot, RunAlphaBetaVars* rabVars, unsigned int tilLevel, unsigned int* idPossibility, void* pPossibilities, unsigned int& maxWonfreqValuesSubMoves, float& alpha, float& beta)
{
    // locals
    void* pBackup;
    unsigned int curPoss;

    for (curPoss = 0; curPoss < knot->numPossibilities; curPoss++) {
        // output
        if (tilLevel == depthOfFullTree && !calcDatabase) {
            printMoveInformation(rabVars->curThreadNo, idPossibility[curPoss], pPossibilities);
            rabVars->freqValuesSubMoves[SKV_VALUE_INVALID] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_LOST] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_DRAWN] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON] = 0;
        }

        // move
        move(rabVars->curThreadNo, idPossibility[curPoss], knot->isOpponentLevel, &pBackup, pPossibilities);

        // recursive call
        letTheTreeGrow(&knot->branches[curPoss], rabVars, tilLevel - 1, alpha, beta);

        // undo move
        undo(rabVars->curThreadNo, idPossibility[curPoss], knot->isOpponentLevel, pBackup, pPossibilities);

        // output
        if (tilLevel == depthOfFullTree && !calcDatabase) {
            rabVars->freqValuesSubMovesBranchWon[curPoss] = rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON];
            if (rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON] > maxWonfreqValuesSubMoves && knot->branches[curPoss].shortValue == SKV_VALUE_GAME_DRAWN) {
                maxWonfreqValuesSubMoves = rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON];
            }
            if (hFileShortKnotValues != nullptr && layerInDatabase) {
                storeValueOfMove(rabVars->curThreadNo, idPossibility[curPoss], pPossibilities, knot->branches[curPoss].shortValue, rabVars->freqValuesSubMoves, knot->branches[curPoss].plyInfo);
                PRINT(0, this, "\t: " << ((knot->branches[curPoss].shortValue == SKV_VALUE_GAME_WON) ? "WON" : ((knot->branches[curPoss].shortValue == SKV_VALUE_GAME_LOST) ? "LOST" : ((knot->branches[curPoss].shortValue == SKV_VALUE_GAME_DRAWN) ? "DRAW" : "INVALID"))) << endl);
            } else {
                PRINT(0, this, "\t: " << knot->branches[curPoss].floatValue << endl);
            }
        } else if (tilLevel == depthOfFullTree - 1 && !calcDatabase) {
            rabVars->freqValuesSubMoves[knot->branches[curPoss].shortValue]++;
        }

        // don't use alpha beta if using database
        if (hFileShortKnotValues != nullptr && calcDatabase)
            continue;

        if (hFileShortKnotValues != nullptr && tilLevel + 1 >= depthOfFullTree)
            continue;

        // alpha beta algorithm
        if (!knot->isOpponentLevel) {
            if (knot->branches[curPoss].floatValue >= beta) {
                knot->numPossibilities = curPoss + 1;
                break;
            } else if (knot->branches[curPoss].floatValue > alpha) {
                alpha = knot->branches[curPoss].floatValue;
            }
        } else {
            if (knot->branches[curPoss].floatValue <= alpha) {
                knot->numPossibilities = curPoss + 1;
                break;
            } else if (knot->branches[curPoss].floatValue < beta) {
                beta = knot->branches[curPoss].floatValue;
            }
        }
    }

    // let delete pPossibilities
    if (tilLevel < depthOfFullTree) {
        deletePossibilities(rabVars->curThreadNo, pPossibilities);
    } else {
        pRootPossibilities = pPossibilities;
    }
}

//-----------------------------------------------------------------------------
// alphaBetaCalcKnotValue()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaCalcKnotValue(Knot* knot)
{
    // locals
    float maxValue = knot->branches[0].floatValue;
    unsigned int maxBranch = 0;
    unsigned int i;

    // opponent tries to minimize the value
    if (knot->isOpponentLevel) {
        for (i = 1; i < knot->numPossibilities; i++) {
            // version 21: it should be impossible that knot->shortValue is equal SKV_VALUE_INVALID
            if (/*knot->shortValue != SKV_VALUE_INVALID && */ knot->branches[i].floatValue < maxValue) {
                maxValue = knot->branches[i].floatValue;
                maxBranch = i;
            }
        }
        // maximize the value
    } else {
        for (i = 1; i < knot->numPossibilities; i++) {
            if (/*knot->shortValue != SKV_VALUE_INVALID && */ knot->branches[i].floatValue > maxValue) {
                maxValue = knot->branches[i].floatValue;
                maxBranch = i;
            }
        }
    }

    // set value
    knot->floatValue = knot->branches[maxBranch].floatValue;
    knot->shortValue = knot->branches[maxBranch].shortValue;
}

//-----------------------------------------------------------------------------
// alphaBetaCalcPlyInfo()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaCalcPlyInfo(Knot* knot)
{
    // locals
    unsigned int i;
    unsigned int maxBranch;
    PlyInfoVarType maxPlyInfo;
    TwoBit shortKnotValue;

    //
    if (knot->shortValue == SKV_VALUE_GAME_DRAWN) {
        knot->plyInfo = PLYINFO_VALUE_DRAWN;
    } else if (knot->shortValue == SKV_VALUE_INVALID) {
        knot->plyInfo = PLYINFO_VALUE_INVALID;
    } else {
        // calculate value of knot
        shortKnotValue = (knot->isOpponentLevel) ? skvPerspectiveMatrix[knot->shortValue][PL_TO_MOVE_UNCHANGED] : knot->shortValue;
        maxPlyInfo = (shortKnotValue == SKV_VALUE_GAME_WON) ? PLYINFO_VALUE_DRAWN : 0;
        maxBranch = 0;

        // when current knot is a won state
        if (shortKnotValue == SKV_VALUE_GAME_WON) {
            for (i = 0; i < knot->numPossibilities; i++) {
                // invert knot value if necessary
                shortKnotValue = (knot->branches[i].isOpponentLevel) ? skvPerspectiveMatrix[knot->branches[i].shortValue][PL_TO_MOVE_UNCHANGED] : knot->branches[i].shortValue;

                // take the minimum of the lost states (negative float values)
                if ((knot->branches[i].plyInfo < maxPlyInfo && shortKnotValue == SKV_VALUE_GAME_LOST && knot->isOpponentLevel != knot->branches[i].isOpponentLevel)

                    // after this move the same player will continue, so take the minimum of the won states
                    || (knot->branches[i].plyInfo < maxPlyInfo && shortKnotValue == SKV_VALUE_GAME_WON && knot->isOpponentLevel == knot->branches[i].isOpponentLevel)) {
                    maxPlyInfo = knot->branches[i].plyInfo;
                    maxBranch = i;
                }
            }

            // current state is a lost state
        } else {
            for (i = 0; i < knot->numPossibilities; i++) {
                // invert knot value if necessary
                shortKnotValue = (knot->branches[i].isOpponentLevel) ? skvPerspectiveMatrix[knot->branches[i].shortValue][PL_TO_MOVE_UNCHANGED] : knot->branches[i].shortValue;

                // after this move the same player will continue, so take the maximum of the lost states (negative float values)
                if ((knot->branches[i].plyInfo > maxPlyInfo && shortKnotValue == SKV_VALUE_GAME_WON && knot->isOpponentLevel != knot->branches[i].isOpponentLevel)

                    // take the maximum of the won states, since that's the longest path
                    || (knot->branches[i].plyInfo > maxPlyInfo && shortKnotValue == SKV_VALUE_GAME_LOST && knot->isOpponentLevel == knot->branches[i].isOpponentLevel)) {
                    maxPlyInfo = knot->branches[i].plyInfo;
                    maxBranch = i;
                }
            }
        }

        // set value
        knot->plyInfo = knot->branches[maxBranch].plyInfo + 1;
    }
}

//-----------------------------------------------------------------------------
// alphaBetaChooseBestMove()
// select randomly one of the best moves, if they are equivalent
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaChooseBestMove(Knot* knot, RunAlphaBetaVars* rabVars, unsigned int tilLevel, unsigned int* idPossibility, unsigned int maxWonfreqValuesSubMoves)
{
    // locals
    float dif;
    unsigned int numBestChoices = 0;
    unsigned int* bestBranches = new unsigned int[maxNumBranches];
    unsigned int i;
    unsigned int maxBranch;

    // select randomly one of the best moves, if they are equivalent
    if (tilLevel == depthOfFullTree && !calcDatabase) {
        // check every possible move
        for (numBestChoices = 0, i = 0; i < knot->numPossibilities; i++) {
            // use information in database
            if (layerInDatabase && hFileShortKnotValues != nullptr) {
                // selected move with equal knot value
                if (knot->branches[i].shortValue == knot->shortValue) {
                    // best move lead to drawn state
                    if (knot->shortValue == SKV_VALUE_GAME_DRAWN) {
                        if (maxWonfreqValuesSubMoves == rabVars->freqValuesSubMovesBranchWon[i]) {
                            bestBranches[numBestChoices] = i;
                            numBestChoices++;
                        }

                        // best move lead to lost or won state
                    } else {
                        if (knot->plyInfo == knot->branches[i].plyInfo + 1) {
                            bestBranches[numBestChoices] = i;
                            numBestChoices++;
                        }
                    }
                }
                // conventional mini-max algorithm
            } else {
                dif = knot->branches[i].floatValue - knot->floatValue;
                dif = (dif > 0) ? dif : -1.0f * dif;
                if (dif < FPKV_THRESHOLD) {
                    bestBranches[numBestChoices] = i;
                    numBestChoices++;
                }
            }
        }
    }

    // set value
    maxBranch = (numBestChoices ? bestBranches[rand() % numBestChoices] : 0);
    knot->bestMoveId = idPossibility[maxBranch];
    knot->bestBranch = maxBranch;
    SAFE_DELETE_ARRAY(bestBranches);
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
