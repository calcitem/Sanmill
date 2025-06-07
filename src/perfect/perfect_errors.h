// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_errors.h

#ifndef PERFECT_ERRORS_H
#define PERFECT_ERRORS_H

#include <string>
#include <fstream>
#include <vector>

#ifdef _MSC_VER
#include <windows.h>
#else
#include <pthread.h>
#endif

namespace PerfectErrors {

// Enum for error codes
enum ErrorCode {
    PE_NO_ERROR = 0,
    PE_RUNTIME_ERROR,
    PE_INVALID_ARGUMENT,
    PE_DATABASE_NOT_FOUND,
    PE_FILE_IO_ERROR,
    PE_GAME_OVER,
    PE_OUT_OF_RANGE,
    PE_INVALID_GAME_STATE,
    PE_FILE_NOT_FOUND,
    PE_OUT_OF_MEMORY
};

struct ErrorContext
{
    ErrorCode code = PE_NO_ERROR;
    std::string message;
    const char *file = nullptr;
    int line = 0;
};

#ifdef _MSC_VER
extern DWORD tls_key;
#else
extern pthread_key_t key;
#endif

void initialize_thread_local_storage();
void cleanup_thread_local_storage();

// Core functions
void setError(ErrorCode code, const std::string &message, const char *file,
              int line);
void clearError();
bool hasError();
const ErrorContext &getErrorContext();
std::string getLastErrorMessage();

// Macros to simplify error setting
#define SET_ERROR_CODE(code, msg) \
    PerfectErrors::setError(code, msg, __FILE__, __LINE__)
#define SET_ERROR_MESSAGE(code, msg) \
    PerfectErrors::setError(code, msg, __FILE__, __LINE__)
#define SET_ERROR_AND_RETURN(code, msg, retVal) \
    do { \
        PerfectErrors::setError(code, msg, __FILE__, __LINE__); \
        return retVal; \
    } while (0)

// Helper functions for error handling
inline ErrorCode getLastErrorCode()
{
    return getErrorContext().code;
}

inline bool checkRange(const std::string &paramName, int value, int min,
                       int max)
{
    if (value < min || value > max) {
        setError(PE_OUT_OF_RANGE,
                 paramName + " must be between " + std::to_string(min) +
                     " and " + std::to_string(max),
                 __FILE__, __LINE__);
        return false;
    }
    return true;
}

inline bool checkFileExists(const std::string &path)
{
    std::ifstream f(path.c_str());
    if (!f.good()) {
        setError(PE_FILE_NOT_FOUND, "File not found: " + path, __FILE__,
                 __LINE__);
        return false;
    }
    return true;
}

inline bool checkMemory(void *ptr)
{
    if (ptr == nullptr) {
        setError(PE_OUT_OF_MEMORY, "Out of memory", __FILE__, __LINE__);
        return false;
    }
    return true;
}

} // namespace PerfectErrors

#endif // PERFECT_ERRORS_H