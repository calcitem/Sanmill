/*********************************************************************
	miniMax_database.cpp
	Copyright (c) Thomas Weber. All rights reserved.
	Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#include "miniMax.h"

//-----------------------------------------------------------------------------
// Name: ~MiniMax()
// Desc: MiniMax class destructor
//-----------------------------------------------------------------------------
void MiniMax::closeDatabase()
{
	// close database
	if (hFileShortKnotValues != nullptr)
	{
		unloadAllLayers();
		SAFE_DELETE_ARRAY(layerStats);
		CloseHandle(hFileShortKnotValues);
		hFileShortKnotValues = nullptr;
	}

	// close ply information file
	if (hFilePlyInfo != nullptr)
	{
		unloadAllPlyInfos();
		SAFE_DELETE_ARRAY(plyInfos);
		CloseHandle(hFilePlyInfo);
		hFilePlyInfo = nullptr;
	}
}

//-----------------------------------------------------------------------------
// Name: unloadPlyInfo()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::unloadPlyInfo(unsigned int layerNumber)
{
	PlyInfo *myPis = &plyInfos[layerNumber];
	memoryUsed2 -= myPis->sizeInBytes;
	arrayInfos.removeArray(layerNumber, ArrayInfo::arrayType_plyInfos, myPis->sizeInBytes, 0);
	SAFE_DELETE_ARRAY(myPis->plyInfo);
	myPis->plyInfoIsLoaded = false;
}

//-----------------------------------------------------------------------------
// Name: unloadLayer()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::unloadLayer(unsigned int layerNumber)
{
	LayerStats *myLss = &layerStats[layerNumber];
	SAFE_DELETE_ARRAY(myLss->shortKnotValueByte);
	memoryUsed2 -= myLss->sizeInBytes;
	arrayInfos.removeArray(layerNumber, ArrayInfo::arrayType_layerStats, myLss->sizeInBytes, 0);
	myLss->layerIsLoaded = false;
}

//-----------------------------------------------------------------------------
// Name: unloadAllPlyInfos()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::unloadAllPlyInfos()
{
	for (unsigned int i = 0; i < plyInfoHeader.numLayers; i++)
	{
		unloadPlyInfo(i);
	}
}

//-----------------------------------------------------------------------------
// Name: unloadAllLayers()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::unloadAllLayers()
{
	for (unsigned int i = 0; i < skvfHeader.numLayers; i++)
	{
		unloadLayer(i);
	}
}

//-----------------------------------------------------------------------------
// Name: saveBytesToFile()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::saveBytesToFile(HANDLE hFile, long long offset, unsigned int numBytes, void *pBytes)
{
	DWORD dwBytesWritten;
	LARGE_INTEGER liDistanceToMove;
	unsigned int restingBytes = numBytes;
	void *myPointer = pBytes;
	bool errorPrint = false;

	liDistanceToMove.QuadPart = offset;

	while (errorPrint = !SetFilePointerEx(hFile, liDistanceToMove, nullptr, FILE_BEGIN))
	{
		if (!errorPrint)
			PRINT(1, this, "ERROR: SetFilePointerEx  failed!");
	}

	while (restingBytes > 0)
	{
		if (WriteFile(hFile, myPointer, restingBytes, &dwBytesWritten, nullptr) == TRUE)
		{
			restingBytes -= dwBytesWritten;
			myPointer = (void *)(((unsigned char *)myPointer) + dwBytesWritten);
			if (restingBytes > 0)
				PRINT(2, this, "Still " << restingBytes << " to write!");
		}
		else
		{
			if (!errorPrint)
				PRINT(0, this, "ERROR: WriteFile Failed!");
			errorPrint = true;
		}
	}
}

//-----------------------------------------------------------------------------
// Name: loadBytesFromFile()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::loadBytesFromFile(HANDLE hFile, long long offset, unsigned int numBytes, void *pBytes)
{
	DWORD dwBytesRead;
	LARGE_INTEGER liDistanceToMove;
	unsigned int restingBytes = numBytes;
	void *myPointer = pBytes;
	bool errorPrint = false;

	liDistanceToMove.QuadPart = offset;

	while (errorPrint = !SetFilePointerEx(hFile, liDistanceToMove, nullptr, FILE_BEGIN))
	{
		if (!errorPrint)
			PRINT(0, this, "ERROR: SetFilePointerEx failed!");
	}

	while (restingBytes > 0)
	{
		if (ReadFile(hFile, pBytes, restingBytes, &dwBytesRead, nullptr) == TRUE)
		{
			restingBytes -= dwBytesRead;
			myPointer = (void *)(((unsigned char *)myPointer) + dwBytesRead);
			if (restingBytes > 0)
			{
				PRINT(2, this, "Still " << restingBytes << " bytes to read!");
			}
		}
		else
		{
			if (!errorPrint)
				PRINT(0, this, "ERROR: ReadFile Failed!");
			errorPrint = true;
		}
	}
}

//-----------------------------------------------------------------------------
// Name: isCurrentStateInDatabase()
// Desc:
//-----------------------------------------------------------------------------
bool MiniMax::isCurrentStateInDatabase(unsigned int threadNo)
{
	unsigned int layerNum, stateNumber;

	if (hFileShortKnotValues == nullptr)
	{
		return false;
	}
	else
	{
		getLayerAndStateNumber(threadNo, layerNum, stateNumber);
		return layerStats[layerNum].layerIsCompletedAndInFile;
	}
}

//-----------------------------------------------------------------------------
// Name: saveHeader()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::saveHeader(SkvFileHeader *dbH, LayerStats *lStats)
{
	DWORD dwBytesWritten;
	SetFilePointer(hFileShortKnotValues, 0, nullptr, FILE_BEGIN);
	WriteFile(hFileShortKnotValues, dbH, sizeof(SkvFileHeader), &dwBytesWritten, nullptr);
	WriteFile(hFileShortKnotValues, lStats, sizeof(LayerStats) * dbH->numLayers, &dwBytesWritten, nullptr);
}

//-----------------------------------------------------------------------------
// Name: saveHeader()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::saveHeader(PlyInfoFileHeader *piH, PlyInfo *pInfo)
{
	DWORD dwBytesWritten;
	SetFilePointer(hFilePlyInfo, 0, nullptr, FILE_BEGIN);
	WriteFile(hFilePlyInfo, piH, sizeof(PlyInfoFileHeader), &dwBytesWritten, nullptr);
	WriteFile(hFilePlyInfo, pInfo, sizeof(PlyInfo) * piH->numLayers, &dwBytesWritten, nullptr);
}

//-----------------------------------------------------------------------------
// Name: openDatabase()
// Desc:
//-----------------------------------------------------------------------------
bool MiniMax::openDatabase(const char *directory, unsigned int maximumNumberOfBranches)
{
	if (strlen(directory) && !PathFileExistsA(directory))
	{
		PRINT(0, this, "ERROR: Database path " << directory << " not valid!");
		return falseOrStop();
	}
	openSkvFile(directory, maximumNumberOfBranches);
	openPlyInfoFile(directory);
	return true;
}

//-----------------------------------------------------------------------------
// Name: openSkvFile()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::openSkvFile(const char *directory, unsigned int maximumNumberOfBranches)
{
	// locals
	stringstream ssDatabaseFile;
	DWORD dwBytesRead;
	unsigned int i;

	// don't open file twice
	if (hFileShortKnotValues != nullptr)
		return;

	// remember directory name
	fileDirectory.assign(directory);
	ssDatabaseFile << fileDirectory << (strlen(directory) ? "\\" : "") << "shortKnotValue.dat";
	PRINT(2, this, "Open short knot value file: " << fileDirectory << (strlen(directory) ? "\\" : "") << "shortKnotValue.dat" << endl);

	// Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_RANDOM_ACCESS)
	hFileShortKnotValues = CreateFileA(ssDatabaseFile.str().c_str(), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

	// opened file succesfully
	if (hFileShortKnotValues == INVALID_HANDLE_VALUE)
	{
		hFileShortKnotValues = nullptr;
		return;
	}

	// set header to invalid
	skvfHeader.headerCode = 0;
	maxNumBranches = maximumNumberOfBranches;

	// database complete ?
	ReadFile(hFileShortKnotValues, &skvfHeader, sizeof(SkvFileHeader), &dwBytesRead, nullptr);

	// invalid file ?
	if (dwBytesRead != sizeof(SkvFileHeader) || skvfHeader.headerCode != SKV_FILE_HEADER_CODE)
	{

		// create default header
		skvfHeader.completed = false;
		skvfHeader.numLayers = getNumberOfLayers();
		skvfHeader.headerCode = SKV_FILE_HEADER_CODE;
		skvfHeader.headerAndStatsSize = sizeof(LayerStats) * skvfHeader.numLayers + sizeof(SkvFileHeader);
		layerStats = new LayerStats[skvfHeader.numLayers];
		layerStats[0].layerOffset = 0;

		for (i = 0; i < skvfHeader.numLayers; i++)
		{
			getSuccLayers(i, &layerStats[i].numSuccLayers, &layerStats[i].succLayers[0]);
			layerStats[i].partnerLayer = getPartnerLayer(i);
			layerStats[i].knotsInLayer = getNumberOfKnotsInLayer(i);
			layerStats[i].sizeInBytes = (layerStats[i].knotsInLayer + 3) / 4;
			layerStats[i].shortKnotValueByte = nullptr;
			layerStats[i].skvCompressed = nullptr;
			layerStats[i].layerIsLoaded = false;
			layerStats[i].layerIsCompletedAndInFile = false;
			layerStats[i].numWonStates = 0;
			layerStats[i].numLostStates = 0;
			layerStats[i].numDrawnStates = 0;
			layerStats[i].numInvalidStates = 0;
		}

		for (i = 1; i < skvfHeader.numLayers; i++)
		{
			layerStats[i].layerOffset = layerStats[i - 1].layerOffset + layerStats[i - 1].sizeInBytes;
		}

		// write header
		saveHeader(&skvfHeader, layerStats);

		// read layer stats
	}
	else
	{
		layerStats = new LayerStats[skvfHeader.numLayers];
		ReadFile(hFileShortKnotValues, layerStats, sizeof(LayerStats) * skvfHeader.numLayers, &dwBytesRead, nullptr);
		for (i = 0; i < skvfHeader.numLayers; i++)
		{
			layerStats[i].shortKnotValueByte = nullptr;
			layerStats[i].skvCompressed = nullptr;
		}
	}
}

//-----------------------------------------------------------------------------
// Name: openPlyInfoFile()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::openPlyInfoFile(const char *directory)
{
	// locals
	stringstream ssFile;
	DWORD dwBytesRead;
	unsigned int i;

	// don't open file twice
	if (hFilePlyInfo != nullptr)
		return;

	// remember directory name
	ssFile << directory << (strlen(directory) ? "\\" : "") << "plyInfo.dat";
	PRINT(2, this, "Open ply info file: " << ssFile.str() << endl
										  << endl);

	// Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_RANDOM_ACCESS)
	hFilePlyInfo = CreateFileA(ssFile.str().c_str(), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

	// opened file succesfully
	if (hFilePlyInfo == INVALID_HANDLE_VALUE)
	{
		hFilePlyInfo = nullptr;
		return;
	}

	// set header to invalid
	plyInfoHeader.headerCode = 0;

	// database complete ?
	ReadFile(hFilePlyInfo, &plyInfoHeader, sizeof(plyInfoHeader), &dwBytesRead, nullptr);

	// invalid file ?
	if (dwBytesRead != sizeof(plyInfoHeader) || plyInfoHeader.headerCode != PLYINFO_HEADER_CODE)
	{

		// create default header
		plyInfoHeader.plyInfoCompleted = false;
		plyInfoHeader.numLayers = getNumberOfLayers();
		plyInfoHeader.headerCode = PLYINFO_HEADER_CODE;
		plyInfoHeader.headerAndPlyInfosSize = sizeof(PlyInfo) * plyInfoHeader.numLayers + sizeof(plyInfoHeader);
		plyInfos = new PlyInfo[plyInfoHeader.numLayers];
		plyInfos[0].layerOffset = 0;

		for (i = 0; i < plyInfoHeader.numLayers; i++)
		{
			plyInfos[i].knotsInLayer = getNumberOfKnotsInLayer(i);
			plyInfos[i].plyInfo = nullptr;
			plyInfos[i].plyInfoCompressed = nullptr;
			plyInfos[i].plyInfoIsLoaded = false;
			plyInfos[i].plyInfoIsCompletedAndInFile = false;
			plyInfos[i].sizeInBytes = plyInfos[i].knotsInLayer * sizeof(PlyInfoVarType);
		}

		for (i = 1; i < plyInfoHeader.numLayers; i++)
		{
			plyInfos[i].layerOffset = plyInfos[i - 1].layerOffset + plyInfos[i - 1].sizeInBytes;
		}

		// write header
		saveHeader(&plyInfoHeader, plyInfos);

		// read layer stats
	}
	else
	{
		plyInfos = new PlyInfo[plyInfoHeader.numLayers];
		ReadFile(hFilePlyInfo, plyInfos, sizeof(PlyInfo) * plyInfoHeader.numLayers, &dwBytesRead, nullptr);
		for (i = 0; i < plyInfoHeader.numLayers; i++)
		{
			plyInfos[i].plyInfo = nullptr;
			plyInfos[i].plyInfoCompressed = nullptr;
		}
	}
}

//-----------------------------------------------------------------------------
// Name: saveLayerToFile()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::saveLayerToFile(unsigned int layerNumber)
{
	// don't save layer and header when only preparing layers
	PlyInfo *myPis = &plyInfos[layerNumber];
	LayerStats *myLss = &layerStats[layerNumber];
	if (onlyPrepareLayer)
		return;

	// save layer if there are any states
	if (myLss->sizeInBytes)
	{

		// short knot values & ply info
		curCalculationActionId = MM_ACTION_SAVING_LAYER_TO_FILE;
		saveBytesToFile(hFileShortKnotValues, skvfHeader.headerAndStatsSize + myLss->layerOffset, myLss->sizeInBytes, myLss->shortKnotValueByte);
		saveBytesToFile(hFilePlyInfo, plyInfoHeader.headerAndPlyInfosSize + myPis->layerOffset, myPis->sizeInBytes, myPis->plyInfo);
	}

	// mark layer as completed
	myLss->layerIsCompletedAndInFile = true;
	myPis->plyInfoIsCompletedAndInFile = true;
}

//-----------------------------------------------------------------------------
// Name: measureIops()
// Desc:
//-----------------------------------------------------------------------------
inline void MiniMax::measureIops(long long &numOperations, LARGE_INTEGER &interval, LARGE_INTEGER &curTimeBefore, char text[])
{
	// locals
	LARGE_INTEGER curTimeAfter;

	if (!MEASURE_IOPS)
		return;
	numOperations++; // ... not thread-safe !!!

	// only the time for the io-operation is considered and accumulated
	if (MEASURE_ONLY_IO)
	{
		QueryPerformanceCounter(&curTimeAfter);
		interval.QuadPart += curTimeAfter.QuadPart - curTimeBefore.QuadPart;   // ... not thread-safe !!!
		double totalTimeGone = (double)interval.QuadPart / frequency.QuadPart; // ... not thread-safe !!!
		if (totalTimeGone >= 5.0)
		{
			PRINT(0, this, text << "operations per second for last interval: " << (int)(numOperations / totalTimeGone));
			interval.QuadPart = 0; // ... not thread-safe !!!
			numOperations = 0;	   // ... not thread-safe !!!
		}
		// the whole time passed since the beginning of the interval is considered
	}
	else if (numOperations >= MEASURE_TIME_FREQUENCY)
	{
		QueryPerformanceCounter(&curTimeAfter);
		double totalTimeGone = (double)(curTimeAfter.QuadPart - interval.QuadPart) / frequency.QuadPart; // ... not thread-safe !!!
		PRINT(0, this, text << "operations per second for last interval: " << numOperations / totalTimeGone);
		interval.QuadPart = curTimeAfter.QuadPart; // ... not thread-safe !!!
		numOperations = 0;						   // ... not thread-safe !!!
	}
}

//-----------------------------------------------------------------------------
// Name: readKnotValueFromDatabase()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::readKnotValueFromDatabase(unsigned int threadNo, unsigned int &layerNumber, unsigned int &stateNumber, TwoBit &knotValue, bool &invalidLayerOrStateNumber, bool &layerInDatabaseAndCompleted)
{
	// get state number, since this is the address, where the value is saved
	getLayerAndStateNumber(threadNo, layerNumber, stateNumber);

	// layer in database and completed ?
	LayerStats *myLss = &layerStats[layerNumber];
	layerInDatabaseAndCompleted = myLss->layerIsCompletedAndInFile;

	// valid state and layer number ?
	if (layerNumber > skvfHeader.numLayers || stateNumber > myLss->knotsInLayer)
	{
		invalidLayerOrStateNumber = true;
	}
	else
	{
		invalidLayerOrStateNumber = false; // checkStateIntegrity();
	}

	if (invalidLayerOrStateNumber)
	{
		knotValue = SKV_VALUE_INVALID;
		return;
	}

	// read
	readKnotValueFromDatabase(layerNumber, stateNumber, knotValue);
}

//-----------------------------------------------------------------------------
// Name: readKnotValueFromDatabase()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::readKnotValueFromDatabase(unsigned int layerNumber, unsigned int stateNumber, TwoBit &knotValue)
{
	// locals
	TwoBit databaseByte;
	long long bytesAllocated;
	TwoBit defValue = SKV_WHOLE_BYTE_IS_INVALID;
	LayerStats *myLss = &layerStats[layerNumber];

	// valid state and layer number ?
	if (layerNumber > skvfHeader.numLayers || stateNumber > myLss->knotsInLayer)
	{
		PRINT(0, this, "ERROR: INVALID layerNumber OR stateNumber in readKnotValueFromDatabase()!");
		knotValue = SKV_VALUE_INVALID;
		return;
	}

	//  if database is complete get whole byte from file
	if (skvfHeader.completed || layerInDatabase || myLss->layerIsCompletedAndInFile)
	{
		EnterCriticalSection(&csDatabase);
		loadBytesFromFile(hFileShortKnotValues, skvfHeader.headerAndStatsSize + myLss->layerOffset + stateNumber / 4, 1, &databaseByte);
		LeaveCriticalSection(&csDatabase);
	}
	else
	{

		// is layer already loaded
		if (!myLss->layerIsLoaded)
		{

			EnterCriticalSection(&csDatabase);
			if (!myLss->layerIsLoaded)
			{
				// if layer is in database and completed, then load layer from file into memory, set default value otherwise
				myLss->shortKnotValueByte = new unsigned char[myLss->sizeInBytes];
				if (myLss->layerIsCompletedAndInFile)
				{
					loadBytesFromFile(hFileShortKnotValues, skvfHeader.headerAndStatsSize + myLss->layerOffset, myLss->sizeInBytes, myLss->shortKnotValueByte);
				}
				else
				{
					memset(myLss->shortKnotValueByte, SKV_WHOLE_BYTE_IS_INVALID, myLss->sizeInBytes);
				}
				bytesAllocated = myLss->sizeInBytes;
				arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_layerStats, myLss->sizeInBytes, 0);

				// output
				myLss->layerIsLoaded = true;
				memoryUsed2 += bytesAllocated;
				PRINT(3, this, "Allocated " << bytesAllocated << " bytes in memory for knot values of layer " << layerNumber << ", which is " << (myLss->layerIsCompletedAndInFile ? "" : " NOT ") << " fully calculated, due to read operation.");
			}
			LeaveCriticalSection(&csDatabase);
		}

		// measure io-operations per second
		LARGE_INTEGER curTimeBefore;
		if (MEASURE_IOPS && MEASURE_ONLY_IO)
		{
			QueryPerformanceCounter(&curTimeBefore);
		}

		// read ply info from array
		databaseByte = myLss->shortKnotValueByte[stateNumber / 4];

		// measure io-operations per second
		measureIops(numReadSkvOperations, readSkvInterval, curTimeBefore, "Read  knot value ");
	}

	// make half byte
	knotValue = _rotr8(databaseByte, 2 * (stateNumber % 4)) & 3;
}

//-----------------------------------------------------------------------------
// Name: readPlyInfoFromDatabase()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::readPlyInfoFromDatabase(unsigned int layerNumber, unsigned int stateNumber, PlyInfoVarType &value)
{
	// locals
	unsigned int curKnot;
	PlyInfoVarType defValue = PLYINFO_VALUE_UNCALCULATED;
	long long bytesAllocated;
	PlyInfo *myPis = &plyInfos[layerNumber];

	// valid state and layer number ?
	if (layerNumber > plyInfoHeader.numLayers || stateNumber > myPis->knotsInLayer)
	{
		PRINT(0, this, "ERROR: INVALID layerNumber OR stateNumber in readPlyInfoFromDatabase()!");
		value = PLYINFO_VALUE_INVALID;
		return;
	}

	// if database is complete get whole byte from file
	if (plyInfoHeader.plyInfoCompleted || layerInDatabase || myPis->plyInfoIsCompletedAndInFile)
	{
		EnterCriticalSection(&csDatabase);
		loadBytesFromFile(hFilePlyInfo, plyInfoHeader.headerAndPlyInfosSize + myPis->layerOffset + sizeof(PlyInfoVarType) * stateNumber, sizeof(PlyInfoVarType), &value);
		LeaveCriticalSection(&csDatabase);
	}
	else
	{

		// is layer already in memory?
		if (!myPis->plyInfoIsLoaded)
		{
			EnterCriticalSection(&csDatabase);
			if (!myPis->plyInfoIsLoaded)
			{
				// if layer is in database and completed, then load layer from file into memory; set default value otherwise
				myPis->plyInfo = new PlyInfoVarType[myPis->knotsInLayer];
				if (myPis->plyInfoIsCompletedAndInFile)
				{
					loadBytesFromFile(hFilePlyInfo, plyInfoHeader.headerAndPlyInfosSize + myPis->layerOffset, myPis->sizeInBytes, myPis->plyInfo);
				}
				else
				{
					for (curKnot = 0; curKnot < myPis->knotsInLayer; curKnot++)
					{
						myPis->plyInfo[curKnot] = defValue;
					}
				}
				bytesAllocated = myPis->sizeInBytes;
				arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_plyInfos, myPis->sizeInBytes, 0);
				myPis->plyInfoIsLoaded = true;
				memoryUsed2 += bytesAllocated;
				PRINT(3, this, "Allocated " << bytesAllocated << " bytes in memory for ply info of layer " << layerNumber << ", which is " << (myPis->plyInfoIsCompletedAndInFile ? "" : " NOT ") << " fully calculated, due to read operation.");
			}
			LeaveCriticalSection(&csDatabase);
		}

		// measure io-operations per second
		LARGE_INTEGER curTimeBefore;
		if (MEASURE_IOPS && MEASURE_ONLY_IO)
		{
			QueryPerformanceCounter(&curTimeBefore);
		}

		// read ply info from array
		value = myPis->plyInfo[stateNumber];

		// measure io-operations per second
		measureIops(numReadPlyOperations, readPlyInterval, curTimeBefore, "Read  ply info   ");
	}
}

//-----------------------------------------------------------------------------
// Name: saveKnotValueInDatabase()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::saveKnotValueInDatabase(unsigned int layerNumber, unsigned int stateNumber, TwoBit knotValue)
{
	// locals
	long long bytesAllocated;
	TwoBit defValue = SKV_WHOLE_BYTE_IS_INVALID;
	LayerStats *myLss = &layerStats[layerNumber];

	// valid state and layer number ?
	if (layerNumber > skvfHeader.numLayers || stateNumber > myLss->knotsInLayer)
	{
		PRINT(0, this, "ERROR: INVALID layerNumber OR stateNumber in saveKnotValueInDatabase()!");
		return;
	}

	// is layer already completed ?
	if (myLss->layerIsCompletedAndInFile)
	{
		PRINT(0, this, "ERROR: layer already completed and in file! function: saveKnotValueInDatabase()!");
		return;
	}

	// is layer already loaded?
	if (!myLss->layerIsLoaded)
	{

		EnterCriticalSection(&csDatabase);
		if (!myLss->layerIsLoaded)
		{
			// reserve memory for this layer & create array for ply info with default value
			myLss->shortKnotValueByte = new TwoBit[myLss->sizeInBytes];
			memset(myLss->shortKnotValueByte, SKV_WHOLE_BYTE_IS_INVALID, myLss->sizeInBytes);
			bytesAllocated = myLss->sizeInBytes;
			arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_layerStats, myLss->sizeInBytes, 0);

			// output
			memoryUsed2 += bytesAllocated;
			PRINT(3, this, "Allocated " << bytesAllocated << " bytes in memory for knot values of layer " << layerNumber << " due to write operation!");
			myLss->layerIsLoaded = true;
		}
		LeaveCriticalSection(&csDatabase);
	}

	// measure io-operations per second
	LARGE_INTEGER curTimeBefore;
	if (MEASURE_IOPS && MEASURE_ONLY_IO)
	{
		QueryPerformanceCounter(&curTimeBefore);
	}

	// set value
	long *pShortKnotValue = ((long *)myLss->shortKnotValueByte) + stateNumber / ((sizeof(long) * 8) / 2);
	long numBitsToShift = 2 * (stateNumber % ((sizeof(long) * 8) / 2)); // little-endian byte-order
	long mask = 0x00000003 << numBitsToShift;
	long curShortKnotValueLong, newShortKnotValueLong;

	do
	{
		curShortKnotValueLong = *pShortKnotValue;
		newShortKnotValueLong = (curShortKnotValueLong & (~mask)) + (knotValue << numBitsToShift);
	} while (InterlockedCompareExchange(pShortKnotValue, newShortKnotValueLong, curShortKnotValueLong) != curShortKnotValueLong);

	// measure io-operations per second
	measureIops(numWriteSkvOperations, writeSkvInterval, curTimeBefore, "Write knot value ");
}

//-----------------------------------------------------------------------------
// Name: savePlyInfoInDatabase()
// Desc:
//-----------------------------------------------------------------------------
void MiniMax::savePlyInfoInDatabase(unsigned int layerNumber, unsigned int stateNumber, PlyInfoVarType value)
{
	// locals
	unsigned int curKnot;
	PlyInfoVarType defValue = PLYINFO_VALUE_UNCALCULATED;
	long long bytesAllocated;
	PlyInfo *myPis = &plyInfos[layerNumber];

	// valid state and layer number ?
	if (layerNumber > plyInfoHeader.numLayers || stateNumber > myPis->knotsInLayer)
	{
		PRINT(0, this, "ERROR: INVALID layerNumber OR stateNumber in savePlyInfoInDatabase()!");
		return;
	}

	// is layer already completed ?
	if (myPis->plyInfoIsCompletedAndInFile)
	{
		PRINT(0, this, "ERROR: layer already completed and in file! function: savePlyInfoInDatabase()!");
		return;
	}

	// is layer already loaded
	if (!myPis->plyInfoIsLoaded)
	{

		EnterCriticalSection(&csDatabase);
		if (!myPis->plyInfoIsLoaded)
		{
			// reserve memory for this layer & create array for ply info with default value
			myPis->plyInfo = new PlyInfoVarType[myPis->knotsInLayer];
			for (curKnot = 0; curKnot < myPis->knotsInLayer; curKnot++)
			{
				myPis->plyInfo[curKnot] = defValue;
			}
			bytesAllocated = myPis->sizeInBytes;
			arrayInfos.addArray(layerNumber, ArrayInfo::arrayType_plyInfos, myPis->sizeInBytes, 0);
			myPis->plyInfoIsLoaded = true;
			memoryUsed2 += bytesAllocated;
			PRINT(3, this, "Allocated " << bytesAllocated << " bytes in memory for ply info of layer " << layerNumber << " due to write operation!");
		}
		LeaveCriticalSection(&csDatabase);
	}

	// measure io-operations per second
	LARGE_INTEGER curTimeBefore;
	if (MEASURE_IOPS && MEASURE_ONLY_IO)
	{
		QueryPerformanceCounter(&curTimeBefore);
	}

	// set value
	myPis->plyInfo[stateNumber] = value;

	// measure io-operations per second
	measureIops(numWritePlyOperations, writePlyInterval, curTimeBefore, "Write ply info   ");
}
