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
    unsigned char *curReadingPointer;

    // ''
    unsigned char *curWritingPointer;

    // size in bytes of a block
    unsigned int blockSize;

    // index of the block, where reading is taking place
    unsigned int curReadingBlock;

    // index of the block, where writing is taking place
    unsigned int curWritingBlock;

    // amount of blocks
    unsigned int blockCount;

    // true if curReadingBlock > curWritingBlock, false otherwise
    bool readWriteInSameRound;

    // Functions
    void writeDataToFile(HANDLE hFile, int64_t offset, unsigned int sizeInBytes,
                         void *pData);
    void readDataFromFile(HANDLE hFile, int64_t offset,
                          unsigned int sizeInBytes, void *pData);

public:
    // Constructor / destructor
    CyclicArray(unsigned int blockSizeInBytes, unsigned int nBlocks,
                const char *fileName);
    ~CyclicArray();

    // Functions
    bool addBytes(unsigned int nBytes, unsigned char *pData);
    bool takeBytes(unsigned int nBytes, unsigned char *pData);
    bool loadFile(const char *fileName, LONGLONG &nBytesLoaded);
    bool saveFile(const char *fileName);
    bool bytesAvailable();
};

#endif // CYLCIC_ARRAY_H_INCLUDED
