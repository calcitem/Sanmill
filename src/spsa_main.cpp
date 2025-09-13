// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// spsa_main.cpp - Main application for SPSA parameter tuning

#include "spsa_tuner.h"
#include "option.h"
#include <iostream>
#include <fstream>
#include <iomanip>
#include <string>
#include <sstream>
#include <signal.h>

using namespace SPSA;

// Global tuner instance for signal handling
std::unique_ptr<SPSATuner> g_tuner;

// Signal handler for graceful shutdown
void signal_handler(int signal)
{
    std::cout << "\nReceived signal " << signal << ". Stopping tuning..."
              << std::endl;
    if (g_tuner) {
        g_tuner->stop_tuning();
    }
}

// Print usage information
void print_usage(const std::string &program_name)
{
    std::cout << "SPSA Parameter Tuning System for Sanmill" << std::endl;
    std::cout << "Usage: " << program_name << " [options]" << std::endl;
    std::cout << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  -h, --help              Show this help message"
              << std::endl;
    std::cout << "  -c, --config FILE       Load configuration from file"
              << std::endl;
    std::cout << "  -p, --params FILE       Load initial parameters from file"
              << std::endl;
    std::cout << "  -o, --output FILE       Output best parameters to file"
              << std::endl;
    std::cout << "  -l, --log FILE          Log file path (default: "
                 "spsa_tuning.log)"
              << std::endl;
    std::cout << "  -i, --iterations N      Maximum number of iterations "
                 "(default: 1000)"
              << std::endl;
    std::cout << "  -g, --games N           Games per evaluation (default: 100)"
              << std::endl;
    std::cout << "  -t, --threads N         Maximum number of threads "
                 "(default: 8)"
              << std::endl;
    std::cout << "  -a, --learning-rate R   Learning rate parameter a "
                 "(default: 0.16)"
              << std::endl;
    std::cout << "  -s, --perturbation R    Perturbation parameter c (default: "
                 "0.05)"
              << std::endl;
    std::cout << "  -r, --resume FILE       Resume from checkpoint file"
              << std::endl;
    std::cout << "  -v, --verbose           Enable verbose debug output"
              << std::endl;
    std::cout << "  -q, --quiet             Disable debug output (default)"
              << std::endl;
    std::cout << "  --alpha R               Learning rate decay exponent "
                 "(default: 0.602)"
              << std::endl;
    std::cout << "  --gamma R               Perturbation decay exponent "
                 "(default: 0.101)"
              << std::endl;
    std::cout << "  --convergence R         Convergence threshold (default: "
                 "0.001)"
              << std::endl;
    std::cout << "  --window N              Convergence window size (default: "
                 "50)"
              << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  " << program_name << " --iterations 500 --games 200"
              << std::endl;
    std::cout << "  " << program_name
              << " --params initial.txt --output final.txt" << std::endl;
    std::cout << "  " << program_name << " --resume checkpoint.txt"
              << std::endl;
}

// Load configuration from file
SPSAConfig load_config_file(const std::string &filename)
{
    SPSAConfig config;
    std::ifstream file(filename);

    if (!file.is_open()) {
        std::cerr << "Warning: Cannot open config file " << filename
                  << ". Using default configuration." << std::endl;
        return config;
    }

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }

        std::istringstream iss(line);
        std::string key, value;

        if (std::getline(iss, key, '=') && std::getline(iss, value)) {
            // Trim whitespace
            key.erase(0, key.find_first_not_of(" \t"));
            key.erase(key.find_last_not_of(" \t") + 1);
            value.erase(0, value.find_first_not_of(" \t"));
            value.erase(value.find_last_not_of(" \t") + 1);

            if (key == "learning_rate" || key == "a") {
                config.a = std::stod(value);
            } else if (key == "perturbation" || key == "c") {
                config.c = std::stod(value);
            } else if (key == "stability" || key == "A") {
                config.A = std::stod(value);
            } else if (key == "alpha") {
                config.alpha = std::stod(value);
            } else if (key == "gamma") {
                config.gamma = std::stod(value);
            } else if (key == "max_iterations") {
                config.max_iterations = std::stoi(value);
            } else if (key == "games_per_evaluation") {
                config.games_per_evaluation = std::stoi(value);
            } else if (key == "max_threads") {
                config.max_threads = std::stoi(value);
            } else if (key == "convergence_threshold") {
                config.convergence_threshold = std::stod(value);
            } else if (key == "convergence_window") {
                config.convergence_window = std::stoi(value);
            } else if (key == "log_file") {
                config.log_file = value;
            } else if (key == "checkpoint_file") {
                config.checkpoint_file = value;
            } else if (key == "checkpoint_frequency") {
                config.checkpoint_frequency = std::stoi(value);
            }
        }
    }

    return config;
}

