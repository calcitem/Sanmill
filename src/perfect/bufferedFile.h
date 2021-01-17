/*********************************************************************\
	bufferedFile.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef BUFFERED_FILE_H
#define BUFFERED_FILE_H

#include <windows.h>
#include <iostream>
#include <string>

using namespace std;

/*** Klassen *********************************************************/

class bufferedFileClass
{
private: 
	// Variables
	HANDLE				hFile;								// Handle of the file
	unsigned int		numThreads;							// number of threads
	unsigned char *		readBuffer;							// Array of size [numThreads*blockSize] containing the data of the block, where reading is taking place
	unsigned char *		writeBuffer;						//	 '' - access by [threadNo*bufferSize+position] 
	long long *			curReadingPointer;					// array of size [numThreads] with pointers to the byte which is currently read
	long long *			curWritingPointer;					//			''
	unsigned int *		bytesInReadBuffer;					// 
	unsigned int *		bytesInWriteBuffer;					// 
	unsigned int		bufferSize;							// size in bytes of a buffer
	long long			fileSize;							// size in bytes
	CRITICAL_SECTION	csIO;

	// Functions
	void	writeDataToFile		(HANDLE hFile, long long offset, unsigned int sizeInBytes, void *pData);
	void	readDataFromFile	(HANDLE hFile, long long offset, unsigned int sizeInBytes, void *pData);
	
public:
    // Constructor / destructor
    bufferedFileClass			(unsigned int numThreads, unsigned int bufferSizeInBytes, const char *fileName);
    ~bufferedFileClass			();

	// Functions
	bool		flushBuffers	();
	bool		writeBytes		(unsigned int numBytes, unsigned char* pData);
	bool		readBytes		(unsigned int numBytes, unsigned char* pData);
	bool		writeBytes		(unsigned int threadNo, long long positionInFile, unsigned int numBytes, unsigned char* pData);
	bool		readBytes		(unsigned int threadNo, long long positionInFile, unsigned int numBytes, unsigned char* pData);
	long long	getFileSize		();
};

#endif
