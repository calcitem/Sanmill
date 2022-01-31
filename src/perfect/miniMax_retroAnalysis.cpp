/*********************************************************************
    miniMax_retroAnalysis.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
s\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

//-----------------------------------------------------------------------------
// calcKnotValuesByRetroAnalysis()
//
// The COUNT-ARRAY is the main element of the algorithmn. It contains the number
// of succeeding states for the drawn gamestates, whose short knot value has to
// be determined. If all succeeding states (branches representing possible
// moves) are for example won than, a state can be marked as lost, since no
// branch will lead to a drawn or won situation any more. Each time the short
// knot value of a game state has been determined, the state will be added to
// 'statesToProcess'. This list is like a queue of states, which still has to be
// processed.
//-----------------------------------------------------------------------------
bool MiniMax::calcKnotValuesByRetroAnalysis(const vector<uint32_t> &layersToCalc)
{
    // locals
    bool abortCalc = false;
    uint32_t curLayer; // Counter variable
    uint32_t threadNo;
    stringstream ssLayers;
    retroAnalysisGlobalVars retroVars;

    // init retro vars
    retroVars.thread.resize(threadManager.getThreadCount());
    for (threadNo = 0; threadNo < threadManager.getThreadCount(); threadNo++) {
        retroVars.thread[threadNo].statesToProcess.resize(PLYINFO_EXP_VALUE,
                                                          nullptr);
        retroVars.thread[threadNo].stateToProcessCount = 0;
        retroVars.thread[threadNo].threadNo = threadNo;
    }
    retroVars.countArrays.resize(layersToCalc.size(), nullptr);
    retroVars.layerInitialized.resize(skvfHeader.LayerCount, false);
    retroVars.layersToCalculate = layersToCalc;
    retroVars.pMiniMax = this;

    for (retroVars.totalKnotCount = 0, retroVars.knotToCalcCount = 0,
        curLayer = 0;
         curLayer < layersToCalc.size(); curLayer++) {
        retroVars.knotToCalcCount += layerStats[layersToCalc[curLayer]]
                                         .knotsInLayer;
        retroVars.totalKnotCount += layerStats[layersToCalc[curLayer]]
                                        .knotsInLayer;
        retroVars.layerInitialized[layersToCalc[curLayer]] = true;
        for (uint32_t curSubLayer = 0;
             curSubLayer <
             layerStats[layersToCalc[curLayer]].succeedingLayerCount;
             curSubLayer++) {
            if (retroVars.layerInitialized[layerStats[layersToCalc[curLayer]]
                                               .succeedingLayers[curSubLayer]])
                continue;
            else
                retroVars.layerInitialized[layerStats[layersToCalc[curLayer]]
                                               .succeedingLayers[curSubLayer]] =
                    true;
            retroVars.totalKnotCount +=
                layerStats[layerStats[layersToCalc[curLayer]]
                               .succeedingLayers[curSubLayer]]
                    .knotsInLayer;
        }
    }

    retroVars.layerInitialized.assign(skvfHeader.LayerCount, false);

    // output & filenames
    for (curLayer = 0; curLayer < layersToCalc.size(); curLayer++)
        ssLayers << " " << layersToCalc[curLayer];
    PRINT(0, this,
          "*** Calculate layers" << ssLayers.str() << " by retro analysis ***");

    // initialization
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    if (!initRetroAnalysis(retroVars)) {
        abortCalc = true;
        goto freeMem;
    }

    // prepare count arrays
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    if (!prepareCountArrays(retroVars)) {
        abortCalc = true;
        goto freeMem;
    }

    // stop here if only preparing layer
    if (onlyPrepareLayer)
        goto freeMem;

    // iteration
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2 << endl);
    if (!performRetroAnalysis(retroVars)) {
        abortCalc = true;
        goto freeMem;
    }

    // show output
    PRINT(2, this, "  Bytes in memory: " << memoryUsed2);
    for (curLayer = 0; curLayer < layersToCalc.size(); curLayer++) {
        showLayerStats(layersToCalc[curLayer]);
    }
    PRINT(2, this, "");

    // free memory
freeMem:
    for (threadNo = 0; threadNo < threadManager.getThreadCount(); threadNo++) {
        for (uint32_t plyCounter = 0;
             plyCounter < retroVars.thread[threadNo].statesToProcess.size();
             plyCounter++) {
            SAFE_DELETE(retroVars.thread[threadNo].statesToProcess[plyCounter]);
        }
    }

    for (curLayer = 0; curLayer < layersToCalc.size(); curLayer++) {
        if (retroVars.countArrays[curLayer] != nullptr) {
            memoryUsed2 -= layerStats[layersToCalc[curLayer]].knotsInLayer *
                           sizeof(CountArrayVarType);
            arrayInfos.removeArray(
                layersToCalc[curLayer], ArrayInfo::arrayType_countArray,
                layerStats[layersToCalc[curLayer]].knotsInLayer *
                    sizeof(CountArrayVarType),
                0);
        }
        SAFE_DELETE_ARRAY(retroVars.countArrays[curLayer]);
    }

    if (!abortCalc)
        PRINT(2, this, "  Bytes in memory: " << memoryUsed2);

    return !abortCalc;
}

//-----------------------------------------------------------------------------
// initRetroAnalysis()
// The state values for all game situations in the database are marked as
// invalid, as undecided, as won or as  lost by using the function
// getSituationValue().
//-----------------------------------------------------------------------------
bool MiniMax::initRetroAnalysis(retroAnalysisGlobalVars &retroVars)
{
#ifndef __clang__ // TODO(calcitem)

    // locals

    // path of the working dir
    stringstream ssInitArrayPath;

    // filename corresponding to a cyclic array file which is used for storage
    stringstream ssInitArrayFilePath;

    // true if the initialization info is already available in a file
    bool initAlreadyDone = false;

    // process each layer
    for (uint32_t curLayerId = 0; // current processed layer within
                                  // 'layersToCalculate'
         curLayerId < retroVars.layersToCalculate.size(); curLayerId++) {
        // set current processed layer number
        const uint32_t layerNumber = retroVars.layersToCalculate[curLayerId];
        curCalcActionId = MM_ACTION_INIT_RETRO_ANAL;
        PRINT(1, this,
              endl << "  *** Initialization of layer " << layerNumber << " ("
                   << getOutputInfo(layerNumber) << ") which has "
                   << layerStats[layerNumber].knotsInLayer << " knots ***");

        // file names
        ssInitArrayPath.str("");
        ssInitArrayPath << fileDir << (fileDir.size() ? "\\" : "")
                        << "initLayer";
        ssInitArrayFilePath.str("");
        ssInitArrayFilePath << fileDir << (fileDir.size() ? "\\" : "")
                            << "initLayer\\initLayer" << layerNumber << ".dat";

        // does initialization file exist ?
        CreateDirectoryA(ssInitArrayPath.str().c_str(), nullptr);
        BufferedFile *initArray = new BufferedFile(
            threadManager.getThreadCount(), FILE_BUFFER_SIZE,
            ssInitArrayFilePath.str().c_str());
        if (initArray->getFileSize() ==
            static_cast<LONGLONG>(layerStats[layerNumber].knotsInLayer)) {
            PRINT(2, this,
                  "    Loading init states from file: "
                      << ssInitArrayFilePath.str());
            initAlreadyDone = true;
        }

        // don't add layers twice
        if (retroVars.layerInitialized[layerNumber])
            continue;

        retroVars.layerInitialized[layerNumber] = true;

        // prepare params
        stateProcessedCount = 0;
        retroVars.statsValueCounter[SKV_VALUE_GAME_WON] = 0;
        retroVars.statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
        retroVars.statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
        retroVars.statsValueCounter[SKV_VALUE_INVALID] = 0;
        ThreadManager::ThreadVarsArray tva(
            threadManager.getThreadCount(),
            (InitRetroAnalysisVars &)InitRetroAnalysisVars(
                this, &retroVars, layerNumber, initArray, initAlreadyDone));

        // process each state in the current layer
        switch (threadManager.execParallelLoop(
            initRetroAnalysisThreadProc, tva.getPointerToArray(),
            tva.getArraySize(), TM_SCHED_STATIC, 0,
            layerStats[layerNumber].knotsInLayer - 1, 1)) {
        case TM_RETVAL_OK:
            break;
        case TM_RETVAL_EXEC_CANCELLED:
            PRINT(0, this,
                  "\n****************************************\nMain thread: "
                  "Execution cancelled by "
                  "user!\n****************************************\n");
            SAFE_DELETE(initArray);
            return false;
        default:
        case TM_RETVAL_INVALID_PARAM:
        case TM_RETVAL_UNEXPECTED_ERROR:
            return falseOrStop();
        }

        // reduce and delete thread specific data
        tva.reduce();
        initAlreadyDone = false;
        initArray->flushBuffers();
        SAFE_DELETE(initArray);

        if (stateProcessedCount < layerStats[layerNumber].knotsInLayer)
            return falseOrStop();

        // when init file was created new then save it now
        PRINT(2, this,
              "    Saved initialized states to file: "
                  << ssInitArrayFilePath.str());

        // show statistics
        PRINT(2, this,
              "    won     states: "
                  << retroVars.statsValueCounter[SKV_VALUE_GAME_WON]);
        PRINT(2, this,
              "    lost    states: "
                  << retroVars.statsValueCounter[SKV_VALUE_GAME_LOST]);
        PRINT(2, this,
              "    draw    states: "
                  << retroVars.statsValueCounter[SKV_VALUE_GAME_DRAWN]);
        PRINT(2, this,
              "    invalid states: "
                  << retroVars.statsValueCounter[SKV_VALUE_INVALID]);
    }
#endif // __clang__

    return true;
}

//-----------------------------------------------------------------------------
// initRetroAnalysisParallelSub()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::initRetroAnalysisThreadProc(void *pParam, uint32_t index)
{
    // locals
    const auto iraVars = static_cast<InitRetroAnalysisVars *>(pParam);
    MiniMax *m = iraVars->pMiniMax;
    float floatValue;     // dummy variable for calls of getSituationValue()
    StateAdress curState; // current state counter for loops
    TwoBit curStateValue; // for calls of getSituationValue()

    curState.layerNumber = iraVars->layerNumber;
    curState.stateNumber = index;
    iraVars->statesProcessed++;

    // print status
    if (iraVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
        PRINT(2, m,
              "Already initialized "
                  << m->stateProcessedCount << " of "
                  << m->layerStats[curState.layerNumber].knotsInLayer
                  << " states");
    }

    // layer initialization already done ? if so, then read from file
    if (iraVars->initAlreadyDone) {
        if (!iraVars->bufferedFile->readBytes(
                iraVars->curThreadNo, index * sizeof(TwoBit), sizeof(TwoBit),
                (unsigned char *)&curStateValue)) {
            PRINT(0, m, "ERROR: initArray->takeBytes() failed");
            return m->falseOrStop();
        }

        // initialization not done
    } else {
        // set current selected situation
        if (!m->setSituation(iraVars->curThreadNo, curState.layerNumber,
                             curState.stateNumber)) {
            curStateValue = SKV_VALUE_INVALID;
        } else {
            // get value of current situation
            m->getSituationValue(iraVars->curThreadNo, floatValue,
                                 curStateValue);
        }
    }

    // save init value
    if (curStateValue != SKV_VALUE_INVALID) {
        // save short knot value
        m->saveKnotValueInDatabase(curState.layerNumber, curState.stateNumber,
                                   curStateValue);

        // put in list if state is final
        if (curStateValue == SKV_VALUE_GAME_WON ||
            curStateValue == SKV_VALUE_GAME_LOST) {
            // ply info
            m->savePlyInfoInDatabase(curState.layerNumber, curState.stateNumber,
                                     0);

            // add state to list
            m->addStateToProcessQueue(
                *iraVars->retroVars,
                iraVars->retroVars->thread[iraVars->curThreadNo], 0, &curState);
        }
    }

    // write data to file
    if (!iraVars->initAlreadyDone) {
        // curStateValue should be 2 at index == 1329322
        if (!iraVars->bufferedFile->writeBytes(
                iraVars->curThreadNo, index * sizeof(TwoBit), sizeof(TwoBit),
                (unsigned char *)&curStateValue)) {
            PRINT(0, m, "ERROR: bufferedFile->writeBytes failed!");
            return m->falseOrStop();
        }
    }

    iraVars->statsValueCounter[curStateValue]++;

    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// prepareCountArrays()
//
//-----------------------------------------------------------------------------
bool MiniMax::prepareCountArrays(retroAnalysisGlobalVars &retroVars)
{
    // locals
    uint32_t nKnotsInCurLayer;
    StateAdress curState;           // current state counter for loops
    uint32_t curLayer = 0;          // Counter variable
    CountArrayVarType defValue = 0; // default counter array value
    DWORD dwWritten;
    DWORD dwRead;
    LARGE_INTEGER fileSize;
    HANDLE hFileCountArray = nullptr; // file handle for loading and saving the
                                      // arrays in 'countArrays'
    stringstream ssCountArrayPath;
    stringstream ssCountArrayFilePath;
    stringstream ssLayers;

    // output & filenames
    for (curLayer = 0; curLayer < retroVars.layersToCalculate.size();
         curLayer++)
        ssLayers << " " << retroVars.layersToCalculate[curLayer];

    ssCountArrayPath << fileDir << (fileDir.size() ? "\\" : "") << "countArray";
    ssCountArrayFilePath << fileDir << (fileDir.size() ? "\\" : "")
                         << "countArray\\countArray" << ssLayers.str()
                         << ".dat";
    PRINT(2, this,
          "  *** Prepare count arrays for layers " << ssLayers.str() << " ***"
                                                   << endl);
    curCalcActionId = MM_ACTION_PREPARE_COUNT_ARRAY;

    // prepare count arrays
    CreateDirectoryA(ssCountArrayPath.str().c_str(), nullptr);

    if ((hFileCountArray = CreateFileA(
             ssCountArrayFilePath.str().c_str(), GENERIC_READ | GENERIC_WRITE,
             FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
             FILE_ATTRIBUTE_NORMAL, nullptr)) == INVALID_HANDLE_VALUE) {
        PRINT(0, this,
              "ERROR: Could not open File " << ssCountArrayFilePath.str()
                                            << "!");
        return falseOrStop();
    }

    // allocate memory for count arrays
    for (curLayer = 0; curLayer < retroVars.layersToCalculate.size();
         curLayer++) {
        nKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]]
                               .knotsInLayer;
        retroVars.countArrays[curLayer] =
            new CountArrayVarType[nKnotsInCurLayer];
        std::memset(retroVars.countArrays[curLayer], 0,
                    sizeof(CountArrayVarType) * nKnotsInCurLayer);
        memoryUsed2 += nKnotsInCurLayer * sizeof(CountArrayVarType);
        arrayInfos.addArray(retroVars.layersToCalculate[curLayer],
                            ArrayInfo::arrayType_countArray,
                            nKnotsInCurLayer * sizeof(CountArrayVarType), 0);
    }

    // load file if already existed
    if (GetFileSizeEx(hFileCountArray, &fileSize) &&
        fileSize.QuadPart == retroVars.knotToCalcCount) {
        PRINT(2, this,
              "  Load number of succeeders from file: "
                  << ssCountArrayFilePath.str().c_str());

        for (curLayer = 0; curLayer < retroVars.layersToCalculate.size();
             curLayer++) {
            nKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]]
                                   .knotsInLayer;
            if (!ReadFile(hFileCountArray, retroVars.countArrays[curLayer],
                          nKnotsInCurLayer * sizeof(CountArrayVarType), &dwRead,
                          nullptr))
                return falseOrStop();
            if (dwRead != nKnotsInCurLayer * sizeof(CountArrayVarType))
                return falseOrStop();
        }

        // else calculate number of succedding states
    } else {
        // Set default value 0
        for (curLayer = 0; curLayer < retroVars.layersToCalculate.size();
             curLayer++) {
            nKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]]
                                   .knotsInLayer;
            for (curState.stateNumber = 0;
                 curState.stateNumber < nKnotsInCurLayer;
                 curState.stateNumber++) {
                retroVars.countArrays[curLayer][curState.stateNumber] = defValue;
            }
        }

        // calculate values
        if (!calcNumSucceeders(retroVars)) {
            CloseHandle(hFileCountArray);
            return false;
        }

        // save to file
        for (curLayer = 0, dwWritten = 0;
             curLayer < retroVars.layersToCalculate.size(); curLayer++) {
            nKnotsInCurLayer = layerStats[retroVars.layersToCalculate[curLayer]]
                                   .knotsInLayer;
            if (!WriteFile(hFileCountArray, retroVars.countArrays[curLayer],
                           nKnotsInCurLayer * sizeof(CountArrayVarType),
                           &dwWritten, nullptr))
                return falseOrStop();
            if (dwWritten != nKnotsInCurLayer * sizeof(CountArrayVarType))
                return falseOrStop();
        }

        PRINT(2, this,
              "  Count array saved to file: " << ssCountArrayFilePath.str());
    }

    // finish
    CloseHandle(hFileCountArray);
    return true;
}

//-----------------------------------------------------------------------------
// calcNumSucceeders()
//
//-----------------------------------------------------------------------------
bool MiniMax::calcNumSucceeders(retroAnalysisGlobalVars &retroVars)
{
#ifndef __clang__ // TODO(calcitem)

    // locals
    StateAdress curState;  // current state counter for loops
    StateAdress succState; // current succeeding state counter for loops
    vector succCalculated(skvfHeader.LayerCount, false); //

    // process each layer
    for (uint32_t curLayerId = 0; // current processed layer within
                                  // 'layersToCalculate'
         curLayerId < retroVars.layersToCalculate.size(); curLayerId++) {
        // set current processed layer number
        const uint32_t layerNumber = retroVars.layersToCalculate[curLayerId];
        PRINT(0, this,
              "  *** Calculate number of succeeding states for each state of "
              "layer "
                  << layerNumber << " ***");

        // process layer ...
        if (!succCalculated[layerNumber]) {
            // prepare params for multi threading
            succCalculated[layerNumber] = true;
            stateProcessedCount = 0;
            ThreadManager::ThreadVarsArray tva(
                threadManager.getThreadCount(),
                (AddNumSucceedersVars &)AddNumSucceedersVars(this, &retroVars,
                                                             layerNumber));

            // process each state in the current layer
            switch (threadManager.execParallelLoop(
                addNumSucceedersThreadProc, tva.getPointerToArray(),
                tva.getArraySize(), TM_SCHED_STATIC, 0,
                layerStats[layerNumber].knotsInLayer - 1, 1)) {
            case TM_RETVAL_OK:
                break;
            case TM_RETVAL_EXEC_CANCELLED:
                PRINT(0, this,
                      "\n****************************************\nMain "
                      "thread: "
                      "Execution canceled by "
                      "user!\n****************************************\n");
                return false;
            default:
            case TM_RETVAL_INVALID_PARAM:
            case TM_RETVAL_UNEXPECTED_ERROR:
                return falseOrStop();
            }

            // reduce and delete thread specific data
            tva.reduce();
            if (stateProcessedCount < layerStats[layerNumber].knotsInLayer)
                return falseOrStop();

            // don't calculate layers twice
        } else {
            return falseOrStop();
        }

        // ... and process succeeding layers
        for (curState.layerNumber = 0;
             curState.layerNumber <
             layerStats[layerNumber].succeedingLayerCount;
             curState.layerNumber++) {
            // get current pred. layer
            succState.layerNumber = layerStats[layerNumber]
                                        .succeedingLayers[curState.layerNumber];

            // don't add layers twice
            if (succCalculated[succState.layerNumber])
                continue;

            succCalculated[succState.layerNumber] = true;

            // don't process layers without states
            if (!layerStats[succState.layerNumber].knotsInLayer)
                continue;

            // check all states of pred. layer
            PRINT(2, this,
                  "    - Do the same for the succeeding layer "
                      << static_cast<int>(succState.layerNumber));

            // prepare params for multithreading
            stateProcessedCount = 0;
            ThreadManager::ThreadVarsArray tva(
                threadManager.getThreadCount(),
                (AddNumSucceedersVars &)AddNumSucceedersVars(
                    this, &retroVars, succState.layerNumber));

            // process each state in the current layer
            switch (threadManager.execParallelLoop(
                addNumSucceedersThreadProc, tva.getPointerToArray(),
                tva.getArraySize(), TM_SCHED_STATIC, 0,
                layerStats[succState.layerNumber].knotsInLayer - 1, 1)) {
            case TM_RETVAL_OK:
                break;
            case TM_RETVAL_EXEC_CANCELLED:
                PRINT(0, this,
                      "\n****************************************\nMain "
                      "thread: "
                      "Execution cancelled by "
                      "user!\n****************************************\n");
                return false;
            default:
            case TM_RETVAL_INVALID_PARAM:
            case TM_RETVAL_UNEXPECTED_ERROR:
                return falseOrStop();
            }

            // reduce and delete thread specific data
            tva.reduce();
            if (stateProcessedCount <
                layerStats[succState.layerNumber].knotsInLayer)
                return falseOrStop();
        }
    }
#endif // __clang__

    // everything fine
    return true;
}

//-----------------------------------------------------------------------------
// addNumSucceedersThreadProc()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::addNumSucceedersThreadProc(void *pParam, uint32_t index)
{
    // locals
    const auto ansVars = static_cast<AddNumSucceedersVars *>(pParam);
    MiniMax *m = ansVars->pMiniMax;
    const uint32_t nLayersToCalculate = static_cast<uint32_t>(
        ansVars->retroVars->layersToCalculate.size());
    uint32_t curLayerId; // current processed layer within
                         // 'layersToCalculate'
    uint32_t amountOfPred;
    CountArrayVarType countValue;
    StateAdress predState;
    StateAdress curState;
    TwoBit curStateValue;
    PlyInfoVarType nPlies; // number of plies of the current considered
                           // succeeding state
    bool cuStateAddedToProcessQueue = false;

    curState.layerNumber = ansVars->layerNumber;
    curState.stateNumber = (StateNumberVarType)index;

    // print status
    ansVars->statesProcessed++;
    if (ansVars->statesProcessed % OUTPUT_EVERY_N_STATES == 0) {
        m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
        PRINT(2, m,
              "    Already processed "
                  << m->stateProcessedCount << " of "
                  << m->layerStats[curState.layerNumber].knotsInLayer
                  << " states");
    }

    // invalid state ?
    m->readKnotValueFromDatabase(curState.layerNumber, curState.stateNumber,
                                 curStateValue);
    if (curStateValue == SKV_VALUE_INVALID)
        return TM_RETVAL_OK;

    // set current selected situation
    if (!m->setSituation(ansVars->curThreadNo, curState.layerNumber,
                         curState.stateNumber)) {
        PRINT(0, m, "ERROR: setSituation() returned false!");
        return TM_RETVAL_TERMINATE_ALL_THREADS;
    }

    // get list with state numbers of predecessors
    m->getPredecessors(ansVars->curThreadNo, &amountOfPred, ansVars->predVars);

    // iteration
    for (uint32_t curPred = 0; curPred < amountOfPred; curPred++) {
        // current predecessor
        predState.layerNumber = ansVars->predVars[curPred].predLayerNumbers;
        predState.stateNumber = ansVars->predVars[curPred].predStateNumbers;

        // don't calculate states from layers above yet
        for (curLayerId = 0; curLayerId < nLayersToCalculate; curLayerId++) {
            if (ansVars->retroVars->layersToCalculate[curLayerId] ==
                predState.layerNumber)
                break;
        }

        if (curLayerId == nLayersToCalculate)
            continue;

        // put in list (with states to be processed) if state is final
        if (!cuStateAddedToProcessQueue &&
            (curStateValue == SKV_VALUE_GAME_WON ||
             curStateValue == SKV_VALUE_GAME_LOST)) {
            m->readPlyInfoFromDatabase(curState.layerNumber,
                                       curState.stateNumber, nPlies);
            m->addStateToProcessQueue(
                *ansVars->retroVars,
                ansVars->retroVars->thread[ansVars->curThreadNo], nPlies,
                &curState);
            cuStateAddedToProcessQueue = true;
        }

        // add this state as possible move
        long *pCountValue = reinterpret_cast<long *>(
                                ansVars->retroVars->countArrays[curLayerId]) +
                            predState.stateNumber /
                                (sizeof(long) / sizeof(CountArrayVarType));
        const long nBitsToShift =
            sizeof(CountArrayVarType) * 8 *
            (predState.stateNumber %
             (sizeof(long) / sizeof(CountArrayVarType))); // little-endian
                                                          // byte-order
        const long mask = 0x000000ff << nBitsToShift;
        long curCountLong, newCountLong;

        do {
#if 0
            cout << "predState.stateNumber = " << predState.stateNumber << endl;
            cout << "pCountValue = " << pCountValue << endl;
#endif

            curCountLong = *pCountValue;
            const long temp = (curCountLong & mask) >> nBitsToShift;
            countValue = static_cast<CountArrayVarType>(temp);
            if (countValue == 255) {
                PRINT(0, m, "ERROR: maximum value for Count[] reached!");
                return TM_RETVAL_TERMINATE_ALL_THREADS;
            }

            countValue++;
            newCountLong = (curCountLong & (~mask)) +
                           (countValue << nBitsToShift);
        } while (InterlockedCompareExchange(pCountValue, newCountLong,
                                            curCountLong) != curCountLong);
    }

    // everything is fine
    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// performRetroAnalysis()
//
//-----------------------------------------------------------------------------
bool MiniMax::performRetroAnalysis(retroAnalysisGlobalVars &retroVars)
{
    // locals
    StateAdress curState; // current state counter for loops
    TwoBit curStateValue; // current state value

    PRINT(2, this, "  *** Begin Iteration ***");
    stateProcessedCount = 0;
    curCalcActionId = MM_ACTION_PERFORM_RETRO_ANAL;

    // process each state in the current layer
    switch (threadManager.execInParallel(performRetroAnalysisThreadProc,
                                         (void **)&retroVars, 0)) {
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

    // if there are still states to process, than something went wrong
    for (uint32_t curThreadNo = 0; curThreadNo < threadManager.getThreadCount();
         curThreadNo++) {
        if (retroVars.thread[curThreadNo].stateToProcessCount) {
            PRINT(0, this,
                  "ERROR: There are still states to process after performing "
                  "retro analysis!");
            return falseOrStop();
        }
    }

    // copy drawn and invalid states to ply info
    PRINT(2, this, "    Copy drawn and invalid states to ply info database...");

    for (uint32_t curLayerId = 0; // current processed layer within
                                  // 'layersToCalculate'
         curLayerId < retroVars.layersToCalculate.size(); curLayerId++) {
        for (curState.layerNumber = retroVars.layersToCalculate[curLayerId],
            curState.stateNumber = 0;
             curState.stateNumber <
             layerStats[curState.layerNumber].knotsInLayer;
             curState.stateNumber++) {
            readKnotValueFromDatabase(curState.layerNumber,
                                      curState.stateNumber, curStateValue);
            if (curStateValue == SKV_VALUE_GAME_DRAWN)
                savePlyInfoInDatabase(curState.layerNumber,
                                      curState.stateNumber,
                                      PLYINFO_VALUE_DRAWN);
            if (curStateValue == SKV_VALUE_INVALID)
                savePlyInfoInDatabase(curState.layerNumber,
                                      curState.stateNumber,
                                      PLYINFO_VALUE_INVALID);
        }
    }

    PRINT(1, this, "  *** Iteration finished! ***");

    // every thing ok
    return true;
}

//-----------------------------------------------------------------------------
// performRetroAnalysisThreadProc()
//
//-----------------------------------------------------------------------------
DWORD MiniMax::performRetroAnalysisThreadProc(void *pParam)
{
    // locals
    const auto retroVars = static_cast<retroAnalysisGlobalVars *>(pParam);
    MiniMax *m = retroVars->pMiniMax;
    const uint32_t threadNo = m->threadManager.getThreadNumber();
    RetroAnalysisThreadVars *threadVars = &retroVars->thread[threadNo];

    TwoBit predStateValue;
    uint32_t curLayerId;   // current processed layer within
                           // 'layersToCalculate'
    uint32_t amountOfPred; // total numbers of predecessors and current
                           // considered one
    uint32_t threadCounter;
    int64_t stateProcessedCount;
    int64_t totalNumStatesToProcess;
    PlyInfoVarType curNumPlies;
    PlyInfoVarType plyTillCurStateCount;
    PlyInfoVarType nPliesTillPredState;
    CountArrayVarType countValue;
    StateAdress predState;
    StateAdress curState; // current state counter for while-loop
    TwoBit curStateValue; // current state value
    RetroAnalysisPredVars predVars[PREDECESSOR_COUNT_MAX];

    for (stateProcessedCount = 0, curNumPlies = 0;
         curNumPlies < threadVars->statesToProcess.size(); curNumPlies++) {
        // skip empty and uninitialized cyclic arrays
        if (threadVars->statesToProcess[curNumPlies] != nullptr) {
            if (threadNo == 0) {
                PRINT(0, m,
                      "    Current number of plies: "
                          << static_cast<uint32_t>(curNumPlies) << "/"
                          << threadVars->statesToProcess.size());
                for (threadCounter = 0;
                     threadCounter < m->threadManager.getThreadCount();
                     threadCounter++) {
                    PRINT(0, m,
                          "      States to process for thread "
                              << threadCounter << ": "
                              << retroVars->thread[threadCounter]
                                     .stateToProcessCount);
                }
            }

            while (threadVars->statesToProcess[curNumPlies]->takeBytes(
                sizeof(StateAdress),
                reinterpret_cast<unsigned char *>(&curState))) {
                // execution canceled by user?
                if (m->threadManager.wasExecCancelled()) {
                    PRINT(0, m,
                          "\n****************************************\nSub-"
                          "thread no. "
                              << threadNo
                              << ": Execution cancelled by "
                                 "user!\n**************************************"
                                 "**"
                                 "\n");
                    return TM_RETVAL_EXEC_CANCELLED;
                }

                // get value of current state
                m->readKnotValueFromDatabase(
                    curState.layerNumber, curState.stateNumber, curStateValue);
                m->readPlyInfoFromDatabase(curState.layerNumber,
                                           curState.stateNumber,
                                           plyTillCurStateCount);

                if (plyTillCurStateCount != curNumPlies) {
                    PRINT(0, m, "ERROR: plyTillCurStateCount != curNumPlies");
                    return TM_RETVAL_TERMINATE_ALL_THREADS;
                }

                // console output
                stateProcessedCount++;
                threadVars->stateToProcessCount--;
                if (stateProcessedCount % OUTPUT_EVERY_N_STATES == 0) {
                    m->stateProcessedCount += OUTPUT_EVERY_N_STATES;
                    for (totalNumStatesToProcess = 0, threadCounter = 0;
                         threadCounter < m->threadManager.getThreadCount();
                         threadCounter++) {
                        totalNumStatesToProcess += retroVars
                                                       ->thread[threadCounter]
                                                       .stateToProcessCount;
                    }
                    PRINT(2, m,
                          "    states already processed: "
                              << m->stateProcessedCount
                              << " \t states still in list: "
                              << totalNumStatesToProcess);
                }

                // set current selected situation
                if (!m->setSituation(threadNo, curState.layerNumber,
                                     curState.stateNumber)) {
                    PRINT(0, m, "ERROR: setSituation() returned false!");
                    return TM_RETVAL_TERMINATE_ALL_THREADS;
                }

                // get list with state numbers of predecessors
                m->getPredecessors(threadNo, &amountOfPred, predVars);

                // iteration
                for (uint32_t curPred = 0; curPred < amountOfPred; curPred++) {
                    // current predecessor
                    predState.layerNumber = predVars[curPred].predLayerNumbers;
                    predState.stateNumber = predVars[curPred].predStateNumbers;

                    // don't calculate states from layers above yet
                    for (curLayerId = 0;
                         curLayerId < retroVars->layersToCalculate.size();
                         curLayerId++) {
                        if (retroVars->layersToCalculate[curLayerId] ==
                            predState.layerNumber)
                            break;
                    }
                    if (curLayerId == retroVars->layersToCalculate.size())
                        continue;

                    // get value of predecessor
                    m->readKnotValueFromDatabase(predState.layerNumber,
                                                 predState.stateNumber,
                                                 predStateValue);

                    // only drawn states are relevant here, since the other are
                    // already calculated
                    if (predStateValue == SKV_VALUE_GAME_DRAWN) {
                        // if current considered state is a lost game then all
                        // predecessors are a won game
                        if (curStateValue ==
                            m->skvPerspectiveMatrix
                                [SKV_VALUE_GAME_LOST]
                                [predVars[curPred].playerToMoveChanged ?
                                     PL_TO_MOVE_CHANGED :
                                     PL_TO_MOVE_UNCHANGED]) {
                            m->saveKnotValueInDatabase(predState.layerNumber,
                                                       predState.stateNumber,
                                                       SKV_VALUE_GAME_WON);
                            m->savePlyInfoInDatabase(
                                predState.layerNumber, predState.stateNumber,
                                plyTillCurStateCount +
                                    1); // (requirement: curNumPlies ==
                                        // plyTillCurStateCount)
                            if (plyTillCurStateCount + 1 < curNumPlies) {
                                PRINT(0, m,
                                      "ERROR: Current number of plies is "
                                      "bigger "
                                      "than plyTillCurStateCount + 1!");
                                return TM_RETVAL_TERMINATE_ALL_THREADS;
                            }
                            m->addStateToProcessQueue(*retroVars, *threadVars,
                                                      plyTillCurStateCount + 1,
                                                      &predState);
                            // if current state is a won game, then this state
                            // is not an option any more for all predecessors
                        } else {
                            // reduce count value by one
                            long *pCountValue =
                                reinterpret_cast<long *>(
                                    retroVars->countArrays[curLayerId]) +
                                predState.stateNumber /
                                    (sizeof(long) / sizeof(CountArrayVarType));
                            const long nBitsToShift =
                                sizeof(CountArrayVarType) * 8 *
                                (predState.stateNumber %
                                 (sizeof(long) /
                                  sizeof(CountArrayVarType))); // little-endian
                                                               // byte-order
                            const long mask = 0x000000ff << nBitsToShift;
                            long curCountLong, newCountLong;

                            do {
                                curCountLong = *pCountValue;
                                const long temp = (curCountLong & mask) >>
                                                  nBitsToShift;
                                countValue = static_cast<CountArrayVarType>(
                                    temp);

                                if (countValue > 0) {
                                    countValue--;
                                    newCountLong = (curCountLong & (~mask)) +
                                                   (countValue << nBitsToShift);
                                } else {
                                    PRINT(0, m,
                                          "ERROR: Count is already zero!");
                                    return TM_RETVAL_TERMINATE_ALL_THREADS;
                                }
                            } while (InterlockedCompareExchange(
                                         pCountValue, newCountLong,
                                         curCountLong) != curCountLong);

                            // ply info (requirement: curNumPlies ==
                            // plyTillCurStateCount)
                            m->readPlyInfoFromDatabase(predState.layerNumber,
                                                       predState.stateNumber,
                                                       nPliesTillPredState);
                            if (nPliesTillPredState ==
                                    PLYINFO_VALUE_UNCALCULATED ||
                                plyTillCurStateCount + 1 >
                                    nPliesTillPredState) {
                                m->savePlyInfoInDatabase(predState.layerNumber,
                                                         predState.stateNumber,
                                                         plyTillCurStateCount +
                                                             1);
                            }

                            // when all successor are won states then this is a
                            // lost state (this should only be the case for one
                            // thread)
                            if (countValue == 0) {
                                m->saveKnotValueInDatabase(
                                    predState.layerNumber,
                                    predState.stateNumber, SKV_VALUE_GAME_LOST);
                                if (plyTillCurStateCount + 1 < curNumPlies) {
                                    PRINT(0, m,
                                          "ERROR: Current number of plies is "
                                          "bigger than plyTillCurStateCount + "
                                          "1!");
                                    return TM_RETVAL_TERMINATE_ALL_THREADS;
                                }
                                m->addStateToProcessQueue(
                                    *retroVars, *threadVars,
                                    plyTillCurStateCount + 1, &predState);
                            }
                        }
                    }
                }
            }
        }

        // there might be other threads still processing states with this ply
        // number
        m->threadManager.waitForOtherThreads(threadNo);
    }

    // every thing ok
    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// addStateToProcessQueue()
//
//-----------------------------------------------------------------------------
bool MiniMax::addStateToProcessQueue(const retroAnalysisGlobalVars &retroVars,
                                     RetroAnalysisThreadVars &threadVars,
                                     uint32_t plyNumber, StateAdress *pState)
{
    // resize vector if too small
    if (plyNumber >= threadVars.statesToProcess.size()) {
        threadVars.statesToProcess.resize(
            max(plyNumber + 1, 10 * threadVars.statesToProcess.size()),
            nullptr);
        PRINT(4, this,
              "    statesToProcess resized to "
                  << threadVars.statesToProcess.size());
    }

    // initialize cyclic array if necessary
    if (threadVars.statesToProcess[plyNumber] == nullptr) {
        stringstream ssStatesToProcessFilePath;
        stringstream ssStatesToProcessPath;
        ssStatesToProcessPath << fileDir << (fileDir.size() ? "\\" : "")
                              << "statesToProcess";
        CreateDirectoryA(ssStatesToProcessPath.str().c_str(), nullptr);
        ssStatesToProcessFilePath.str("");
        ssStatesToProcessFilePath
            << ssStatesToProcessPath.str()
            << "\\statesToProcessWithPlyCounter=" << plyNumber
            << "andThread=" << threadVars.threadNo << ".dat";
        threadVars.statesToProcess[plyNumber] = new CyclicArray(
            BLOCK_SIZE_IN_CYCLIC_ARRAY * sizeof(StateAdress),
            static_cast<uint32_t>(retroVars.totalKnotCount /
                                  BLOCK_SIZE_IN_CYCLIC_ARRAY) +
                1,
            ssStatesToProcessFilePath.str().c_str());
        PRINT(4, this,
              "    Created cyclic array: " << ssStatesToProcessFilePath.str());
    }

    // add state
    if (!threadVars.statesToProcess[plyNumber]->addBytes(
            sizeof(StateAdress), reinterpret_cast<unsigned char *>(pState))) {
        PRINT(0, this,
              "ERROR: Cyclic list to small! stateToProcessCount:"
                  << threadVars.stateToProcessCount);
        return falseOrStop();
    }

    // everything was fine
    threadVars.stateToProcessCount++;

    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
