/*********************************************************************
    bufferedFile.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "bufferedFile.h"

//-----------------------------------------------------------------------------
// bufferedFile()
// Creates a cyclic array. The passed file is used as temporary data buffer for
// the cyclic array.
//-----------------------------------------------------------------------------
BufferedFile::BufferedFile(unsigned int numberOfThreads,
    unsigned int bufferSizeInBytes, const char* fileName)
{
    // locals
    unsigned int curThread;

    // Init blocks
    bufferSize = bufferSizeInBytes;
    numThreads = numberOfThreads;
    readBuffer = new unsigned char[numThreads * bufferSize];
    writeBuffer = new unsigned char[numThreads * bufferSize];
    curWritingPointer = new int64_t[numThreads];
    curReadingPointer = new int64_t[numThreads];
    bytesInReadBuffer = new unsigned int[numThreads];
    bytesInWriteBuffer = new unsigned int[numThreads];

    for (curThread = 0; curThread < numThreads; curThread++) {
        curReadingPointer[curThread] = 0;
        curWritingPointer[curThread] = 0;
        bytesInReadBuffer[curThread] = 0;
        bytesInWriteBuffer[curThread] = 0;
    }

    InitializeCriticalSection(&csIO);

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH |
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
    // flush buffers
    flushBuffers();
    DeleteCriticalSection(&csIO);

    // delete arrays
    delete[] readBuffer;
    delete[] writeBuffer;
    delete[] curReadingPointer;
    delete[] curWritingPointer;
    delete[] bytesInReadBuffer;
    delete[] bytesInWriteBuffer;

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
    for (unsigned int threadNo = 0; threadNo < numThreads; threadNo++) {
        writeDataToFile(hFile,
            curWritingPointer[threadNo] - bytesInWriteBuffer[threadNo],
            bytesInWriteBuffer[threadNo],
            &writeBuffer[threadNo * bufferSize + 0]);
        bytesInWriteBuffer[threadNo] = 0;
    }

    return true;
}

//-----------------------------------------------------------------------------
// writeDataToFile()
// Writes 'sizeInBytes'-bytes to the position 'offset' to the file.
//-----------------------------------------------------------------------------
void BufferedFile::writeDataToFile(
    HANDLE fd, int64_t offset, unsigned int sizeInBytes, void* pData)
{
    DWORD dwBytesWritten;
    LARGE_INTEGER liDistanceToMove;
    unsigned int restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    EnterCriticalSection(&csIO);

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl << "SetFilePointerEx  failed!";

    while (restingBytes > 0) {
        if (WriteFile(fd, pData, sizeInBytes, &dwBytesWritten, nullptr)
            == TRUE) {
            restingBytes -= dwBytesWritten;
            pData = (void*)(((unsigned char*)pData) + dwBytesWritten);
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
void BufferedFile::readDataFromFile(
    HANDLE fd, int64_t offset, unsigned int sizeInBytes, void* pData)
{
    DWORD dwBytesRead;
    LARGE_INTEGER liDistanceToMove;
    unsigned int restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    EnterCriticalSection(&csIO);

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl << "SetFilePointerEx failed!";

    while (restingBytes > 0) {
        if (ReadFile(fd, pData, sizeInBytes, &dwBytesRead, nullptr) == TRUE) {
            restingBytes -= dwBytesRead;
            pData = (void*)(((unsigned char*)pData) + dwBytesRead);
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
bool BufferedFile::writeBytes(unsigned int numBytes, unsigned char* pData)
{
    return writeBytes(0, curWritingPointer[0], numBytes, pData);
}

//-----------------------------------------------------------------------------
// writeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::writeBytes(unsigned int threadNo, int64_t positionInFile,
    unsigned int numBytes, unsigned char* pData)
{
    // parameters ok?
    if (threadNo >= numThreads)
        return false;

    if (pData == nullptr)
        return false;

    // locals

    // if buffer full or not sequential write operation write buffer to file
    if (bytesInWriteBuffer[threadNo]
        && (positionInFile != curWritingPointer[threadNo]
            || bytesInWriteBuffer[threadNo] + numBytes >= bufferSize)) {
        writeDataToFile(hFile,
            curWritingPointer[threadNo] - bytesInWriteBuffer[threadNo],
            bytesInWriteBuffer[threadNo],
            &writeBuffer[threadNo * bufferSize + 0]);
        bytesInWriteBuffer[threadNo] = 0;
    }

    // copy data into buffer
    memcpy(&writeBuffer[threadNo * bufferSize + bytesInWriteBuffer[threadNo]],
        pData, numBytes);
    bytesInWriteBuffer[threadNo] += numBytes;
    curWritingPointer[threadNo] = positionInFile + numBytes;

    // everything ok
    return true;
}

//-----------------------------------------------------------------------------
// takeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::readBytes(unsigned int numBytes, unsigned char* pData)
{
    return readBytes(0, curReadingPointer[0], numBytes, pData);
}

//-----------------------------------------------------------------------------
// takeBytes()
//
//-----------------------------------------------------------------------------
bool BufferedFile::readBytes(unsigned int threadNo, int64_t positionInFile,
    unsigned int numBytes, unsigned char* pData)
{
    // parameters ok?
    if (threadNo >= numThreads)
        return false;

    if (pData == nullptr)
        return false;

    // read from file into buffer if not enough data in buffer or if it is not
    // an sequential reading operation?
    if (positionInFile != curReadingPointer[threadNo]
        || bytesInReadBuffer[threadNo] < numBytes) {
        bytesInReadBuffer[threadNo] = ((positionInFile + bufferSize <= fileSize)
                ? bufferSize
                : (unsigned int)(fileSize - positionInFile));
        if (bytesInReadBuffer[threadNo] < numBytes)
            return false;
        readDataFromFile(hFile, positionInFile, bytesInReadBuffer[threadNo],
            &readBuffer[threadNo * bufferSize + bufferSize
                - bytesInReadBuffer[threadNo]]);
    }

    memcpy(pData,
        &readBuffer[threadNo * bufferSize + bufferSize
            - bytesInReadBuffer[threadNo]],
        numBytes);
    bytesInReadBuffer[threadNo] -= numBytes;
    curReadingPointer[threadNo] = positionInFile + numBytes;

    // everything ok
    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
