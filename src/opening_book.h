// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// opening_book.h

#ifndef OPENING_BOOK_H_INCLUDED
#define OPENING_BOOK_H_INCLUDED

#include "config.h"

#ifdef OPENING_BOOK

#include <deque>
#include <string>

// Forward declarations
enum File : int;
enum Rank : int;
struct Position;

/// OpeningBook namespace encapsulates all opening book-related functionalities.
namespace OpeningBook {

// Initialize the opening book deques
void initialize();

// Check if there are available opening moves
bool has_moves();

// Get the best move as a string from the opening book
std::string get_best_move();

// Convert a square to a string representation
void sq2str(char *str);

} // namespace OpeningBook

#endif // OPENING_BOOK

#endif // OPENING_BOOK_H_INCLUDED
