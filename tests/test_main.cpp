// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019- Sanmill developers (see AUTHORS file)

// test_main.cpp

#include "bitboard.h"
#include "option.h"
#include "position.h"
#include "search.h"
#include "uci.h"
#include "thread_pool.h"

#include <gtest/gtest.h>

int main(int argc, char **argv)
{
    UCI::init(Options);
    Bitboards::init();
    Position::init();

    // Disable AI move shuffling so every test run produces the same results.
    // The default is true (enabled), which introduces non-determinism.
    gameOptions.setShufflingEnabled(false);

    // Threads.set(static_cast<size_t>(Options["Threads"]));
    Search::clear();

    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
