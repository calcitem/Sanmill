// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// spsa_tuner.h - SPSA (Simultaneous Perturbation Stochastic Approximation)
// Parameter Tuning System

#ifndef SPSA_TUNER_H_INCLUDED
#define SPSA_TUNER_H_INCLUDED

#include "types.h"
#include "position.h"
#include <vector>
#include <string>
#include <random>
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>

namespace SPSA {

// Structure to hold a single tunable parameter
struct Parameter
{
    std::string name;         // Parameter name for identification
    double value;             // Current parameter value
    double min_value;         // Minimum allowed value
    double max_value;         // Maximum allowed value
    double perturbation_size; // Size of perturbation for this parameter
    bool is_integer; // Whether this parameter should be treated as integer

    Parameter(const std::string &n, double val, double min_val, double max_val,
              double pert_size, bool is_int = false)
        : name(n)
        , value(val)
        , min_value(min_val)
        , max_value(max_val)
        , perturbation_size(pert_size)
        , is_integer(is_int)
    { }

    // Clamp value to valid range
    void clamp()
    {
        value = std::max(min_value, std::min(max_value, value));
        if (is_integer) {
            value = std::round(value);
        }
    }
};

// Configuration for SPSA algorithm
struct SPSAConfig
{
    double a;                 // Learning rate parameter
    double c;                 // Perturbation size parameter
    double A;                 // Stability constant
    double alpha;             // Learning rate decay exponent (typically 0.602)
    double gamma;             // Perturbation decay exponent (typically 0.101)
    int max_iterations;       // Maximum number of SPSA iterations
    int games_per_evaluation; // Number of games to play for each evaluation
    int max_threads;          // Maximum number of threads for parallel games
    double convergence_threshold; // Threshold for convergence detection
    int convergence_window;       // Window size for convergence detection
    std::string log_file;         // Log file path
    std::string checkpoint_file;  // Checkpoint file path
    int checkpoint_frequency;     // Save checkpoint every N iterations

    SPSAConfig()
        : a(0.16)
        , c(0.05)
        , A(100)
        , alpha(0.602)
        , gamma(0.101)
        , max_iterations(1000)
        , games_per_evaluation(100)
        , max_threads(8)
        , convergence_threshold(0.001)
        , convergence_window(50)
        , log_file("spsa_tuning.log")
        , checkpoint_file("spsa_checkpoint.txt")
        , checkpoint_frequency(10)
    { }
};

// Game result statistics
struct GameResult
{
    int wins;
    int losses;
    int draws;

    GameResult()
        : wins(0)
        , losses(0)
        , draws(0)
    { }

    int total_games() const { return wins + losses + draws; }
    double win_rate() const
    {
        int total = total_games();
        return total > 0 ? static_cast<double>(wins) / total : 0.0;
    }
    double score() const
    {
        int total = total_games();
        return total > 0 ? (wins + 0.5 * draws) / total : 0.5;
    }
};

// Forward declarations
class GameEngine;
class TestFramework;

// Main SPSA tuning class
class SPSATuner
{
public:
    explicit SPSATuner(const SPSAConfig &config);
    ~SPSATuner();

    // Add a parameter to be tuned
    void add_parameter(const Parameter &param);

    // Load parameters from file
    bool load_parameters(const std::string &filename);

    // Save parameters to file
    bool save_parameters(const std::string &filename) const;

    // Load checkpoint from file
    bool load_checkpoint(const std::string &filename);

    // Save checkpoint to file
    bool save_checkpoint(const std::string &filename) const;

    // Start the tuning process
    void start_tuning();

    // Stop the tuning process
    void stop_tuning();

    // Get current parameters
    const std::vector<Parameter> &get_parameters() const { return parameters_; }

    // Get current iteration
    int get_current_iteration() const { return current_iteration_; }

    // Check if tuning is running
    bool is_running() const { return running_; }

    // Get best score achieved so far
    double get_best_score() const { return best_score_; }

private:
    // SPSA algorithm implementation
    void spsa_iteration();

    // Generate perturbation vector
    std::vector<double> generate_perturbation();

    // Apply perturbation to parameters
    std::vector<Parameter> apply_perturbation(const std::vector<double> &delta,
                                              double sign);

