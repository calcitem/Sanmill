/*********************************************************************\
	cyclicArray.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef CYLCIC_ARRAY_H
#define CYLCIC_ARRAY_H

#include <windows.h>
#include <iostream>
#include <string>

using namespace std;

/*** Klassen *********************************************************/

class cyclicArray
{
private: 
	// Variables
	HANDLE			hFile;								// Handle of the file
	unsigned char*	readingBlock;						// Array of size [blockSize] containing the data of the block, where reading is taking place
	unsigned char*	writingBlock;						//			''
	unsigned char*  curReadingPointer;					// pointer to the byte which is currently read
	unsigned char*  curWritingPointer;					//			''
	unsigned int	blockSize;							// size in bytes of a block
	unsigned int	curReadingBlock;					// index of the block, where reading is taking place
	unsigned int	curWritingBlock;					// index of the block, where writing is taking place
	unsigned int	numBlocks;							// amount of blocks
	bool			readWriteInSameRound;				// true if curReadingBlock > curWritingBlock, false otherwise

	// Functions
	void writeDataToFile	(HANDLE hFile, long long offset, unsigned int sizeInBytes, void *pData);
	void readDataFromFile	(HANDLE hFile, long long offset, unsigned int sizeInBytes, void *pData);
	
public:
    // Constructor / destructor
    cyclicArray				(unsigned int blockSizeInBytes, unsigned int numberOfBlocks, const char *fileName);
    ~cyclicArray			();

	// Functions
	bool	addBytes		(unsigned int numBytes, unsigned char* pData);
	bool	takeBytes		(unsigned int numBytes, unsigned char* pData);
	bool	loadFile		(const char *fileName, LONGLONG &numBytesLoaded);
	bool	saveFile		(const char *fileName);
	bool	bytesAvailable	();
};

#endif
