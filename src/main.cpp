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
#endif // QT_GUI_LIB
