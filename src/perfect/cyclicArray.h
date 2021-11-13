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

using namespace std;

class CyclicArray {
private:
    // Variables
    HANDLE hFile; // Handle of the file
    unsigned char* readingBlock; // Array of size [blockSize] containing the data of the block, where reading is taking place
    unsigned char* writingBlock; //			''
    unsigned char* curReadingPointer; // pointer to the byte which is currently read
    unsigned char* curWritingPointer; //			''
    unsigned int blockSize; // size in bytes of a block
    unsigned int curReadingBlock; // index of the block, where reading is taking place
    unsigned int curWritingBlock; // index of the block, where writing is taking place
    unsigned int numBlocks; // amount of blocks
    bool readWriteInSameRound; // true if curReadingBlock > curWritingBlock, false otherwise

    // Functions
    void writeDataToFile(HANDLE hFile, long long offset, unsigned int sizeInBytes, void* pData);
    void readDataFromFile(HANDLE hFile, long long offset, unsigned int sizeInBytes, void* pData);

public:
    // Constructor / destructor
    CyclicArray(unsigned int blockSizeInBytes, unsigned int numberOfBlocks, const char* fileName);
    ~CyclicArray();

    // Functions
    bool addBytes(unsigned int numBytes, unsigned char* pData);
    bool takeBytes(unsigned int numBytes, unsigned char* pData);
    bool loadFile(const char* fileName, LONGLONG& numBytesLoaded);
    bool saveFile(const char* fileName);
    bool bytesAvailable();
};

#endif // CYLCIC_ARRAY_H_INCLUDED
