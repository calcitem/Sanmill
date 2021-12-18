/*********************************************************************
    strLib.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
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
int MyString::hiBit(unsigned int n)
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
// c_strA()
//
//-----------------------------------------------------------------------------
const char *MyString::c_strA()
{
    return strA;
}

//-----------------------------------------------------------------------------
// c_strW()
//
//-----------------------------------------------------------------------------
const WCHAR *MyString::c_strW()
{
    return strW;
}

//-----------------------------------------------------------------------------
// assign()
//
//-----------------------------------------------------------------------------
MyString &MyString::assign(const char *cStr)
{
    // locals
    size_t convertedChars = 0;
    size_t newLen = strlen(cStr);
    size_t newReserved = (size_t)hiBit((unsigned int)newLen) * 2;

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
    size_t newLen = wcslen(cStr);
    size_t newReserved = (size_t)hiBit((unsigned int)newLen) * 2;

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

//-----------------------------------------------------------------------------
// readAsciiData()
// This functions reads in a table of floating point values faster than "cin".
//-----------------------------------------------------------------------------
bool readAsciiData(HANDLE hFile, double *pData, unsigned int nValues,
                   unsigned char decSeperator, unsigned char colSeparator)
{
    // constants
    const unsigned int maxValLenInBytes = 32;
    const unsigned int bufSize = 1000;

    // locals
    DWORD dwBytesRead;
    unsigned char buf[bufSize];
    unsigned char *curByte = &buf[0];
    unsigned int curReadVal = 0;
    unsigned int actualBufSize = 0;
    unsigned int curBufPos = bufSize;
    unsigned int decPos = 0;

    // ATTENTION: Only allows 8 digits before the decimal point
    int integralVal = 0;

    // ATTENTION: Only allows 8 digits before the decimal point
    int fractionalVal = 0;

    int expVal = 1;
    bool valIsNeg = false;
    bool expIsNeg = false;
    bool decPlace = false;
    bool exp = false;
    double fractionalFactor[] = {0,           0.1,         0.01,
                                 0.001,       0.0001,      0.00001,
                                 0.000001,    0.0000001,   0.00000001,
                                 0.000000001, 0.0000000001};

    // read each value
    do {
        // read from buffer if necessary
        if (curBufPos >= bufSize - maxValLenInBytes) {
            memcpy(&buf[0], &buf[curBufPos], bufSize - curBufPos);
            if (!ReadFile(hFile, &buf[bufSize - curBufPos], curBufPos,
                          &dwBytesRead, nullptr))
                return false;
            actualBufSize = bufSize - curBufPos + dwBytesRead;
            curBufPos = 0;
            curByte = &buf[curBufPos];
        }

        // process current byte
        switch (*curByte) {
        case '-':
            if (exp) {
                expIsNeg = true;
            } else {
                valIsNeg = true;
            }
            break;
        case '+': /* ignore */
            break;
        case 'e':
        case 'E':
            exp = true;
            decPlace = false;
            break;
        case '0':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 0;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 0;
            } else {
                integralVal *= 10;
                integralVal += 0;
            }
            break;
        case '1':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 1;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 1;
            } else {
                integralVal *= 10;
                integralVal += 1;
            }
            break;
        case '2':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 2;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 2;
            } else {
                integralVal *= 10;
                integralVal += 2;
            }
            break;
        case '3':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 3;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 3;
            } else {
                integralVal *= 10;
                integralVal += 3;
            }
            break;
        case '4':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 4;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 4;
            } else {
                integralVal *= 10;
                integralVal += 4;
            }
            break;
        case '5':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 5;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 5;
            } else {
                integralVal *= 10;
                integralVal += 5;
            }
            break;
        case '6':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 6;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 6;
            } else {
                integralVal *= 10;
                integralVal += 6;
            }
            break;
        case '7':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 7;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 7;
            } else {
                integralVal *= 10;
                integralVal += 7;
            }
            break;
        case '8':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 8;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 8;
            } else {
                integralVal *= 10;
                integralVal += 8;
            }
            break;
        case '9':
            if (decPlace) {
                fractionalVal *= 10;
                fractionalVal += 9;
                decPos++;
            } else if (exp) {
                expVal *= 10;
                expVal += 9;
            } else {
                integralVal *= 10;
                integralVal += 9;
            }
            break;
        default:
            if (*curByte == decSeperator) {
                decPlace = true;
                exp = false;
            } else if (*curByte == colSeparator) {
                // everything ok?
                if (decPos > 8) {
                    cout << "ERROR in function readAsciiData(): Too many "
                            "digits on decimal place. Maximum is 8 !"
                         << std::endl;
                    return false;
                }

                // calculate final value
                (*pData) = integralVal;
                if (decPos) {
                    (*pData) += fractionalVal * fractionalFactor[decPos];
                }

                if (valIsNeg) {
                    (*pData) *= -1;
                }

                if (exp) {
                    (*pData) *= pow(10, expIsNeg ? -1 * expVal : 1);
                }

                // init
                valIsNeg = false;
                expIsNeg = false;
                decPlace = false;
                exp = false;
                integralVal = 0;
                fractionalVal = 0;
                expVal = 1;
                decPos = 0;

                // save value
                pData++;
                curReadVal++;
            } else {
                // do nothing
            }
            break;
        }

        // consider next byte
        curBufPos++;
        curByte++;

        // buffer overrun?
        if (curBufPos >= actualBufSize)
            return false;
    } while (curReadVal < nValues);

    // quit
    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