// Save configuration to file
void save_config_file(const std::string &filename, const SPSAConfig &config)
{
    std::ofstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Error: Cannot save config file " << filename << std::endl;
        return;
    }

    file << "# SPSA Configuration File" << std::endl;
    file << "# Generated automatically" << std::endl;
    file << std::endl;
    file << "learning_rate=" << config.a << std::endl;
    file << "perturbation=" << config.c << std::endl;
    file << "stability=" << config.A << std::endl;
    file << "alpha=" << config.alpha << std::endl;
    file << "gamma=" << config.gamma << std::endl;
    file << "max_iterations=" << config.max_iterations << std::endl;
    file << "games_per_evaluation=" << config.games_per_evaluation << std::endl;
    file << "max_threads=" << config.max_threads << std::endl;
    file << "convergence_threshold=" << config.convergence_threshold
         << std::endl;
    file << "convergence_window=" << config.convergence_window << std::endl;
    file << "log_file=" << config.log_file << std::endl;
    file << "checkpoint_file=" << config.checkpoint_file << std::endl;
    file << "checkpoint_frequency=" << config.checkpoint_frequency << std::endl;
}

// Print current configuration
void print_config(const SPSAConfig &config)
{
    std::cout << "SPSA Configuration:" << std::endl;
    std::cout << "  Learning rate (a): " << config.a << std::endl;
    std::cout << "  Perturbation (c): " << config.c << std::endl;
    std::cout << "  Stability (A): " << config.A << std::endl;
    std::cout << "  Alpha: " << config.alpha << std::endl;
    std::cout << "  Gamma: " << config.gamma << std::endl;
    std::cout << "  Max iterations: " << config.max_iterations << std::endl;
    std::cout << "  Games per evaluation: " << config.games_per_evaluation
              << std::endl;
    std::cout << "  Max threads: " << config.max_threads << std::endl;
    std::cout << "  Convergence threshold: " << config.convergence_threshold
              << std::endl;
    std::cout << "  Convergence window: " << config.convergence_window
              << std::endl;
    std::cout << "  Log file: " << config.log_file << std::endl;
    std::cout << "  Checkpoint file: " << config.checkpoint_file << std::endl;
    std::cout << std::endl;
}

// Interactive mode for parameter adjustment
void interactive_mode(SPSATuner &tuner)
{
    std::cout << "\n=== Interactive Parameter Tuning Mode ===" << std::endl;
    std::cout << "Commands:" << std::endl;
    std::cout << "  start     - Start tuning process" << std::endl;
    std::cout << "  stop      - Stop tuning process" << std::endl;
    std::cout << "  status    - Show current status" << std::endl;
    std::cout << "  params    - Show current parameters" << std::endl;
    std::cout << "  save FILE - Save parameters to file" << std::endl;
    std::cout << "  load FILE - Load parameters from file" << std::endl;
    std::cout << "  quit      - Exit program" << std::endl;
    std::cout << std::endl;

    std::string command;
    while (std::cout << "spsa> " && std::getline(std::cin, command)) {
        std::istringstream iss(command);
        std::string cmd;
        iss >> cmd;

        if (cmd == "start") {
            if (tuner.is_running()) {
                std::cout << "Tuning is already running." << std::endl;
            } else {
                std::thread tuning_thread(&SPSATuner::start_tuning, &tuner);
                tuning_thread.detach();
                std::cout << "Started tuning in background." << std::endl;
            }
        } else if (cmd == "stop") {
            if (tuner.is_running()) {
                tuner.stop_tuning();
                std::cout << "Stopped tuning." << std::endl;
            } else {
                std::cout << "Tuning is not running." << std::endl;
            }
        } else if (cmd == "status") {
            std::cout << "Status: "
                      << (tuner.is_running() ? "Running" : "Stopped")
                      << std::endl;
            std::cout << "Current iteration: " << tuner.get_current_iteration()
                      << std::endl;
            std::cout << "Best score: " << std::fixed << std::setprecision(4)
                      << tuner.get_best_score() << std::endl;
        } else if (cmd == "params") {
            const auto &params = tuner.get_parameters();
            std::cout << "Current parameters (" << params.size()
                      << "):" << std::endl;
            for (const auto &param : params) {
                std::cout << "  " << param.name << ": " << std::fixed
                          << std::setprecision(4) << param.value << " ["
                          << param.min_value << ", " << param.max_value << "]"
                          << std::endl;
            }
        } else if (cmd == "save") {
            std::string filename;
            if (iss >> filename) {
                if (tuner.save_parameters(filename)) {
                    std::cout << "Parameters saved to " << filename
                              << std::endl;
                } else {
                    std::cout << "Error saving parameters." << std::endl;
                }
            } else {
                std::cout << "Usage: save FILENAME" << std::endl;
            }
        } else if (cmd == "load") {
            std::string filename;
            if (iss >> filename) {
                if (tuner.load_parameters(filename)) {
                    std::cout << "Parameters loaded from " << filename
                              << std::endl;
                } else {
                    std::cout << "Error loading parameters." << std::endl;
                }
            } else {
                std::cout << "Usage: load FILENAME" << std::endl;
            }
        } else if (cmd == "quit" || cmd == "exit") {
            if (tuner.is_running()) {
                std::cout << "Stopping tuning before exit..." << std::endl;
                tuner.stop_tuning();
            }
            break;
        } else if (cmd == "help" || cmd == "?") {
            std::cout << "Available commands: start, stop, status, params, "
                         "save, load, quit"
                      << std::endl;
        } else if (!cmd.empty()) {
            std::cout << "Unknown command: " << cmd
                      << ". Type 'help' for available commands." << std::endl;
        }
    }
}

