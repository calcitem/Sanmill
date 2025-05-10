// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// main.cpp

#include "bitboard.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "thread_pool.h"
#include "uci.h"
#include <iostream>

#ifdef FLUTTER_UI
#include "engine_main.h"
#endif

#ifndef QT_GUI_LIB
#ifdef UNIT_TEST_MODE
int console_main(void)
#else
#ifdef FLUTTER_UI
int eng_main(int argc, char *argv[])
#else
int main(int argc, char *argv[])
#endif // FLUTTER_UI
#endif // UNIT_TEST_MODE
{
    std::cout << engine_info() << std::endl;

#ifdef FLUTTER_UI
    println("uciok");
#endif

    UCI::init(Options);
    Bitboards::init();
    Position::init();
    Threads.set(static_cast<size_t>(Options["Threads"]));
    Search::clear(); // After threads are up

#ifndef UNIT_TEST_MODE
    UCI::loop(argc, argv);
#endif

    Threads.set(0);
    return 0;
}

#if defined(__clang__) && defined(PGO_GENERATE)
// Ensures that the profile data is written to disk when the shared library is unloaded.
// Only needed in PGO generation builds where instrumentation is present.
extern "C" int __llvm_profile_write_file(void);
__attribute__((destructor)) static void flush_profraw_at_exit() {
    __llvm_profile_write_file();
}
#endif

#endif // QT_GUI_LIB
