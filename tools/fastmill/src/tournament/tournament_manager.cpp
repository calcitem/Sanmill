// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_manager.cpp - Implementation of tournament manager

#include "tournament_manager.h"
#include "utils/logger.h"
#include <algorithm>
#include <iostream>
#include <iomanip>

namespace fastmill {

TournamentManager::TournamentManager(const TournamentConfig &config)
    : config_(config)
{
    // Initialize engine manager
    engine_manager_ = std::make_unique<EngineManager>(config_.engines);

    // Initialize ELO calculator
    elo_calculator_ = std::make_unique<EloCalculator>();
    for (const auto &engine : config_.engines) {
        elo_calculator_->addEngine(engine.name);
    }
}

TournamentManager::~TournamentManager()
{
    stop();

    // Wait for all worker threads to finish
    for (auto &thread : worker_threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }

    if (progress_reporter_thread_.joinable()) {
        progress_reporter_thread_.join();
    }
}

TournamentStats TournamentManager::run()
{
    logTournamentStart();

    // Initialize all engines
    if (!engine_manager_->initializeAll()) {
        Logger::error("Failed to initialize all engines");
        stats_.errors = 1;
        return stats_;
    }

    // Generate tournament pairings
    switch (config_.type) {
    case TournamentType::ROUNDROBIN:
        generateRoundRobinPairings();
        break;
    case TournamentType::GAUNTLET:
        generateGauntletPairings();
        break;
    case TournamentType::SWISS:
        generateSwissPairings();
        break;
    }

    progress_.total_matches = static_cast<int>(match_queue_.size());
    progress_.start_time = std::chrono::steady_clock::now();

    Logger::info("Starting tournament with " +
                 std::to_string(progress_.total_matches) + " matches");

    // Start worker threads
    running_ = true;
    for (int i = 0; i < config_.concurrency; ++i) {
        worker_threads_.emplace_back(&TournamentManager::workerThread, this, i);
    }

    // Start progress reporter
    progress_reporter_thread_ = std::thread(
        &TournamentManager::progressReporterWorker, this);

    // Wait for all matches to complete
    for (auto &thread : worker_threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }

    running_ = false;

    // Wait for progress reporter to finish
    if (progress_reporter_thread_.joinable()) {
        progress_reporter_thread_.join();
    }

    // Save results
    saveResults();

    logTournamentEnd();
    printFinalResults();

    return stats_;
}

void TournamentManager::pause()
{
    paused_ = true;
    Logger::info("Tournament paused");
}

void TournamentManager::resume()
{
    paused_ = false;
    Logger::info("Tournament resumed");
}

void TournamentManager::stop()
{
    stopped_ = true;
    running_ = false;
    Logger::info("Tournament stopped");
}

TournamentProgress TournamentManager::getProgress() const
{
    std::lock_guard<std::mutex> lock(stats_mutex_);
    return progress_;
}

TournamentStats TournamentManager::getCurrentStats() const
{
    std::lock_guard<std::mutex> lock(stats_mutex_);
    return stats_;
}

void TournamentManager::generateRoundRobinPairings()
{
    Logger::info("Generating Round Robin pairings");

    size_t num_engines = config_.engines.size();

    for (int round = 0; round < config_.rounds; ++round) {
        for (size_t i = 0; i < num_engines; ++i) {
            for (size_t j = i + 1; j < num_engines; ++j) {
                // Each pair plays twice (once with each color)
                match_queue_.emplace(i, j, round * 2);
                match_queue_.emplace(j, i, round * 2 + 1);
            }
        }
    }
}

void TournamentManager::generateGauntletPairings()
{
    Logger::info("Generating Gauntlet pairings");

    if (config_.engines.size() < 2) {
        Logger::error("Gauntlet requires at least 2 engines");
        return;
    }

    // First engine plays against all others
    size_t gauntlet_engine = 0;

    for (int round = 0; round < config_.rounds; ++round) {
        for (size_t i = 1; i < config_.engines.size(); ++i) {
            // Gauntlet engine plays both colors
            match_queue_.emplace(gauntlet_engine, i, round * 2);
            match_queue_.emplace(i, gauntlet_engine, round * 2 + 1);
        }
    }
}

void TournamentManager::generateSwissPairings()
{
    Logger::warning("Swiss system not yet implemented, falling back to Round "
                    "Robin");
    generateRoundRobinPairings();
}

void TournamentManager::workerThread(int worker_id)
{
    Logger::debug("Worker thread " + std::to_string(worker_id) + " started");

    while (running_ && !stopped_) {
        // Wait if paused
        while (paused_ && !stopped_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        if (stopped_)
            break;

        // Get next match from queue
        MatchPairing pairing(0, 0, 0);
        bool has_match = false;

        {
            std::lock_guard<std::mutex> lock(queue_mutex_);
            if (!match_queue_.empty()) {
                pairing = match_queue_.front();
                match_queue_.pop();
                has_match = true;
                progress_.running_matches++;
            }
        }

        if (has_match) {
            executeMatch(pairing);
        } else {
            // No more matches, wait a bit before checking again
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    Logger::debug("Worker thread " + std::to_string(worker_id) + " finished");
}

void TournamentManager::executeMatch(const MatchPairing &pairing)
{
    MillEngineWrapper *white_engine = engine_manager_->getEngine(
        pairing.white_engine_index);
    MillEngineWrapper *black_engine = engine_manager_->getEngine(
        pairing.black_engine_index);

    if (!white_engine || !black_engine) {
        Logger::error("Invalid engine indices in match pairing");
        return;
    }

    Logger::debug("Starting match: " + white_engine->getName() + " vs " +
                  black_engine->getName());

    MatchRunner runner(white_engine, black_engine, config_);
    MatchResult result = runner.runMatch();

    processMatchResult(result, pairing);
}

void TournamentManager::processMatchResult(const MatchResult &result,
                                           const MatchPairing &pairing)
{
    std::lock_guard<std::mutex> lock(stats_mutex_);

    // Update statistics
    updateStatistics(result);
    updateEloRatings(result, pairing);

    progress_.completed_matches++;
    progress_.running_matches--;

    Logger::info("Match completed: " + result.white_engine + " vs " +
                 result.black_engine +
                 " - Score: " + std::to_string(result.getScore()));
}

void TournamentManager::updateStatistics(const MatchResult &result)
{
    for (const auto &game : result.games) {
        stats_.games_played++;

        switch (game.result) {
        case GameResult::Result::WHITE_WINS:
            stats_.white_wins++;
            break;
        case GameResult::Result::BLACK_WINS:
            stats_.black_wins++;
            break;
        case GameResult::Result::DRAW:
            stats_.draws++;
            break;
        case GameResult::Result::TIMEOUT:
            stats_.timeouts++;
            break;
        case GameResult::Result::ERROR:
            stats_.errors++;
            break;
        }

        stats_.total_time += game.duration;
    }
}

void TournamentManager::updateEloRatings(const MatchResult &result,
                                         const MatchPairing & /* pairing */)
{
    for (const auto &game : result.games) {
        double white_score;
        switch (game.result) {
        case GameResult::Result::WHITE_WINS:
            white_score = 1.0;
            break;
        case GameResult::Result::BLACK_WINS:
            white_score = 0.0;
            break;
        case GameResult::Result::DRAW:
            white_score = 0.5;
            break;
        default:
            continue; // Skip timeouts and errors for ELO calculation
        }

        elo_calculator_->updateRatings(result.white_engine, result.black_engine,
                                       white_score);
    }
}

void TournamentManager::saveResults() const
{
    if (!config_.pgn_output_path.empty()) {
        Logger::info("Saving PGN games to: " + config_.pgn_output_path);
        // PGN saving would be implemented here
    }
}

void TournamentManager::savePGNGames(
    const std::vector<MatchResult> & /* results */) const
{
    // PGN saving implementation would go here
}

void TournamentManager::printCurrentStandings() const
{
    auto rankings = elo_calculator_->getRankings();

    std::cout << "\n=== Current Standings ===\n";
    std::cout << std::setw(4) << "Rank" << std::setw(20) << "Engine"
              << std::setw(10) << "Rating" << std::setw(8) << "Games"
              << std::setw(6) << "W" << std::setw(6) << "L" << std::setw(6)
              << "D" << std::setw(8) << "Score%" << "\n";
    std::cout << std::string(68, '-') << "\n";

    for (size_t i = 0; i < rankings.size(); ++i) {
        const auto &rating = rankings[i];
        std::cout << std::setw(4) << (i + 1) << std::setw(20) << rating.name
                  << std::setw(10) << std::fixed << std::setprecision(1)
                  << rating.rating << std::setw(8) << rating.games_played
                  << std::setw(6) << rating.wins << std::setw(6)
                  << rating.losses << std::setw(6) << rating.draws
                  << std::setw(7) << std::fixed << std::setprecision(1)
                  << (rating.getScore() * 100) << "%"
                  << "\n";
    }
    std::cout << "\n";
}

void TournamentManager::printFinalResults() const
{
    std::cout << "\n=== Final Tournament Results ===\n";
    printCurrentStandings();

    std::cout << "Tournament Statistics:\n";
    std::cout << "Total games: " << stats_.games_played << "\n";
    std::cout << "White wins: " << stats_.white_wins << " (" << std::fixed
              << std::setprecision(1)
              << (100.0 * stats_.white_wins / std::max(1, stats_.games_played))
              << "%)\n";
    std::cout << "Black wins: " << stats_.black_wins << " (" << std::fixed
              << std::setprecision(1)
              << (100.0 * stats_.black_wins / std::max(1, stats_.games_played))
              << "%)\n";
    std::cout << "Draws: " << stats_.draws << " (" << std::fixed
              << std::setprecision(1)
              << (100.0 * stats_.draws / std::max(1, stats_.games_played))
              << "%)\n";
    std::cout << "Timeouts: " << stats_.timeouts << "\n";
    std::cout << "Errors: " << stats_.errors << "\n";
    std::cout << "Average game time: "
              << (stats_.total_time.count() / std::max(1, stats_.games_played))
              << " ms\n";
    std::cout << "Total tournament time: "
              << std::chrono::duration_cast<std::chrono::seconds>(
                     progress_.getElapsedTime())
                     .count()
              << " seconds\n";
}

std::string TournamentManager::getEngineDisplayName(size_t index) const
{
    if (index < config_.engines.size()) {
        return config_.engines[index].name;
    }
    return "Unknown";
}

void TournamentManager::logTournamentStart() const
{
    Logger::info("=== Tournament Starting ===");

    std::string tournament_type = (config_.type == TournamentType::ROUNDROBIN ?
                                       "Round Robin" :
                                   config_.type == TournamentType::GAUNTLET ?
                                       "Gauntlet" :
                                       "Swiss");
    Logger::info("Type: " + tournament_type);
    Logger::info("Engines: " + std::to_string(config_.engines.size()));
    Logger::info("Rounds: " + std::to_string(config_.rounds));
    Logger::info("Concurrency: " + std::to_string(config_.concurrency));
    Logger::info("Time control: " + config_.time_control.toString());
}

void TournamentManager::logTournamentEnd() const
{
    Logger::info("=== Tournament Completed ===");
    Logger::info("Games played: " + std::to_string(stats_.games_played));
    Logger::info(
        "Duration: " +
        std::to_string(std::chrono::duration_cast<std::chrono::seconds>(
                           progress_.getElapsedTime())
                           .count()) +
        " seconds");
}

void TournamentManager::reportProgress() const
{
    TournamentProgress current_progress = getProgress();

    std::cout << "\rProgress: " << current_progress.completed_matches << "/"
              << current_progress.total_matches << " (" << std::fixed
              << std::setprecision(1) << current_progress.getProgressPercent()
              << "%)"
              << " - Running: " << current_progress.running_matches
              << " - Elapsed: "
              << std::chrono::duration_cast<std::chrono::seconds>(
                     current_progress.getElapsedTime())
                     .count()
              << "s" << std::flush;
}

void TournamentManager::progressReporterWorker()
{
    while (running_) {
        reportProgress();
        std::this_thread::sleep_for(std::chrono::seconds(5));

        // Print standings every 30 seconds
        static int counter = 0;
        if (++counter % 6 == 0) {
            std::cout << "\n";
            printCurrentStandings();
        }
    }

    // Final progress report
    std::cout << "\n";
}

} // namespace fastmill
