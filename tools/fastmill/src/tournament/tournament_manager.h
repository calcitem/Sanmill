// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tournament_manager.h - Tournament management for Mill engines
// Based on fastchess TournamentManager but adapted for Mill game

#pragma once

#include <memory>
#include <vector>
#include <string>

#include "tournament_config.h"
#include "cli/cli_parser.h"

namespace fastmill {

class BaseTournament;

class TournamentManager {
public:
    TournamentManager(const TournamentConfig& config);
    ~TournamentManager();
    
    // Start the tournament
    void start();
    
private:
    TournamentConfig config_;
    std::unique_ptr<BaseTournament> tournament_;
    
    // Initialize tournament based on type
    void createTournament();
};

// Base class for all tournament types
class BaseTournament {
public:
    explicit BaseTournament(const TournamentConfig& config);
    virtual ~BaseTournament() = default;
    
    // Start the tournament
    virtual void start() = 0;
    
protected:
    TournamentConfig config_;
    
    // Common tournament functionality
    void initializeEngines();
    void runMatches();
    void printResults();
    
    // Match scheduling
    virtual void generatePairings() = 0;
    
    // Statistics
    int total_games_ = 0;
    int completed_games_ = 0;
};

// Round Robin tournament implementation
class RoundRobinTournament : public BaseTournament {
public:
    explicit RoundRobinTournament(const TournamentConfig& config);
    
    void start() override;
    
protected:
    void generatePairings() override;
};

// Gauntlet tournament implementation  
class GauntletTournament : public BaseTournament {
public:
    explicit GauntletTournament(const TournamentConfig& config);
    
    void start() override;
    
protected:
    void generatePairings() override;
};

} // namespace fastmill