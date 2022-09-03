/*********************************************************************\
    strLib.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef STRLIB_H_INCLUDED
#define STRLIB_H_INCLUDED

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <windows.h>

using std::cout;
using std::string;

class MyString
{
private:
    // variables
    WCHAR *strW {nullptr};
    char *strA {nullptr};
    size_t length {0};
    size_t reserved {0};

    // functions

public:
    // functions
    MyString();
    explicit MyString(const char *cStr);
    explicit MyString(const WCHAR *cStr);
    ~MyString();

    MyString &assign(const char *cStr);
    MyString &assign(const WCHAR *cStr);

    static int hiBit(uint32_t n);
};

#endif // STRLIB_H_INCLUDED
