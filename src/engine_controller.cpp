// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine_controller.cpp

#include "engine_controller.h"

#include <iostream>
#include <sstream>
#include <string>

#include "uci.h"
#include "thread.h"
#include "search.h"
#include "misc.h"
#include "engine_commands.h"
#include "search_engine.h"

EngineController::EngineController(SearchEngine &searchEngine)
    : searchEngine_(searchEngine)
{
    // Constructor
}

EngineController::~EngineController()
{
    // Destructor
}

void EngineController::handleCommand(const std::string &cmd, Position *pos)
{
    std::istringstream is(cmd);
    std::string token;
    is >> token;

    if (token == "go") {
        searchPos = *pos;
        EngineCommands::go(searchEngine_, &searchPos);
    } else if (token == "position") {
        EngineCommands::position(pos, is);
    } else if (token == "ucinewgame") {
        Search::clear(); // Clear the search state for a new game
        // Additional custom non-UCI commands, mainly for debugging.
        // Do not use these commands during a search!
    } else if (token == "d") {
        // Output the current position state
        sync_cout << *pos << sync_endl;
    } else if (token == "compiler") {
        // Output compiler information
        sync_cout << compiler_info() << sync_endl;
    } else if (token == "analyze") {
        analyzePos = *pos;
        EngineCommands::position(&analyzePos, is);
        // Call the analyze function instead of analyze_position
        EngineCommands::analyze(searchEngine_, &analyzePos);
    } else {
        // Handle additional custom commands if necessary
        sync_cout << "Unknown command in EngineController: " << cmd
                  << sync_endl;
    }
}
