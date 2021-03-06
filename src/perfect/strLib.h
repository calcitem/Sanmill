/*********************************************************************\
    strLib.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
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
bool readAsciiData(HANDLE hFile, double *pData, unsigned int numValues, unsigned char decimalSeperator, unsigned char columnSeparator);

class MyString
{
private:
    // variables
    WCHAR *strW = nullptr;
    char *strA = nullptr;
    size_t length = 0;
    size_t reserved = 0;

    // functions

public:
    // functions
    MyString();
    MyString(const char *cStr);
    MyString(const WCHAR *cStr);
    ~MyString();

    const char *c_strA();
    const WCHAR *c_strW();
    MyString &assign(const char *cStr);
    MyString &assign(const WCHAR *cStr);

    static int hibit(unsigned int n);
};

#endif
