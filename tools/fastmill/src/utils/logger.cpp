// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.cpp - Implementation of logging utility

#include "logger.h"
#include <iomanip>
#include <sstream>

namespace fastmill {

// Static member definitions
LogLevel Logger::log_level_ = LogLevel::INFO;
std::ofstream Logger::log_file_;
std::mutex Logger::log_mutex_;
bool Logger::initialized_ = false;

void Logger::initialize(const std::string &log_file, LogLevel level)
{
    std::lock_guard<std::mutex> lock(log_mutex_);

    if (initialized_) {
        shutdown();
    }

    log_level_ = level;

    if (!log_file.empty()) {
        log_file_.open(log_file, std::ios::out | std::ios::app);
        if (!log_file_.is_open()) {
            std::cerr << "Warning: Could not open log file: " << log_file
                      << std::endl;
        }
    }

    initialized_ = true;
    info("Logger initialized");
}

void Logger::shutdown()
{
    std::lock_guard<std::mutex> lock(log_mutex_);

    if (log_file_.is_open()) {
        info("Logger shutting down");
        log_file_.close();
    }

    initialized_ = false;
}

void Logger::debug(const std::string &message)
{
    log(LogLevel::DEBUG, message);
}

void Logger::info(const std::string &message)
{
    log(LogLevel::INFO, message);
}

void Logger::warning(const std::string &message)
{
    log(LogLevel::WARNING, message);
}

void Logger::error(const std::string &message)
{
    log(LogLevel::ERROR, message);
}

void Logger::log(LogLevel level, const std::string &message)
{
    if (level < log_level_) {
        return; // Message level is below current log level
    }

    std::lock_guard<std::mutex> lock(log_mutex_);

    std::string timestamp = getCurrentTimestamp();
    std::string level_str = levelToString(level);
    std::string formatted_message = "[" + timestamp + "] [" + level_str + "] " +
                                    message;

    // Always output to console for errors and warnings
    if (level >= LogLevel::WARNING) {
        std::cerr << formatted_message << std::endl;
    } else {
        std::cout << formatted_message << std::endl;
    }

    // Write to log file if available
    if (log_file_.is_open()) {
        log_file_ << formatted_message << std::endl;
        log_file_.flush();
    }
}

std::string Logger::getCurrentTimestamp()
{
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                  now.time_since_epoch()) %
              1000;

    std::stringstream ss;
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    ss << '.' << std::setfill('0') << std::setw(3) << ms.count();

    return ss.str();
}

std::string Logger::levelToString(LogLevel level)
{
    switch (level) {
    case LogLevel::DEBUG:
        return "DEBUG";
    case LogLevel::INFO:
        return "INFO ";
    case LogLevel::WARNING:
        return "WARN ";
    case LogLevel::ERROR:
        return "ERROR";
    default:
        return "UNKN ";
    }
}

} // namespace fastmill
