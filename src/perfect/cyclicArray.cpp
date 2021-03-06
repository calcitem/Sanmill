/*********************************************************************
    CyclicArray.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "cyclicArray.h"

//-----------------------------------------------------------------------------
// CyclicArray()
// Creates a cyclic array. The passed file is used as temporary data buffer for the cyclic array.
//-----------------------------F------------------------------------------------
CyclicArray::CyclicArray(unsigned int blockSizeInBytes, unsigned int numberOfBlocks, const char *fileName)
{
    // Init blocks
    blockSize = blockSizeInBytes;
    numBlocks = numberOfBlocks;
    readingBlock = new unsigned char[blockSize];
    writingBlock = new unsigned char[blockSize];
    curReadingPointer = writingBlock;
    curWritingPointer = writingBlock;
    readWriteInSameRound = true;
    curReadingBlock = 0;
    curWritingBlock = 0;

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_RANDOM_ACCESS)
    hFile = CreateFileA(fileName, 
                        GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, 
                        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file succesfully
    if (hFile == INVALID_HANDLE_VALUE) {
        hFile = nullptr;
        return;
    }
}

//-----------------------------------------------------------------------------
// ~RandomAI()
// RandomAI class destructor
//-----------------------------------------------------------------------------
CyclicArray::~CyclicArray()
{
    // delete arrays
    delete[] readingBlock;
    delete[] writingBlock;

    // close file
    if (hFile != nullptr)
        CloseHandle(hFile);
}

//-----------------------------------------------------------------------------
// writeDataToFile()
// Writes 'sizeInBytes'-bytes to the position 'offset' to the file.
//-----------------------------------------------------------------------------
void CyclicArray::writeDataToFile(HANDLE fd, long long offset, unsigned int sizeInBytes, void *pData)
{
    DWORD dwBytesWritten;
    LARGE_INTEGER liDistanceToMove;
    unsigned int restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl
        << "SetFilePointerEx  failed!";

    while (restingBytes > 0) {
        if (WriteFile(fd, pData, sizeInBytes, &dwBytesWritten, nullptr) == TRUE) {
            restingBytes -= dwBytesWritten;
            pData = (void *)(((unsigned char *)pData) + dwBytesWritten);
            if (restingBytes > 0)
                cout << endl
                << "Still " << restingBytes << " to write!";
        } else {
            cout << endl
                << "WriteFile Failed!";
        }
    }
}

//-----------------------------------------------------------------------------
// readDataFromFile()
// Reads 'sizeInBytes'-bytes from the position 'offset' of the file.
//-----------------------------------------------------------------------------
void CyclicArray::readDataFromFile(HANDLE fd, long long offset, unsigned int sizeInBytes, void *pData)
{
    DWORD dwBytesRead;
    LARGE_INTEGER liDistanceToMove;
    unsigned int restingBytes = sizeInBytes;

    liDistanceToMove.QuadPart = offset;

    while (!SetFilePointerEx(fd, liDistanceToMove, nullptr, FILE_BEGIN))
        cout << endl
        << "SetFilePointerEx failed!";

    while (restingBytes > 0) {
        if (ReadFile(fd, pData, sizeInBytes, &dwBytesRead, nullptr) == TRUE) {
            restingBytes -= dwBytesRead;
            pData = (void *)(((unsigned char *)pData) + dwBytesRead);
            if (restingBytes > 0)
                cout << endl
                << "Still " << restingBytes << " to read!";
        } else {
            cout << endl
                << "ReadFile Failed!";
        }
    }
}

//-----------------------------------------------------------------------------
// addBytes()
// Add the passed data to the cyclic array. If the writing pointer reaches the end of a block,
//       the data of the whole block is written to the file and the next block is considered for writing.
//-----------------------------------------------------------------------------
bool CyclicArray::addBytes(unsigned int numBytes, unsigned char *pData)
{
    // locals
    unsigned int bytesWritten = 0;

    // write each byte
    while (bytesWritten < numBytes) {

        // store byte in current reading block
        *curWritingPointer = *pData;
        curWritingPointer++;
        bytesWritten++;
        pData++;

        // when block is full then save current one to file and begin new one
        if (curWritingPointer == writingBlock + blockSize) {

            // copy data into reading block?
            if (curReadingBlock == curWritingBlock) {
                memcpy(readingBlock, writingBlock, blockSize);
                curReadingPointer = readingBlock + (curReadingPointer - writingBlock);
            }

            // will reading block be overwritten?
            if (curReadingBlock == curWritingBlock && !readWriteInSameRound)
                return false;

            // store bock in file
            writeDataToFile(hFile, ((long long)blockSize) * ((long long)curWritingBlock), blockSize, writingBlock);

            // set pointer to beginnig of writing block
            curWritingPointer = writingBlock;
            curWritingBlock = (curWritingBlock + 1) % numBlocks;

            if (curWritingBlock == 0)
                readWriteInSameRound = false;
        }
    }

    // everything ok
    return true;
}

//-----------------------------------------------------------------------------
// bytesAvailable()
// 
//-----------------------------------------------------------------------------
bool CyclicArray::bytesAvailable()
{
    if (curReadingBlock == curWritingBlock && curReadingPointer == curWritingPointer && readWriteInSameRound)
        return false;
    else
        return true;
}

//-----------------------------------------------------------------------------
// takeBytes()
// Load data from the cyclic array. If the reading pointer reaches the end of a block,
//       the data of the next whole block is read from the file.
//-----------------------------------------------------------------------------
bool CyclicArray::takeBytes(unsigned int numBytes, unsigned char *pData)
{
    // locals
    unsigned int bytesRead = 0;

    // read each byte
    while (bytesRead < numBytes) {

        // was current reading byte already written ?
        if (curReadingBlock == curWritingBlock && curReadingPointer == curWritingPointer && readWriteInSameRound)
            return false;

        // read current byte
        *pData = *curReadingPointer;
        curReadingPointer++;
        bytesRead++;
        pData++;

        // load next block?
        if (curReadingPointer == readingBlock + blockSize) {
            // go to next block
            curReadingBlock = (curReadingBlock + 1) % numBlocks;
            if (curReadingBlock == 0)
                readWriteInSameRound = true;

            // writing block reached ?
            if (curReadingBlock == curWritingBlock) {
                curReadingPointer = writingBlock;
            } else {
                // set pointer to beginnig of reading block
                curReadingPointer = readingBlock;

                // read whole block from file
                readDataFromFile(hFile, ((long long)blockSize) * ((long long)curReadingBlock), blockSize, readingBlock);
            }
        }
    }

    // everything ok
    return true;
}

//-----------------------------------------------------------------------------
// loadFile()
// Load the passed file into the cyclic array.
//       The passed filename must be different than the passed filename to the constructor cyclicarray().
//-----------------------------------------------------------------------------
bool CyclicArray::loadFile(const char *fileName, LONGLONG &numBytesLoaded)
{
    // locals
    HANDLE hLoadFile;
    unsigned char *dataInFile;
    LARGE_INTEGER largeInt;
    LONGLONG maxFileSize = ((LONGLONG)blockSize) * ((LONGLONG)numBlocks);
    LONGLONG curOffset = 0;
    unsigned int numBlocksInFile;
    unsigned int curBlock;
    unsigned int numBytesInLastBlock;
    numBytesLoaded = 0;

    // cyclic array file must be open
    if (hFile == nullptr)
        return false;

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_RANDOM_ACCESS)
    hLoadFile = CreateFileA(fileName, 
                            GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file succesfully
    if (hLoadFile == INVALID_HANDLE_VALUE) {
        return false;
    }

    // does data of file fit into cyclic array ?
    GetFileSizeEx(hLoadFile, &largeInt);

    if (maxFileSize < largeInt.QuadPart) {
        CloseHandle(hLoadFile);
        return false;
    }

    // reset
    curReadingPointer = writingBlock;
    curWritingPointer = writingBlock;
    readWriteInSameRound = true;
    curReadingBlock = 0;
    curWritingBlock = 0;

    numBlocksInFile = (unsigned int)(largeInt.QuadPart / ((LONGLONG)blockSize)) + 1;
    numBytesInLastBlock = (unsigned int)(largeInt.QuadPart % ((LONGLONG)blockSize));
    dataInFile = new unsigned char[blockSize];

    //
    for (curBlock = 0; curBlock < numBlocksInFile - 1; curBlock++, curOffset += blockSize) {
        // load data from file
        readDataFromFile(hLoadFile, curOffset, blockSize, dataInFile);

        // put block in cyclic array
        addBytes(blockSize, dataInFile);
    }

    // last block
    readDataFromFile(hLoadFile, curOffset, numBytesInLastBlock, dataInFile);
    addBytes(numBytesInLastBlock, dataInFile);
    curOffset += numBytesInLastBlock;
    numBytesLoaded = curOffset;

    // everything ok
    delete[] dataInFile;
    CloseHandle(hLoadFile);
    return true;
}

//-----------------------------------------------------------------------------
// saveFile()
// Writes the whole current content of the cyclic array to the passed file.
//       The passed filename must be different than the passed filename to the constructor cyclicarray().
//-----------------------------------------------------------------------------
bool CyclicArray::saveFile(const char *fileName)
{
    // locals
    unsigned char *dataInFile;
    HANDLE hSaveFile;
    LONGLONG curOffset;
    unsigned int curBlock;
    unsigned int bytesToWrite;
    void *pointer;

    // cyclic array file must be open
    if (hFile == nullptr) {
        return false;
    }

    // Open Database-File (FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_RANDOM_ACCESS)
    hSaveFile = CreateFileA(fileName, 
                            GENERIC_WRITE, FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

    // opened file succesfully
    if (hSaveFile == INVALID_HANDLE_VALUE) {
        return false;
    }

    // alloc mem
    curOffset = 0;
    curBlock = curReadingBlock;
    dataInFile = new unsigned char[blockSize];

    do {
        // copy current block
        if (curBlock == curWritingBlock && curBlock == curReadingBlock) {
            pointer = curReadingPointer;
            bytesToWrite = (unsigned int)(curWritingPointer - curReadingPointer);
        } else if (curBlock == curWritingBlock) {
            pointer = writingBlock;
            bytesToWrite = (unsigned int)(curWritingPointer - writingBlock);
        } else if (curBlock == curReadingBlock) {
            pointer = curReadingPointer;
            bytesToWrite = blockSize - (unsigned int)(curReadingPointer - readingBlock);
        } else {
            readDataFromFile(hFile, ((long long)curBlock) * ((long long)blockSize), blockSize, dataInFile);
            pointer = dataInFile;
            bytesToWrite = blockSize;
        }

        // save data to file
        writeDataToFile(hSaveFile, curOffset, bytesToWrite, pointer);
        curOffset += bytesToWrite;

        // exit?
        if (curBlock == curWritingBlock)
            break;
        else
            curBlock = (curBlock + 1) % numBlocks;

    } while (true);

    // everything ok
    delete[] dataInFile;
    CloseHandle(hSaveFile);
    return true;
}
