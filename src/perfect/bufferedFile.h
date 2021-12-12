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

class BufferedFile
{
private:
    // Variables

    // Handle of the file
    HANDLE hFile;

    // number of threads
    unsigned int numThreads;

    // Array of size [numThreads*blockSize] containing the data of the block,
    // where reading is taking place
    unsigned char *readBuffer;

    // '' - access by [threadNo*bufferSize+position]
    unsigned char *writeBuffer;

    // Array of size [numThreads] with pointers to the byte which is currently
    // read
    int64_t *curReadingPointer;
    // ''
    int64_t *curWritingPointer;

    unsigned int *bytesInReadBuffer;

    unsigned int *bytesInWriteBuffer;

    // size in bytes of a buffer
    unsigned int bufferSize;

    // size in bytes
    int64_t fileSize;

    CRITICAL_SECTION csIO;

    // Functions
    void writeDataToFile(HANDLE hFile, int64_t offset, unsigned int sizeInBytes,
                         void *pData);
    void readDataFromFile(HANDLE hFile, int64_t offset,
                          unsigned int sizeInBytes, void *pData);

public:
    // Constructor / destructor
    BufferedFile(unsigned int numThreads, unsigned int bufferSizeInBytes,
                 const char *fileName);
    ~BufferedFile();

    // Functions
    bool flushBuffers();
    bool writeBytes(unsigned int numBytes, unsigned char *pData);
    bool readBytes(unsigned int numBytes, unsigned char *pData);
    bool writeBytes(unsigned int threadNo, int64_t positionInFile,
                    unsigned int numBytes, unsigned char *pData);
    bool readBytes(unsigned int threadNo, int64_t positionInFile,
                   unsigned int numBytes, unsigned char *pData);
    int64_t getFileSize();
};

#endif // BUFFERED_FILE_H_INCLUDED
