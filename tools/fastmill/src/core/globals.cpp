// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// globals.cpp - Implementation of global state management

// Enable POSIX functions
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "globals.h"
#include "logger.h"

#include <cassert>
#include <mutex>
#include <algorithm>

#ifdef _WIN32
#include <windows.h>
#include <signal.h>
#else
#include <signal.h>
#include <unistd.h>
#include <cstdlib>
#include <sys/types.h>
#include <sys/wait.h>
#endif

namespace fastmill {

// Global atomic flags
namespace atomic {
std::atomic_bool stop = false;
std::atomic_bool abnormal_termination = false;
} // namespace atomic

// Global process list
std::vector<ProcessInformation> process_list;
std::mutex process_list_mutex;

#ifdef _WIN32
BOOL WINAPI ctrlHandler(DWORD dwCtrlType) {
    switch (dwCtrlType) {
        case CTRL_C_EVENT:
        case CTRL_BREAK_EVENT:
        case CTRL_CLOSE_EVENT:
            atomic::stop = true;
            atomic::abnormal_termination = true;
            writeToOpenPipes();
            return TRUE;
        default:
            return FALSE;
    }
}
#else
void signalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        atomic::stop = true;
        atomic::abnormal_termination = true;
        writeToOpenPipes();
    }
}
#endif

void setCtrlCHandler() {
#ifdef _WIN32
    SetConsoleCtrlHandler(ctrlHandler, TRUE);
#else
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
#endif
}

void writeToOpenPipes() {
    const char nullbyte = '\0';
    
    std::lock_guard<std::mutex> lock(process_list_mutex);
    
    for (const auto& process : process_list) {
        Logger::debug("Writing to process with identifier: " + std::to_string(process.identifier));
        
#ifdef _WIN32
        DWORD bytes_written;
        WriteFile(reinterpret_cast<HANDLE>(process.fd_write), &nullbyte, 1, &bytes_written, nullptr);
#else
        ssize_t bytes_written = write(process.fd_write, &nullbyte, 1);
        (void)bytes_written; // Suppress unused variable warning
#endif
    }
}

void stopProcesses() {
    std::lock_guard<std::mutex> lock(process_list_mutex);
    
    for (const auto& process : process_list) {
        Logger::debug("Cleaning up process with identifier: " + std::to_string(process.identifier));
        
#ifdef _WIN32
        HANDLE handle = reinterpret_cast<HANDLE>(process.identifier);
        TerminateProcess(handle, 0);
        CloseHandle(handle);
        CloseHandle(reinterpret_cast<HANDLE>(process.fd_write));
#else
        kill(process.identifier, SIGTERM);
        close(process.fd_write);
#endif
    }
    
    process_list.clear();
}

void addProcess(const ProcessInformation& process) {
    std::lock_guard<std::mutex> lock(process_list_mutex);
    process_list.push_back(process);
}

void removeProcess(int identifier) {
    std::lock_guard<std::mutex> lock(process_list_mutex);
    
    auto it = std::find_if(process_list.begin(), process_list.end(),
                          [identifier](const ProcessInformation& p) {
                              return p.identifier == identifier;
                          });
    
    if (it != process_list.end()) {
        process_list.erase(it);
    }
}

} // namespace fastmill
