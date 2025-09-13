// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_manager.h - Main tournament management for Mill engines

#pragma once

#include <vector>
#include <memory>
#include <thread>
#include <mutex>
#include <atomic>
#include <queue>

#include "tournament/tournament_types.h"
#include "tournament/match_runner.h"
#include "engine/mill_engine_wrapper.h"
#include "stats/elo_calculator.h"

namespace fastmill {

// Pairing for a match
struct MatchPairing
{
    size_t white_engine_index;
    size_t black_engine_index;
    int round_number;

    MatchPairing(size_t white, size_t black, int round)
        : white_engine_index(white)
        , black_engine_index(black)
        , round_number(round)
    { }
};

// Tournament progress tracking
struct TournamentProgress
{
    int total_matches {0};
    int completed_matches {0};
    int running_matches {0};
    std::chrono::steady_clock::time_point start_time;

    double getProgressPercent() const
    {
        return total_matches > 0 ? (100.0 * completed_matches / total_matches) :
                                   0.0;
    }

    std::chrono::milliseconds getElapsedTime() const
    {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start_time);
    }
};

// Main tournament manager class
class TournamentManager
{
public:
    explicit TournamentManager(const TournamentConfig &config);
    ~TournamentManager();

    // Run the complete tournament
    TournamentStats run();

    // Tournament control
    void pause();
    void resume();
    void stop();

    // Progress monitoring
    TournamentProgress getProgress() const;
    TournamentStats getCurrentStats() const;

private:
    TournamentConfig config_;
    std::unique_ptr<EngineManager> engine_manager_;
    std::unique_ptr<EloCalculator> elo_calculator_;

    // Tournament state
    std::atomic<bool> running_ {false};
    std::atomic<bool> paused_ {false};
    std::atomic<bool> stopped_ {false};

    // Match scheduling
    std::queue<MatchPairing> match_queue_;
    std::mutex queue_mutex_;

    // Statistics
    TournamentStats stats_;
    TournamentProgress progress_;
    mutable std::mutex stats_mutex_;

    // Thread management
    std::vector<std::thread> worker_threads_;

    // Tournament generation
    void generateRoundRobinPairings();
    void generateGauntletPairings();
    void generateSwissPairings(); // Placeholder for future implementation

    // Match execution
    void workerThread(int worker_id);
    void executeMatch(const MatchPairing &pairing);

    // Results processing
    void processMatchResult(const MatchResult &result,
                            const MatchPairing &pairing);
    void updateStatistics(const MatchResult &result);
    void updateEloRatings(const MatchResult &result,
                          const MatchPairing &pairing);

    // Output generation
    void saveResults() const;
    void savePGNGames(const std::vector<MatchResult> &results) const;
    void printCurrentStandings() const;
    void printFinalResults() const;

    // Utility methods
    std::string getEngineDisplayName(size_t index) const;
    void logTournamentStart() const;
    void logTournamentEnd() const;

    // Progress reporting
    void reportProgress() const;
    std::thread progress_reporter_thread_;
    void progressReporterWorker();
};

} // namespace fastmill
