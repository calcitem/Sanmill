/*********************************************************************\
	strLib.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef STRLIB_H
#define STRLIB_H

#include <windows.h>
#include <iostream>
#include <stdlib.h>
#include <string>
#include <stdio.h>
#include <assert.h>

using namespace std;

// general functions
bool readAsciiData(HANDLE hFile, double* pData, unsigned int numValues, unsigned char decimalSeperator, unsigned char columnSeparator);

class mystring
{
private:
	
	// variables
	WCHAR*			strW			= nullptr;
	char *			strA			= nullptr;
	size_t			length			= 0;
	size_t			reserved		= 0;

	// functions

public:

	// functions
					mystring		();
					mystring		(const char  *cStr);
					mystring		(const WCHAR *cStr);
					~mystring		();

	const char *	c_strA			();
	const WCHAR *	c_strW			();
	mystring &		assign			(const char  *cStr);
	mystring &		assign			(const WCHAR *cStr);

	static int		hibit			(unsigned int n);
};

#endif