    // Evaluate parameter set by playing games
    double evaluate_parameters(const std::vector<Parameter> &params);

    // Update parameters based on gradient estimate
    void update_parameters(const std::vector<double> &delta, double gradient);

    // Calculate learning rate for current iteration
    double calculate_learning_rate(int iteration) const;

    // Calculate perturbation size for current iteration
    double calculate_perturbation_size(int iteration) const;

    // Check for convergence
    bool check_convergence();

    // Log iteration results
    void log_iteration(int iteration, double score_plus, double score_minus,
                       double gradient, const std::vector<double> &delta);

    // Initialize default evaluation parameters
    void initialize_default_parameters();

    SPSAConfig config_;
    std::vector<Parameter> parameters_;
    std::vector<Parameter> best_parameters_;
    std::vector<double> score_history_;

    std::unique_ptr<TestFramework> test_framework_;

    int current_iteration_;
    double best_score_;
    bool running_;

    std::mt19937 rng_;
    std::mutex mutex_;
    std::condition_variable cv_;

    // Thread management
    std::vector<std::thread> worker_threads_;
    std::atomic<bool> should_stop_;
};

// Test framework for automated game playing
class TestFramework
{
public:
    explicit TestFramework(int max_threads);
    ~TestFramework();

    // Play games between two parameter sets
    GameResult play_match(const std::vector<Parameter> &params1,
                          const std::vector<Parameter> &params2, int num_games);

    // Play games with one parameter set against baseline
    GameResult evaluate_against_baseline(const std::vector<Parameter> &params,
                                         int num_games);

    // Set baseline parameters
    void set_baseline_parameters(const std::vector<Parameter> &baseline);

private:
    // Single game between two engines
    Color play_single_game(const std::vector<Parameter> &white_params,
                           const std::vector<Parameter> &black_params,
                           bool verbose = false);

    // Worker thread function for parallel game playing
    void game_worker(const std::vector<Parameter> &params1,
                     const std::vector<Parameter> &params2, int games_to_play,
                     GameResult &result, std::mutex &result_mutex);

    int max_threads_;
    std::vector<Parameter> baseline_parameters_;
    std::mt19937 rng_;
    std::mutex rng_mutex_;
};

// Game engine wrapper for parameter testing
class GameEngine
{
public:
    explicit GameEngine(const std::vector<Parameter> &params);

    // Make a move for the current position
    Move get_best_move(Position &pos, int time_limit_ms = 1000);

    // Update engine parameters
    void update_parameters(const std::vector<Parameter> &params);

    // Get current parameters
    const std::vector<Parameter> &get_parameters() const { return parameters_; }

private:
    // Apply parameters to engine
    void apply_parameters();

    std::vector<Parameter> parameters_;

    // Engine-specific parameter mappings
    struct EngineParameters
    {
        double exploration_parameter;
        double bias_factor;
        int alpha_beta_depth;
        Value piece_value;
        Value piece_inhand_value;
        Value piece_onboard_value;
        Value piece_needremove_value;
        double mobility_weight;

        EngineParameters()
            : exploration_parameter(0.5)
            , bias_factor(0.05)
            , alpha_beta_depth(6)
            , piece_value(VALUE_EACH_PIECE)
            , piece_inhand_value(VALUE_EACH_PIECE_INHAND)
            , piece_onboard_value(VALUE_EACH_PIECE_ONBOARD)
            , piece_needremove_value(VALUE_EACH_PIECE_NEEDREMOVE)
            , mobility_weight(1.0)
        { }
    } engine_params_;
};

// Utility functions
namespace Utils {
// Parse parameter file
std::vector<Parameter> parse_parameter_file(const std::string &filename);

// Write parameter file
bool write_parameter_file(const std::string &filename,
                          const std::vector<Parameter> &params);

// Generate random starting position
Position generate_random_position(std::mt19937 &rng);

// Convert parameter vector to string for logging
std::string parameters_to_string(const std::vector<Parameter> &params);

// Calculate Elo difference from win rate
double win_rate_to_elo(double win_rate);

// Get current timestamp string
std::string get_timestamp();
} // namespace Utils

} // namespace SPSA

#endif // SPSA_TUNER_H_INCLUDED
