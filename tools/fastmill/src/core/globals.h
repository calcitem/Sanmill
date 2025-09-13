// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// globals.h - Global state management for Fastmill
// Based on fastchess globals but adapted for Mill game

#pragma once

#include <atomic>
#include <vector>
#include <memory>

namespace fastmill {

// Global atomic flags for tournament control
namespace atomic {
extern std::atomic_bool stop;
extern std::atomic_bool abnormal_termination;
} // namespace atomic

// Process information for cleanup
struct ProcessInformation {
    int identifier;  // PID on Unix, handle on Windows
    int fd_write;    // File descriptor for writing to process
};

// Global process list for cleanup
extern std::vector<ProcessInformation> process_list;

// Signal handling functions
void setCtrlCHandler();
void writeToOpenPipes();
void stopProcesses();

// Thread-safe process management
void addProcess(const ProcessInformation& process);
void removeProcess(int identifier);

} // namespace fastmill
