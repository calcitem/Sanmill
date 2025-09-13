// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// spsa_example.cpp - Example usage of SPSA parameter tuning system

#include "spsa_tuner.h"
#include <iostream>
#include <iomanip>
#include <thread>

using namespace SPSA;

int main()
{
    std::cout << "SPSA Parameter Tuning Example for Sanmill" << std::endl;
    std::cout << "=========================================" << std::endl;

    // Create configuration
    SPSAConfig config;
    config.max_iterations = 50;       // Short example run
    config.games_per_evaluation = 20; // Fewer games for faster testing
    config.max_threads = 4;           // Moderate thread count
    config.log_file = "example_tuning.log";

    std::cout << "Creating SPSA tuner with example configuration..."
              << std::endl;

    // Create tuner
    SPSATuner tuner(config);

    // Add some custom parameters for demonstration
    std::cout << "Adding custom parameters..." << std::endl;
    tuner.add_parameter(
        Parameter("example_mobility_weight", 1.2, 0.5, 2.0, 0.1));
    tuner.add_parameter(Parameter("example_piece_bonus", 3, 1, 10, 1.0, true));

    // Show current parameters
    const auto &params = tuner.get_parameters();
    std::cout << "\nParameters to be tuned (" << params.size()
              << "):" << std::endl;
    for (const auto &param : params) {
        std::cout << "  " << param.name << ": " << param.value << " ["
                  << param.min_value << ", " << param.max_value << "]"
                  << std::endl;
    }

    std::cout << "\nStarting tuning process..." << std::endl;
    std::cout << "This will run " << config.max_iterations
              << " iterations with " << config.games_per_evaluation
              << " games each." << std::endl;
    std::cout << "Press Ctrl+C to stop early if needed." << std::endl;

    // Start tuning in a separate thread
    std::thread tuning_thread(&SPSATuner::start_tuning, &tuner);

    // Monitor progress
    while (tuner.is_running()) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
        std::cout << "Progress: Iteration " << tuner.get_current_iteration() + 1
                  << "/" << config.max_iterations
                  << ", Best score: " << std::fixed << std::setprecision(4)
                  << tuner.get_best_score() << std::endl;
    }

    // Wait for completion
    tuning_thread.join();

    // Show final results
    std::cout << "\nTuning completed!" << std::endl;
    std::cout << "Final best score: " << std::fixed << std::setprecision(4)
              << tuner.get_best_score() << std::endl;

    // Save results
    if (tuner.save_parameters("example_best_params.txt")) {
        std::cout << "Best parameters saved to example_best_params.txt"
                  << std::endl;
    }

    // Show final parameters
    const auto &final_params = tuner.get_parameters();
    std::cout << "\nFinal optimized parameters:" << std::endl;
    for (const auto &param : final_params) {
        std::cout << "  " << param.name << ": " << std::fixed
                  << std::setprecision(4) << param.value << std::endl;
    }

    std::cout << "\nExample completed successfully!" << std::endl;
    return 0;
}
