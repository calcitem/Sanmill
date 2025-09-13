// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_engine_wrapper.h - Wrapper for Mill UCI engines

#pragma once

#include <string>
#include <vector>
#include <chrono>
#include <memory>

#ifdef _WIN32
#include <windows.h>
#include <process.h>
#else
#include <unistd.h>
#include <sys/types.h>
#endif

// Reuse existing Sanmill headers
#include "types.h"
#include "position.h"
#include "uci.h"
#include "engine_controller.h"
#include "rule.h"

// Tournament types
#include "tournament/tournament_types.h"

namespace fastmill {

// Engine process management (simplified from fastchess)
class EngineProcess
{
public:
    explicit EngineProcess(const EngineConfig &config);
    ~EngineProcess();

    bool start();
    void stop();
    bool isAlive() const { return alive_; }

    bool sendCommand(const std::string &command);
    std::string readLine(
        std::chrono::milliseconds timeout = std::chrono::milliseconds(1000));

private:
    EngineConfig config_;
    bool alive_ {false};

#ifdef _WIN32
    HANDLE process_handle_ {INVALID_HANDLE_VALUE};
    HANDLE stdin_write_ {INVALID_HANDLE_VALUE};
    HANDLE stdout_read_ {INVALID_HANDLE_VALUE};
#else
    pid_t pid_ {-1};
    int stdin_fd_ {-1};
    int stdout_fd_ {-1};
#endif
};

// Mill engine wrapper that uses existing Sanmill UCI infrastructure
class MillEngineWrapper
{
public:
    explicit MillEngineWrapper(const EngineConfig &config);
    ~MillEngineWrapper();

    // Engine lifecycle
    bool initialize();
    void shutdown();
    bool isReady() const { return ready_; }

    // Game management using existing Position class
    bool newGame(const Rule &rule_variant);
    bool setPosition(const Position &pos);
    Move getBestMove(const Position &pos, std::chrono::milliseconds think_time);

    // Engine information
    const std::string &getName() const { return config_.name; }
    const std::string &getAuthor() const { return author_; }

    // Statistics
    uint64_t getNodesSearched() const { return nodes_searched_; }
    int getDepth() const { return search_depth_; }

private:
    EngineConfig config_;
    std::unique_ptr<EngineProcess> process_;
    bool ready_ {false};

    // Engine info
    std::string author_;
    std::string version_;

    // Search statistics
    uint64_t nodes_searched_ {0};
    int search_depth_ {0};

    // Internal methods
    bool waitForReady(
        std::chrono::milliseconds timeout = std::chrono::milliseconds(5000));
    bool sendUciCommand(const std::string &command);
    std::string waitForResponse(
        const std::string &expected_prefix,
        std::chrono::milliseconds timeout = std::chrono::milliseconds(1000));

    // Parse UCI responses
    void parseIdResponse(const std::string &line);
    void parseInfoResponse(const std::string &line);
    Move parseBestMoveResponse(const std::string &line);
};

// Engine manager for tournament
class EngineManager
{
public:
    explicit EngineManager(const std::vector<EngineConfig> &engine_configs);
    ~EngineManager();

    bool initializeAll();
    void shutdownAll();

    MillEngineWrapper *getEngine(size_t index);
    size_t getEngineCount() const { return engines_.size(); }

    // Engine health monitoring
    bool areAllEnginesReady() const;
    void restartEngine(size_t index);

private:
    std::vector<EngineConfig> configs_;
    std::vector<std::unique_ptr<MillEngineWrapper>> engines_;
};

} // namespace fastmill
