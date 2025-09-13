// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// cli_parser.cpp - Implementation of CLI parser

#include "cli_parser.h"
#include "core/logger.h"
#include <iostream>
#include <stdexcept>
#include <algorithm>

namespace fastmill {

// Version information
const std::string CLIParser::Version = "Fastmill 1.0.0";

TournamentConfig CLIParser::parse(int argc, char* argv[]) {
    TournamentConfig config;
    
    // Convert to internal format
    args_.clear();
    for (int i = 1; i < argc; ++i) {
        args_.push_back(argv[i]);
    }
    current_index_ = 0;
    
    // Parse all arguments
    while (hasNextArg()) {
        std::string arg = getNextArg();
        
        if (arg == "-engine") {
            parseEngineArgs(config);
        } else if (arg == "-each") {
            parseEachArgs(config);
        } else {
            parseGeneralArgs(config);
        }
    }
    
    validateConfig(config);
    return config;
}

void CLIParser::parseEngineArgs(TournamentConfig& config) {
    std::vector<std::string> engine_args;
    
    // Collect all arguments until next option
    while (hasNextArg() && peekNextArg()[0] != '-') {
        engine_args.push_back(getNextArg());
    }
    
    if (!engine_args.empty()) {
        EngineConfig engine = parseEngineConfig(engine_args);
        config.engines.push_back(engine);
    }
}

void CLIParser::parseEachArgs(TournamentConfig& config) {
    if (hasNextArg()) {
        std::string tc_arg = getNextArg();
        if (tc_arg.find("tc=") == 0) {
            config.time_control = parseTimeControl(tc_arg.substr(3));
        }
    }
}

void CLIParser::parseGeneralArgs(TournamentConfig& config) {
    // Go back one step since we already consumed the argument
    if (current_index_ > 0) {
        current_index_--;
    }
    
    std::string arg = getNextArg();
    
    if (arg == "-rounds" && hasNextArg()) {
        config.rounds = std::stoi(getNextArg());
    } else if (arg == "-concurrency" && hasNextArg()) {
        config.concurrency = std::stoi(getNextArg());
    } else if (arg == "-tournament" && hasNextArg()) {
        config.type = parseTournamentType(getNextArg());
    } else if (arg == "-pgnout" && hasNextArg()) {
        config.pgn.file = getNextArg();
        config.pgn.save_games = true;
    } else if (arg == "-log" && hasNextArg()) {
        config.log.file = getNextArg();
    }
}

std::string CLIParser::getNextArg() {
    if (current_index_ < args_.size()) {
        return args_[current_index_++];
    }
    return "";
}

std::string CLIParser::peekNextArg() const {
    if (current_index_ < args_.size()) {
        return args_[current_index_];
    }
    return "";
}

bool CLIParser::hasNextArg() const {
    return current_index_ < args_.size();
}

EngineConfig CLIParser::parseEngineConfig(const std::vector<std::string>& engine_args) {
    EngineConfig config;
    
    for (const auto& arg : engine_args) {
        if (arg.find("cmd=") == 0) {
            config.command = arg.substr(4);
        } else if (arg.find("name=") == 0) {
            config.name = arg.substr(5);
        } else if (arg.find("dir=") == 0) {
            config.working_directory = arg.substr(4);
        }
    }
    
    // Set default name if not provided
    if (config.name.empty() && !config.command.empty()) {
        config.name = config.command;
    }
    
    return config;
}

TimeControl CLIParser::parseTimeControl(const std::string& tc_string) {
    TimeControl tc;
    
    // Parse format like "60+1" (60 seconds + 1 second increment)
    size_t plus_pos = tc_string.find('+');
    if (plus_pos != std::string::npos) {
        std::string base_str = tc_string.substr(0, plus_pos);
        std::string inc_str = tc_string.substr(plus_pos + 1);
        
        tc.base_time = std::chrono::milliseconds(static_cast<int>(std::stod(base_str) * 1000));
        tc.increment = std::chrono::milliseconds(static_cast<int>(std::stod(inc_str) * 1000));
    } else {
        // Just base time, no increment
        tc.base_time = std::chrono::milliseconds(static_cast<int>(std::stod(tc_string) * 1000));
        tc.increment = std::chrono::milliseconds(0);
    }
    
    return tc;
}

TournamentType CLIParser::parseTournamentType(const std::string& type_string) {
    std::string lower_type = toLowerCase(type_string);
    
    if (lower_type == "roundrobin" || lower_type == "rr") {
        return TournamentType::ROUNDROBIN;
    } else if (lower_type == "gauntlet") {
        return TournamentType::GAUNTLET;
    } else if (lower_type == "swiss") {
        return TournamentType::SWISS;
    } else {
        throw std::invalid_argument("Unknown tournament type: " + type_string);
    }
}

std::vector<std::string> CLIParser::tokenize(const std::string& str, char delimiter) {
    std::vector<std::string> tokens;
    std::string token;
    
    for (char c : str) {
        if (c == delimiter) {
            if (!token.empty()) {
                tokens.push_back(token);
                token.clear();
            }
        } else {
            token += c;
        }
    }
    
    if (!token.empty()) {
        tokens.push_back(token);
    }
    
    return tokens;
}

std::string CLIParser::toLowerCase(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::tolower);
    return result;
}

std::string CLIParser::getValueAfterEquals(const std::string& arg) {
    size_t pos = arg.find('=');
    return (pos != std::string::npos) ? arg.substr(pos + 1) : "";
}

void CLIParser::validateConfig(const TournamentConfig& config) {
    if (config.engines.size() < 2) {
        throw std::invalid_argument("At least 2 engines are required for a tournament");
    }
    
    for (const auto& engine : config.engines) {
        validateEngineConfig(engine);
    }
    
    validateTimeControl(config.time_control);
    
    if (config.rounds < 1) {
        throw std::invalid_argument("Number of rounds must be at least 1");
    }
    
    if (config.concurrency < 1) {
        throw std::invalid_argument("Concurrency must be at least 1");
    }
}

void CLIParser::validateEngineConfig(const EngineConfig& engine) {
    if (engine.command.empty()) {
        throw std::invalid_argument("Engine command cannot be empty");
    }
    if (engine.name.empty()) {
        throw std::invalid_argument("Engine name cannot be empty");
    }
}

void CLIParser::validateTimeControl(const TimeControl& tc) {
    if (tc.base_time <= std::chrono::milliseconds(0)) {
        throw std::invalid_argument("Base time must be positive");
    }
}

void CLIParser::showError(const std::string& message) {
    std::cerr << "Error: " << message << std::endl;
}

void CLIParser::showUsage() {
    std::cout << "Fastmill - Tournament tool for Mill (Nine Men's Morris) engines\n\n";
    std::cout << "Usage: fastmill [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  -engine cmd=ENGINE name=NAME [dir=DIR]   Add an engine\n";
    std::cout << "  -each tc=TIME_CONTROL                    Set time control\n";
    std::cout << "  -rounds N                                Number of rounds\n";
    std::cout << "  -concurrency N                           Number of concurrent games\n";
    std::cout << "  -tournament TYPE                         Tournament type\n";
    std::cout << "  -pgnout FILE                             Save games to PGN file\n";
    std::cout << "  -log FILE                                Log file path\n";
}

} // namespace fastmill