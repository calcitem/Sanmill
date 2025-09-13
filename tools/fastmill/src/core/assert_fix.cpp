// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// assert_fix.cpp - Fix for missing __assert_func in Cygwin

#include <cstdio>
#include <cstdlib>

// Define __assert_func for Cygwin compatibility
extern "C" void __assert_func(const char* file, int line, const char* func, const char* expr) {
    fprintf(stderr, "Assertion failed: %s, function %s, file %s, line %d.\n",
            expr, func, file, line);
    abort();
}
