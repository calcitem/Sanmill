// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// opening_book.cpp

#include "opening_book.h"
#include <cstdio>  // For snprintf
#include <cassert> // For assert

#ifdef OPENING_BOOK

#include "position.h" // Assuming position.h defines File, Rank, and related functions

using std::deque;
using std::string;

namespace OpeningBook {

// Define the opening book deques
static deque<int> openingBookDeque({
    /* B W */
    21,
    23,
    19,
    20,
    17,
    18,
    15,
});

static deque<int> openingBookDequeBak;

/// Initialize the opening book (if any initialization is needed)
void initialize()
{
    // Currently, the deque is initialized statically.
    // If dynamic initialization is needed, implement here.
}

/// Check if there are available opening moves
bool has_moves()
{
    return !openingBookDeque.empty();
}

/// Get the best move as a string from the opening book
string get_best_move()
{
    char obc[16] = {0};
    sq2str(obc);
    return string(obc);
}

/// Convert a square to a string representation using standard notation
void sq2str(char *str)
{
    assert(str != nullptr);
    if (openingBookDeque.empty()) {
        snprintf(str, 16, "no_move");
        return;
    }

    int sq = openingBookDeque.front();
    openingBookDeque.pop_front();
    openingBookDequeBak.push_back(sq);

    bool isRemove = false;
    if (sq < 0) {
        sq = -sq;
        isRemove = true;
    }

    // Convert square to standard notation
    static const char *squareToStandard[40] = {
        // 0-7: unused
        "", "", "", "", "", "", "", "",
        // 8-15: inner ring
        "d5", "e5", "e4", "e3", "d3", "c3", "c4", "c5",
        // 16-23: middle ring
        "d6", "f6", "f4", "f2", "d2", "b2", "b4", "b6",
        // 24-31: outer ring
        "d7", "g7", "g4", "g1", "d1", "a1", "a4", "a7",
        // 32-39: unused
        "", "", "", "", "", "", "", ""};

    if (sq >= 0 && sq < 40 && squareToStandard[sq][0] != '\0') {
        if (isRemove) {
            snprintf(str, 16, "x%s", squareToStandard[sq]);
        } else {
            snprintf(str, 16, "%s", squareToStandard[sq]);
        }
    } else {
        snprintf(str, 16, "invalid_sq");
    }
}

} // namespace OpeningBook

#endif // OPENING_BOOK
