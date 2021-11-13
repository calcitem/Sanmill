/*********************************************************************\
    bufferedFile.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef BUFFERED_FILE_H_INCLUDED
#define BUFFERED_FILE_H_INCLUDED

#include <iostream>
#include <string>
#include <windows.h>

using namespace std;

class BufferedFile {
private:
    // Variables
    HANDLE hFile; // Handle of the file
    unsigned int numThreads; // number of threads
    unsigned char* readBuffer; // Array of size [numThreads*blockSize] containing the data of the block, where reading is taking place
    unsigned char* writeBuffer; //	 '' - access by [threadNo*bufferSize+position]
    long long* curReadingPointer; // array of size [numThreads] with pointers to the byte which is currently read
    long long* curWritingPointer; //			''
    unsigned int* bytesInReadBuffer; //
    unsigned int* bytesInWriteBuffer; //
    unsigned int bufferSize; // size in bytes of a buffer
    long long fileSize; // size in bytes
    CRITICAL_SECTION csIO;

    // Functions
    void writeDataToFile(HANDLE hFile, long long offset, unsigned int sizeInBytes, void* pData);
    void readDataFromFile(HANDLE hFile, long long offset, unsigned int sizeInBytes, void* pData);

public:
    // Constructor / destructor
    BufferedFile(unsigned int numThreads, unsigned int bufferSizeInBytes, const char* fileName);
    ~BufferedFile();

    // Functions
    bool flushBuffers();
    bool writeBytes(unsigned int numBytes, unsigned char* pData);
    bool readBytes(unsigned int numBytes, unsigned char* pData);
    bool writeBytes(unsigned int threadNo, long long positionInFile, unsigned int numBytes, unsigned char* pData);
    bool readBytes(unsigned int threadNo, long long positionInFile, unsigned int numBytes, unsigned char* pData);
    long long getFileSize();
};

#endif // BUFFERED_FILE_H_INCLUDED
