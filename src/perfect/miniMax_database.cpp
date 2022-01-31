/*********************************************************************
    miniMax_database.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMax.h"

#pragma warning(disable : 4127)
#pragma warning(disable : 4706)

//-----------------------------------------------------------------------------
// ~MiniMax()
// MiniMax class destructor
//-----------------------------------------------------------------------------
void MiniMax::closeDatabase()
{
    // close database
    if (hFileShortKnotValues != nullptr) {
        unloadAllLayers();
        SAFE_DELETE_ARRAY(layerStats);
        CloseHandle(hFileShortKnotValues);
        hFileShortKnotValues = nullptr;
    }

    // close ply info file
    if (hFilePlyInfo != nullptr) {
        unloadAllPlyInfos();
        SAFE_DELETE_ARRAY(plyInfos);
        CloseHandle(hFilePlyInfo);
        hFilePlyInfo = nullptr;
    }
}

//-----------------------------------------------------------------------------
// unloadPlyInfo()
//
//-----------------------------------------------------------------------------
void MiniMax::unloadPlyInfo(uint32_t layerNumber)
{
    PlyInfo *myPis = &plyInfos[layerNumber];
    memoryUsed2 -= myPis->sizeInBytes;
    arrayInfos.removeArray(layerNumber, ArrayInfo::arrayType_plyInfos,
                           myPis->sizeInBytes, 0);
    SAFE_DELETE_ARRAY(myPis->plyInfo);
    myPis->plyInfoIsLoaded = false;
}

//-----------------------------------------------------------------------------
// unloadLayer()
//
//-----------------------------------------------------------------------------
void MiniMax::unloadLayer(uint32_t layerNumber)
{
    LayerStats *myLss = &layerStats[layerNumber];
    SAFE_DELETE_ARRAY(myLss->shortKnotValueByte);
    memoryUsed2 -= myLss->sizeInBytes;
    arrayInfos.removeArray(layerNumber, ArrayInfo::arrayType_layerStats,
                           myLss->sizeInBytes, 0);
    myLss->layerIsLoaded = false;
}

//-----------------------------------------------------------------------------
// unloadAllPlyInfos()
//
//-----------------------------------------------------------------------------
void MiniMax::unloadAllPlyInfos()
{
    for (uint32_t i = 0; i < plyInfoHeader.LayerCount; i++) {
        unloadPlyInfo(i);
    }
}

//-----------------------------------------------------------------------------
// unloadAllLayers()
//
//-----------------------------------------------------------------------------
void MiniMax::unloadAllLayers()
{
    for (uint32_t i = 0; i < skvfHeader.LayerCount; i++) {
        unloadLayer(i);
    }
}

//-----------------------------------------------------------------------------
// saveBytesToFile()
//
//-----------------------------------------------------------------------------
void MiniMax::saveBytesToFile(HANDLE hFile, int64_t offset, uint32_t nBytes,
                              void *pBytes)
{
    DWORD dwBytesWritten;
    LARGE_INTEGER liDistanceToMove;
    uint32_t restingBytes = nBytes;
    void *myPointer = pBytes;
    bool errorPrint;

    liDistanceToMove.QuadPart = offset;

    while (errorPrint = !SetFilePointerEx(hFile, liDistanceToMove, nullptr,
                                          FILE_BEGIN)) {
        if (!errorPrint)
            PRINT(1, this, "ERROR: SetFilePointerEx  failed!");
    }

    while (restingBytes > 0) {
        if (WriteFile(hFile, myPointer, restingBytes, &dwBytesWritten,
                      nullptr) == TRUE) {
            restingBytes -= dwBytesWritten;
            myPointer = static_cast<void *>(
                static_cast<unsigned char *>(myPointer) + dwBytesWritten);
            if (restingBytes > 0)
                PRINT(2, this, "Still " << restingBytes << " to write!");
        } else {
            if (!errorPrint)
                PRINT(0, this, "ERROR: WriteFile Failed!");
            errorPrint = true;
        }
    }
}

//-----------------------------------------------------------------------------
// loadBytesFromFile()
//
//-----------------------------------------------------------------------------
void MiniMax::loadBytesFromFile(HANDLE hFile, int64_t offset, uint32_t nBytes,
                                void *pBytes)
{
    DWORD dwBytesRead;
    LARGE_INTEGER liDistanceToMove;
    uint32_t restingBytes = nBytes;
    void *myPointer = pBytes;
    bool errorPrint;

    liDistanceToMove.QuadPart = offset;

    while (errorPrint = !SetFilePointerEx(hFile, liDistanceToMove, nullptr,
                                          FILE_BEGIN)) {
        if (!errorPrint)
            PRINT(0, this, "ERROR: SetFilePointerEx failed!");
    }

    while (restingBytes > 0) {
        if (ReadFile(hFile, pBytes, restingBytes, &dwBytesRead, nullptr) ==
            TRUE) {
            restingBytes -= dwBytesRead;
            myPointer = static_cast<void *>(
                static_cast<unsigned char *>(myPointer) + dwBytesRead);
            if (restingBytes > 0) {
                PRINT(2, this, "Still " << restingBytes << " bytes to read!");
            }
        } else {
            if (!errorPrint)
                PRINT(0, this, "ERROR: ReadFile Failed!");
            errorPrint = true;
        }
    }
}

//-----------------------------------------------------------------------------
// isCurStateInDatabase()
//
//-----------------------------------------------------------------------------
bool MiniMax::isCurStateInDatabase(uint32_t threadNo)
{
    uint32_t layerNum, stateNumber;

    if (hFileShortKnotValues == nullptr) {
        return false;
    }

    getLayerAndStateNumber(threadNo, layerNum, stateNumber);
    return layerStats[layerNum].layerIsCompletedAndInFile;
}

//-----------------------------------------------------------------------------
// saveHeader()
//
//-----------------------------------------------------------------------------
void MiniMax::saveHeader(const SkvFileHeader *dbH,
                         const LayerStats *lStats) const
{
    DWORD dwBytesWritten;
    SetFilePointer(hFileShortKnotValues, 0, nullptr, FILE_BEGIN);
    WriteFile(hFileShortKnotValues, dbH, sizeof(SkvFileHeader), &dwBytesWritten,
              nullptr);
    WriteFile(hFileShortKnotValues, lStats,
              sizeof(LayerStats) * dbH->LayerCount, &dwBytesWritten, nullptr);
}

//-----------------------------------------------------------------------------
// saveHeader()
//
//-----------------------------------------------------------------------------
void MiniMax::saveHeader(const PlyInfoFileHeader *piH,
                         const PlyInfo *pInfo) const
{
    DWORD dwBytesWritten;
    SetFilePointer(hFilePlyInfo, 0, nullptr, FILE_BEGIN);
    WriteFile(hFilePlyInfo, piH, sizeof(PlyInfoFileHeader), &dwBytesWritten,
              nullptr);
    WriteFile(hFilePlyInfo, pInfo, sizeof(PlyInfo) * piH->LayerCount,
              &dwBytesWritten, nullptr);
}

//-----------------------------------------------------------------------------
// openDatabase()
//
//-----------------------------------------------------------------------------
bool MiniMax::openDatabase(const char *dir, uint32_t branchCountMax)
{
    if (strlen(dir) && !PathFileExistsA(dir)) {
        PRINT(0, this, "ERROR: Database path " << dir << " not valid!");
        return falseOrStop();
    }
    openSkvFile(dir, branchCountMax);
    openPlyInfoFile(dir);
    return true;
}

//-----------------------------------------------------------------------------
// openSkvFile()
//
//-----------------------------------------------------------------------------
void MiniMax::openSkvFile(const char *dir, uint32_t branchCountMax)
{
    // locals
    stringstream ssDatabaseFile;
    DWORD dwBytesRead;
    uint32_t i;

    // don't open file twice
    if (hFileShortKnotValues != nullptr)
        return;

    // remember dir name
    fileDir.assign(dir);
    ssDatabaseFile << fileDir << (strlen(dir) ? "\\" : "")
                   << "shortKnotValue.dat";
    PRINT(2, this,
          "Open short knot value file: " << fileDir << (strlen(dir) ? "\\" : "")
                                         << "shortKnotValue.dat" << endl);

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH |
    // FILE_FLAG_RANDOM_ACCESS)
    hFileShortKnotValues = CreateFileA(ssDatabaseFile.str().c_str(),
                                       GENERIC_READ | GENERIC_WRITE,
                                       FILE_SHARE_READ | FILE_SHARE_WRITE,
                                       nullptr, OPEN_ALWAYS,
                                       FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file successfully
    if (hFileShortKnotValues == INVALID_HANDLE_VALUE) {
        hFileShortKnotValues = nullptr;
        return;
    }

    // set header to invalid
    skvfHeader.headerCode = 0;
    maxNumBranches = branchCountMax;

    // database complete ?
    if (!ReadFile(hFileShortKnotValues, &skvfHeader, sizeof(SkvFileHeader),
                  &dwBytesRead, nullptr))
        return;

    // invalid file ?
    if (dwBytesRead != sizeof(SkvFileHeader) ||
        skvfHeader.headerCode != SKV_FILE_HEADER_CODE) {
        // create default header
        skvfHeader.completed = false;
        skvfHeader.LayerCount = getNumberOfLayers();
        skvfHeader.headerCode = SKV_FILE_HEADER_CODE;
        skvfHeader.headerAndStatsSize = sizeof(LayerStats) *
                                            skvfHeader.LayerCount +
                                        sizeof(SkvFileHeader);
        layerStats = new LayerStats[skvfHeader.LayerCount];
        std::memset(layerStats, 0, sizeof(LayerStats) * skvfHeader.LayerCount);
        layerStats[0].layerOffset = 0;

        for (i = 0; i < skvfHeader.LayerCount; i++) {
            getSuccLayers(i, &layerStats[i].succeedingLayerCount,
                          &layerStats[i].succeedingLayers[0]);
            layerStats[i].partnerLayer = getPartnerLayer(i);
            layerStats[i].knotsInLayer = getNumberOfKnotsInLayer(i);
            layerStats[i].sizeInBytes = (layerStats[i].knotsInLayer + 3) / 4;
            layerStats[i].shortKnotValueByte = nullptr;
            layerStats[i].skvCompressed = nullptr;
            layerStats[i].layerIsLoaded = false;
            layerStats[i].layerIsCompletedAndInFile = false;
            layerStats[i].wonStateCount = 0;
            layerStats[i].lostStateCount = 0;
            layerStats[i].drawnStateCount = 0;
            layerStats[i].invalidStateCount = 0;
        }

        for (i = 1; i < skvfHeader.LayerCount; i++) {
            layerStats[i].layerOffset = layerStats[i - 1].layerOffset +
                                        layerStats[i - 1].sizeInBytes;
        }

        // write header
        saveHeader(&skvfHeader, layerStats);

        // read layer stats
    } else {
        layerStats = new LayerStats[skvfHeader.LayerCount];
        std::memset(layerStats, 0, sizeof(LayerStats) * skvfHeader.LayerCount);
        if (!ReadFile(hFileShortKnotValues, layerStats,
                      sizeof(LayerStats) * skvfHeader.LayerCount, &dwBytesRead,
                      nullptr))
            return;
        for (i = 0; i < skvfHeader.LayerCount; i++) {
            layerStats[i].shortKnotValueByte = nullptr;
            layerStats[i].skvCompressed = nullptr;
        }
    }
}

//-----------------------------------------------------------------------------
// openPlyInfoFile()
//
//-----------------------------------------------------------------------------
void MiniMax::openPlyInfoFile(const char *dir)
{
    // locals
    stringstream ssFile;
    DWORD dwBytesRead;
    uint32_t i;

    // don't open file twice
    if (hFilePlyInfo != nullptr)
        return;

    // remember dir name
    ssFile << dir << (strlen(dir) ? "\\" : "") << "plyInfo.dat";
    PRINT(2, this, "Open ply info file: " << ssFile.str() << endl << endl);

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH |
    // FILE_FLAG_RANDOM_ACCESS)
    hFilePlyInfo = CreateFileA(ssFile.str().c_str(),
                               GENERIC_READ | GENERIC_WRITE,
                               FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                               OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file successfully
    if (hFilePlyInfo == INVALID_HANDLE_VALUE) {
        hFilePlyInfo = nullptr;
        return;
    }

    // set header to invalid
    plyInfoHeader.headerCode = 0;

    // database complete ?
    if (!ReadFile(hFilePlyInfo, &plyInfoHeader, sizeof(plyInfoHeader),
                  &dwBytesRead, nullptr))
        return;

    // invalid file ?
    if (dwBytesRead != sizeof(plyInfoHeader) ||
        plyInfoHeader.headerCode != PLYINFO_HEADER_CODE) {
        // create default header
        plyInfoHeader.plyInfoCompleted = false;
        plyInfoHeader.LayerCount = getNumberOfLayers();
        plyInfoHeader.headerCode = PLYINFO_HEADER_CODE;
        plyInfoHeader.headerAndPlyInfosSize = sizeof(PlyInfo) *
                                                  plyInfoHeader.LayerCount +
                                              sizeof(plyInfoHeader);
        plyInfos = new PlyInfo[plyInfoHeader.LayerCount];
        std::memset(plyInfos, 0, sizeof(PlyInfo) * plyInfoHeader.LayerCount);
        plyInfos[0].layerOffset = 0;

        for (i = 0; i < plyInfoHeader.LayerCount; i++) {
            plyInfos[i].knotsInLayer = getNumberOfKnotsInLayer(i);
            plyInfos[i].plyInfo = nullptr;
            plyInfos[i].plyInfoCompressed = nullptr;
            plyInfos[i].plyInfoIsLoaded = false;
            plyInfos[i].plyInfoIsCompletedAndInFile = false;
            plyInfos[i].sizeInBytes = plyInfos[i].knotsInLayer *
                                      sizeof(PlyInfoVarType);
        }

        for (i = 1; i < plyInfoHeader.LayerCount; i++) {
            plyInfos[i].layerOffset = plyInfos[i - 1].layerOffset +
                                      plyInfos[i - 1].sizeInBytes;
        }

        // write header
        saveHeader(&plyInfoHeader, plyInfos);

        // read layer stats
    } else {
        plyInfos = new PlyInfo[plyInfoHeader.LayerCount];
        std::memset(plyInfos, 0, sizeof(PlyInfo) * plyInfoHeader.LayerCount);
        if (!ReadFile(hFilePlyInfo, plyInfos,
                      sizeof(PlyInfo) * plyInfoHeader.LayerCount, &dwBytesRead,
                      nullptr))
            return;
        for (i = 0; i < plyInfoHeader.LayerCount; i++) {
            plyInfos[i].plyInfo = nullptr;
            plyInfos[i].plyInfoCompressed = nullptr;
        }
    }
}

//-----------------------------------------------------------------------------
// saveLayerToFile()
//
//-----------------------------------------------------------------------------
void MiniMax::saveLayerToFile(uint32_t layerNumber)
{
    // don't save layer and header when only preparing layers
    PlyInfo *myPis = &plyInfos[layerNumber];
    LayerStats *myLss = &layerStats[layerNumber];

    if (onlyPrepareLayer)
        return;

    // save layer if there are any states
    if (myLss->sizeInBytes) {
        // short knot values & ply info
        curCalcActionId = MM_ACTION_SAVING_LAYER_TO_FILE;
        saveBytesToFile(hFileShortKnotValues,
                        skvfHeader.headerAndStatsSize + myLss->layerOffset,
                        myLss->sizeInBytes, myLss->shortKnotValueByte);
        saveBytesToFile(hFilePlyInfo,
                        plyInfoHeader.headerAndPlyInfosSize +
                            myPis->layerOffset,
                        myPis->sizeInBytes, myPis->plyInfo);
    }

    // mark layer as completed
    myLss->layerIsCompletedAndInFile = true;
    myPis->plyInfoIsCompletedAndInFile = true;
}

//-----------------------------------------------------------------------------
// measureIops()
//
//-----------------------------------------------------------------------------
inline void MiniMax::measureIops(int64_t &nOps, LARGE_INTEGER &interval,
                                 LARGE_INTEGER &curTimeBefore, char text[])
{
    // locals
    LARGE_INTEGER curTimeAfter;

    if constexpr (!MEASURE_IOPS)
        return;
    nOps++; // ... not thread-safe !!!

    // only the time for the io-operation is considered and accumulated
    if (MEASURE_ONLY_IO) {
        QueryPerformanceCounter(&curTimeAfter);
        interval.QuadPart += curTimeAfter.QuadPart -
                             curTimeBefore.QuadPart; // ... not thread-safe !!!
        double totalTimeGone = static_cast<double>(interval.QuadPart) /
                               frequency.QuadPart; // ... not thread-safe !!!
        if (totalTimeGone >= 5.0) {
            PRINT(0, this,
                  text << "operations per second for last interval: "
                       << static_cast<int>(nOps / totalTimeGone));
            interval.QuadPart = 0; // ... not thread-safe !!!
            nOps = 0;              // ... not thread-safe !!!
        }
        // the whole time passed since the beginning of the interval is
        // considered
    } else if (nOps >= MEASURE_TIME_FREQUENCY) {
        QueryPerformanceCounter(&curTimeAfter);
        double totalTimeGone = static_cast<double>(curTimeAfter.QuadPart -
                                                   interval.QuadPart) /
                               frequency.QuadPart; // ... not thread-safe !!!
        PRINT(0, this,
              text << "operations per second for last interval: "
                   << nOps / totalTimeGone);
        interval.QuadPart = curTimeAfter.QuadPart; // ... not thread-safe !!!
        nOps = 0;                                  // ... not thread-safe !!!
    }
}

//-----------------------------------------------------------------------------
// readKnotValueFromDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::readKnotValueFromDatabase(uint32_t threadNo,
                                        uint32_t &layerNumber,
                                        uint32_t &stateNumber,
                                        TwoBit &knotValue,
                                        bool &invalidLayerOrStateNumber,
                                        bool &layerInDatabaseAndCompleted)
{
    // get state number, since this is the address, where the value is saved
    getLayerAndStateNumber(threadNo, layerNumber, stateNumber);

    // layer in database and completed ?
    const LayerStats *myLss = &layerStats[layerNumber];
    layerInDatabaseAndCompleted = myLss->layerIsCompletedAndInFile;

    // valid state and layer number ?
    if (layerNumber > skvfHeader.LayerCount ||
        stateNumber > myLss->knotsInLayer) {
        invalidLayerOrStateNumber = true;
    } else {
        invalidLayerOrStateNumber = false; // checkStateIntegrity();
    }

    if (invalidLayerOrStateNumber) {
        knotValue = SKV_VALUE_INVALID;
        return;
    }

    // read
    readKnotValueFromDatabase(layerNumber, stateNumber, knotValue);
}

//-----------------------------------------------------------------------------
// readKnotValueFromDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::readKnotValueFromDatabase(uint32_t layerNumber,
                                        uint32_t stateNumber, TwoBit &knotValue)
{
    // locals
    TwoBit databaseByte;
    int64_t bytesAllocated;
    // TwoBit defValue = SKV_WHOLE_BYTE_IS_INVALID;
    LayerStats *myLss = &layerStats[layerNumber];

    // valid state and layer number ?
    if (layerNumber > skvfHeader.LayerCount ||
        stateNumber > myLss->knotsInLayer) {
        PRINT(0, this,
              "ERROR: INVALID layerNumber OR stateNumber in "
              "readKnotValueFromDatabase()!");
        knotValue = SKV_VALUE_INVALID;
        return;
    }

    //  if database is complete get whole byte from file
    if (skvfHeader.completed || layerInDatabase ||
        myLss->layerIsCompletedAndInFile) {
        EnterCriticalSection(&csDatabase);
        loadBytesFromFile(hFileShortKnotValues,
                          skvfHeader.headerAndStatsSize + myLss->layerOffset +
                              stateNumber / 4,
                          1, &databaseByte);
        LeaveCriticalSection(&csDatabase);
    } else {
        // is layer already loaded
        if (!myLss->layerIsLoaded) {
            EnterCriticalSection(&csDatabase);

            if (!myLss->layerIsLoaded) {
                // if layer is in database and completed, then load layer from
                // file into memory, set default value otherwise
                myLss->shortKnotValueByte =
                    new unsigned char[myLss->sizeInBytes];
                std::memset(myLss->shortKnotValueByte, 0,
                            sizeof(unsigned char) * myLss->sizeInBytes);
                if (myLss->layerIsCompletedAndInFile) {
                    loadBytesFromFile(
                        hFileShortKnotValues,
                        skvfHeader.headerAndStatsSize + myLss->layerOffset,
                        myLss->sizeInBytes, myLss->shortKnotValueByte);
                } else {
                    memset(myLss->shortKnotValueByte, SKV_WHOLE_BYTE_IS_INVALID,
                           myLss->sizeInBytes);
                }
                bytesAllocated = myLss->sizeInBytes;
                arrayInfos.addArray(layerNumber,
                                    ArrayInfo::arrayType_layerStats,
                                    myLss->sizeInBytes, 0);

                // output
                myLss->layerIsLoaded = true;
                memoryUsed2 += bytesAllocated;
                PRINT(3, this,
                      "Allocated "
                          << bytesAllocated
                          << " bytes in memory for knot values of layer "
                          << layerNumber << ", which is "
                          << (myLss->layerIsCompletedAndInFile ? "" : " NOT ")
                          << " fully calculated, due to read operation.");
            }

            LeaveCriticalSection(&csDatabase);
        }

        // measure io-operations per second
        LARGE_INTEGER curTimeBefore;
        if constexpr (MEASURE_IOPS && MEASURE_ONLY_IO) {
            QueryPerformanceCounter(&curTimeBefore);
        }

        // read ply info from array
        databaseByte = myLss->shortKnotValueByte[stateNumber / 4];

        // measure io-operations per second
        measureIops(nReadSkvOps, readSkvInterval, curTimeBefore,
                    (char *)"Read  knot value ");
    }

    // make half byte
    knotValue = _rotr8(databaseByte, 2 * (stateNumber % 4)) & 3;
}

//-----------------------------------------------------------------------------
// readPlyInfoFromDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::readPlyInfoFromDatabase(uint32_t layerNumber,
                                      uint32_t stateNumber,
                                      PlyInfoVarType &value)
{
    // locals
    uint32_t curKnot;
    constexpr PlyInfoVarType defValue = PLYINFO_VALUE_UNCALCULATED;
    int64_t bytesAllocated;
    PlyInfo *myPis = &plyInfos[layerNumber];

    // valid state and layer number ?
    if (layerNumber > plyInfoHeader.LayerCount ||
        stateNumber > myPis->knotsInLayer) {
        PRINT(0, this,
              "ERROR: INVALID layerNumber OR stateNumber in "
              "readPlyInfoFromDatabase()!");
        value = PLYINFO_VALUE_INVALID;
        return;
    }

    // if database is complete get whole byte from file
    if (plyInfoHeader.plyInfoCompleted || layerInDatabase ||
        myPis->plyInfoIsCompletedAndInFile) {
        EnterCriticalSection(&csDatabase);
        loadBytesFromFile(hFilePlyInfo,
                          plyInfoHeader.headerAndPlyInfosSize +
                              myPis->layerOffset +
                              sizeof(PlyInfoVarType) * stateNumber,
                          sizeof(PlyInfoVarType), &value);
        LeaveCriticalSection(&csDatabase);
    } else {
        // is layer already in memory?
        if (!myPis->plyInfoIsLoaded) {
            EnterCriticalSection(&csDatabase);
            if (!myPis->plyInfoIsLoaded) {
                // if layer is in database and completed, then load layer from
                // file into memory; set default value otherwise
                myPis->plyInfo = new PlyInfoVarType[myPis->knotsInLayer];
                std::memset(myPis->plyInfo, 0,
                            sizeof(PlyInfoVarType) * myPis->knotsInLayer);
                if (myPis->plyInfoIsCompletedAndInFile) {
                    loadBytesFromFile(hFilePlyInfo,
                                      plyInfoHeader.headerAndPlyInfosSize +
                                          myPis->layerOffset,
                                      myPis->sizeInBytes, myPis->plyInfo);
                } else {
                    for (curKnot = 0; curKnot < myPis->knotsInLayer;
                         curKnot++) {
                        myPis->plyInfo[curKnot] = defValue;
                    }
                }
                bytesAllocated = myPis->sizeInBytes;
                arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_plyInfos,
                                    myPis->sizeInBytes, 0);
                myPis->plyInfoIsLoaded = true;
                memoryUsed2 += bytesAllocated;
                PRINT(3, this,
                      "Allocated "
                          << bytesAllocated
                          << " bytes in memory for ply info of layer "
                          << layerNumber << ", which is "
                          << (myPis->plyInfoIsCompletedAndInFile ? "" : " NOT ")
                          << " fully calculated, due to read operation.");
            }
            LeaveCriticalSection(&csDatabase);
        }

        // measure io-operations per second
        LARGE_INTEGER curTimeBefore;
        if constexpr (MEASURE_IOPS && MEASURE_ONLY_IO) {
            QueryPerformanceCounter(&curTimeBefore);
        }

        // read ply info from array
        value = myPis->plyInfo[stateNumber];

        // measure io-operations per second
        measureIops(nReadPlyOps, readPlyInterval, curTimeBefore,
                    (char *)"Read  ply info   ");
    }
}

//-----------------------------------------------------------------------------
// saveKnotValueInDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::saveKnotValueInDatabase(uint32_t layerNumber,
                                      uint32_t stateNumber, TwoBit knotValue)
{
    // locals
    int64_t bytesAllocated;
    // TwoBit defValue = SKV_WHOLE_BYTE_IS_INVALID;
    LayerStats *myLss = &layerStats[layerNumber];

    // valid state and layer number ?
    if (layerNumber > skvfHeader.LayerCount ||
        stateNumber > myLss->knotsInLayer) {
        PRINT(0, this,
              "ERROR: INVALID layerNumber OR stateNumber in "
              "saveKnotValueInDatabase()!");
        return;
    }

    // is layer already completed ?
    if (myLss->layerIsCompletedAndInFile) {
        PRINT(0, this,
              "ERROR: layer already completed and in file! function: "
              "saveKnotValueInDatabase()!");
        return;
    }

    // is layer already loaded?
    if (!myLss->layerIsLoaded) {
        EnterCriticalSection(&csDatabase);
        if (!myLss->layerIsLoaded) {
            // reserve memory for this layer & create array for ply info with
            // default value
            myLss->shortKnotValueByte = new TwoBit[myLss->sizeInBytes];
            memset(myLss->shortKnotValueByte, SKV_WHOLE_BYTE_IS_INVALID,
                   myLss->sizeInBytes);
            bytesAllocated = myLss->sizeInBytes;
            arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_layerStats,
                                myLss->sizeInBytes, 0);

            // output
            memoryUsed2 += bytesAllocated;
            PRINT(3, this,
                  "Allocated " << bytesAllocated
                               << " bytes in memory for knot values of layer "
                               << layerNumber << " due to write operation!");
            myLss->layerIsLoaded = true;
        }
        LeaveCriticalSection(&csDatabase);
    }

    // measure io-operations per second
    LARGE_INTEGER curTimeBefore;
    if constexpr (MEASURE_IOPS && MEASURE_ONLY_IO) {
        QueryPerformanceCounter(&curTimeBefore);
    }

    // set value
    long *pShortKnotValue = reinterpret_cast<long *>(
                                myLss->shortKnotValueByte) +
                            stateNumber / ((sizeof(long) * 8) / 2);
    const long nBitsToShift = 2 * (stateNumber %
                                   ((sizeof(long) * 8) / 2)); // little-endian
                                                              // byte-order
    const long mask = 0x00000003 << nBitsToShift;
    long curShortKnotValueLong, newShortKnotValueLong;

    do {
        curShortKnotValueLong = *pShortKnotValue;
        newShortKnotValueLong = (curShortKnotValueLong & (~mask)) +
                                (knotValue << nBitsToShift);
    } while (InterlockedCompareExchange(pShortKnotValue, newShortKnotValueLong,
                                        curShortKnotValueLong) !=
             curShortKnotValueLong);

    // measure io-operations per second
    measureIops(nWriteSkvOps, writeSkvInterval, curTimeBefore,
                (char *)"Write knot value ");
}

//-----------------------------------------------------------------------------
// savePlyInfoInDatabase()
//
//-----------------------------------------------------------------------------
void MiniMax::savePlyInfoInDatabase(uint32_t layerNumber, uint32_t stateNumber,
                                    PlyInfoVarType value)
{
    // locals
    uint32_t curKnot;
    constexpr PlyInfoVarType defValue = PLYINFO_VALUE_UNCALCULATED;
    int64_t bytesAllocated;
    PlyInfo *myPis = &plyInfos[layerNumber];

    // valid state and layer number ?
    if (layerNumber > plyInfoHeader.LayerCount ||
        stateNumber > myPis->knotsInLayer) {
        PRINT(0, this,
              "ERROR: INVALID layerNumber OR stateNumber in "
              "savePlyInfoInDatabase()!");
        return;
    }

    // is layer already completed ?
    if (myPis->plyInfoIsCompletedAndInFile) {
        PRINT(0, this,
              "ERROR: layer already completed and in file! function: "
              "savePlyInfoInDatabase()!");
        return;
    }

    // is layer already loaded
    if (!myPis->plyInfoIsLoaded) {
        EnterCriticalSection(&csDatabase);

        if (!myPis->plyInfoIsLoaded) {
            // reserve memory for this layer & create array for ply info with
            // default value
            myPis->plyInfo = new PlyInfoVarType[myPis->knotsInLayer];
            std::memset(myPis->plyInfo, 0 /* TODO: defValue */,
                        sizeof(PlyInfoVarType) * myPis->knotsInLayer);

            for (curKnot = 0; curKnot < myPis->knotsInLayer; curKnot++) {
                myPis->plyInfo[curKnot] = defValue;
            }

            bytesAllocated = myPis->sizeInBytes;
            arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_plyInfos,
                                myPis->sizeInBytes, 0);
            myPis->plyInfoIsLoaded = true;
            memoryUsed2 += bytesAllocated;
            PRINT(3, this,
                  "Allocated " << bytesAllocated
                               << " bytes in memory for ply info of layer "
                               << layerNumber << " due to write operation!");
        }

        LeaveCriticalSection(&csDatabase);
    }

    // measure io-operations per second
    LARGE_INTEGER curTimeBefore;
    if constexpr (MEASURE_IOPS && MEASURE_ONLY_IO) {
        QueryPerformanceCounter(&curTimeBefore);
    }

    // set value
    myPis->plyInfo[stateNumber] = value;

    // measure io-operations per second
    measureIops(nWritePlyOps, writePlyInterval, curTimeBefore,
                (char *)"Write ply info   ");
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
