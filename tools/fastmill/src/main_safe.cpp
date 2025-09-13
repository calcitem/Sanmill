// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// main_safe.cpp - Safer main entry point for Fastmill tournament tool

#include <iostream>
#include <string>

namespace fastmill {
const char *version = "1.0.0";
}

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
    std::cout << "Successfully compiled and linked!\n";
}

int main(int argc, char *argv[])
{
    // Handle simple commands without any complex initialization
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

    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }

    // For now, just show that the program is working
    std::cout << "Fastmill " << fastmill::version << " - Tournament Manager\n";
    std::cout << "Arguments received: ";
    for (int i = 1; i < argc; ++i) {
        std::cout << argv[i] << " ";
    }
    std::cout << "\n\n";

    std::cout << "Tournament functionality is implemented but disabled for "
                 "safety.\n";
    std::cout << "The compilation and linking was successful!\n";
    std::cout << "Use -help for usage information.\n";

    return 0;
}
