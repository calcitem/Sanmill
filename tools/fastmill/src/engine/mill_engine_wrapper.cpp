// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_engine_wrapper.cpp - Implementation of Mill UCI engine wrapper

// Enable POSIX functions on Unix systems
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "mill_engine_wrapper.h"
#include "utils/logger.h"

#include <sstream>
#include <thread>
#include <algorithm>

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

// EngineProcess implementation
EngineProcess::EngineProcess(const EngineConfig &config)
    : config_(config)
{ }

EngineProcess::~EngineProcess()
{
    stop();
}

bool EngineProcess::start()
{
    if (alive_)
        return true;

#ifdef _WIN32
    // Windows implementation using CreateProcess
    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    HANDLE stdin_read, stdout_write;

    // Create pipes
    if (!CreatePipe(&stdin_read, &stdin_write_, &sa, 0) ||
        !CreatePipe(&stdout_read_, &stdout_write, &sa, 0)) {
        Logger::error("Failed to create pipes for engine: " + config_.name);
        return false;
    }

    // Make sure the write handle to the child process's pipe for STDIN is not
    // inherited
    SetHandleInformation(stdin_write_, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(stdout_read_, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.hStdError = stdout_write;
    si.hStdOutput = stdout_write;
    si.hStdInput = stdin_read;
    si.dwFlags |= STARTF_USESTDHANDLES;

    // Build command line
    std::string cmdline = config_.command;
    for (const auto &arg : config_.args) {
        cmdline += " " + arg;
    }

    // Create the process
    if (!CreateProcess(NULL, const_cast<char *>(cmdline.c_str()), NULL, NULL,
                       TRUE, CREATE_NO_WINDOW, NULL,
                       config_.working_directory.empty() ?
                           NULL :
                           config_.working_directory.c_str(),
                       &si, &pi)) {
        Logger::error("Failed to start engine: " + config_.name);
        CloseHandle(stdin_read);
        CloseHandle(stdout_write);
        return false;
    }

    process_handle_ = pi.hProcess;
    CloseHandle(pi.hThread);
    CloseHandle(stdin_read);
    CloseHandle(stdout_write);

    alive_ = true;
    return true;

#else
    // Unix implementation using fork/exec
    int stdin_pipe[2], stdout_pipe[2];

    if (pipe(stdin_pipe) == -1 || pipe(stdout_pipe) == -1) {
        Logger::error("Failed to create pipes for engine: " + config_.name);
        return false;
    }

    pid_ = fork();
    if (pid_ == -1) {
        Logger::error("Failed to fork process for engine: " + config_.name);
        return false;
    }

    if (pid_ == 0) {
        // Child process
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stdout_pipe[1], STDERR_FILENO);

        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);

        // Change working directory if specified
        if (!config_.working_directory.empty()) {
            chdir(config_.working_directory.c_str());
        }

        // Build argument list
        std::vector<char *> args;
        args.push_back(const_cast<char *>(config_.command.c_str()));
        for (const auto &arg : config_.args) {
            args.push_back(const_cast<char *>(arg.c_str()));
        }
        args.push_back(nullptr);

        execvp(config_.command.c_str(), args.data());
        exit(1); // If exec fails
    } else {
        // Parent process
        close(stdin_pipe[0]);
        close(stdout_pipe[1]);

        stdin_fd_ = stdin_pipe[1];
        stdout_fd_ = stdout_pipe[0];

        // Set non-blocking mode for stdout
        int flags = fcntl(stdout_fd_, F_GETFL, 0);
        fcntl(stdout_fd_, F_SETFL, flags | O_NONBLOCK);

        alive_ = true;
        return true;
    }
#endif
}

void EngineProcess::stop()
{
    if (!alive_)
        return;

#ifdef _WIN32
    if (process_handle_ != INVALID_HANDLE_VALUE) {
        TerminateProcess(process_handle_, 0);
        CloseHandle(process_handle_);
        process_handle_ = INVALID_HANDLE_VALUE;
    }
    if (stdin_write_ != INVALID_HANDLE_VALUE) {
        CloseHandle(stdin_write_);
        stdin_write_ = INVALID_HANDLE_VALUE;
    }
    if (stdout_read_ != INVALID_HANDLE_VALUE) {
        CloseHandle(stdout_read_);
        stdout_read_ = INVALID_HANDLE_VALUE;
    }
#else
    if (pid_ > 0) {
        kill(pid_, SIGTERM);
        waitpid(pid_, nullptr, 0);
        pid_ = -1;
    }
    if (stdin_fd_ != -1) {
        close(stdin_fd_);
        stdin_fd_ = -1;
    }
    if (stdout_fd_ != -1) {
        close(stdout_fd_);
        stdout_fd_ = -1;
    }
#endif

    alive_ = false;
}

