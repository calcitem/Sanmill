// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_types.h - Tournament-specific type definitions for Mill

#pragma once

#include <string>
#include <chrono>
#include <vector>

// Reuse all core types from main Sanmill project
#include "types.h"
#include "rule.h"

namespace fastmill {

// Tournament types
enum class TournamentType { ROUNDROBIN, GAUNTLET, SWISS };

// Time control for Mill games
struct TimeControl
{
    std::chrono::milliseconds base_time {60000}; // 1 minute base time
    std::chrono::milliseconds increment {1000};  // 1 second increment
    int moves_to_go {0};                         // 0 means no move limit

    std::string toString() const
    {
        return std::to_string(base_time.count() / 1000) + "+" +
               std::to_string(increment.count() / 1000);
    }
};

// Engine configuration for Mill engines
struct EngineConfig
{
    std::string name;
    std::string command;
    std::string working_directory;
    std::vector<std::string> args;
    std::chrono::milliseconds startup_time {5000};

    // Mill-specific engine options using existing Rule struct
    Rule rule_variant; // Which Mill variant to use
    int search_depth {10};
    bool use_opening_book {true};
};

// Tournament configuration
struct TournamentConfig
{
    TournamentType type {TournamentType::ROUNDROBIN};
    std::vector<EngineConfig> engines;
    TimeControl time_control;
    int rounds {1};
    int concurrency {1};
    bool save_games {true};
    std::string pgn_output_path;
    std::string log_file_path;

    // Mill-specific tournament settings using existing Rule struct
    Rule mill_variant;
    bool use_opening_book {false};
    std::string opening_book_path;
    bool randomize_openings {true};

    // Adjudication settings
    int max_moves {200};      // Maximum moves before draw
    int repetition_limit {3}; // Threefold repetition
    bool adjudicate_draws {true};
    int draw_score_limit {10}; // Centipawn limit for draw adjudication
    int draw_move_count {50};  // Moves to adjudicate draw
};

// Tournament statistics
struct TournamentStats
{
    int games_played {0};
    int white_wins {0};
    int black_wins {0};
    int draws {0};
    int timeouts {0};
    int errors {0};
    std::chrono::milliseconds total_time {0};

    double getWinRate(const std::string &engine_name) const;
    double getScore(const std::string &engine_name) const;
};

// Output format options
enum class OutputFormat { HUMAN_READABLE, JSON, CSV, PGN };

} // namespace fastmill
