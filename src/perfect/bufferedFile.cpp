/*********************************************************************
    bufedFile.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "bufferedFile.h"

//-----------------------------------------------------------------------------
// BufferedFile()
// Creates a cyclic array. The passed file is used as temporary data buf for
// the cyclic array.
//-----------------------------------------------------------------------------
BufferedFile::BufferedFile(uint32_t nThreads, uint32_t bufSizeInBytes,
                           const char *fileName)
{
    // Init blocks
    bufSize = bufSizeInBytes;
    nThreads = nThreads;
    readBuf = new unsigned char[nThreads * bufSize];
    std::memset(readBuf, 0, nThreads * bufSize);
    writeBuf = new unsigned char[nThreads * bufSize];
    std::memset(writeBuf, 0, nThreads * bufSize);
    curWritingPtr = new int64_t[nThreads];
    std::memset(curWritingPtr, 0, sizeof(int64_t) * nThreads);
    curReadingPtr = new int64_t[nThreads];
    std::memset(curReadingPtr, 0, sizeof(int64_t) * nThreads);
    bytesInReadBuf = new uint32_t[nThreads];
    std::memset(bytesInReadBuf, 0, sizeof(uint32_t) * nThreads);
    bytesInWriteBuf = new uint32_t[nThreads];
    std::memset(bytesInWriteBuf, 0, sizeof(uint32_t) * nThreads);

    for (uint32_t thd = 0; thd < nThreads; thd++) {
        curReadingPtr[thd] = 0;
        curWritingPtr[thd] = 0;
        bytesInReadBuf[thd] = 0;
        bytesInWriteBuf[thd] = 0;
    }

    InitializeCriticalSection(&csIO);

    // Open Database-File
    // (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH |
    // FILE_FLAG_RANDOM_ACCESS)
    hFile = CreateFileA(fileName, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file successfully
    if (hFile == INVALID_HANDLE_VALUE) {
        hFile = nullptr;
        return;
    }

    // update file size
    getFileSize();
}

//-----------------------------------------------------------------------------
// ~BufferedFile()
// BufferedFile class destructor
//-----------------------------------------------------------------------------
BufferedFile::~BufferedFile()
{
    // flush bufs
    flushBuffers();
    DeleteCriticalSection(&csIO);

    // delete arrays
    delete[] readBuf;
    delete[] writeBuf;
    delete[] curReadingPtr;
    delete[] curWritingPtr;
    delete[] bytesInReadBuf;
    delete[] bytesInWriteBuf;

    // close file
    if (hFile != nullptr)
        CloseHandle(hFile);
}

//-----------------------------------------------------------------------------
// getFileSize()
//
//-----------------------------------------------------------------------------
int64_t BufferedFile::getFileSize()
{
    LARGE_INTEGER liFileSize;
    GetFileSizeEx(hFile, &liFileSize);
    fileSize = liFileSize.QuadPart;

    return fileSize;
}

//-----------------------------------------------------------------------------
// flushBuffers()
//
//-----------------------------------------------------------------------------
bool BufferedFile::flushBuffers()
{
    for (uint32_t thd = 0; thd < threadCount; thd++) {
        writeDataToFile(hFile, curWritingPtr[thd] - bytesInWriteBuf[thd],
                        bytesInWriteBuf[thd], &writeBuf[thd * bufSize + 0]);
        bytesInWriteBuf[thd] = 0;
    }

    return true;
}

//-----------------------------------------------------------------------------
// writeDataToFile()
// Writes 'sizeInBytes'-bytes to the position 'offset' to the file.
//-----------------------------------------------------------------------------
void BufferedFile::writeDataToFile(HANDLE fd, int64_t offset,
                                   uint32_t sizeInBytes, void *pData)
{
    DWORD dwBytesWritten;
    LARGE_INTEGER liDistanceToMove;
    uint32_t restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    EnterCriticalSection(&csIO);

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl << "SetFilePointerEx  failed!";

    while (restingBytes > 0) {
        if (WriteFile(fd, pData, sizeInBytes, &dwBytesWritten, nullptr) ==
            TRUE) {
            restingBytes -= dwBytesWritten;
            pData = static_cast<void *>(static_cast<unsigned char *>(pData) +
                                        dwBytesWritten);
            if (restingBytes > 0)
                cout << endl << "Still " << restingBytes << " to write!";
        } else {
            cout << endl << "WriteFile Failed!";
        }
    }

    LeaveCriticalSection(&csIO);
}

//-----------------------------------------------------------------------------
// readDataFromFile()
// Reads 'sizeInBytes'-bytes from the position 'offset' of the file.
//-----------------------------------------------------------------------------
void BufferedFile::readDataFromFile(HANDLE fd, int64_t offset,
                                    uint32_t sizeInBytes, void *pData)
{
    DWORD dwBytesRead;
    LARGE_INTEGER liDistanceToMove;
    uint32_t restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    EnterCriticalSection(&csIO);

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl << "SetFilePointerEx failed!";

    while (restingBytes > 0) {
        if (ReadFile(fd, pData, sizeInBytes, &dwBytesRead, nullptr) == TRUE) {
            restingBytes -= dwBytesRead;
            pData = static_cast<void *>(static_cast<unsigned char *>(pData) +
                                        dwBytesRead);
            if (restingBytes > 0)
                cout << endl << "Still " << restingBytes << " to read!";
        } else {
            cout << endl << "ReadFile Failed!";
        }
    }

    LeaveCriticalSection(&csIO);
}

//-----------------------------------------------------------------------------
// writeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::writeBytes(uint32_t nBytes, unsigned char *pData)
{
    return writeBytes(0, curWritingPtr[0], nBytes, pData);
}

//-----------------------------------------------------------------------------
// writeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::writeBytes(uint32_t threadNo, int64_t positionInFile,
                              uint32_t nBytes, unsigned char *pData)
{
#if 0
    // TODO(calcitem): Use ThreadManager.threadCount instead of threadCount
    // params ok?
    if (threadNo >= threadCount)
        return false;
#endif

    if (pData == nullptr)
        return false;

    // locals

    // if buf full or not sequential write operation write buf to file
    if (bytesInWriteBuf[threadNo] &&
        (positionInFile != curWritingPtr[threadNo] ||
         bytesInWriteBuf[threadNo] + nBytes >= bufSize)) {
        writeDataToFile(hFile,
                        curWritingPtr[threadNo] - bytesInWriteBuf[threadNo],
                        bytesInWriteBuf[threadNo],
                        &writeBuf[threadNo * bufSize + 0]);
        bytesInWriteBuf[threadNo] = 0;
    }

    // copy data into buf
    memcpy(&writeBuf[threadNo * bufSize + bytesInWriteBuf[threadNo]], pData,
           nBytes);
    bytesInWriteBuf[threadNo] += nBytes;
    curWritingPtr[threadNo] = positionInFile + nBytes;

    // everything ok
    return true;
}

//-----------------------------------------------------------------------------
// takeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::readBytes(uint32_t nBytes, unsigned char *pData)
{
    return readBytes(0, curReadingPtr[0], nBytes, pData);
}

//-----------------------------------------------------------------------------
// takeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::readBytes(uint32_t threadNo, int64_t positionInFile,
                             uint32_t nBytes, unsigned char *pData)
{
    // params ok?
    if (threadNo >= threadCount)
        return false;

    if (pData == nullptr)
        return false;

    // read from file into buf if not enough data in buf or if it is not
    // an sequential reading operation?
    if (positionInFile != curReadingPtr[threadNo] ||
        bytesInReadBuf[threadNo] < nBytes) {
        bytesInReadBuf[threadNo] = (positionInFile + bufSize <= fileSize) ?
                                       bufSize :
                                       static_cast<uint32_t>(fileSize -
                                                             positionInFile);
        if (bytesInReadBuf[threadNo] < nBytes)
            return false;
        readDataFromFile(
            hFile, positionInFile, bytesInReadBuf[threadNo],
            &readBuf[threadNo * bufSize + bufSize - bytesInReadBuf[threadNo]]);
    }

    memcpy(pData,
           &readBuf[threadNo * bufSize + bufSize - bytesInReadBuf[threadNo]],
           nBytes);
    bytesInReadBuf[threadNo] -= nBytes;
    curReadingPtr[threadNo] = positionInFile + nBytes;

    // everything ok
    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
