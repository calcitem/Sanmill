// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_uci_engine.cpp - Implementation of UCI engine interface for Mill engines
// Based on fastchess UciEngine but adapted for Mill game

#include "mill_uci_engine.h"
#include "core/logger.h"

#include <sstream>
#include <algorithm>

// Minimal Position implementation for compilation
class Position {
public:
    Position() = default;
    // Add minimal methods needed for compilation
};

namespace fastmill {

MillUciEngine::MillUciEngine(const EngineConfig& config, bool realtime_logging) 
    : config_(config), realtime_logging_(realtime_logging) {
    
    loadConfig(config);
    
    // Create process for engine communication
    process_ = std::make_unique<EngineProcess>(config_.command, config_.args, config_.working_directory);
}

MillUciEngine::~MillUciEngine() {
    quit();
}

EngineStatus MillUciEngine::start() {
    if (started_) {
        return EngineStatus::OK;
    }
    
    Logger::info("Starting engine: " + config_.name);
    
    ProcessStatus status = process_->start();
    if (status != ProcessStatus::OK) {
        Logger::error("Failed to start engine process: " + config_.name);
        return EngineStatus::ERROR;
    }
    
    started_ = true;
    return EngineStatus::OK;
}

void MillUciEngine::quit() {
    if (started_ && process_) {
        writeEngine("quit");
        process_->terminate();
        started_ = false;
        uci_ok_ = false;
    }
}

bool MillUciEngine::isAlive() const {
    return started_ && process_ && process_->isAlive();
}

EngineStatus MillUciEngine::uci() {
    if (!isAlive()) {
        return EngineStatus::ERROR;
    }
    
    Logger::debug("Sending UCI command to: " + config_.name);
    
    EngineStatus status = writeEngine("uci");
    if (status != EngineStatus::OK) {
        return status;
    }
    
    // Read UCI response
    std::vector<std::string> output;
    status = readUntil("uciok", std::chrono::milliseconds(5000), output);
    
    if (status == EngineStatus::OK) {
        parseUciOutput(output);
        uci_ok_ = true;
        Logger::info("Engine " + config_.name + " initialized successfully");
    } else {
        Logger::error("Engine " + config_.name + " did not respond with uciok");
    }
    
    return status;
}

EngineStatus MillUciEngine::isready(std::chrono::milliseconds threshold) {
    if (!uci_ok_) {
        return EngineStatus::ERROR;
    }
    
    Logger::debug("Pinging engine: " + config_.name);
    
    EngineStatus status = writeEngine("isready");
    if (status != EngineStatus::OK) {
        return status;
    }
    
    std::vector<std::string> output;
    return readUntil("readyok", threshold, output);
}

EngineStatus MillUciEngine::ucinewgame() {
    if (!uci_ok_) {
        return EngineStatus::ERROR;
    }
    
    Logger::debug("Starting new game for engine: " + config_.name);
    
    EngineStatus status = writeEngine("ucinewgame");
    if (status != EngineStatus::OK) {
        return status;
    }
    
    // Wait for engine to be ready
    return isready();
}

bool MillUciEngine::position(const std::vector<std::string>& moves, const std::string& fen) {
    if (!uci_ok_) {
        return false;
    }
    
    std::string position_cmd = "position ";
    if (fen == "startpos") {
        position_cmd += "startpos";
    } else {
        position_cmd += "fen " + fen;
    }
    
    if (!moves.empty()) {
        position_cmd += " moves";
        for (const auto& move : moves) {
            position_cmd += " " + move;
        }
    }
    
    return writeEngine(position_cmd) == EngineStatus::OK;
}

bool MillUciEngine::position(const Position& pos) {
    // For now, use a simplified approach to avoid complex dependencies
    // Just use the startpos for basic functionality
    return position({}, "startpos");
}

EngineStatus MillUciEngine::go(const std::vector<std::string>& commands) {
    if (!uci_ok_) {
        return EngineStatus::ERROR;
    }
    
    std::string go_cmd = "go";
    for (const auto& cmd : commands) {
        go_cmd += " " + cmd;
    }
    
    // Clear previous results
    best_move_.reset();
    ponder_move_.reset();
    nodes_ = 0;
    depth_ = 0;
    score_ = 0;
    
    EngineStatus status = writeEngine(go_cmd);
    if (status != EngineStatus::OK) {
        return status;
    }
    
    // Read until bestmove
    std::vector<std::string> output;
    status = readUntil("bestmove", std::chrono::milliseconds(30000), output); // 30 second timeout
    
    if (status == EngineStatus::OK) {
        // Parse the output for info and bestmove
        for (const auto& line : output) {
            if (line.find("info ") == 0) {
                parseInfoLine(line);
            } else if (line.find("bestmove ") == 0) {
                parseBestMoveLine(line);
            }
        }
    }
    
    return status;
}

EngineStatus MillUciEngine::go_time(std::chrono::milliseconds time) {
    std::vector<std::string> commands = {"movetime", std::to_string(time.count())};
    return go(commands);
}

EngineStatus MillUciEngine::go_depth(int depth) {
    std::vector<std::string> commands = {"depth", std::to_string(depth)};
    return go(commands);
}

std::optional<std::string> MillUciEngine::getBestMove() {
    return best_move_;
}

std::optional<std::string> MillUciEngine::getPonderMove() {
    return ponder_move_;
}

// Private methods
EngineStatus MillUciEngine::writeEngine(const std::string& command) {
    if (!isAlive()) {
        return EngineStatus::ERROR;
    }
    
    Logger::debug("Sending to " + config_.name + ": " + command);
    
    ProcessStatus status = process_->writeInput(command);
    return (status == ProcessStatus::OK) ? EngineStatus::OK : EngineStatus::ERROR;
}

EngineStatus MillUciEngine::readUntil(const std::string& target, 
                                     std::chrono::milliseconds timeout,
                                     std::vector<std::string>& output) {
    if (!isAlive()) {
        return EngineStatus::ERROR;
    }
    
    auto start_time = std::chrono::steady_clock::now();
    
    while (std::chrono::steady_clock::now() - start_time < timeout) {
        std::vector<ProcessLine> lines;
        ProcessStatus status = process_->readOutput(lines, target, std::chrono::milliseconds(100));
        
        for (const auto& line : lines) {
            output.push_back(line.line);
            
            if (realtime_logging_) {
                Logger::readFromEngine(line.line, line.time, config_.name, line.is_error);
            }
            
            if (line.line.find(target) == 0) {
                return EngineStatus::OK;
            }
        }
        
        if (status == ProcessStatus::ERROR) {
            return EngineStatus::ERROR;
        }
    }
    
    Logger::warning("Timeout waiting for '" + target + "' from engine: " + config_.name);
    return EngineStatus::TIMEOUT;
}

void MillUciEngine::parseUciOutput(const std::vector<std::string>& lines) {
    for (const auto& line : lines) {
        if (line.find("id name ") == 0) {
            name_ = line.substr(8);
        } else if (line.find("id author ") == 0) {
            author_ = line.substr(10);
        }
    }
}

void MillUciEngine::parseInfoLine(const std::string& line) {
    std::istringstream iss(line);
    std::string token;
    
    while (iss >> token) {
        if (token == "nodes") {
            iss >> nodes_;
        } else if (token == "depth") {
            iss >> depth_;
        } else if (token == "score") {
            iss >> token; // "cp" or "mate"
            if (token == "cp") {
                iss >> score_;
            }
        }
    }
}

void MillUciEngine::parseBestMoveLine(const std::string& line) {
    std::istringstream iss(line);
    std::string token;
    
    iss >> token; // "bestmove"
    if (iss >> token) {
        best_move_ = token;
        
        // Check for ponder move
        if (iss >> token && token == "ponder") {
            if (iss >> token) {
                ponder_move_ = token;
            }
        }
    }
}

void MillUciEngine::setupReadEngine() {
    // Setup for reading engine output
    // Implementation would depend on process management details
}

void MillUciEngine::loadConfig(const EngineConfig& config) {
    config_ = config;
    
    // Load any additional configuration
    Logger::debug("Loaded configuration for engine: " + config_.name);
}

} // namespace fastmill
