// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_errors.cpp

#include "perfect_errors.h"
#include "perfect_log.h"
#include <iostream>
#include <sstream>
#include <cstdlib>

namespace PerfectErrors {

#ifdef _MSC_VER
DWORD tls_key;
#else
pthread_key_t key;
#endif

namespace {
void destructor(void *value)
{
    delete static_cast<ErrorContext *>(value);
}
} // namespace

void initialize_thread_local_storage()
{
#ifdef _MSC_VER
    if ((tls_key = TlsAlloc()) == TLS_OUT_OF_INDEXES) {
        std::cerr << "Failed to allocate TLS key" << std::endl;
        exit(1);
    }
#else
    pthread_key_create(&key, destructor);
#endif
}

void cleanup_thread_local_storage()
{
#ifdef _MSC_VER
    TlsFree(tls_key);
#else
    pthread_key_delete(key);
#endif
}

static ErrorContext *get_error_context()
{
#ifdef _MSC_VER
    ErrorContext *context = static_cast<ErrorContext *>(TlsGetValue(tls_key));
    if (!context) {
        context = new ErrorContext();
        TlsSetValue(tls_key, context);
    }
#else
    ErrorContext *context = static_cast<ErrorContext *>(
        pthread_getspecific(key));
    if (!context) {
        context = new ErrorContext();
        pthread_setspecific(key, context);
    }
#endif
    return context;
}

// Set an error for the current thread.
// This will only set the error if no other error has been recorded for the
// current operation.
void setError(ErrorCode code, const std::string &message, const char *file,
              int line)
{
    ErrorContext *context = get_error_context();
    // Only set the error if no other error has been recorded
    if (context->code == PE_NO_ERROR) {
        context->code = code;
        context->message = message;
        context->file = file;
        context->line = line;
    }
}

// Clear the error for the current thread.
void clearError()
{
    get_error_context()->code = PE_NO_ERROR;
    get_error_context()->message.clear();
    get_error_context()->file = nullptr;
    get_error_context()->line = 0;
}

// Get a constant reference to the error context for the current thread.
const ErrorContext &getErrorContext()
{
    return *get_error_context();
}

std::string getLastErrorMessage()
{
    std::stringstream ss;
    const auto &context = getErrorContext();
    if (context.code != PE_NO_ERROR) {
        ss << "Error (code " << context.code << "): " << context.message;
        if (context.file) {
            ss << " at " << context.file << ":" << context.line;
        }
    } else {
        ss << "No error.";
    }
    return ss.str();
}

bool hasError()
{
    return get_error_context()->code != PE_NO_ERROR;
}

} // namespace PerfectErrors