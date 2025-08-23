// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine_commands.h

#ifndef ENGINE_COMMANDS_H_INCLUDED
#define ENGINE_COMMANDS_H_INCLUDED

#include <string>
#include <sstream>
#include <deque>
#include "position.h"

class SearchEngine;

namespace EngineCommands {

/// Handles the "go" UCI command to start the search.
void go(SearchEngine &searchEngine, Position *pos);

/// Handles the "analyze" UCI command to evaluate all legal moves.
void analyze(SearchEngine &searchEngine, Position *pos);

/// Handles the "position" UCI command to set up the board position.
/// The caller must provide a persistent StateInfo deque whose element addresses
/// remain stable across push_back, to keep the Position::state() chain valid.
void position(Position *pos, std::istringstream &is,
              std::deque<StateInfo> &states);

/// Initializes the starting FEN based on piece count.
void init_start_fen();

/// The starting FEN string after initialization.
extern char StartFEN[BUFSIZ];

} // namespace EngineCommands

#endif // ENGINE_COMMANDS_H_INCLUDED
