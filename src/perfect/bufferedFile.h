/*********************************************************************\
    bufferedFile.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
    HANDLE hFile {nullptr};

    // number of threads
    uint32_t threadCount {0};

    // Array of size [threadCount*blockSize] containing the data of the block,
    // where reading is taking place
    unsigned char *readBuf {nullptr};

    // '' - access by [threadNo*bufSize+position]
    unsigned char *writeBuf {nullptr};

    // Array of size [threadCount] with pointers to the byte which is currently
    // read
    int64_t *curReadingPtr {nullptr};
    // ''
    int64_t *curWritingPtr {nullptr};

    uint32_t *bytesInReadBuf {nullptr};

    uint32_t *bytesInWriteBuf {nullptr};

    // size in bytes of a buf
    uint32_t bufSize {0};

    // size in bytes
    int64_t fileSize {0};

    CRITICAL_SECTION csIO;

    // Functions
    void writeDataToFile(HANDLE hFile, int64_t offset, uint32_t sizeInBytes,
                         void *pData);
    void readDataFromFile(HANDLE hFile, int64_t offset, uint32_t sizeInBytes,
                          void *pData);

public:
    // Constructor / destructor
    BufferedFile(uint32_t threadCount, uint32_t bufSizeInBytes,
                 const char *fileName);
    ~BufferedFile();

    // Functions
    bool flushBuffers();
    bool writeBytes(uint32_t nBytes, unsigned char *pData);
    bool readBytes(uint32_t nBytes, unsigned char *pData);
    bool writeBytes(uint32_t threadNo, int64_t positionInFile, uint32_t nBytes,
                    unsigned char *pData);
    bool readBytes(uint32_t threadNo, int64_t positionInFile, uint32_t nBytes,
                   unsigned char *pData);
    int64_t getFileSize();
};

#endif // BUFFERED_FILE_H_INCLUDED
