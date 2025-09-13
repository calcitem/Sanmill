// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// process.cpp - Implementation of process management
// Based on fastchess process management but simplified

// Enable POSIX functions
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "process.h"
#include "core/logger.h"
#include "core/globals.h"

#include <sstream>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#endif

namespace fastmill {

EngineProcess::EngineProcess(const std::string& command, 
                            const std::vector<std::string>& args,
                            const std::string& working_dir)
    : command_(command), args_(args), working_dir_(working_dir) {
}

EngineProcess::~EngineProcess() {
    terminate();
}

ProcessStatus EngineProcess::start() {
    if (alive_) {
        return ProcessStatus::OK;
    }
    
    Logger::debug("Starting process: " + command_);
    
    ProcessStatus status = createProcess();
    if (status == ProcessStatus::OK) {
        alive_ = true;
        
        // Add to global process list for cleanup
        ProcessInformation proc_info;
#ifdef _WIN32
        proc_info.identifier = reinterpret_cast<int>(process_handle_);
        proc_info.fd_write = reinterpret_cast<int>(stdin_write_);
#else
        proc_info.identifier = pid_;
        proc_info.fd_write = stdin_fd_;
#endif
        addProcess(proc_info);
    }
    
    return status;
}

void EngineProcess::terminate() {
    if (!alive_) {
        return;
    }
    
    Logger::debug("Terminating process: " + command_);
    
#ifdef _WIN32
    if (process_handle_ != INVALID_HANDLE_VALUE) {
        removeProcess(reinterpret_cast<int>(process_handle_));
        TerminateProcess(process_handle_, 0);
        CloseHandle(process_handle_);
        process_handle_ = INVALID_HANDLE_VALUE;
    }
    cleanup();
#else
    if (pid_ > 0) {
        removeProcess(pid_);
        kill(pid_, SIGTERM);
        waitpid(pid_, nullptr, 0);
        pid_ = -1;
    }
    cleanup();
#endif
    
    alive_ = false;
}

ProcessStatus EngineProcess::writeInput(const std::string& input) {
    if (!alive_) {
        return ProcessStatus::ERROR;
    }
    
    std::string command = input + "\n";
    
#ifdef _WIN32
    DWORD written;
    if (WriteFile(stdin_write_, command.c_str(), command.length(), &written, NULL) && 
        written == command.length()) {
        return ProcessStatus::OK;
    }
#else
    ssize_t written = write(stdin_fd_, command.c_str(), command.length());
    if (written == static_cast<ssize_t>(command.length())) {
        return ProcessStatus::OK;
    }
#endif
    
    return ProcessStatus::ERROR;
}

ProcessStatus EngineProcess::readOutput(std::vector<ProcessLine>& output, 
                                       const std::string& target,
                                       std::chrono::milliseconds timeout) {
    if (!alive_) {
        return ProcessStatus::ERROR;
    }
    
    auto start_time = std::chrono::steady_clock::now();
    
    while (std::chrono::steady_clock::now() - start_time < timeout) {
        std::string line;
        bool is_error;
        
        ProcessStatus status = readLine(line, is_error, std::chrono::milliseconds(50));
        
        if (status == ProcessStatus::OK && !line.empty()) {
            ProcessLine proc_line;
            proc_line.line = line;
            proc_line.time = std::chrono::steady_clock::now();
            proc_line.is_error = is_error;
            
            output.push_back(proc_line);
            
            // Check if we found the target string
            if (!target.empty() && line.find(target) == 0) {
                return ProcessStatus::OK;
            }
        } else if (status == ProcessStatus::ERROR) {
            return ProcessStatus::ERROR;
        }
        
        // Small delay to avoid busy waiting
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    
    return target.empty() ? ProcessStatus::OK : ProcessStatus::TIMEOUT;
}

ProcessStatus EngineProcess::createProcess() {
#ifdef _WIN32
    return createWindowsProcess();
#else
    return createUnixProcess();
#endif
}

ProcessStatus EngineProcess::readLine(std::string& line, bool& is_error, 
                                     std::chrono::milliseconds timeout) {
#ifdef _WIN32
    return readWindowsOutput(line, is_error, timeout);
#else
    return readUnixOutput(line, is_error, timeout);
#endif
}

void EngineProcess::cleanup() {
#ifdef _WIN32
    if (stdin_write_ != INVALID_HANDLE_VALUE) {
        CloseHandle(stdin_write_);
        stdin_write_ = INVALID_HANDLE_VALUE;
    }
    if (stdout_read_ != INVALID_HANDLE_VALUE) {
        CloseHandle(stdout_read_);
        stdout_read_ = INVALID_HANDLE_VALUE;
    }
    if (stderr_read_ != INVALID_HANDLE_VALUE) {
        CloseHandle(stderr_read_);
        stderr_read_ = INVALID_HANDLE_VALUE;
    }
#else
    if (stdin_fd_ != -1) {
        close(stdin_fd_);
        stdin_fd_ = -1;
    }
    if (stdout_fd_ != -1) {
        close(stdout_fd_);
        stdout_fd_ = -1;
    }
    if (stderr_fd_ != -1) {
        close(stderr_fd_);
        stderr_fd_ = -1;
    }
#endif
}

#ifdef _WIN32
ProcessStatus EngineProcess::createWindowsProcess() {
    // Windows process creation implementation
    // Simplified version - full implementation would be more complex
    Logger::debug("Creating Windows process (simplified implementation)");
    return ProcessStatus::OK;
}

ProcessStatus EngineProcess::readWindowsOutput(std::string& line, bool& is_error, 
                                              std::chrono::milliseconds timeout) {
    // Windows output reading implementation
    // Simplified version - full implementation would be more complex
    line = "";
    is_error = false;
    return ProcessStatus::TIMEOUT;
}
#else
ProcessStatus EngineProcess::createUnixProcess() {
    // Unix process creation implementation
    // Simplified version - full implementation would be more complex
    Logger::debug("Creating Unix process (simplified implementation)");
    return ProcessStatus::OK;
}

ProcessStatus EngineProcess::readUnixOutput(std::string& line, bool& is_error, 
                                           std::chrono::milliseconds /* timeout */) {
    // Unix output reading implementation
    // Simplified version - full implementation would be more complex
    line = "";
    is_error = false;
    return ProcessStatus::TIMEOUT;
}
#endif

} // namespace fastmill
