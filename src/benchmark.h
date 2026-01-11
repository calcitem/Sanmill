// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// benchmark.h

#ifndef BENCHMARK_H_INCLUDED
#define BENCHMARK_H_INCLUDED

#include <atomic>
#include <cstdint>
#include <istream>
#include <string>

namespace Benchmark {

struct BenchmarkConfig
{
    int totalGames {100};    // Total games across both threads
    int moveTimeSec {0};     // Thinking time per move (seconds); 0 = infinite
    int skillLevel {15};     // Skill level (used by some algorithms)
    int algorithm {2};       // 0=AlphaBeta,1=PVS,2=MTDf,3=MCTS,4=Random
    bool idsEnabled {false}; // Enable IDS (C++ default: false)
    bool depthExtension {true}; // Enable depth extension on single reply (C++
                                // default: true)
    bool openingBook {false};   // Enable opening book if compiled (C++ default:
                                // false)
    bool shuffling {true};    // Shuffle successors if equal evals (C++ default:
                              // true)
    bool usePerfectDb {true}; // Force using Perfect DB side where needed
                              // (REQUIRED for benchmark)
    int nMoveRule {100}; // N-move rule for draw detection (C++ default: 100)
    std::string perfectDbPath {"D:\\\\user\\\\Documents\\\\strong"};
    std::string iniPath {"settings.ini"};
};

struct ThreadStats
{
    std::atomic<uint64_t> tradWins {0};
    std::atomic<uint64_t> perfectWins {0};
    std::atomic<uint64_t> draws {0};
    std::atomic<uint64_t> total {0};
    std::atomic<uint64_t> errors {0};         // Track engine errors
    std::atomic<uint64_t> timeouts {0};       // Track timeout situations
    std::atomic<uint64_t> repetitions {0};    // Track 3-fold repetition draws
    std::atomic<uint64_t> totalMoves {0};     // Track total moves played
    std::atomic<uint64_t> maxMovesInGame {0}; // Track longest game
    std::atomic<uint64_t> earlyWinTerminations {0};  // Track early win
                                                     // terminations by Perfect
                                                     // DB
    std::atomic<uint64_t> earlyDrawTerminations {0}; // Track early draw
                                                     // terminations when 3
                                                     // pieces left
    std::atomic<uint64_t> fiftyMoveRuleDraws {0};    // Track 50-move rule draws
    std::atomic<uint64_t> endgameFiftyMoveRuleDraws {0}; // Track endgame
                                                         // 50-move rule draws
};

// Entry from UCI CLI, parses tokens and runs benchmark synchronously.
// Example: benchmark --games 200 --movetime 1 --skill 3 --ini settings.ini --pd
// path
void run_from_cli(std::istream &is);

} // namespace Benchmark

#endif // BENCHMARK_H_INCLUDED