// Main function
int main(int argc, char *argv[])
{
    std::cout << "Sanmill SPSA Parameter Tuning System" << std::endl;
    std::cout << "=====================================" << std::endl;

    // Install signal handlers for graceful shutdown
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Default configuration
    SPSAConfig config;
    std::string params_file;
    std::string output_file;
    std::string config_file;
    std::string resume_file;
    bool interactive_mode_flag = false;
    bool verbose_mode = false;
    bool quiet_mode = false;

    // Parse command line arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg == "-h" || arg == "--help") {
            print_usage(argv[0]);
            return 0;
        } else if (arg == "-c" || arg == "--config") {
            if (++i < argc) {
                config_file = argv[i];
            } else {
                std::cerr << "Error: " << arg << " requires a filename"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-p" || arg == "--params") {
            if (++i < argc) {
                params_file = argv[i];
            } else {
                std::cerr << "Error: " << arg << " requires a filename"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-o" || arg == "--output") {
            if (++i < argc) {
                output_file = argv[i];
            } else {
                std::cerr << "Error: " << arg << " requires a filename"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-l" || arg == "--log") {
            if (++i < argc) {
                config.log_file = argv[i];
            } else {
                std::cerr << "Error: " << arg << " requires a filename"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-i" || arg == "--iterations") {
            if (++i < argc) {
                config.max_iterations = std::stoi(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-g" || arg == "--games") {
            if (++i < argc) {
                config.games_per_evaluation = std::stoi(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-t" || arg == "--threads") {
            if (++i < argc) {
                config.max_threads = std::stoi(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-a" || arg == "--learning-rate") {
            if (++i < argc) {
                config.a = std::stod(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-s" || arg == "--perturbation") {
            if (++i < argc) {
                config.c = std::stod(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-r" || arg == "--resume") {
            if (++i < argc) {
                resume_file = argv[i];
            } else {
                std::cerr << "Error: " << arg << " requires a filename"
                          << std::endl;
                return 1;
            }
        } else if (arg == "--alpha") {
            if (++i < argc) {
                config.alpha = std::stod(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "--gamma") {
            if (++i < argc) {
                config.gamma = std::stod(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "--convergence") {
            if (++i < argc) {
                config.convergence_threshold = std::stod(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "--window") {
            if (++i < argc) {
                config.convergence_window = std::stoi(argv[i]);
            } else {
                std::cerr << "Error: " << arg << " requires a number"
                          << std::endl;
                return 1;
            }
        } else if (arg == "-v" || arg == "--verbose") {
            verbose_mode = true;
        } else if (arg == "-q" || arg == "--quiet") {
            quiet_mode = true;
        } else if (arg == "--interactive") {
            interactive_mode_flag = true;
        } else {
            std::cerr << "Error: Unknown option " << arg << std::endl;
            print_usage(argv[0]);
            return 1;
        }
    }

    // Set developer mode based on verbose/quiet flags
    if (verbose_mode && quiet_mode) {
        std::cerr << "Error: Cannot specify both --verbose and --quiet"
                  << std::endl;
        return 1;
    }

    if (verbose_mode) {
        gameOptions.setDeveloperMode(true);
        std::cout << "Verbose mode enabled - debug output will be shown"
                  << std::endl;
    } else if (quiet_mode) {
        gameOptions.setDeveloperMode(false);
        std::cout << "Quiet mode enabled - debug output suppressed"
                  << std::endl;
    } else {
        // Default: quiet mode for SPSA tuning to reduce noise
        gameOptions.setDeveloperMode(false);
    }

    // Load configuration from file if specified
    if (!config_file.empty()) {
        config = load_config_file(config_file);
    }

    // Print configuration
    print_config(config);

    // Create tuner
    g_tuner = std::make_unique<SPSATuner>(config);

    // Load initial parameters if specified
    if (!params_file.empty()) {
        if (!g_tuner->load_parameters(params_file)) {
            std::cerr << "Error: Failed to load parameters from " << params_file
                      << std::endl;
            return 1;
        }
    }

    // Resume from checkpoint if specified
    if (!resume_file.empty()) {
        if (!g_tuner->load_checkpoint(resume_file)) {
            std::cerr << "Warning: Failed to load checkpoint from "
                      << resume_file << std::endl;
        }
    }

    // Start tuning
    if (interactive_mode_flag) {
        interactive_mode(*g_tuner);
    } else {
        g_tuner->start_tuning();

        // Save results if output file specified
        if (!output_file.empty()) {
            if (g_tuner->save_parameters(output_file)) {
                std::cout << "Best parameters saved to " << output_file
                          << std::endl;
            } else {
                std::cerr << "Error: Failed to save parameters to "
                          << output_file << std::endl;
            }
        }
    }

    std::cout << "SPSA tuning completed successfully." << std::endl;
    return 0;
}
