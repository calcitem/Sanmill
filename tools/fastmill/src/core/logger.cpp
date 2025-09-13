// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.cpp - Implementation of logging system

#include "logger.h"
#include <iomanip>
#include <sstream>

namespace fastmill {

// Static member definitions
Logger::Level Logger::level_ = Logger::Level::INFO;
std::ofstream Logger::log_file_;
std::mutex Logger::log_mutex_;
std::atomic_bool Logger::should_log_ = false;
bool Logger::initialized_ = false;

void Logger::initialize(const std::string& log_file, Level level) {
    std::lock_guard<std::mutex> lock(log_mutex_);
    
    if (initialized_) {
        shutdown();
    }
    
    level_ = level;
    
    if (!log_file.empty()) {
        log_file_.open(log_file, std::ios::out | std::ios::app);
        if (log_file_.is_open()) {
            should_log_ = true;
        } else {
            std::cerr << "Warning: Could not open log file: " << log_file << std::endl;
        }
    }
    
    initialized_ = true;
    info("Fastmill logger initialized");
}

void Logger::shutdown() {
    std::lock_guard<std::mutex> lock(log_mutex_);
    
    if (log_file_.is_open()) {
        info("Logger shutting down");
        log_file_.close();
    }
    
    should_log_ = false;
    initialized_ = false;
}

void Logger::trace(const std::string& message) {
    log(Level::TRACE, message);
}

void Logger::debug(const std::string& message) {
    log(Level::DEBUG, message);
}

void Logger::info(const std::string& message) {
    log(Level::INFO, message);
}

void Logger::warning(const std::string& message) {
    log(Level::WARN, message);
}

void Logger::error(const std::string& message) {
    log(Level::ERROR, message);
}

void Logger::fatal(const std::string& message) {
    log(Level::FATAL, message);
}

void Logger::print(const std::string& message) {
    std::cout << message << std::endl;
    
    // Also log to file if available
    if (should_log_) {
        log(Level::INFO, message);
    }
}

void Logger::readFromEngine(const std::string& line, 
                           std::chrono::steady_clock::time_point /* time */,
                           const std::string& engine_name,
                           bool is_error) {
    std::string prefix = is_error ? "[ERR]" : "[OUT]";
    std::string message = prefix + " " + engine_name + ": " + line;
    
    if (is_error) {
        error(message);
    } else {
        debug(message);
    }
}

void Logger::log(Level level, const std::string& message) {
    if (level < level_) {
        return; // Message level is below current log level
    }
    
    std::lock_guard<std::mutex> lock(log_mutex_);
    
    std::string timestamp = getCurrentTimestamp();
    std::string level_str = levelToString(level);
    std::string formatted_message = "[" + timestamp + "] [" + level_str + "] " + message;
    
    // Output to console based on level
    if (level >= Level::ERROR) {
        std::cerr << formatted_message << std::endl;
    } else {
        std::cout << formatted_message << std::endl;
    }
    
    // Write to log file if available
    if (should_log_ && log_file_.is_open()) {
        log_file_ << formatted_message << std::endl;
        log_file_.flush();
    }
}

std::string Logger::getCurrentTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;
    
    std::stringstream ss;
    ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    ss << '.' << std::setfill('0') << std::setw(3) << ms.count();
    
    return ss.str();
}

std::string Logger::levelToString(Level level) {
    switch (level) {
        case Level::TRACE:   return "TRACE";
        case Level::DEBUG:   return "DEBUG";
        case Level::INFO:    return "INFO ";
        case Level::WARN:    return "WARN ";
        case Level::ERROR:   return "ERROR";
        case Level::FATAL:   return "FATAL";
        default:             return "UNKN ";
    }
}

} // namespace fastmill
