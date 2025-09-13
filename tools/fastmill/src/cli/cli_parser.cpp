// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// cli_parser.cpp - Implementation of CLI parser

#include "cli_parser.h"
#include "utils/logger.h"
#include <iostream>
#include <stdexcept>
#include <algorithm>

namespace fastmill {

TournamentConfig CLIParser::parse(int argc, char *argv[])
{
    TournamentConfig config;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg == "-engine") {
            // Parse engine configuration
            std::vector<std::string> engine_args;
            for (int j = i + 1; j < argc && argv[j][0] != '-'; ++j) {
                engine_args.push_back(argv[j]);
                i = j;
            }

            if (!engine_args.empty()) {
                EngineConfig engine = parseEngineConfig(engine_args);
                config.engines.push_back(engine);
            }
        } else if (arg == "-each" && i + 1 < argc) {
            std::string tc_arg = argv[++i];
            if (tc_arg.find("tc=") == 0) {
                config.time_control = parseTimeControl(tc_arg.substr(3));
            }
        } else if (arg == "-rounds" && i + 1 < argc) {
            config.rounds = std::stoi(argv[++i]);
        } else if (arg == "-concurrency" && i + 1 < argc) {
            config.concurrency = std::stoi(argv[++i]);
        } else if (arg == "-tournament" && i + 1 < argc) {
            config.type = parseTournamentType(argv[++i]);
        } else if (arg == "-openings" && i + 1 < argc) {
            config.opening_book_path = argv[++i];
            config.use_opening_book = true;
        } else if (arg == "-pgnout" && i + 1 < argc) {
            config.pgn_output_path = argv[++i];
            config.save_games = true;
        } else if (arg == "-log" && i + 1 < argc) {
            config.log_file_path = argv[++i];
        }
    }

    validateConfig(config);
    return config;
}

EngineConfig CLIParser::parseEngineConfig(const std::vector<std::string> &args)
{
    EngineConfig config;

    for (const auto &arg : args) {
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

TimeControl CLIParser::parseTimeControl(const std::string &tc_string)
{
    TimeControl tc;

    // Parse format like "60+1" (60 seconds + 1 second increment)
    size_t plus_pos = tc_string.find('+');
    if (plus_pos != std::string::npos) {
        std::string base_str = tc_string.substr(0, plus_pos);
        std::string inc_str = tc_string.substr(plus_pos + 1);

        tc.base_time = std::chrono::milliseconds(
            static_cast<int>(std::stod(base_str) * 1000));
        tc.increment = std::chrono::milliseconds(
            static_cast<int>(std::stod(inc_str) * 1000));
    } else {
        // Just base time, no increment
        tc.base_time = std::chrono::milliseconds(
            static_cast<int>(std::stod(tc_string) * 1000));
        tc.increment = std::chrono::milliseconds(0);
    }

    return tc;
}

TournamentType CLIParser::parseTournamentType(const std::string &type_string)
{
    std::string lower_type = type_string;
    std::transform(lower_type.begin(), lower_type.end(), lower_type.begin(),
                   ::tolower);

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

std::vector<std::string> CLIParser::tokenize(const std::string &str,
                                             char delimiter)
{
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

std::string CLIParser::getValueAfterEquals(const std::string &arg)
{
    size_t pos = arg.find('=');
    return (pos != std::string::npos) ? arg.substr(pos + 1) : "";
}

void CLIParser::validateConfig(const TournamentConfig &config)
{
    if (config.engines.size() < 2) {
        throw std::invalid_argument("At least 2 engines are required for a "
                                    "tournament");
    }

    for (const auto &engine : config.engines) {
        if (engine.command.empty()) {
            throw std::invalid_argument("Engine command cannot be empty");
        }
        if (engine.name.empty()) {
            throw std::invalid_argument("Engine name cannot be empty");
        }
    }

    if (config.rounds < 1) {
        throw std::invalid_argument("Number of rounds must be at least 1");
    }

    if (config.concurrency < 1) {
        throw std::invalid_argument("Concurrency must be at least 1");
    }

    if (config.time_control.base_time <= std::chrono::milliseconds(0)) {
        throw std::invalid_argument("Base time must be positive");
    }
}

void CLIParser::showError(const std::string &message)
{
    std::cerr << "Error: " << message << std::endl;
}

void CLIParser::showUsage()
{
    std::cout << "Fastmill - Tournament tool for Mill (Nine Men's Morris) "
                 "engines\n\n";
    std::cout << "Usage: fastmill [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  -engine cmd=ENGINE name=NAME [dir=DIR]   Add an engine\n";
    std::cout << "  -each tc=TIME_CONTROL                    Set time control "
                 "(format: base+increment)\n";
    std::cout << "  -rounds N                                Number of "
                 "rounds\n";
    std::cout << "  -concurrency N                           Number of "
                 "concurrent games\n";
    std::cout << "  -tournament TYPE                         Tournament type "
                 "(roundrobin, gauntlet, swiss)\n";
    std::cout << "  -openings FILE                           Opening book "
                 "file\n";
    std::cout << "  -pgnout FILE                             Save games to PGN "
                 "file\n";
    std::cout << "  -log FILE                                Log file path\n";
}

} // namespace fastmill
