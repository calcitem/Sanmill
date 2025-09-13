// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// process.h - Process management for engine communication
// Based on fastchess process management but simplified for Mill engines

#pragma once

#include <string>
#include <vector>
#include <chrono>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/types.h>
#endif

namespace fastmill {

enum class ProcessStatus {
    OK,
    TIMEOUT,
    ERROR,
    CRASHED
};

struct ProcessLine {
    std::string line;
    std::chrono::steady_clock::time_point time;
    bool is_error;
};

class EngineProcess {
public:
    explicit EngineProcess(const std::string& command, 
                          const std::vector<std::string>& args = {},
                          const std::string& working_dir = "");
    ~EngineProcess();
    
    // Process lifecycle
    ProcessStatus start();
    void terminate();
    bool isAlive() const { return alive_; }
    
    // Communication
    ProcessStatus writeInput(const std::string& input);
    ProcessStatus readOutput(std::vector<ProcessLine>& output, 
                            const std::string& target = "",
                            std::chrono::milliseconds timeout = std::chrono::milliseconds(1000));
    
    // Configuration
    void setRealtimeLogging(bool enabled) { realtime_logging_ = enabled; }
    
private:
    std::string command_;
    std::vector<std::string> args_;
    std::string working_dir_;
    bool realtime_logging_{false};
    bool alive_{false};
    
#ifdef _WIN32
    HANDLE process_handle_{INVALID_HANDLE_VALUE};
    HANDLE thread_handle_{INVALID_HANDLE_VALUE};
    HANDLE stdin_write_{INVALID_HANDLE_VALUE};
    HANDLE stdout_read_{INVALID_HANDLE_VALUE};
    HANDLE stderr_read_{INVALID_HANDLE_VALUE};
#else
    pid_t pid_{-1};
    int stdin_fd_{-1};
    int stdout_fd_{-1};
    int stderr_fd_{-1};
#endif
    
    // Internal methods
    ProcessStatus createProcess();
    ProcessStatus readLine(std::string& line, bool& is_error, 
                          std::chrono::milliseconds timeout);
    void cleanup();
    
    // Platform-specific helpers
#ifdef _WIN32
    ProcessStatus createWindowsProcess();
    ProcessStatus readWindowsOutput(std::string& line, bool& is_error, 
                                   std::chrono::milliseconds timeout);
#else
    ProcessStatus createUnixProcess();
    ProcessStatus readUnixOutput(std::string& line, bool& is_error, 
                                std::chrono::milliseconds timeout);
#endif
};

} // namespace fastmill
