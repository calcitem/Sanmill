// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// cli_parser.h - Command line interface parser for Fastmill
// Based on fastchess CLI but adapted for Mill tournaments

#pragma once

#include <vector>
#include <string>
#include <map>

#include "tournament/tournament_config.h"

namespace fastmill {

class CLIParser {
public:
    CLIParser() = default;
    
    // Parse command line arguments into tournament configuration
    TournamentConfig parse(int argc, char* argv[]);
    
    // Version information
    static const std::string Version;
    
private:
    // Parsing state
    std::vector<std::string> args_;
    size_t current_index_{0};
    
    // Parse different argument types
    void parseEngineArgs(TournamentConfig& config);
    void parseEachArgs(TournamentConfig& config);
    void parseGeneralArgs(TournamentConfig& config);
    
    // Helper methods
    std::string getNextArg();
    std::string peekNextArg() const;
    bool hasNextArg() const;
    
    // Parsing utilities
    EngineConfig parseEngineConfig(const std::vector<std::string>& engine_args);
    TimeControl parseTimeControl(const std::string& tc_string);
    TournamentType parseTournamentType(const std::string& type_string);
    
    // Key-value parsing
    std::map<std::string, std::string> parseKeyValuePairs(const std::vector<std::string>& args);
    
    // Validation
    void validateConfig(const TournamentConfig& config);
    void validateEngineConfig(const EngineConfig& engine);
    void validateTimeControl(const TimeControl& tc);
    
    // Error handling
    void showError(const std::string& message);
    void showUsage();
    
    // Utility functions
    std::vector<std::string> tokenize(const std::string& str, char delimiter = ' ');
    std::string toLowerCase(const std::string& str);
    std::string getValueAfterEquals(const std::string& arg);
};

} // namespace fastmill