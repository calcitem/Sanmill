// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// cli_parser.h - Command line interface parser for Fastmill

#pragma once

#include <vector>
#include <string>
#include "tournament/tournament_types.h"

namespace fastmill {

class CLIParser
{
public:
    CLIParser() = default;

    // Parse command line arguments into tournament configuration
    TournamentConfig parse(int argc, char *argv[]);

private:
    // Parsing helpers
    EngineConfig parseEngineConfig(const std::vector<std::string> &args);
    TimeControl parseTimeControl(const std::string &tc_string);
    TournamentType parseTournamentType(const std::string &type_string);

    // Utility functions
    std::vector<std::string> tokenize(const std::string &str,
                                      char delimiter = ' ');
    std::string getValueAfterEquals(const std::string &arg);

    // Validation
    void validateConfig(const TournamentConfig &config);

    // Error handling
    void showError(const std::string &message);
    void showUsage();
};

} // namespace fastmill
