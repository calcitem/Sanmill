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
#include "nnue/nnue_training.h"

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
    } else if (token == "generate_nnue_data") {
        // Handle NNUE training data generation with strict mode and phase quotas
        std::string output_file;
        int num_positions = 50000; // default
        int num_threads = 0;       // auto-detect
        
        is >> output_file;
        if (!(is >> num_positions)) {
            num_positions = 50000;
        }
        if (!(is >> num_threads)) {
            num_threads = 0; // auto-detect
        }
        
        if (output_file.empty()) {
            output_file = "training_data.txt";
        }
        
        sync_cout << "Generating " << num_positions << " NNUE training positions to " 
                  << output_file << " with " << (num_threads > 0 ? std::to_string(num_threads) : "auto") 
                  << " threads..." << sync_endl;
        
        // Create default phase quotas: 70% moving, 30% placing
        std::vector<NNUE::PhaseQuota> phase_quotas;
        phase_quotas.emplace_back(Phase::moving, 
                                 static_cast<int>(num_positions * 0.7f),
                                 static_cast<int>(num_positions * 0.5f), 
                                 2.0f);
        phase_quotas.emplace_back(Phase::placing, 
                                 static_cast<int>(num_positions * 0.3f),
                                 static_cast<int>(num_positions * 0.2f), 
                                 1.0f);
        
        NNUE::TrainingDataGenerator generator;
        
        bool success = generator.generate_training_set(output_file, num_positions, 
                                                     phase_quotas, num_threads);
        
        // Assert success - errors are surfaced rather than masked
        assert(success && "NNUE training data generation failed");
        
        sync_cout << "NNUE training data generation completed successfully." << sync_endl;
    } else {
        // Handle additional custom commands if necessary
        sync_cout << "Unknown command in EngineController: " << cmd
                  << sync_endl;
    }
}
