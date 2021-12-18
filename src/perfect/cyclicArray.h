/*********************************************************************\
    CyclicArray.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef CYLCIC_ARRAY_H_INCLUDED
#define CYLCIC_ARRAY_H_INCLUDED

#include <iostream>
#include <string>
#include <windows.h>

using std::cout;
using std::string;

class CyclicArray
{
private:
    // Variables
    HANDLE hFile; // Handle of the file
    // Array of size [blockSize] containing the data of the block, where reading
    // is taking place
    unsigned char *readingBlock;

    // ''
    unsigned char *writingBlock;

    // pointer to the byte which is currently read
    unsigned char *curReadingPtr;

    // ''
    unsigned char *curWritingPtr;

    // size in bytes of a block
    uint32_t blockSize;

    // index of the block, where reading is taking place
    uint32_t curReadingBlock;

    // index of the block, where writing is taking place
    uint32_t curWritingBlock;

    // amount of blocks
    uint32_t blockCount;

    // true if curReadingBlock > curWritingBlock, false otherwise
    bool readWriteInSameRound;

    // Functions
    void writeDataToFile(HANDLE hFile, int64_t offset, uint32_t sizeInBytes,
                         void *pData);
    void readDataFromFile(HANDLE hFile, int64_t offset, uint32_t sizeInBytes,
                          void *pData);

public:
    // Constructor / destructor
    CyclicArray(uint32_t blockSizeInBytes, uint32_t nBlocks,
                const char *fileName);
    ~CyclicArray();

    // Functions
    bool addBytes(uint32_t nBytes, unsigned char *pData);
    bool takeBytes(uint32_t nBytes, unsigned char *pData);
};

#endif // CYLCIC_ARRAY_H_INCLUDED
