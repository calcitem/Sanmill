/*********************************************************************\
    CyclicArray.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
    unsigned char *readingBlock {nullptr};

    // ''
    unsigned char *writingBlock {nullptr};

    // pointer to the byte which is currently read
    unsigned char *curReadingPtr {nullptr};

    // ''
    unsigned char *curWritingPtr {nullptr};

    // size in bytes of a block
    uint32_t blockSize {0};

    // index of the block, where reading is taking place
    uint32_t curReadingBlock {0};

    // index of the block, where writing is taking place
    uint32_t curWritingBlock {0};

    // amount of blocks
    uint32_t blockCount {0};

    // true if curReadingBlock > curWritingBlock, false otherwise
    bool readWriteInSameRound {false};

    // Functions
    static void writeDataToFile(HANDLE hFile, int64_t offset,
                                uint32_t sizeInBytes, void *pData);
    static void readDataFromFile(HANDLE hFile, int64_t offset,
                                 uint32_t sizeInBytes, void *pData);

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
