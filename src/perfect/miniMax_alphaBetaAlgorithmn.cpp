/*********************************************************************
    miniMax_alphaBetaAlgorithmn.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
bool MiniMax::calcKnotValuesByAlphaBeta(uint32_t layerNumber)
{
    // locals
    AlphaBetaGlobalVars alphaBetaVars(this, layerNumber); // multi-thread vars

    // Version 10:
    PRINT(1, this,
          "*** Calculate layer " << layerNumber
                                 << " by alpha-beta-algorithmn ***" << endl);
    curCalcActionId = MM_ACTION_PERFORM_ALPHA_BETA;

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

    // update layerStats[].wonStateCount, etc.
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    showLayerStats(layerNumber);

    return true;
}

//-----------------------------------------------------------------------------
// saveKnotValueInDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaSaveInDatabase(uint32_t threadNo, uint32_t layerNumber,
                                      uint32_t stateNumber, TwoBit knotValue,
                                      PlyInfoVarType plyValue, bool invertValue)
{
    // locals
    uint32_t *symStateNumbers = nullptr;
    uint32_t symStateCount;

    // invert value ?
    if (knotValue > SKV_VALUE_GAME_WON) {
        while (true) {
        }
    }
    if (invertValue)
        knotValue = skvPerspectiveMatrix[knotValue][PL_TO_MOVE_UNCHANGED];

    // get numbers of symmetric states
    getSymStateNumWithDoubles(threadNo, &symStateCount, &symStateNumbers);

    // save
    saveKnotValueInDatabase(layerNumber, stateNumber, knotValue);
    savePlyInfoInDatabase(layerNumber, stateNumber, plyValue);

    // save value for all symmetric states
    for (uint32_t i = 0; i < symStateCount; i++) {
        // get state number
        const uint32_t sysStateNumber = symStateNumbers[i];

        // don't save orig state twice
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
bool MiniMax::initAlphaBeta(AlphaBetaGlobalVars &alphaBetaVars)
{
#ifndef __clang__ // TODO(calcitem)

    // true if the initialization info is already available in a file
    bool initAlreadyDone = false;

    stringstream ssInvArrayDir;
    stringstream ssInvArrayFilePath;

    // set current processed layer number
    PRINT(1, this,
          endl << "  *** Signing of invalid states for layer "
               << alphaBetaVars.layerNumber << " ("
               << getOutputInfo(alphaBetaVars.layerNumber) << ") which has "
               << layerStats[alphaBetaVars.layerNumber].knotsInLayer
               << " knots ***");

    // file names
    ssInvArrayDir.str("");
    ssInvArrayDir << fileDir << (fileDir.size() ? "\\" : "") << "invalidStates";
    ssInvArrayFilePath.str("");
    ssInvArrayFilePath << fileDir << (fileDir.size() ? "\\" : "")
                       << "invalidStates\\invalidStatesOfLayer"
                       << alphaBetaVars.layerNumber << ".dat";

    // does initialization file exist ?
    CreateDirectoryA(ssInvArrayDir.str().c_str(), nullptr);
    BufferedFile *invalidArray = new BufferedFile(
        threadManager.getThreadCount(), FILE_BUFFER_SIZE,
        ssInvArrayFilePath.str().c_str());

    if (invalidArray->getFileSize() ==
        static_cast<LONGLONG>(
            layerStats[alphaBetaVars.layerNumber].knotsInLayer)) {
        PRINT(2, this,
              "  Loading invalid states from file: "
                  << ssInvArrayFilePath.str());
        initAlreadyDone = true;
    }

    // prepare params
    stateProcessedCount = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID] = 0;
    ThreadManager::ThreadVarsArray tva(
        threadManager.getThreadCount(),
        (InitAlphaBetaVars &)InitAlphaBetaVars(this, &alphaBetaVars,
                                               alphaBetaVars.layerNumber,
                                               invalidArray, initAlreadyDone));

    // process each state in the current layer
    switch (threadManager.execParallelLoop(
        initAlphaBetaThreadProc, tva.getPointerToArray(), tva.getArraySize(),
        TM_SCHED_STATIC, 0,
        layerStats[alphaBetaVars.layerNumber].knotsInLayer - 1, 1)) {
    case TM_RETVAL_OK:
        break;
    case TM_RETVAL_EXEC_CANCELLED:
        PRINT(0, this,
              "\n****************************************\nMain thread: "
              "Exec cancelled by "
              "user!\n****************************************\n");
        SAFE_DELETE(invalidArray);
        return false;
    default:
    case TM_RETVAL_INVALID_PARAM:
    case TM_RETVAL_UNEXPECTED_ERROR:
        PRINT(0, this,
              "\n****************************************\nMain thread: "
              "Invalid "
              "or unexpected "
              "param!\n****************************************\n");
        return falseOrStop();
    }

    // reduce and delete thread specific data
    tva.reduce();
    if (stateProcessedCount <
        layerStats[alphaBetaVars.layerNumber].knotsInLayer) {
        SAFE_DELETE(invalidArray);
        return falseOrStop();
    }
    invalidArray->flushBuffers();
    SAFE_DELETE(invalidArray);

    // when init file was created new then save it now
    PRINT(2, this,
          "    Saved initialized states to file: " << ssInvArrayFilePath.str());

    // show statistics
    PRINT(2, this,
          "    won     states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON]);
    PRINT(2, this,
          "    lost    states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST]);
    PRINT(2, this,
          "    draw    states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);
    PRINT(2, this,
          "    invalid states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID]);
#endif // __clang__

    return true;
}

//-----------------------------------------------------------------------------
// initAlphaBetaThreadProc()
// set short knot value to SKV_VALUE_INVALID, ply info to PLYINFO_VALUE_INVALID
// and knotAlreadyCalculated to true or false, whether setSituation() returns
// true or false
//-----------------------------------------------------------------------------
DWORD MiniMax::initAlphaBetaThreadProc(void *pParam, uint32_t index)
{
    // locals
    const auto iabVars = static_cast<InitAlphaBetaVars *>(pParam);
    MiniMax *m = iabVars->pMiniMax;
    float floatValue;         // dummy variable for calls of getSituationValue()
    StateAdress curState;     // current state counter for loops
    TwoBit curStateValue = 0; // for calls of getSituationValue()
    PlyInfoVarType plyInfo;   // depends on the curStateValue

    curState.layerNumber = iabVars->layerNumber;
    curState.stateNumber = index;
    iabVars->statesProcessed++;

    // print status
    if (iabVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
        PRINT(2, m,
              "Already initialized "
                  << m->stateProcessedCount << " of "
                  << m->layerStats[curState.layerNumber].knotsInLayer
                  << " states");
    }

    // layer initialization already done ? if so, then read from file
    if (iabVars->initAlreadyDone) {
        if (!iabVars->bufferedFile->readBytes(
                iabVars->curThreadNo, index * sizeof(TwoBit), sizeof(TwoBit),
                (unsigned char *)&curStateValue)) {
            PRINT(0, m, "ERROR: initArray->takeBytes() failed");
            return m->falseOrStop();
        }
        // initialization not done
    } else {
        // set current selected situation
        if (!m->setSituation(iabVars->curThreadNo, curState.layerNumber,
                             curState.stateNumber)) {
            curStateValue = SKV_VALUE_INVALID;
        } else {
            // get value of current situation
            m->getSituationValue(iabVars->curThreadNo, floatValue,
                                 curStateValue);
        }
    }

    // calculate ply info
    if (curStateValue == SKV_VALUE_GAME_WON ||
        curStateValue == SKV_VALUE_GAME_LOST) {
        plyInfo = 0;
    } else if (curStateValue == SKV_VALUE_INVALID) {
        plyInfo = PLYINFO_VALUE_INVALID;
    } else {
        plyInfo = PLYINFO_VALUE_UNCALCULATED;
    }

    // save short knot value & ply info
    // (m->alphaBetaSaveInDatabase(iabVars->curThreadNo, curStateValue, plyInfo,
    // false); ???)
    m->saveKnotValueInDatabase(curState.layerNumber, curState.stateNumber,
                               curStateValue);
    m->savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber,
                             plyInfo);

    // write data to file
    if (!iabVars->initAlreadyDone) {
        if (!iabVars->bufferedFile->writeBytes(
                iabVars->curThreadNo, index * sizeof(TwoBit), sizeof(TwoBit),
                (unsigned char *)&curStateValue)) {
            PRINT(0, m, "ERROR: bufferedFile->writeBytes failed!");
            return m->falseOrStop();
        }
    }

    iabVars->statsValueCounter[curStateValue]++;

    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// runAlphaBeta()
//
//-----------------------------------------------------------------------------
bool MiniMax::runAlphaBeta(AlphaBetaGlobalVars &alphaBetaVars)
{
#ifndef __clang__ // TODO(calcitem)

    // prepare params
    PRINT(1, this,
          "  Calculate layer " << alphaBetaVars.layerNumber
                               << " with function letTheTreeGrow():");
    stateProcessedCount = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
    alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID] = 0;
    ThreadManager::ThreadVarsArray tva(
        threadManager.getThreadCount(),
        (RunAlphaBetaVars &)RunAlphaBetaVars(this, &alphaBetaVars,
                                             alphaBetaVars.layerNumber));

    // so far no multi-threading implemented
    threadManager.setThreadCount(1);

    // process each state in the current layer
    switch (threadManager.execParallelLoop(
        runAlphaBetaThreadProc, tva.getPointerToArray(), tva.getArraySize(),
        TM_SCHED_STATIC, 0,
        layerStats[alphaBetaVars.layerNumber].knotsInLayer - 1, 1)) {
    case TM_RETVAL_OK:
        break;
    case TM_RETVAL_EXEC_CANCELLED:
        PRINT(0, this,
              "\n****************************************\nMain thread: "
              "Execution cancelled by "
              "user!\n****************************************\n");
        return false;
    default:
    case TM_RETVAL_INVALID_PARAM:
    case TM_RETVAL_UNEXPECTED_ERROR:
        return falseOrStop();
    }

    threadManager.setThreadCount(4);

    // reduce and delete thread specific data
    tva.reduce();
    if (stateProcessedCount <
        layerStats[alphaBetaVars.layerNumber].knotsInLayer)
        return falseOrStop();

    // show statistics
    PRINT(2, this,
          "    won     states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_WON]);
    PRINT(2, this,
          "    lost    states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_LOST]);
    PRINT(2, this,
          "    draw    states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);
    PRINT(2, this,
          "    invalid states: "
              << alphaBetaVars.statsValueCounter[SKV_VALUE_INVALID]);
#endif // __clang__

    return true;
}

//-----------------------------------------------------------------------------
// runAlphaBetaThreadProc()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::runAlphaBetaThreadProc(void *pParam, uint32_t index)
{
    // locals
    const auto rabVars = static_cast<RunAlphaBetaVars *>(pParam);
    MiniMax *m = rabVars->pMiniMax;
    StateAdress curState;   // current state counter for loops
    Knot root;              //
    PlyInfoVarType plyInfo; // depends on the curStateValue

    curState.layerNumber = rabVars->layerNumber;
    curState.stateNumber = index;
    rabVars->statesProcessed++;

    // print status
    if (rabVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
        PRINT(2, m,
              "  Processed " << m->stateProcessedCount << " of "
                             << m->layerStats[curState.layerNumber].knotsInLayer
                             << " states");
    }

    // Version 10: state already calculated? if so leave.
    m->readPlyInfoFromDatabase(curState.layerNumber, curState.stateNumber,
                               plyInfo);

    if (plyInfo != PLYINFO_VALUE_UNCALCULATED)
        return TM_RETVAL_OK;

    // set current selected situation
    if (m->setSituation(rabVars->curThreadNo, curState.layerNumber,
                        curState.stateNumber)) {
        // calculate value of situation
        m->letTheTreeGrow(&root, rabVars, m->fullTreeDepth, SKV_VALUE_GAME_LOST,
                          SKV_VALUE_GAME_WON);
    } else {
        // should not occur, because already tested by plyInfo ==
        // PLYINFO_VALUE_UNCALCULATED
        MessageBoxW(nullptr,
                    L"This event should never occur. if (!m->setSituation())",
                    L"ERROR", MB_OK);
    }
    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// letTheTreeGrow()
//
//-----------------------------------------------------------------------------
void MiniMax::letTheTreeGrow(Knot *knot, RunAlphaBetaVars *rabVars,
                             uint32_t tilLevel, float alpha, float beta)
{
    // Locals
    void *pPossibilities;
    uint32_t *idPossibility;
    uint32_t layerNumber = 0; // layer number of current state
    uint32_t stateNumber = 0; // state number of current state
    uint32_t maxWonfreqValuesSubMoves = 0;

    // standard values
    knot->branches =
        &rabVars->branchArray[(fullTreeDepth - tilLevel) * maxNumBranches];
    knot->possibilityCount = 0;
    knot->bestBranch = 0;
    knot->bestMoveId = 0;
    knot->isOpponentLevel = getOpponentLevel(rabVars->curThreadNo);
    knot->plyInfo = PLYINFO_VALUE_UNCALCULATED;
    knot->shortValue = SKV_VALUE_GAME_DRAWN;
    knot->floatValue = static_cast<float>(knot->shortValue);

    // evaluate situation, mustn't occur while calculating database
    if (tilLevel == 0) {
        if (calcDatabase) {
            // if tilLevel is equal zero it means that memory is gone out, since
            // each recursive step needs memory
            PRINT(0, this, "ERROR: tilLevel == 0");
            knot->shortValue = SKV_VALUE_INVALID;
            knot->plyInfo = PLYINFO_VALUE_INVALID;
            knot->floatValue = static_cast<float>(knot->shortValue);
            falseOrStop();
        } else {
            getSituationValue(rabVars->curThreadNo, knot->floatValue,
                              knot->shortValue);
        }
        // investigate branches
    } else {
        // get layer and state number of current state and look if short knot
        // value can be found in database or in an array
        if (alphaBetaTryDatabase(knot, rabVars, tilLevel, layerNumber,
                                 stateNumber))
            return;

        // get number of possibilities
        idPossibility = getPossibilities(rabVars->curThreadNo,
                                         &knot->possibilityCount,
                                         &knot->isOpponentLevel,
                                         &pPossibilities);

        // unable to move
        if (knot->possibilityCount == 0) {
            // if unable to move a final state is reached
            knot->plyInfo = 0;
            getSituationValue(rabVars->curThreadNo, knot->floatValue,
                              knot->shortValue);
            if (tilLevel == fullTreeDepth - 1)
                rabVars->freqValuesSubMoves[knot->shortValue]++;

            // if unable to move an invalid state was reached if nobody has won
            if (calcDatabase && knot->shortValue == SKV_VALUE_GAME_DRAWN) {
                knot->shortValue = SKV_VALUE_INVALID;
                knot->plyInfo = PLYINFO_VALUE_INVALID;
                knot->floatValue = static_cast<float>(knot->shortValue);
            }

            // movement is possible
        } else {
            // move, letTreeGrow, undo
            alphaBetaTryPossibilities(knot, rabVars, tilLevel, idPossibility,
                                      pPossibilities, maxWonfreqValuesSubMoves,
                                      alpha, beta);

            // calculate value of knot - its the value of the best branch
            alphaBetaCalcKnotValue(knot);

            // calculate ply info
            alphaBetaCalcPlyInfo(knot);

            // select randomly one of the best moves, if they are equivalent
            alphaBetaChooseBestMove(knot, rabVars, tilLevel, idPossibility,
                                    maxWonfreqValuesSubMoves);
        }

        // save value and best branch into database and set value as valid
        if (calcDatabase && hFileShortKnotValues && hFilePlyInfo)
            alphaBetaSaveInDatabase(rabVars->curThreadNo, layerNumber,
                                    stateNumber, knot->shortValue,
                                    knot->plyInfo, knot->isOpponentLevel);
    }
}

//-----------------------------------------------------------------------------
// alphaBetaTryDatabase()
//
// 1 - Determines layerNumber and stateNumber for the given game situation.
// 2 - Look into database if knot value and ply info are already calculated. If
// so sets knot->shortValue, knot->floatValue and knot->plyInfo. CAUTION:
// knot->isOpponentLevel must be set and valid.
//-----------------------------------------------------------------------------
bool MiniMax::alphaBetaTryDatabase(Knot *knot, const RunAlphaBetaVars *rabVars,
                                   uint32_t tilLevel, uint32_t &layerNumber,
                                   uint32_t &stateNumber)
{
    // locals
    bool invalidLayerOrStateNumber;
    bool subLayerInDatabaseAndCompleted;
    TwoBit shortKnotValue = SKV_VALUE_INVALID;
    PlyInfoVarType plyInfo = PLYINFO_VALUE_UNCALCULATED;

    // use database ?
    if (hFilePlyInfo != nullptr && hFileShortKnotValues != nullptr &&
        (calcDatabase || layerInDatabase)) {
        // situation already existed in database ?
        readKnotValueFromDatabase(rabVars->curThreadNo, layerNumber,
                                  stateNumber, shortKnotValue,
                                  invalidLayerOrStateNumber,
                                  subLayerInDatabaseAndCompleted);
        readPlyInfoFromDatabase(layerNumber, stateNumber, plyInfo);

        // it was possible to achieve an invalid state using move(),
        // so the orig state was an invalid one
        if ((tilLevel < fullTreeDepth && invalidLayerOrStateNumber) ||
            (tilLevel < fullTreeDepth && shortKnotValue == SKV_VALUE_INVALID &&
             subLayerInDatabaseAndCompleted) ||
            (tilLevel < fullTreeDepth && shortKnotValue == SKV_VALUE_INVALID &&
             plyInfo != PLYINFO_VALUE_UNCALCULATED)) { // version 22: replaced:
            // curCalculatedLayer ==
            // layerNumber &&
            // knot->plyInfo !=
            // PLYINFO_VALUE_UNCALCULATED))
            // {
            knot->shortValue = SKV_VALUE_INVALID;
            knot->plyInfo = PLYINFO_VALUE_INVALID;
            knot->floatValue = static_cast<float>(knot->shortValue);
            return true;
        }

        // print out put, if not calculating database, but requesting a knot
        // value
        if (shortKnotValue != SKV_VALUE_INVALID && tilLevel == fullTreeDepth &&
            !calcDatabase && subLayerInDatabaseAndCompleted) {
            PRINT(2, this,
                  "This state is marked as "
                      << (shortKnotValue == SKV_VALUE_GAME_WON ?
                              "WON" :
                              (shortKnotValue == SKV_VALUE_GAME_LOST ?
                                   "LOST" :
                                   (shortKnotValue == SKV_VALUE_GAME_DRAWN ?
                                        "DRAW" :
                                        "INVALID")))
                      << endl);
        }

        // when knot value is valid then return best branch
        if ((calcDatabase && tilLevel < fullTreeDepth &&
             shortKnotValue != SKV_VALUE_INVALID &&
             plyInfo != PLYINFO_VALUE_UNCALCULATED) ||
            (!calcDatabase && tilLevel < fullTreeDepth - 1 &&
             shortKnotValue != SKV_VALUE_INVALID)) {
            // switch if is not opponent level
            if (knot->isOpponentLevel) {
                knot->shortValue =
                    skvPerspectiveMatrix[shortKnotValue][PL_TO_MOVE_UNCHANGED];
            } else {
                knot->shortValue =
                    skvPerspectiveMatrix[shortKnotValue][PL_TO_MOVE_CHANGED];
            }
            knot->floatValue = static_cast<float>(knot->shortValue);
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
void MiniMax::alphaBetaTryPossibilities(Knot *knot, RunAlphaBetaVars *rabVars,
                                        uint32_t tilLevel,
                                        const uint32_t *idPossibility,
                                        void *pPossibilities,
                                        uint32_t &maxWonfreqValuesSubMoves,
                                        float &alpha, float &beta)
{
    // locals
    void *pBackup;

    for (uint32_t curPoss = 0; curPoss < knot->possibilityCount; curPoss++) {
        // output
        if (tilLevel == fullTreeDepth && !calcDatabase) {
            printMoveInfo(rabVars->curThreadNo, idPossibility[curPoss],
                          pPossibilities);
            rabVars->freqValuesSubMoves[SKV_VALUE_INVALID] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_LOST] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_DRAWN] = 0;
            rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON] = 0;
        }

        // move
        move(rabVars->curThreadNo, idPossibility[curPoss],
             knot->isOpponentLevel, &pBackup, pPossibilities);

        // recursive call
        letTheTreeGrow(&knot->branches[curPoss], rabVars, tilLevel - 1, alpha,
                       beta);

        // undo move
        undo(rabVars->curThreadNo, idPossibility[curPoss],
             knot->isOpponentLevel, pBackup, pPossibilities);

        // output
        if (tilLevel == fullTreeDepth && !calcDatabase) {
            rabVars->freqValuesSubMovesBranchWon[curPoss] =
                rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON];
            if (rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON] >
                    maxWonfreqValuesSubMoves &&
                knot->branches[curPoss].shortValue == SKV_VALUE_GAME_DRAWN) {
                maxWonfreqValuesSubMoves =
                    rabVars->freqValuesSubMoves[SKV_VALUE_GAME_WON];
            }
            if (hFileShortKnotValues != nullptr && layerInDatabase) {
                storeMoveValue(rabVars->curThreadNo, idPossibility[curPoss],
                               pPossibilities,
                               knot->branches[curPoss].shortValue,
                               rabVars->freqValuesSubMoves,
                               knot->branches[curPoss].plyInfo);
                PRINT(0, this,
                      "\t: " << (knot->branches[curPoss].shortValue ==
                                         SKV_VALUE_GAME_WON ?
                                     "WON" :
                                     (knot->branches[curPoss].shortValue ==
                                              SKV_VALUE_GAME_LOST ?
                                          "LOST" :
                                          (knot->branches[curPoss].shortValue ==
                                                   SKV_VALUE_GAME_DRAWN ?
                                               "DRAW" :
                                               "INVALID")))
                             << endl);
            } else {
                PRINT(0, this,
                      "\t: " << knot->branches[curPoss].floatValue << endl);
            }
        } else if (tilLevel == fullTreeDepth - 1 && !calcDatabase) {
            rabVars->freqValuesSubMoves[knot->branches[curPoss].shortValue]++;
        }

        // don't use alpha beta if using database
        if (hFileShortKnotValues != nullptr && calcDatabase) {
            continue;
        }

        if (hFileShortKnotValues != nullptr && tilLevel + 1 >= fullTreeDepth) {
            continue;
        }

        // alpha beta algorithm
        if (!knot->isOpponentLevel) {
            if (knot->branches[curPoss].floatValue >= beta) {
                knot->possibilityCount = curPoss + 1;
                break;
            }
            if (knot->branches[curPoss].floatValue > alpha) {
                alpha = knot->branches[curPoss].floatValue;
            }
        } else {
            if (knot->branches[curPoss].floatValue <= alpha) {
                knot->possibilityCount = curPoss + 1;
                break;
            }
            if (knot->branches[curPoss].floatValue < beta) {
                beta = knot->branches[curPoss].floatValue;
            }
        }
    }

    // let delete pPossibilities
    if (tilLevel < fullTreeDepth) {
        deletePossibilities(rabVars->curThreadNo, pPossibilities);
    } else {
        pRootPossibilities = pPossibilities;
    }
}

//-----------------------------------------------------------------------------
// alphaBetaCalcKnotValue()
//
//-----------------------------------------------------------------------------
void MiniMax::alphaBetaCalcKnotValue(Knot *knot)
{
    // locals
    float maxValue = knot->branches[0].floatValue;
    uint32_t maxBranch = 0;
    uint32_t i;

    // opponent tries to minimize the value
    if (knot->isOpponentLevel) {
        for (i = 1; i < knot->possibilityCount; i++) {
            // version 21: it should be impossible that knot->shortValue is
            // equal SKV_VALUE_INVALID
            if (/* knot->shortValue != SKV_VALUE_INVALID && */ knot->branches[i]
                    .floatValue < maxValue) {
                maxValue = knot->branches[i].floatValue;
                maxBranch = i;
            }
        }
        // maximize the value
    } else {
        for (i = 1; i < knot->possibilityCount; i++) {
            if (/* knot->shortValue != SKV_VALUE_INVALID && */ knot->branches[i]
                    .floatValue > maxValue) {
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
void MiniMax::alphaBetaCalcPlyInfo(Knot *knot) const
{
    // locals
    uint32_t i;
    uint32_t maxBranch;
    PlyInfoVarType maxPlyInfo;
    TwoBit shortKnotValue;

    if (knot->shortValue == SKV_VALUE_GAME_DRAWN) {
        knot->plyInfo = PLYINFO_VALUE_DRAWN;
    } else if (knot->shortValue == SKV_VALUE_INVALID) {
        knot->plyInfo = PLYINFO_VALUE_INVALID;
    } else {
        // calculate value of knot
        shortKnotValue =
            knot->isOpponentLevel ?
                skvPerspectiveMatrix[knot->shortValue][PL_TO_MOVE_UNCHANGED] :
                knot->shortValue;
        maxPlyInfo = shortKnotValue == SKV_VALUE_GAME_WON ?
                         PLYINFO_VALUE_DRAWN :
                         0;
        maxBranch = 0;

        // when current knot is a won state
        if (shortKnotValue == SKV_VALUE_GAME_WON) {
            for (i = 0; i < knot->possibilityCount; i++) {
                // invert knot value if necessary
                shortKnotValue =
                    knot->branches[i].isOpponentLevel ?
                        skvPerspectiveMatrix[knot->branches[i].shortValue]
                                            [PL_TO_MOVE_UNCHANGED] :
                        knot->branches[i].shortValue;

                // take the minimum of the lost states (negative float values)
                if ((knot->branches[i].plyInfo < maxPlyInfo &&
                     shortKnotValue == SKV_VALUE_GAME_LOST &&
                     knot->isOpponentLevel != knot->branches[i].isOpponentLevel)

                    // after this move the same player will continue, so take
                    // the minimum of the won states
                    || (knot->branches[i].plyInfo < maxPlyInfo &&
                        shortKnotValue == SKV_VALUE_GAME_WON &&
                        knot->isOpponentLevel ==
                            knot->branches[i].isOpponentLevel)) {
                    maxPlyInfo = knot->branches[i].plyInfo;
                    maxBranch = i;
                }
            }

            // current state is a lost state
        } else {
            for (i = 0; i < knot->possibilityCount; i++) {
                // invert knot value if necessary
                shortKnotValue =
                    (knot->branches[i].isOpponentLevel) ?
                        skvPerspectiveMatrix[knot->branches[i].shortValue]
                                            [PL_TO_MOVE_UNCHANGED] :
                        knot->branches[i].shortValue;

                // after this move the same player will continue, so take the
                // maximum of the lost states (negative float values)
                if ((knot->branches[i].plyInfo > maxPlyInfo &&
                     shortKnotValue == SKV_VALUE_GAME_WON &&
                     knot->isOpponentLevel != knot->branches[i].isOpponentLevel)

                    // take the maximum of the won states, since that's the
                    // longest path
                    || (knot->branches[i].plyInfo > maxPlyInfo &&
                        shortKnotValue == SKV_VALUE_GAME_LOST &&
                        knot->isOpponentLevel ==
                            knot->branches[i].isOpponentLevel)) {
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
void MiniMax::alphaBetaChooseBestMove(Knot *knot,
                                      const RunAlphaBetaVars *rabVars,
                                      uint32_t tilLevel,
                                      const uint32_t *idPossibility,
                                      uint32_t maxWonfreqValuesSubMoves) const
{
    // locals
    float dif;
    uint32_t nBestChoices = 0;
    auto bestBranches = new uint32_t[maxNumBranches];
    std::memset(bestBranches, 0, sizeof(uint32_t) * maxNumBranches);
    uint32_t i;

    // select randomly one of the best moves, if they are equivalent
    if (tilLevel == fullTreeDepth && !calcDatabase) {
        // check every possible move
        for (nBestChoices = 0, i = 0; i < knot->possibilityCount; i++) {
            // use info in database
            if (layerInDatabase && hFileShortKnotValues != nullptr) {
                // selected move with equal knot value
                if (knot->branches[i].shortValue == knot->shortValue) {
                    // best move lead to drawn state
                    if (knot->shortValue == SKV_VALUE_GAME_DRAWN) {
                        if (maxWonfreqValuesSubMoves ==
                            rabVars->freqValuesSubMovesBranchWon[i]) {
                            bestBranches[nBestChoices] = i;
                            nBestChoices++;
                        }

                        // best move lead to lost or won state
                    } else {
                        if (knot->plyInfo == knot->branches[i].plyInfo + 1) {
                            bestBranches[nBestChoices] = i;
                            nBestChoices++;
                        }
                    }
                }
                // conventional mini-max algorithm
            } else {
                dif = knot->branches[i].floatValue - knot->floatValue;
                dif = dif > 0 ? dif : -1.0f * dif;
                if (dif < FPKV_THRESHOLD) {
                    bestBranches[nBestChoices] = i;
                    nBestChoices++;
                }
            }
        }
    }

    // set value
    const uint32_t maxBranch = nBestChoices ?
                                   bestBranches[rand() % nBestChoices] :
                                   0;
    knot->bestMoveId = idPossibility[maxBranch];
    knot->bestBranch = maxBranch;
    SAFE_DELETE_ARRAY(bestBranches);
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
