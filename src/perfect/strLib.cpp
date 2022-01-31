/*********************************************************************
    strLib.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "strLib.h"

//-----------------------------------------------------------------------------
// hiBit()
//
//-----------------------------------------------------------------------------
int MyString::hiBit(uint32_t n)
{
    n |= (n >> 1);
    n |= (n >> 2);
    n |= (n >> 4);
    n |= (n >> 8);
    n |= (n >> 16);
    return n - (n >> 1);
}

//-----------------------------------------------------------------------------
// MyString()
//
//-----------------------------------------------------------------------------
MyString::MyString() { }

//-----------------------------------------------------------------------------
// MyString()
//
//-----------------------------------------------------------------------------
MyString::MyString(const char *cStr)
{
    assign(cStr);
}

//-----------------------------------------------------------------------------
// MyString()
//
//-----------------------------------------------------------------------------
MyString::MyString(const WCHAR *cStr)
{
    assign(cStr);
}

//-----------------------------------------------------------------------------
// MyString()
//
//-----------------------------------------------------------------------------
MyString::~MyString()
{
    if (strA != nullptr) {
        delete[] strA;
        strA = nullptr;
    }

    if (strW != nullptr) {
        delete[] strW;
        strW = nullptr;
    }

    strW = nullptr;
    strA = nullptr;
    length = 0;
    reserved = 0;
}

//-----------------------------------------------------------------------------
// assign()
//
//-----------------------------------------------------------------------------
MyString &MyString::assign(const char *cStr)
{
    // locals
    size_t convertedChars = 0;
    const size_t newLen = strlen(cStr);
    const size_t newReserved = static_cast<size_t>(
                                   hiBit(static_cast<uint32_t>(newLen))) *
                               2;

    if (reserved < newReserved)
        this->~MyString();

    if (strA == nullptr)
        strA = new char[newReserved];

    if (strW == nullptr)
        strW = new WCHAR[newReserved];

    reserved = newReserved;
    length = newLen;

    strcpy_s(strA, newReserved, cStr);
    mbstowcs_s(&convertedChars, strW, newLen + 1, cStr, _TRUNCATE);

    return *this;
}

//-----------------------------------------------------------------------------
// assign()
//
//-----------------------------------------------------------------------------
MyString &MyString::assign(const WCHAR *cStr)
{
    // locals
    size_t retval;
    const size_t newLen = wcslen(cStr);
    const size_t newReserved = static_cast<size_t>(
                                   hiBit(static_cast<uint32_t>(newLen))) *
                               2;

    if (reserved < newReserved)
        this->~MyString();

    if (strA == nullptr)
        strA = new char[newReserved];

    if (strW == nullptr)
        strW = new WCHAR[newReserved];

    reserved = newReserved;
    length = newLen;

    wcscpy_s(strW, newReserved, cStr);
    wcstombs_s(&retval, strA, newLen + 1, cStr, newLen + 1);

    return *this;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