bool EngineProcess::sendCommand(const std::string &command)
{
    if (!alive_)
        return false;

    std::string cmd = command + "\n";

#ifdef _WIN32
    DWORD written;
    return WriteFile(stdin_write_, cmd.c_str(), cmd.length(), &written, NULL) &&
           written == cmd.length();
#else
    ssize_t written = write(stdin_fd_, cmd.c_str(), cmd.length());
    return written == static_cast<ssize_t>(cmd.length());
#endif
}

std::string EngineProcess::readLine(std::chrono::milliseconds timeout)
{
    if (!alive_)
        return "";

    std::string line;
    auto start_time = std::chrono::steady_clock::now();

    while (std::chrono::steady_clock::now() - start_time < timeout) {
        char ch;

#ifdef _WIN32
        DWORD read;
        if (ReadFile(stdout_read_, &ch, 1, &read, NULL) && read == 1) {
            if (ch == '\n') {
                // Remove trailing \r if present
                if (!line.empty() && line.back() == '\r') {
                    line.pop_back();
                }
                return line;
            } else if (ch != '\r') {
                line += ch;
            }
        }
#else
        ssize_t result = read(stdout_fd_, &ch, 1);
        if (result == 1) {
            if (ch == '\n') {
                return line;
            } else if (ch != '\r') {
                line += ch;
            }
        } else if (result == -1 && errno == EAGAIN) {
            // No data available, continue waiting
        } else {
            break; // Error or EOF
        }
#endif

        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    return line; // May be empty or partial line
}

// MillEngineWrapper implementation
MillEngineWrapper::MillEngineWrapper(const EngineConfig &config)
    : config_(config)
    , process_(std::make_unique<EngineProcess>(config))
{ }

MillEngineWrapper::~MillEngineWrapper()
{
    shutdown();
}

bool MillEngineWrapper::initialize()
{
    Logger::info("Initializing engine: " + config_.name);

    if (!process_->start()) {
        Logger::error("Failed to start engine process: " + config_.name);
        return false;
    }

    // Wait for engine to start
    std::this_thread::sleep_for(config_.startup_time);

    // Send UCI command
    if (!sendUciCommand("uci")) {
        Logger::error("Failed to send UCI command to engine: " + config_.name);
        return false;
    }

    // Read engine information
    auto start_time = std::chrono::steady_clock::now();
    auto timeout = std::chrono::milliseconds(5000);

    while (std::chrono::steady_clock::now() - start_time < timeout) {
        std::string line = process_->readLine(std::chrono::milliseconds(100));
        if (line.empty())
            continue;

        Logger::debug("Engine " + config_.name + ": " + line);

        if (line.find("id ") == 0) {
            parseIdResponse(line);
        } else if (line == "uciok") {
            ready_ = true;
            Logger::info("Engine " + config_.name +
                         " initialized successfully");
            return true;
        }
    }

    Logger::error("Engine " + config_.name + " did not respond with uciok");
    return false;
}

void MillEngineWrapper::shutdown()
{
    if (process_) {
        sendUciCommand("quit");
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        process_->stop();
    }
    ready_ = false;
}

bool MillEngineWrapper::newGame(const Rule & /* rule_variant */)
{
    if (!ready_)
        return false;

    // Send ucinewgame command
    if (!sendUciCommand("ucinewgame")) {
        return false;
    }

    // Set rule variant options if needed
    // This would depend on how the engine accepts rule variants
    // For now, assume the engine uses the default rule
    // TODO: Implement rule variant configuration

    return waitForReady();
}

bool MillEngineWrapper::setPosition(const Position &pos)
{
    if (!ready_)
        return false;

    // Convert position to FEN or position string
    // This would use the existing Position class methods
    std::string position_cmd = "position fen " + pos.fen();

    return sendUciCommand(position_cmd);
}

Move MillEngineWrapper::getBestMove(const Position &pos,
                                    std::chrono::milliseconds think_time)
{
    if (!ready_)
        return MOVE_NONE;

    // Set position
    if (!setPosition(pos)) {
        return MOVE_NONE;
    }

    // Send go command with time limit
    std::string go_cmd = "go movetime " + std::to_string(think_time.count());
    if (!sendUciCommand(go_cmd)) {
        return MOVE_NONE;
    }

    // Wait for bestmove response
    auto start_time = std::chrono::steady_clock::now();
    auto timeout = think_time + std::chrono::milliseconds(1000); // Extra time
                                                                 // for overhead

    while (std::chrono::steady_clock::now() - start_time < timeout) {
        std::string line = process_->readLine(std::chrono::milliseconds(100));
        if (line.empty())
            continue;

        if (line.find("info ") == 0) {
            parseInfoResponse(line);
        } else if (line.find("bestmove ") == 0) {
            return parseBestMoveResponse(line);
        }
    }

    Logger::warning("Engine " + config_.name +
                    " did not respond with bestmove in time");
    return MOVE_NONE;
}

// Private methods
bool MillEngineWrapper::waitForReady(std::chrono::milliseconds timeout)
{
    if (!sendUciCommand("isready")) {
        return false;
    }

    return waitForResponse("readyok", timeout) == "readyok";
}

bool MillEngineWrapper::sendUciCommand(const std::string &command)
{
    Logger::debug("Sending to " + config_.name + ": " + command);
    return process_->sendCommand(command);
}

std::string
MillEngineWrapper::waitForResponse(const std::string &expected_prefix,
                                   std::chrono::milliseconds timeout)
{
    auto start_time = std::chrono::steady_clock::now();

    while (std::chrono::steady_clock::now() - start_time < timeout) {
        std::string line = process_->readLine(std::chrono::milliseconds(100));
        if (line.empty())
            continue;

        Logger::debug("Received from " + config_.name + ": " + line);

        if (line.find(expected_prefix) == 0) {
            return line;
        }
    }

    return "";
}

void MillEngineWrapper::parseIdResponse(const std::string &line)
{
    if (line.find("id name ") == 0) {
        author_ = line.substr(8); // Skip "id name "
    } else if (line.find("id author ") == 0) {
        author_ = line.substr(10); // Skip "id author "
    }
}

void MillEngineWrapper::parseInfoResponse(const std::string &line)
{
    std::istringstream iss(line);
    std::string token;

    while (iss >> token) {
        if (token == "nodes") {
            iss >> nodes_searched_;
        } else if (token == "depth") {
            iss >> search_depth_;
        }
    }
}

Move MillEngineWrapper::parseBestMoveResponse(const std::string &line)
{
    std::istringstream iss(line);
    std::string token, move_str;

    iss >> token; // "bestmove"
    if (iss >> move_str) {
        // Convert move string to Move using existing Sanmill functions
        // Note: UCI::to_move requires a Position* parameter, so we return
        // MOVE_NONE for now In a real implementation, we would need to maintain
        // the current position
        return MOVE_NONE; // Placeholder - would need position context
    }

    return MOVE_NONE;
}

// EngineManager implementation
EngineManager::EngineManager(const std::vector<EngineConfig> &engine_configs)
    : configs_(engine_configs)
{
    engines_.reserve(configs_.size());
    for (const auto &config : configs_) {
        engines_.emplace_back(std::make_unique<MillEngineWrapper>(config));
    }
}

EngineManager::~EngineManager()
{
    shutdownAll();
}

bool EngineManager::initializeAll()
{
    Logger::info("Initializing " + std::to_string(engines_.size()) +
                 " engines");

    bool all_success = true;
    for (auto &engine : engines_) {
        if (!engine->initialize()) {
            all_success = false;
            Logger::error("Failed to initialize engine: " + engine->getName());
        }
    }

    return all_success;
}

void EngineManager::shutdownAll()
{
    Logger::info("Shutting down all engines");
    for (auto &engine : engines_) {
        engine->shutdown();
    }
}

MillEngineWrapper *EngineManager::getEngine(size_t index)
{
    if (index >= engines_.size())
        return nullptr;
    return engines_[index].get();
}

bool EngineManager::areAllEnginesReady() const
{
    return std::all_of(engines_.begin(), engines_.end(),
                       [](const auto &engine) { return engine->isReady(); });
}

void EngineManager::restartEngine(size_t index)
{
    if (index >= engines_.size())
        return;

    Logger::warning("Restarting engine: " + engines_[index]->getName());
    engines_[index]->shutdown();
    engines_[index] = std::make_unique<MillEngineWrapper>(configs_[index]);
    engines_[index]->initialize();
}

} // namespace fastmill
