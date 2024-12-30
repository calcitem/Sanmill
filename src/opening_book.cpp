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

/// Convert a square to a string representation
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

    File file = FILE_A;
    Rank rank = RANK_1;
    int sig = 1;

    if (sq < 0) {
        sq = -sq;
        sig = 0;
    }

    file = file_of(sq);
    rank = rank_of(sq);

    if (sig == 1) {
        snprintf(str, 16, "(%d,%d)", file, rank);
    } else {
        snprintf(str, 16, "-(%d,%d)", file, rank);
    }
}

} // namespace OpeningBook

#endif // OPENING_BOOK
