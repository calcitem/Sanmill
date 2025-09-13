// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_config.h - Tournament configuration for Mill tournaments
// Based on fastchess config but adapted for Mill game

#pragma once

#include <string>
#include <vector>
#include <chrono>

// Reuse Mill game types from Sanmill
#include "types.h"
#include "rule.h"

namespace fastmill {

// Tournament types
enum class TournamentType {
    ROUNDROBIN,
    GAUNTLET,
    SWISS
};

// Time control configuration
struct TimeControl {
    std::chrono::milliseconds base_time{60000};    // 1 minute default
    std::chrono::milliseconds increment{1000};     // 1 second increment
    int moves_to_go{0};                           // 0 = no move limit
    
    std::string toString() const {
        return std::to_string(base_time.count() / 1000) + "+" + 
               std::to_string(increment.count() / 1000);
    }
};

// Engine configuration
struct EngineConfig {
    std::string name;
    std::string command;
    std::string working_directory;
    std::vector<std::string> args;
    std::chrono::milliseconds startup_time{5000};
    
    // Mill-specific options
    Rule rule_variant;
    int search_depth{10};
    bool use_opening_book{true};
};

// Adjudication settings
struct DrawAdjudication {
    bool enabled{true};
    int move_number{40};      // Start adjudication after this move
    int move_count{8};        // Number of moves below threshold
    int score{10};            // Score threshold in centipawns
};

struct ResignAdjudication {
    bool enabled{true};
    int move_number{10};      // Start adjudication after this move
    int move_count{4};        // Number of moves below threshold
    int score{400};           // Score threshold in centipawns
};

struct MaxMovesAdjudication {
    bool enabled{true};
    int max_moves{200};       // Maximum moves before draw
};

// PGN output configuration
struct PgnConfig {
    std::string file;
    bool save_games{true};
    bool include_fen{false};
    bool include_eval{false};
};

// Forward declaration (removed duplicate namespace)

// Log configuration
struct LogConfig {
    std::string file;
    int level{2}; // INFO level (0=TRACE, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL)
    bool engine_output{false};
};

// Opening book configuration
struct OpeningConfig {
    std::string file;
    bool randomize{true};
    int max_ply{20};
};

// Main tournament configuration
struct TournamentConfig {
    // Tournament settings
    TournamentType type{TournamentType::ROUNDROBIN};
    std::vector<EngineConfig> engines;
    int rounds{1};
    int concurrency{1};
    
    // Time control
    TimeControl time_control;
    
    // Mill game settings
    Rule mill_variant;
    
    // Adjudication
    DrawAdjudication draw_adjudication;
    ResignAdjudication resign_adjudication;
    MaxMovesAdjudication maxmoves_adjudication;
    
    // Output
    PgnConfig pgn;
    LogConfig log;
    
    // Opening book
    OpeningConfig opening;
    
    // Validation
    bool isValid() const {
        return engines.size() >= 2 && 
               rounds >= 1 && 
               concurrency >= 1 &&
               time_control.base_time > std::chrono::milliseconds(0);
    }
};

} // namespace fastmill
