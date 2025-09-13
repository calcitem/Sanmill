// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// main.cpp - Main entry point for Fastmill tournament tool

#include <iostream>
#include <string>
#include <vector>
#include <chrono>

// Reuse existing Sanmill headers
#include "types.h"
#include "position.h"
#include "uci.h"
#include "rule.h"
#include "mills.h"

// Fastmill specific headers
#include "tournament/tournament_types.h"
#include "tournament/tournament_manager.h"
#include "cli/cli_parser.h"
#include "utils/logger.h"

namespace fastmill {
const char *version = "1.0.0";
}

using namespace fastmill;

void printUsage(const char *program_name)
{
    std::cout << "Fastmill " << fastmill::version
              << " - Tournament tool for Mill (Nine Men's Morris) engines\n\n";
    std::cout << "Usage: " << program_name << " [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  -engine cmd=ENGINE name=NAME [options]  Add an engine\n";
    std::cout << "  -each tc=TIME_CONTROL                   Set time control "
                 "for all engines\n";
    std::cout << "  -rounds N                               Number of rounds "
                 "to play\n";
    std::cout << "  -concurrency N                          Number of "
                 "concurrent games\n";
    std::cout << "  -tournament TYPE                        Tournament type "
                 "(roundrobin, gauntlet, swiss)\n";
    std::cout << "  -rule VARIANT                           Mill rule "
                 "variant\n";
    std::cout << "  -openings FILE                          Opening book "
                 "file\n";
    std::cout << "  -pgnout FILE                            Save games to PGN "
                 "file\n";
    std::cout << "  -log FILE                               Log file path\n";
    std::cout << "  -help                                   Show this help\n";
    std::cout << "  -version                                Show version\n\n";
    std::cout << "Example:\n";
    std::cout << "  " << program_name
              << " -engine cmd=sanmill name=Engine1 \\\n";
    std::cout << "                        -engine cmd=sanmill name=Engine2 "
                 "\\\n";
    std::cout << "                        -each tc=60+1 -rounds 100 "
                 "-concurrency 4\n\n";
}

void printVersion()
{
    std::cout << "Fastmill " << fastmill::version << "\n";
    std::cout << "Tournament tool for Mill (Nine Men's Morris) engines\n";
    std::cout << "Based on Sanmill engine framework\n";
}

int main(int argc, char *argv[])
{
    // Check for simple commands first (before any initialization)
    if (argc >= 2) {
        std::string arg = argv[1];
        if (arg == "-help" || arg == "--help") {
            printUsage(argv[0]);
            return 0;
        }
        if (arg == "-version" || arg == "--version") {
            printVersion();
            return 0;
        }
    }

    // Parse command line arguments
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }

    // Initialize Mills game components from existing Sanmill code (after arg
    // check)
    try {
        Mills::adjacent_squares_init();
        Mills::mill_table_init();
    } catch (const std::exception &e) {
        std::cerr << "Error initializing Mills components: " << e.what()
                  << std::endl;
        return 1;
    }

    try {
        // Initialize logger
        Logger::initialize();

        // Parse command line arguments
        CLIParser parser;
        TournamentConfig config = parser.parse(argc, argv);

        // Validate configuration
        if (config.engines.size() < 2) {
            std::cerr << "Error: At least 2 engines are required for a "
                         "tournament\n";
            return 1;
        }

        Logger::info("Starting Fastmill tournament with " +
                     std::to_string(config.engines.size()) + " engines");

        std::string tournament_type = (config.type ==
                                               TournamentType::ROUNDROBIN ?
                                           "Round Robin" :
                                       config.type == TournamentType::GAUNTLET ?
                                           "Gauntlet" :
                                           "Swiss");
        Logger::info("Tournament type: " + tournament_type);
        Logger::info("Rounds: " + std::to_string(config.rounds));
        Logger::info("Concurrency: " + std::to_string(config.concurrency));
        Logger::info("Time control: " + config.time_control.toString());

        // Create and run tournament
        auto start_time = std::chrono::steady_clock::now();

        TournamentManager tournament(config);
        TournamentStats stats = tournament.run();

        auto end_time = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::seconds>(
            end_time - start_time);

        // Print final results
        std::cout << "\n=== Tournament Results ===\n";
        std::cout << "Games played: " << stats.games_played << "\n";
        std::cout << "White wins: " << stats.white_wins << "\n";
        std::cout << "Black wins: " << stats.black_wins << "\n";
        std::cout << "Draws: " << stats.draws << "\n";
        std::cout << "Timeouts: " << stats.timeouts << "\n";
        std::cout << "Errors: " << stats.errors << "\n";
        std::cout << "Total time: " << duration.count() << " seconds\n";

        Logger::info("Tournament completed successfully");

    } catch (const std::exception &e) {
        std::cerr << "Error: " << e.what() << "\n";
        Logger::error("Tournament failed: " + std::string(e.what()));
        return 1;
    }

    return 0;
}
