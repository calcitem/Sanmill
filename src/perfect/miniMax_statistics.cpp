/*********************************************************************
    miniMax_statistics.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

//-----------------------------------------------------------------------------
// showMemoryStatus()
//
//-----------------------------------------------------------------------------
unsigned int MiniMax::getNumThreads()
{
    return threadManager.getNumThreads();
}

//-----------------------------------------------------------------------------
// anyFreshlyCalculatedLayer()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
bool MiniMax::anyFreshlyCalculatedLayer()
{
    return (lastCalculatedLayer.size() > 0);
}

//-----------------------------------------------------------------------------
// getLastCalculatedLayer()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
unsigned int MiniMax::getLastCalculatedLayer()
{
    unsigned int tmp = lastCalculatedLayer.front();
    lastCalculatedLayer.pop_front();
    return tmp;
}

//-----------------------------------------------------------------------------
// isLayerInDatabase()
//
//-----------------------------------------------------------------------------
bool MiniMax::isLayerInDatabase(unsigned int layerNum)
{
    if (layerStats == nullptr)
        return false;
    return layerStats[layerNum].layerIsCompletedAndInFile;
}

//-----------------------------------------------------------------------------
// getLayerSizeInBytes()
//
//-----------------------------------------------------------------------------
int64_t MiniMax::getLayerSizeInBytes(unsigned int layerNum)
{
    if (plyInfos == nullptr || layerStats == nullptr)
        return 0;
    return (int64_t)layerStats[layerNum].sizeInBytes +
           (int64_t)plyInfos[layerNum].sizeInBytes;
}

//-----------------------------------------------------------------------------
// getNumWonStates()
//
//-----------------------------------------------------------------------------
MiniMax::StateNumberVarType MiniMax::getNumWonStates(unsigned int layerNum)
{
    if (layerStats == nullptr)
        return 0;
    return layerStats[layerNum].numWonStates;
}

//-----------------------------------------------------------------------------
// getNumLostStates()
//
//-----------------------------------------------------------------------------
MiniMax::StateNumberVarType MiniMax::getNumLostStates(unsigned int layerNum)
{
    if (layerStats == nullptr)
        return 0;
    return layerStats[layerNum].numLostStates;
}

//-----------------------------------------------------------------------------
// getNumDrawnStates()
//
//-----------------------------------------------------------------------------
MiniMax::StateNumberVarType MiniMax::getNumDrawnStates(unsigned int layerNum)
{
    if (layerStats == nullptr)
        return 0;
    return layerStats[layerNum].numDrawnStates;
}

//-----------------------------------------------------------------------------
// getNumInvalidStates()
//
//-----------------------------------------------------------------------------
MiniMax::StateNumberVarType MiniMax::getNumInvalidStates(unsigned int layerNum)
{
    if (layerStats == nullptr)
        return 0;
    return layerStats[layerNum].numInvalidStates;
}

//-----------------------------------------------------------------------------
// showMemoryStatus()
//
//-----------------------------------------------------------------------------
void MiniMax::showMemoryStatus()
{
    MEMORYSTATUSEX memStatus;
    memStatus.dwLength = sizeof(memStatus);
    GlobalMemoryStatusEx(&memStatus);

    cout << endl << "dwMemoryLoad           : " << memStatus.dwMemoryLoad;
    cout << endl
         << "ullAvailExtendedVirtual: " << memStatus.ullAvailExtendedVirtual;
    cout << endl << "ullAvailPageFile       : " << memStatus.ullAvailPageFile;
    cout << endl << "ullAvailPhys           : " << memStatus.ullAvailPhys;
    cout << endl << "ullAvailVirtual        : " << memStatus.ullAvailVirtual;
    cout << endl << "ullTotalPageFile       : " << memStatus.ullTotalPageFile;
    cout << endl << "ullTotalPhys           : " << memStatus.ullTotalPhys;
    cout << endl << "ullTotalVirtual        : " << memStatus.ullTotalVirtual;
}

//-----------------------------------------------------------------------------
// setOutputStream()
//
//-----------------------------------------------------------------------------
void MiniMax::setOutputStream(ostream *theStream,
                              void (*printFunc)(void *pUserData),
                              void *pUserData)
{
    osPrint = theStream;
    pDataForUserPrintFunc = pUserData;
    userPrintFunc = printFunc;
}

//-----------------------------------------------------------------------------
// showLayerStats()
//
//-----------------------------------------------------------------------------
void MiniMax::showLayerStats(unsigned int layerNumber)
{
    // locals
    StateAdress curState;
    unsigned int statsValueCounter[] = {0, 0, 0, 0};
    TwoBit curStateValue;

    // calc and show statistics
    for (curState.layerNumber = layerNumber, curState.stateNumber = 0;
         curState.stateNumber < layerStats[curState.layerNumber].knotsInLayer;
         curState.stateNumber++) {
        // get state value
        readKnotValueFromDatabase(curState.layerNumber, curState.stateNumber,
                                  curStateValue);
        statsValueCounter[curStateValue]++;
    }

    layerStats[layerNumber].numWonStates = statsValueCounter[SKV_VALUE_GAME_WON];
    layerStats[layerNumber].numLostStates =
        statsValueCounter[SKV_VALUE_GAME_LOST];
    layerStats[layerNumber].numDrawnStates =
        statsValueCounter[SKV_VALUE_GAME_DRAWN];
    layerStats[layerNumber].numInvalidStates =
        statsValueCounter[SKV_VALUE_INVALID];

    PRINT(1, this, endl << "FINAL STATISTICS OF LAYER " << layerNumber);
    PRINT(1, this, (getOutputInformation(layerNumber)));
    PRINT(1, this,
          " number  states: " << layerStats[curState.layerNumber].knotsInLayer);
    PRINT(1, this,
          " won     states: " << statsValueCounter[SKV_VALUE_GAME_WON]);
    PRINT(1, this,
          " lost    states: " << statsValueCounter[SKV_VALUE_GAME_LOST]);
    PRINT(1, this,
          " draw    states: " << statsValueCounter[SKV_VALUE_GAME_DRAWN]);
    PRINT(1, this, " invalid states: " << statsValueCounter[SKV_VALUE_INVALID]);
}

//-----------------------------------------------------------------------------
// calcLayerStatistics()
//
//-----------------------------------------------------------------------------
bool MiniMax::calcLayerStatistics(char *statisticsFileName)
{
    // locals
    HANDLE statFile;
    DWORD dwBytesWritten;
    StateAdress curState;
    unsigned int *statsValueCounter;
    TwoBit curStateValue;
    char line[10000];
    string text("");

    // database must be open
    if (hFileShortKnotValues == nullptr)
        return false;

    // Open statistics file
    statFile = CreateFileA(statisticsFileName, GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file successfully?
    if (statFile == INVALID_HANDLE_VALUE) {
        statFile = nullptr;
        return false;
    }

    // headline
    text += "layer number\t";
    text += "white pieces\t";
    text += "black pieces\t";
    text += "won states\t";
    text += "lost states\t";
    text += "draw states\t";
    text += "invalid states\t";
    text += "total num states\t";
    text += "num succeeding layers\t";
    text += "partner layer\t";
    text += "size in bytes\t";
    text += "succLayers[0]\t";
    text += "succLayers[1]\n";

    statsValueCounter = new unsigned int[4 * skvfHeader.numLayers];
    curCalculationActionId = MM_ACTION_CALC_LAYER_STATS;

    // calc and show statistics
    for (layerInDatabase = false, curState.layerNumber = 0;
         curState.layerNumber < skvfHeader.numLayers; curState.layerNumber++) {
        // status output
        PRINT(0, this,
              "Calculating statistics of layer: " << (int)curState.layerNumber);

        // zero counters
        statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_WON] = 0;
        statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_LOST] = 0;
        statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_DRAWN] = 0;
        statsValueCounter[4 * curState.layerNumber + SKV_VALUE_INVALID] = 0;

        // only calc stats of completed layers
        if (layerStats[curState.layerNumber].layerIsCompletedAndInFile) {
            for (curState.stateNumber = 0;
                 curState.stateNumber <
                 layerStats[curState.layerNumber].knotsInLayer;
                 curState.stateNumber++) {
                // get state value
                readKnotValueFromDatabase(curState.layerNumber,
                                          curState.stateNumber, curStateValue);
                statsValueCounter[4 * curState.layerNumber + curStateValue]++;
            }

            // free memory
            unloadLayer(curState.layerNumber);
        }

        // add line
        sprintf_s(
            line, "%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
            curState.layerNumber,
            getOutputInformation(curState.layerNumber).c_str(),
            statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_WON],
            statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_LOST],
            statsValueCounter[4 * curState.layerNumber + SKV_VALUE_GAME_DRAWN],
            statsValueCounter[4 * curState.layerNumber + SKV_VALUE_INVALID],
            layerStats[curState.layerNumber].knotsInLayer,
            layerStats[curState.layerNumber].numSuccLayers,
            layerStats[curState.layerNumber].partnerLayer,
            layerStats[curState.layerNumber].sizeInBytes,
            layerStats[curState.layerNumber].succLayers[0],
            layerStats[curState.layerNumber].succLayers[1]);
        text += line;
    }

    // write to file and close it
    WriteFile(statFile, text.c_str(), (DWORD)text.length(), &dwBytesWritten,
              nullptr);
    CloseHandle(statFile);
    SAFE_DELETE_ARRAY(statsValueCounter);
    return true;
}

//-----------------------------------------------------------------------------
// anyArraryInfoToUpdate()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
bool MiniMax::anyArrayInfoToUpdate()
{
    return (arrayInfos.arrayInfosToBeUpdated.size() > 0);
}

//-----------------------------------------------------------------------------
// getArrayInfoForUpdate()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
MiniMax::ArrayInfoChange MiniMax::getArrayInfoForUpdate()
{
    MiniMax::ArrayInfoChange tmp = arrayInfos.arrayInfosToBeUpdated.front();
    arrayInfos.arrayInfosToBeUpdated.pop_front();
    return tmp;
}

//-----------------------------------------------------------------------------
// getCurrentActionStr()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
LPWSTR MiniMax::getCurrentActionStr()
{
    switch (curCalculationActionId) {
    case MM_ACTION_INIT_RETRO_ANAL:
        return (LPWSTR)L"initiating retro-analysis";
    case MM_ACTION_PREPARE_COUNT_ARRAY:
        return (LPWSTR)L"preparing count arrays";
    case MM_ACTION_PERFORM_RETRO_ANAL:
        return (LPWSTR)L"performing retro analysis";
    case MM_ACTION_PERFORM_ALPHA_BETA:
        return (LPWSTR)L"performing alpha-beta-algorithmn";
    case MM_ACTION_TESTING_LAYER:
        return (LPWSTR)L"testing calculated layer";
    case MM_ACTION_SAVING_LAYER_TO_FILE:
        return (LPWSTR)L"saving layer to file";
    case MM_ACTION_CALC_LAYER_STATS:
        return (LPWSTR)L"making layer statistics";
    case MM_ACTION_NONE:
        return (LPWSTR)L"none";
    default:
        return (LPWSTR)L"undefined";
    }
}

//-----------------------------------------------------------------------------
// getCurrentCalculatedLayer()
// called by MAIN-thread in pMiniMax->csOsPrint critical-section
//-----------------------------------------------------------------------------
void MiniMax::getCurrentCalculatedLayer(vector<unsigned int> &layers)
{
    // when retro-analysis is used than two layers are calculated at the same
    // time
    if (shallRetroAnalysisBeUsed(curCalculatedLayer) &&
        layerStats[curCalculatedLayer].partnerLayer != curCalculatedLayer) {
        layers.resize(2);
        layers[0] = curCalculatedLayer;
        layers[1] = layerStats[curCalculatedLayer].partnerLayer;
    } else {
        layers.resize(1);
        layers[0] = curCalculatedLayer;
    }
}

//-----------------------------------------------------------------------------
// ArrayInfoContainer::addArray()
// Caution: layerNumber and type must be a unique pair!
//       called by single CALCULATION-thread
//-----------------------------------------------------------------------------
void MiniMax::ArrayInfoContainer::addArray(unsigned int layerNumber,
                                           unsigned int type, int64_t size,
                                           int64_t compressedSize)
{
    // create new info object and add to list
    EnterCriticalSection(&c->csOsPrint);

    ArrayInfo ais;
    ais.belongsToLayer = layerNumber;
    ais.compressedSizeInBytes = compressedSize;
    ais.sizeInBytes = size;
    ais.type = type;
    ais.updateCounter = 0;
    listArrays.push_back(ais);

    // notify change
    ArrayInfoChange aic;
    aic.arrayInfo = &listArrays.back();
    aic.itemIndex = (unsigned int)listArrays.size() - 1;
    arrayInfosToBeUpdated.push_back(aic);

    // save pointer of info in vector for direct access
    vectorArrays[layerNumber * ArrayInfo::numArrayTypes + type] =
        (--listArrays.end());

    // update GUI
    if (c->userPrintFunc != nullptr) {
        c->userPrintFunc(c->pDataForUserPrintFunc);
    }

    LeaveCriticalSection(&c->csOsPrint);
}

//-----------------------------------------------------------------------------
// ArrayInfoContainer::removeArray()
// called by single CALCULATION-thread
//-----------------------------------------------------------------------------
void MiniMax::ArrayInfoContainer::removeArray(unsigned int layerNumber,
                                              unsigned int type, int64_t size,
                                              int64_t compressedSize)
{
    // find info object in list
    EnterCriticalSection(&c->csOsPrint);

    if (vectorArrays.size() > layerNumber * ArrayInfo::numArrayTypes + type) {
        list<ArrayInfo>::iterator itr =
            vectorArrays[layerNumber * ArrayInfo::numArrayTypes + type];
        if (itr != listArrays.end()) {
            // does sizes fit?
            if (itr->belongsToLayer != layerNumber || itr->type != type ||
                itr->sizeInBytes != size ||
                itr->compressedSizeInBytes != compressedSize) {
                c->falseOrStop();
            }

            // notify change
            ArrayInfoChange aic;
            aic.arrayInfo = nullptr;
            aic.itemIndex = (unsigned int)std::distance(listArrays.begin(),
                                                        itr);
            arrayInfosToBeUpdated.push_back(aic);

            // delete tem from list
            listArrays.erase(itr);
        }
    }

    // update GUI
    if (c->userPrintFunc != nullptr) {
        c->userPrintFunc(c->pDataForUserPrintFunc);
    }

    LeaveCriticalSection(&c->csOsPrint);
}

//-----------------------------------------------------------------------------
// ArrayInfoContainer::updateArray()
// called by mutiple CALCULATION-thread
//-----------------------------------------------------------------------------
void MiniMax::ArrayInfoContainer::updateArray(unsigned int layerNumber,
                                              unsigned int type)
{
    // find info object in list
    list<ArrayInfo>::iterator itr =
        vectorArrays[layerNumber * ArrayInfo::numArrayTypes + type];

    itr->updateCounter++;
    if (itr->updateCounter > ArrayInfo::updateCounterThreshold) {
        // notify change
        EnterCriticalSection(&c->csOsPrint);

        ArrayInfoChange aic;
        aic.arrayInfo = &(*itr);
        aic.itemIndex = (unsigned int)std::distance(listArrays.begin(), itr);
        arrayInfosToBeUpdated.push_back(aic);

        // update GUI
        if (c->userPrintFunc != nullptr) {
            c->userPrintFunc(c->pDataForUserPrintFunc);
        }
        itr->updateCounter = 0;

        LeaveCriticalSection(&c->csOsPrint);
    }
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
