// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// main_complete.cpp - Complete main entry point for Fastmill tournament tool
// Based on fastchess architecture but adapted for Mill game

#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <memory>
#include <exception>

// Fastmill headers
#include "core/logger.h"
#include "core/globals.h"
#include "cli/cli_parser.h"
#include "tournament/tournament_manager.h"

namespace fastmill {
const char* version = "1.0.0";
}

namespace ch = std::chrono;
using namespace fastmill;

void printUsage(const char* program_name) {
    std::cout << "Fastmill " << fastmill::version << " - Tournament tool for Mill (Nine Men's Morris) engines\n\n";
    std::cout << "Usage: " << program_name << " [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  -engine cmd=ENGINE name=NAME [options]  Add an engine\n";
    std::cout << "  -each tc=TIME_CONTROL                   Set time control for all engines\n";
    std::cout << "  -rounds N                               Number of rounds to play\n";
    std::cout << "  -concurrency N                          Number of concurrent games\n";
    std::cout << "  -tournament TYPE                        Tournament type (roundrobin, gauntlet, swiss)\n";
    std::cout << "  -rule VARIANT                           Mill rule variant\n";
    std::cout << "  -openings FILE                          Opening book file\n";
    std::cout << "  -pgnout FILE                            Save games to PGN file\n";
    std::cout << "  -log FILE                               Log file path\n";
    std::cout << "  -help                                   Show this help\n";
    std::cout << "  -version                                Show version\n\n";
    std::cout << "Example:\n";
    std::cout << "  " << program_name << " -engine cmd=sanmill name=Engine1 \\\n";
    std::cout << "                        -engine cmd=sanmill name=Engine2 \\\n";
    std::cout << "                        -each tc=60+1 -rounds 100 -concurrency 4\n\n";
}

void printVersion() {
    std::cout << "Fastmill " << fastmill::version << "\n";
    std::cout << "Tournament tool for Mill (Nine Men's Morris) engines\n";
    std::cout << "Based on Sanmill engine framework\n";
}

int main(int argc, char* argv[]) {
    // Set up signal handlers (similar to fastchess)
    setCtrlCHandler();
    
    // Handle simple commands first
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
    
    const auto t0 = ch::steady_clock::now();
    
    try {
        // Initialize logger early
        Logger::initialize();
        
        // Parse command line arguments
        CLIParser parser;
        auto config = parser.parse(argc, const_cast<char**>(argv));
        
        // Create and start tournament
        auto tournament = TournamentManager(config);
        tournament.start();
        
        if (atomic::abnormal_termination) {
            if (argc > 0) {
                Logger::print("Tournament was interrupted. To resume, restart with same parameters.");
            } else {
                Logger::print("Tournament was interrupted.");
            }
        }
        
    } catch (const std::exception& e) {
        stopProcesses();
        
        Logger::print("PLEASE submit a bug report and include command line parameters and log output.");
        Logger::print("Error: {}", e.what());
        
        return EXIT_FAILURE;
    }
    
    stopProcesses();
    
    Logger::print("Finished tournament");
    
    const auto duration = ch::steady_clock::now() - t0;
    const auto h = ch::duration_cast<ch::hours>(duration).count();
    const auto m = ch::duration_cast<ch::minutes>(duration % ch::hours(1)).count();
    const auto s = ch::duration_cast<ch::seconds>(duration % ch::minutes(1)).count();
    
    Logger::print("Total Time: {:02}:{:02}:{:02} (hours:minutes:seconds)\n", h, m, s);
    
    return atomic::abnormal_termination ? EXIT_FAILURE : EXIT_SUCCESS;
}
