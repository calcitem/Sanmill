// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_uci_engine.h - UCI engine interface for Mill engines
// Based on fastchess UciEngine but adapted for Mill game

#pragma once

#include <string>
#include <vector>
#include <chrono>
#include <memory>
#include <optional>

#include "tournament/tournament_config.h"
#include "engine/process.h"

// Forward declarations to avoid complex dependencies
class Position;

namespace fastmill {

enum class EngineStatus {
    OK,
    TIMEOUT,
    CRASHED,
    ERROR
};

class MillUciEngine {
public:
    explicit MillUciEngine(const EngineConfig& config, bool realtime_logging = false);
    ~MillUciEngine();
    
    // Engine lifecycle
    EngineStatus start();
    void quit();
    bool isAlive() const;
    
    // UCI protocol
    EngineStatus uci();
    EngineStatus isready(std::chrono::milliseconds threshold = std::chrono::milliseconds(5000));
    EngineStatus ucinewgame();
    
    // Position and moves
    bool position(const std::vector<std::string>& moves, const std::string& fen = "startpos");
    bool position(const Position& pos);
    
    // Search
    EngineStatus go(const std::vector<std::string>& commands);
    EngineStatus go_time(std::chrono::milliseconds time);
    EngineStatus go_depth(int depth);
    
    // Get results
    std::optional<std::string> getBestMove();
    std::optional<std::string> getPonderMove();
    
    // Engine information
    std::optional<std::string> getName() const { return name_; }
    std::optional<std::string> getAuthor() const { return author_; }
    
    // Statistics
    uint64_t getNodesSearched() const { return nodes_; }
    int getDepth() const { return depth_; }
    int getScore() const { return score_; }
    
    // Configuration
    const EngineConfig& getConfig() const { return config_; }
    
private:
    EngineConfig config_;
    std::unique_ptr<EngineProcess> process_;
    bool realtime_logging_;
    
    // Engine state
    bool started_{false};
    bool uci_ok_{false};
    
    // Engine information
    std::optional<std::string> name_;
    std::optional<std::string> author_;
    
    // Search results
    std::optional<std::string> best_move_;
    std::optional<std::string> ponder_move_;
    
    // Search statistics
    uint64_t nodes_{0};
    int depth_{0};
    int score_{0};
    
    // Internal methods
    EngineStatus writeEngine(const std::string& command);
    EngineStatus readUntil(const std::string& target, 
                          std::chrono::milliseconds timeout,
                          std::vector<std::string>& output);
    
    void parseUciOutput(const std::vector<std::string>& lines);
    void parseInfoLine(const std::string& line);
    void parseBestMoveLine(const std::string& line);
    
    // Helper methods
    void setupReadEngine();
    void loadConfig(const EngineConfig& config);
};

} // namespace fastmill
