// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.h - Logging system for Fastmill
// Based on fastchess logger but simplified for Mill tournaments

#pragma once

#include <string>
#include <fstream>
#include <iostream>
#include <chrono>
#include <mutex>
#include <atomic>

namespace fastmill {

class Logger {
public:
    enum class Level {
        TRACE = 0,
        DEBUG = 1,
        INFO = 2,
        WARN = 3,
        ERROR = 4,
        FATAL = 5
    };
    
    // Initialize logger
    static void initialize(const std::string& log_file = "", Level level = Level::INFO);
    static void shutdown();
    
    // Logging methods
    static void trace(const std::string& message);
    static void debug(const std::string& message);
    static void info(const std::string& message);
    static void warning(const std::string& message);
    static void error(const std::string& message);
    static void fatal(const std::string& message);
    
    // Generic print method with formatting (simplified)
    static void print(const std::string& message);
    
    // Template method for formatted output (simplified)
    template<typename... Args>
    static void print(const std::string& format, Args&&... /* args */) {
        // Simple implementation without full fmt support
        // TODO: Implement proper string formatting
        print(format); // For now, just print the format string
    }
    
    // Configuration
    static void setLevel(Level level) { level_ = level; }
    static Level getLevel() { return level_; }
    
    // Engine communication logging
    static void readFromEngine(const std::string& line, 
                              std::chrono::steady_clock::time_point time,
                              const std::string& engine_name,
                              bool is_error = false);
    
private:
    static void log(Level level, const std::string& message);
    static std::string getCurrentTimestamp();
    static std::string levelToString(Level level);
    
    static Level level_;
    static std::ofstream log_file_;
    static std::mutex log_mutex_;
    static std::atomic_bool should_log_;
    static bool initialized_;
};

} // namespace fastmill
