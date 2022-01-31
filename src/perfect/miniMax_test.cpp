/*********************************************************************
    miniMax_test.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

//-----------------------------------------------------------------------------
// testLayer()
//
//-----------------------------------------------------------------------------
bool MiniMax::testLayer(uint32_t layerNumber)
{
    // Locals
    uint32_t curThreadNo;

    // database open?
    if (hFileShortKnotValues == nullptr || hFilePlyInfo == nullptr) {
        PRINT(0, this, "ERROR: Database file not open!");
        return falseOrStop();
    }

    // output
    PRINT(1, this,
          endl << "*** Test each state in layer: " << layerNumber << " ***");
    PRINT(1, this, (getOutputInfo(layerNumber)));

    // prepare params for multithreading
    skvfHeader.completed = false;
    layerInDatabase = false;
    stateProcessedCount = 0;
    curCalculatedLayer = layerNumber;
    curCalcActionId = MM_ACTION_TESTING_LAYER;
    auto tlVars = new TestLayersVars[threadManager.getThreadCount()];
    std::memset(tlVars, 0,
                sizeof(TestLayersVars) * threadManager.getThreadCount());

    for (curThreadNo = 0; curThreadNo < threadManager.getThreadCount();
         curThreadNo++) {
        tlVars[curThreadNo].curThreadNo = curThreadNo;
        tlVars[curThreadNo].pMiniMax = this;
        tlVars[curThreadNo].layerNumber = layerNumber;
        tlVars[curThreadNo].statesProcessed = 0;
        tlVars[curThreadNo].subValueInDatabase = new TwoBit[maxNumBranches];
        std::memset(tlVars[curThreadNo].subValueInDatabase, 0,
                    sizeof(TwoBit) * maxNumBranches);
        tlVars[curThreadNo].subPlyInfos = new PlyInfoVarType[maxNumBranches];
        std::memset(tlVars[curThreadNo].subPlyInfos, 0,
                    sizeof(PlyInfoVarType) * maxNumBranches);
        tlVars[curThreadNo].hasCurPlayerChanged = new bool[maxNumBranches];
        std::memset(tlVars[curThreadNo].hasCurPlayerChanged, 0,
                    sizeof(bool) * maxNumBranches);
    }

    // process each state in the current layer
    const uint32_t returnValue = threadManager.execParallelLoop(
        testLayerThreadProc, tlVars, sizeof(TestLayersVars), TM_SCHED_STATIC, 0,
        layerStats[layerNumber].knotsInLayer - 1, 1);
    switch (returnValue) {
    case TM_RETVAL_OK:
    case TM_RETVAL_EXEC_CANCELLED:
        // reduce and delete thread specific data
        for (stateProcessedCount = 0, curThreadNo = 0;
             curThreadNo < threadManager.getThreadCount(); curThreadNo++) {
            stateProcessedCount += tlVars[curThreadNo].statesProcessed;
            SAFE_DELETE_ARRAY(tlVars[curThreadNo].subValueInDatabase);
            SAFE_DELETE_ARRAY(tlVars[curThreadNo].hasCurPlayerChanged);
            SAFE_DELETE_ARRAY(tlVars[curThreadNo].subPlyInfos);
        }
        SAFE_DELETE_ARRAY(tlVars);
        if (returnValue == TM_RETVAL_EXEC_CANCELLED) {
            PRINT(0, this, "Main thread: Execution cancelled by user");
            return false; // ... better would be to return a cancel-specific
                          // value
        }

        break;

    default:
    case TM_RETVAL_INVALID_PARAM:
    case TM_RETVAL_UNEXPECTED_ERROR:
        return falseOrStop();
    }

    // layer is not ok
    if (stateProcessedCount < layerStats[layerNumber].knotsInLayer) {
        PRINT(0, this, "DATABASE ERROR IN LAYER " << layerNumber);
        return falseOrStop();
        // layer is ok
    } else {
        PRINT(1, this, " TEST PASSED !" << endl << endl);
        return true;
    }
}

//-----------------------------------------------------------------------------
// testLayerThreadProc()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::testLayerThreadProc(void *pParam, unsigned index)
{
    // locals
    const auto tlVars = static_cast<TestLayersVars *>(pParam);
    MiniMax *m = tlVars->pMiniMax;
    const uint32_t layerNumber = tlVars->layerNumber;
    const uint32_t stateNumber = index;
    const uint32_t threadNo = tlVars->curThreadNo;
    TwoBit *subValueInDatabase = tlVars->subValueInDatabase;
    PlyInfoVarType *subPlyInfos = tlVars->subPlyInfos;
    bool *hasCurPlayerChanged = tlVars->hasCurPlayerChanged;
    TwoBit shortValueInDatabase;
    PlyInfoVarType plyTillCurStateCount;
    TwoBit shortValueInGame;
    float floatValueInGame;
    PlyInfoVarType min, max;
    uint32_t possibilityCount;
    uint32_t i, j;
    uint32_t tmpStateNumber, tmpLayerNumber;
    void *pPossibilities;
    void *pBackup;
    bool isOpponentLevel;
    bool invalidLayerOrStateNumber;
    bool layerInDatabaseAndCompleted;

    // output
    tlVars->statesProcessed++;
    if (tlVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
        PRINT(0, m,
              m->stateProcessedCount << " states of "
                                     << m->layerStats[layerNumber].knotsInLayer
                                     << " tested");
    }

    // situation already existend in database ?
    m->readKnotValueFromDatabase(layerNumber, stateNumber,
                                 shortValueInDatabase);
    m->readPlyInfoFromDatabase(layerNumber, stateNumber, plyTillCurStateCount);

    // prepare the situation
    if (!m->setSituation(threadNo, layerNumber, stateNumber)) {
        // when situation cannot be constructed then state must be marked as
        // invalid in database
        if (shortValueInDatabase != SKV_VALUE_INVALID ||
            plyTillCurStateCount != PLYINFO_VALUE_INVALID) {
            PRINT(0, m,
                  "ERROR: DATABASE ERROR IN LAYER "
                      << layerNumber << " AND STATE " << stateNumber
                      << ": Could not set situation, but value is not "
                         "invalid.");
            goto errorInDatabase;
        }
        return TM_RETVAL_OK;
    }

    // debug info
    if (m->verbosity > 5) {
        PRINT(5, m, "layer: " << layerNumber << " state: " << stateNumber);
        m->printBoard(threadNo, shortValueInDatabase);
    }

    // get number of possibilities
    m->setOpponentLevel(threadNo, false);
    const uint32_t *idPossibility = m->getPossibilities(
        threadNo, &possibilityCount, &isOpponentLevel, &pPossibilities);

    // unable to move
    if (possibilityCount == 0) {
        // get ingame value
        m->getSituationValue(threadNo, floatValueInGame, shortValueInGame);

        // compare database with game
        if (shortValueInDatabase != shortValueInGame ||
            plyTillCurStateCount != 0) {
            PRINT(0, m,
                  "ERROR: DATABASE ERROR IN LAYER "
                      << layerNumber << " AND STATE " << stateNumber
                      << ": Number of possibilities is zero, but knot value is "
                         "not invalid or ply info equal zero.");
            goto errorInDatabase;
        }
        if (shortValueInDatabase == SKV_VALUE_INVALID) {
            PRINT(0, m,
                  "ERROR: DATABASE ERROR IN LAYER "
                      << layerNumber << " AND STATE " << stateNumber
                      << ": Number of possibilities is zero, but knot value is "
                         "invalid.");
            goto errorInDatabase;
        }
    } else {
        // check each possible move
        for (i = 0; i < possibilityCount; i++) {
            // move
            m->move(threadNo, idPossibility[i], isOpponentLevel, &pBackup,
                    pPossibilities);

            // get database value
            m->readKnotValueFromDatabase(threadNo, tmpLayerNumber,
                                         tmpStateNumber, subValueInDatabase[i],
                                         invalidLayerOrStateNumber,
                                         layerInDatabaseAndCompleted);
            m->readPlyInfoFromDatabase(tmpLayerNumber, tmpStateNumber,
                                       subPlyInfos[i]);
            hasCurPlayerChanged[i] = m->getOpponentLevel(threadNo) == true;

            // debug info
            if (m->verbosity > 5) {
                PRINT(5, m,
                      "layer: " << tmpLayerNumber
                                << " state: " << tmpStateNumber << " value: "
                                << static_cast<int>(subValueInDatabase[i]));
                m->printBoard(threadNo, subValueInDatabase[i]);
            }

            // if layer or state number is invalid then value of testes state
            // must be invalid
            if (invalidLayerOrStateNumber &&
                shortValueInDatabase != SKV_VALUE_INVALID) {
                PRINT(0, m,
                      "ERROR: DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Succeeding state  has invalid layer ("
                          << tmpLayerNumber << ")or state number ("
                          << tmpStateNumber
                          << "), but tested state is not marked as invalid.");
                goto errorInDatabase;
            }

#if 0
            // BUG: Does not work because, layer 101 is calculated before 105,
            // although removing a piece does need this jump.
            if (!layerInDatabaseAndCompleted) {
                PRINT(0, m,
                      "ERROR: DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Succeding state " << tmpStateNumber
                          << " in an uncalculated layer " << tmpLayerNumber
                          << "! Calc layer first!");
                goto errorInDatabase;
            }
#endif

            // undo move
            m->undo(threadNo, idPossibility[i], isOpponentLevel, pBackup,
                    pPossibilities);
        }

        // value possible?
        switch (shortValueInDatabase) {
        case SKV_VALUE_GAME_LOST:
            // all possible moves must be lost for the current player or won for
            // the opponent
            for (i = 0; i < possibilityCount; i++) {
                if (subValueInDatabase[i] != (hasCurPlayerChanged[i] ?
                                                  SKV_VALUE_GAME_WON :
                                                  SKV_VALUE_GAME_LOST) &&
                    subValueInDatabase[i] != SKV_VALUE_INVALID) {
                    PRINT(0, m,
                          "ERROR: DATABASE ERROR IN LAYER "
                              << layerNumber << " AND STATE " << stateNumber
                              << ": All possible moves must be lost for the "
                                 "current player or won for the opponent");
                    goto errorInDatabase;
                }
            }
            // not all options can be invalid
            for (j = 0, i = 0; i < possibilityCount; i++) {
                if (subValueInDatabase[i] == SKV_VALUE_INVALID) {
                    j++;
                }
            }
            if (j == possibilityCount) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ". Not all options can be invalid");
            }
            // ply info must be max(subPlyInfos[]+1)
            max = 0;
            for (i = 0; i < possibilityCount; i++) {
                if (subValueInDatabase[i] == (hasCurPlayerChanged[i] ?
                                                  SKV_VALUE_GAME_WON :
                                                  SKV_VALUE_GAME_LOST)) {
                    if (subPlyInfos[i] + 1 > max) {
                        max = subPlyInfos[i] + 1;
                    }
                }
            }
            if (plyTillCurStateCount > PLYINFO_VALUE_DRAWN) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Knot value is LOST, but nPliesTillCurState "
                             "is "
                             "bigger than PLYINFO_MAX_VALUE.");
                goto errorInDatabase;
            }
            if (plyTillCurStateCount != max) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Number of needed plies is not maximal for LOST "
                             "state.");
                goto errorInDatabase;
            }
            break;

        case SKV_VALUE_GAME_WON:
            // at least one possible move must be lost for the opponent or won
            // for the current player
            for (i = 0; i < possibilityCount; i++) {
#if 0
                if (subValueInDatabase[i] == SKV_VALUE_INVALID) {
                    PRINT(0, m,
                          "DATABASE ERROR IN LAYER "
                              << layerNumber << " AND STATE " << stateNumber
                              << ": At least one possible move must be lost "
                                 "for the opponent or won for the current "
                                 "player. But subValueInDatabase[i] == "
                                 "SKV_VALUE_INVALID.");
                    goto errorInDatabase;
                }
#endif
                if (subValueInDatabase[i] == (hasCurPlayerChanged[i] ?
                                                  SKV_VALUE_GAME_LOST :
                                                  SKV_VALUE_GAME_WON))
                    i = possibilityCount;
            }
            if (i == possibilityCount) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": At least one possible move must be lost for "
                             "the "
                             "opponent or won for the current player.");
                goto errorInDatabase;
            }

            // ply info must be min(subPlyInfos[]+1)
            min = PLYINFO_VALUE_DRAWN;
            for (i = 0; i < possibilityCount; i++) {
                if (subValueInDatabase[i] == (hasCurPlayerChanged[i] ?
                                                  SKV_VALUE_GAME_LOST :
                                                  SKV_VALUE_GAME_WON)) {
                    if (subPlyInfos[i] + 1 < min) {
                        min = subPlyInfos[i] + 1;
                    }
                }
            }
            if (plyTillCurStateCount > PLYINFO_VALUE_DRAWN) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Knot value is WON, but nPliesTillCurState is "
                             "bigger than PLYINFO_MAX_VALUE.");
                goto errorInDatabase;
            }
            if (plyTillCurStateCount != min) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Number of needed plies is "
                             "not minimal for WON state.");
                goto errorInDatabase;
            }
            break;

        case SKV_VALUE_GAME_DRAWN:
            // all possible moves must be won for the opponent, lost for the
            // current player or drawn
            for (j = 0, i = 0; i < possibilityCount; i++) {
#if 0
                if (subValueInDatabase[i] == SKV_VALUE_INVALID) {
                    PRINT(0, m,
                          "DATABASE ERROR IN LAYER "
                              << layerNumber << " AND STATE " << stateNumber
                              << ": All possible moves must be won for the "
                                 "opponent, lost for the current player or "
                                 "drawn. But subValueInDatabase[i] == "
                                 "SKV_VALUE_INVALID.");
                    goto errorInDatabase;
                }
#endif
                if (subValueInDatabase[i] != (hasCurPlayerChanged[i] ?
                                                  SKV_VALUE_GAME_WON :
                                                  SKV_VALUE_GAME_LOST) &&
                    subValueInDatabase[i] != SKV_VALUE_GAME_DRAWN &&
                    subValueInDatabase[i] != SKV_VALUE_INVALID) {
                    PRINT(0, m,
                          "DATABASE ERROR IN LAYER "
                              << layerNumber << " AND STATE " << stateNumber
                              << ": All possible moves must be won for the "
                                 "opponent, lost for the current player or "
                                 "drawn.");
                    goto errorInDatabase;
                }
                if (subValueInDatabase[i] == SKV_VALUE_GAME_DRAWN)
                    j = 1;
            }

            // at least one succeeding state must be drawn
            if (j == 0) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": At least one succeeding state must be drawn.");
                goto errorInDatabase;
            }

            // ply info must also be drawn
            if (plyTillCurStateCount != PLYINFO_VALUE_DRAWN) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Knot value is drawn but ply info is not!");
                goto errorInDatabase;
            }
            break;

        case SKV_VALUE_INVALID:
            // if setSituation() returned true but state value is invalid, then
            // all following states must be invalid
            for (i = 0; i < possibilityCount; i++) {
                if (subValueInDatabase[i] != SKV_VALUE_INVALID)
                    break;
            }
            if (i != possibilityCount) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": If setSituation() returned true but state "
                             "value "
                             "is invalid, then all following states must be "
                             "invalid.");
                goto errorInDatabase;
            }
            // ply info must also be invalid
            if (plyTillCurStateCount != PLYINFO_VALUE_INVALID) {
                PRINT(0, m,
                      "DATABASE ERROR IN LAYER "
                          << layerNumber << " AND STATE " << stateNumber
                          << ": Knot value is invalid but ply info is not!");
                goto errorInDatabase;
            }
            break;
        }
    }

    return TM_RETVAL_OK;

errorInDatabase:
    // terminate all threads
    return TM_RETVAL_TERMINATE_ALL_THREADS;
}

//-----------------------------------------------------------------------------
// testIfSymStatesHaveSameValue()
//
//-----------------------------------------------------------------------------
bool MiniMax::testIfSymStatesHaveSameValue(uint32_t layerNumber)
{
    // Locals
    const uint32_t threadNo = 0;
    TwoBit shortValueInDatabase;
    TwoBit shortValueOfSymState;
    PlyInfoVarType nPliesTillCurState;
    PlyInfoVarType nPliesTillSymState;
    uint32_t stateNumber = 0;
    uint32_t *symStateNumbers = nullptr;
    uint32_t nSymStates;

    // database open?
    if (hFileShortKnotValues == nullptr || hFilePlyInfo == nullptr) {
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

    // test if each state has sym states with the same value
    PRINT(1, this,
          endl << "testIfSymStatesHaveSameValue - TEST EACH STATE IN "
                  "LAYER: "
               << layerNumber);
    PRINT(1, this, getOutputInfo(layerNumber));
    skvfHeader.completed = false;

    for (layerInDatabase = false, stateNumber = 0;
         stateNumber < layerStats[layerNumber].knotsInLayer; stateNumber++) {
        // output
        if (stateNumber % OUTPUT_EVERY_N_STATES == 0)
            PRINT(1, this,
                  stateNumber << " states of "
                              << layerStats[layerNumber].knotsInLayer
                              << " tested");

        // situation already existend in database ?
        readKnotValueFromDatabase(layerNumber, stateNumber,
                                  shortValueInDatabase);
        readPlyInfoFromDatabase(layerNumber, stateNumber, nPliesTillCurState);

        // prepare the situation
        if (!setSituation(threadNo, layerNumber, stateNumber)) {
            // when situation cannot be constructed then state must be marked as
            // invalid in database
            if (shortValueInDatabase != SKV_VALUE_INVALID ||
                nPliesTillCurState != PLYINFO_VALUE_INVALID) {
                goto errorInDatabase;
            }

            continue;
        }

        // get numbers of sym states
        getSymStateNumWithDoubles(threadNo, &nSymStates, &symStateNumbers);

        // save value for all sym states
        for (uint32_t i = 0; i < nSymStates; i++) {
            readKnotValueFromDatabase(layerNumber, symStateNumbers[i],
                                      shortValueOfSymState);
            readPlyInfoFromDatabase(layerNumber, symStateNumbers[i],
                                    nPliesTillSymState);

            if (shortValueOfSymState != shortValueInDatabase ||
                nPliesTillCurState != nPliesTillSymState) {
                PRINT(2, this,
                      "current tested state "
                          << stateNumber << " has value "
                          << static_cast<int>(shortValueInDatabase));
                setSituation(threadNo, layerNumber, stateNumber);
                printBoard(threadNo, shortValueInDatabase);

                PRINT(1, this, "");
                PRINT(1, this,
                      "sym state " << symStateNumbers[i] << " has value "
                                   << static_cast<int>(shortValueOfSymState));
                setSituation(threadNo, layerNumber, symStateNumbers[i]);
                printBoard(threadNo, shortValueOfSymState);

                setSituation(threadNo, layerNumber, stateNumber);
            }
        }
    }

    // layer is ok
    PRINT(0, this, "TEST PASSED !");

    return true;

errorInDatabase:

    // layer is not ok
    if (layerNumber)
        PRINT(0, this,
              "DATABASE ERROR IN LAYER " << layerNumber << " AND STATE "
                                         << stateNumber);

    return falseOrStop();
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
