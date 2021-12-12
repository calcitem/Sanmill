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
    size_t newLength = strlen(cStr);
    size_t newReserved = (size_t)hiBit((unsigned int)newLength) * 2;

    if (reserved < newReserved)
        this->~MyString();

    if (strA == nullptr)
        strA = new char[newReserved];

    if (strW == nullptr)
        strW = new WCHAR[newReserved];

    reserved = newReserved;
    length = newLength;

    strcpy_s(strA, newReserved, cStr);
    mbstowcs_s(&convertedChars, strW, newLength + 1, cStr, _TRUNCATE);

    return *this;
}

//-----------------------------------------------------------------------------
// assign()
//
//-----------------------------------------------------------------------------
MyString &MyString::assign(const WCHAR *cStr)
{
    // locals
    size_t returnValue;
    size_t newLength = wcslen(cStr);
    size_t newReserved = (size_t)hiBit((unsigned int)newLength) * 2;

    if (reserved < newReserved)
        this->~MyString();

    if (strA == nullptr)
        strA = new char[newReserved];

    if (strW == nullptr)
        strW = new WCHAR[newReserved];

    reserved = newReserved;
    length = newLength;

    wcscpy_s(strW, newReserved, cStr);
    wcstombs_s(&returnValue, strA, newLength + 1, cStr, newLength + 1);

    return *this;
}

//-----------------------------------------------------------------------------
// readAsciiData()
// This functions reads in a table of floating point values faster than "cin".
//-----------------------------------------------------------------------------
bool readAsciiData(HANDLE hFile, double *pData, unsigned int numValues,
                   unsigned char decimalSeperator,
                   unsigned char columnSeparator)
{
    // constants
    const unsigned int maxValueLengthInBytes = 32;
    const unsigned int bufferSize = 1000;

    // locals
    DWORD dwBytesRead;
    unsigned char buffer[bufferSize];
    unsigned char *curByte = &buffer[0];
    unsigned int curReadValue = 0;
    unsigned int actualBufferSize = 0;
    unsigned int curBufferPos = bufferSize;
    unsigned int decimalPos = 0;

    // ATTENTION: Only allows 8 digits before the decimal point
    int integralValue = 0;

    // ATTENTION: Only allows 8 digits before the decimal point
    int fractionalValue = 0;

    int exponentialValue = 1;
    bool valIsNegative = false;
    bool expIsNegative = false;
    bool decimalPlace = false;
    bool exponent = false;
    double fractionalFactor[] = {0,           0.1,         0.01,
                                 0.001,       0.0001,      0.00001,
                                 0.000001,    0.0000001,   0.00000001,
                                 0.000000001, 0.0000000001};

    // read each value
    do {
        // read from buffer if necessary
        if (curBufferPos >= bufferSize - maxValueLengthInBytes) {
            memcpy(&buffer[0], &buffer[curBufferPos],
                   bufferSize - curBufferPos);
            if (!ReadFile(hFile, &buffer[bufferSize - curBufferPos],
                          curBufferPos, &dwBytesRead, nullptr))
                return false;
            actualBufferSize = bufferSize - curBufferPos + dwBytesRead;
            curBufferPos = 0;
            curByte = &buffer[curBufferPos];
        }

        // process current byte
        switch (*curByte) {
        case '-':
            if (exponent) {
                expIsNegative = true;
            } else {
                valIsNegative = true;
            }
            break;
        case '+': /* ignore */
            break;
        case 'e':
        case 'E':
            exponent = true;
            decimalPlace = false;
            break;
        case '0':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 0;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 0;
            } else {
                integralValue *= 10;
                integralValue += 0;
            }
            break;
        case '1':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 1;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 1;
            } else {
                integralValue *= 10;
                integralValue += 1;
            }
            break;
        case '2':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 2;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 2;
            } else {
                integralValue *= 10;
                integralValue += 2;
            }
            break;
        case '3':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 3;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 3;
            } else {
                integralValue *= 10;
                integralValue += 3;
            }
            break;
        case '4':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 4;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 4;
            } else {
                integralValue *= 10;
                integralValue += 4;
            }
            break;
        case '5':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 5;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 5;
            } else {
                integralValue *= 10;
                integralValue += 5;
            }
            break;
        case '6':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 6;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 6;
            } else {
                integralValue *= 10;
                integralValue += 6;
            }
            break;
        case '7':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 7;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 7;
            } else {
                integralValue *= 10;
                integralValue += 7;
            }
            break;
        case '8':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 8;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 8;
            } else {
                integralValue *= 10;
                integralValue += 8;
            }
            break;
        case '9':
            if (decimalPlace) {
                fractionalValue *= 10;
                fractionalValue += 9;
                decimalPos++;
            } else if (exponent) {
                exponentialValue *= 10;
                exponentialValue += 9;
            } else {
                integralValue *= 10;
                integralValue += 9;
            }
            break;
        default:
            if (*curByte == decimalSeperator) {
                decimalPlace = true;
                exponent = false;
            } else if (*curByte == columnSeparator) {
                // everything ok?
                if (decimalPos > 8) {
                    cout << "ERROR in function readAsciiData(): Too many "
                            "digits on decimal place. Maximum is 8 !"
                         << std::endl;
                    return false;
                }

                // calc final value
                (*pData) = integralValue;
                if (decimalPos) {
                    (*pData) += fractionalValue * fractionalFactor[decimalPos];
                }

                if (valIsNegative) {
                    (*pData) *= -1;
                }

                if (exponent) {
                    (*pData) *= pow(10,
                                    expIsNegative ? -1 * exponentialValue : 1);
                }

                // init
                valIsNegative = false;
                expIsNegative = false;
                decimalPlace = false;
                exponent = false;
                integralValue = 0;
                fractionalValue = 0;
                exponentialValue = 1;
                decimalPos = 0;

                // save value
                pData++;
                curReadValue++;
            } else {
                // do nothing
            }
            break;
        }

        // consider next byte
        curBufferPos++;
        curByte++;

        // buffer overrun?
        if (curBufferPos >= actualBufferSize)
            return false;
    } while (curReadValue < numValues);

    // quit
    return true;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
