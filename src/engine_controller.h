// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine_controller.h

#ifndef ENGINE_CONTROLLER_H_INCLUDED
#define ENGINE_CONTROLLER_H_INCLUDED

#include <string>
#include "position.h"

class SearchEngine;

/// EngineController is responsible for handling commands from UciServer (or
/// UCI::loop).
class EngineController
{
public:
    EngineController(SearchEngine &searchEngine);
    ~EngineController();

    /// The main entry to handle a command.
    /// We pass in the raw command string and a Position pointer
    /// so we can call existing logic (like go(pos), position(pos, is)).
    void handleCommand(const std::string &cmd, Position *pos);

private:
    // Internal position
    Position searchPos;

    // Analyze position
    Position analyzePos;

    SearchEngine &searchEngine_;

    // If needed, we could store references to Options, or keep an internal
    // Position.
};

#endif // ENGINE_CONTROLLER_H_INCLUDED
