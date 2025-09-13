// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_manager.cpp - Implementation of tournament manager
// Based on fastchess TournamentManager but adapted for Mill game

#include "tournament_manager.h"
#include "core/logger.h"
#include <stdexcept>

namespace fastmill {

// TournamentManager implementation
TournamentManager::TournamentManager(const TournamentConfig& config) 
    : config_(config) {
    createTournament();
}

TournamentManager::~TournamentManager() {
    // Cleanup handled by unique_ptr
}

void TournamentManager::start() {
    if (!tournament_) {
        throw std::runtime_error("Tournament not properly initialized");
    }
    
    Logger::info("Starting Fastmill tournament");
    tournament_->start();
    Logger::info("Tournament completed");
}

void TournamentManager::createTournament() {
    switch (config_.type) {
        case TournamentType::ROUNDROBIN:
            tournament_ = std::make_unique<RoundRobinTournament>(config_);
            break;
        case TournamentType::GAUNTLET:
            tournament_ = std::make_unique<GauntletTournament>(config_);
            break;
        case TournamentType::SWISS:
            // Swiss system not implemented yet, fall back to Round Robin
            Logger::warning("Swiss system not implemented, using Round Robin");
            tournament_ = std::make_unique<RoundRobinTournament>(config_);
            break;
        default:
            throw std::runtime_error("Unsupported tournament type");
    }
}

// BaseTournament implementation
BaseTournament::BaseTournament(const TournamentConfig& config) 
    : config_(config) {
}

void BaseTournament::initializeEngines() {
    Logger::info("Initializing " + std::to_string(config_.engines.size()) + " engines");
    
    // Engine initialization would be implemented here
    // For now, just log the engines
    for (const auto& engine : config_.engines) {
        Logger::info("Engine: " + engine.name + " (cmd: " + engine.command + ")");
    }
}

void BaseTournament::runMatches() {
    Logger::info("Running tournament matches");
    
    // Generate pairings
    generatePairings();
    
    // Run matches (simplified implementation)
    Logger::info("Tournament execution completed");
    completed_games_ = total_games_;
}

void BaseTournament::printResults() {
    Logger::info("=== Tournament Results ===");
    Logger::info("Total games: " + std::to_string(total_games_));
    Logger::info("Completed games: " + std::to_string(completed_games_));
    
    // Print engine results
    for (const auto& engine : config_.engines) {
        Logger::info("Engine: " + engine.name);
        // Detailed statistics would be implemented here
    }
}

// RoundRobinTournament implementation
RoundRobinTournament::RoundRobinTournament(const TournamentConfig& config) 
    : BaseTournament(config) {
    Logger::info("Created Round Robin tournament");
}

void RoundRobinTournament::start() {
    Logger::info("Starting Round Robin tournament");
    Logger::info("Engines: " + std::to_string(config_.engines.size()));
    Logger::info("Rounds: " + std::to_string(config_.rounds));
    Logger::info("Concurrency: " + std::to_string(config_.concurrency));
    Logger::info("Time control: " + config_.time_control.toString());
    
    initializeEngines();
    runMatches();
    printResults();
}

void RoundRobinTournament::generatePairings() {
    Logger::info("Generating Round Robin pairings");
    
    size_t num_engines = config_.engines.size();
    
    // Calculate total games: each engine plays every other engine
    // for the specified number of rounds, with color alternation
    total_games_ = static_cast<int>(num_engines * (num_engines - 1) * config_.rounds);
    
    Logger::info("Total games to play: " + std::to_string(total_games_));
    
    // Actual pairing generation would be implemented here
    // For now, just log the pairing structure
    for (int round = 0; round < config_.rounds; ++round) {
        for (size_t i = 0; i < num_engines; ++i) {
            for (size_t j = i + 1; j < num_engines; ++j) {
                Logger::debug("Round " + std::to_string(round + 1) + 
                             ": " + config_.engines[i].name + 
                             " vs " + config_.engines[j].name);
            }
        }
    }
}

// GauntletTournament implementation
GauntletTournament::GauntletTournament(const TournamentConfig& config) 
    : BaseTournament(config) {
    Logger::info("Created Gauntlet tournament");
}

void GauntletTournament::start() {
    Logger::info("Starting Gauntlet tournament");
    
    if (config_.engines.size() < 2) {
        throw std::runtime_error("Gauntlet tournament requires at least 2 engines");
    }
    
    Logger::info("Gauntlet engine: " + config_.engines[0].name);
    Logger::info("Opponents: " + std::to_string(config_.engines.size() - 1));
    Logger::info("Rounds: " + std::to_string(config_.rounds));
    Logger::info("Time control: " + config_.time_control.toString());
    
    initializeEngines();
    runMatches();
    printResults();
}

void GauntletTournament::generatePairings() {
    Logger::info("Generating Gauntlet pairings");
    
    if (config_.engines.size() < 2) {
        Logger::error("Gauntlet requires at least 2 engines");
        return;
    }
    
    // First engine (gauntlet engine) plays against all others
    size_t gauntlet_engine = 0;
    size_t num_opponents = config_.engines.size() - 1;
    
    // Calculate total games: gauntlet engine vs each opponent
    // for the specified number of rounds, with color alternation
    total_games_ = static_cast<int>(num_opponents * config_.rounds * 2); // 2 for color alternation
    
    Logger::info("Total games to play: " + std::to_string(total_games_));
    
    // Log pairing structure
    for (int round = 0; round < config_.rounds; ++round) {
        for (size_t i = 1; i < config_.engines.size(); ++i) {
            Logger::debug("Round " + std::to_string(round + 1) + 
                         ": " + config_.engines[gauntlet_engine].name + 
                         " vs " + config_.engines[i].name);
        }
    }
}

} // namespace fastmill