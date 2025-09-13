// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.h - Simple logging utility for Fastmill

#pragma once

#include <string>
#include <fstream>
#include <iostream>
#include <chrono>
#include <mutex>

namespace fastmill {

enum class LogLevel { DEBUG = 0, INFO = 1, WARNING = 2, ERROR = 3 };

class Logger
{
public:
    static void initialize(const std::string &log_file = "",
                           LogLevel level = LogLevel::INFO);
    static void shutdown();

    static void debug(const std::string &message);
    static void info(const std::string &message);
    static void warning(const std::string &message);
    static void error(const std::string &message);

    static void setLevel(LogLevel level) { log_level_ = level; }
    static LogLevel getLevel() { return log_level_; }

private:
    static void log(LogLevel level, const std::string &message);
    static std::string getCurrentTimestamp();
    static std::string levelToString(LogLevel level);

    static LogLevel log_level_;
    static std::ofstream log_file_;
    static std::mutex log_mutex_;
    static bool initialized_;
};

} // namespace fastmill
