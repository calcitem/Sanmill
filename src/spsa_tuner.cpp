// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// spsa_tuner.cpp - SPSA Parameter Tuning System Implementation

#include "spsa_tuner.h"
#include "position.h"
#include "search_engine.h"
#include "evaluate.h"
#include "option.h"
#include "movepick.h"
#include "movegen.h"
#include "rule.h"
#include "tunable_parameters_traditional.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <algorithm>
#include <cmath>

namespace SPSA {

// SPSATuner Implementation
SPSATuner::SPSATuner(const SPSAConfig &config)
    : config_(config)
    , current_iteration_(0)
    , best_score_(0.0)
    , running_(false)
    , rng_(std::chrono::steady_clock::now().time_since_epoch().count())
    , should_stop_(false)
{
    test_framework_ = std::make_unique<TestFramework>(config_.max_threads);
    initialize_default_parameters();
}

SPSATuner::~SPSATuner()
{
    stop_tuning();
}

void SPSATuner::add_parameter(const Parameter &param)
{
    std::lock_guard<std::mutex> lock(mutex_);
    parameters_.push_back(param);
    best_parameters_ = parameters_;
}

bool SPSATuner::load_parameters(const std::string &filename)
{
    parameters_ = Utils::parse_parameter_file(filename);
    if (parameters_.empty()) {
        std::cerr << "Error loading parameters from " << filename << std::endl;
        return false;
    }

    best_parameters_ = parameters_;
    std::cout << "Loaded " << parameters_.size() << " parameters from "
              << filename << std::endl;
    return true;
}

bool SPSATuner::save_parameters(const std::string &filename) const
{
    std::lock_guard<std::mutex> lock(const_cast<std::mutex &>(mutex_));
    return Utils::write_parameter_file(filename, best_parameters_);
}

bool SPSATuner::load_checkpoint(const std::string &filename)
{
    std::ifstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    if (!std::getline(file, line)) {
        return false;
    }

    std::istringstream iss(line);
    if (!(iss >> current_iteration_ >> best_score_)) {
        return false;
    }

    // Load score history
    score_history_.clear();
    while (std::getline(file, line) && !line.empty()) {
        double score;
        std::istringstream score_iss(line);
        if (score_iss >> score) {
            score_history_.push_back(score);
        }
    }

    std::cout << "Loaded checkpoint: iteration " << current_iteration_
              << ", best score " << best_score_ << std::endl;
    return true;
}

bool SPSATuner::save_checkpoint(const std::string &filename) const
{
    std::ofstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    file << current_iteration_ << " " << best_score_ << std::endl;

    // Save score history
    for (double score : score_history_) {
        file << score << std::endl;
    }

    return true;
}

void SPSATuner::start_tuning()
{
    if (running_) {
        return;
    }

    // CRITICAL: Check that we're not using MCTS algorithm
    if (gameOptions.getMctsAlgorithm()) {
        std::cerr << "ERROR: SPSA tuning is NOT compatible with MCTS algorithm!"
                  << std::endl;
        std::cerr << "Please switch to Alpha-Beta, PVS, or MTD(f) algorithm "
                     "before running SPSA."
                  << std::endl;
        std::cerr << "Current algorithm setting: MCTS (algorithm = 3)"
                  << std::endl;
        std::cerr << "Recommended algorithms for SPSA tuning:" << std::endl;
        std::cerr << "  - Alpha-Beta (algorithm = 0)" << std::endl;
        std::cerr << "  - PVS (algorithm = 1)" << std::endl;
        std::cerr << "  - MTD(f) (algorithm = 2)" << std::endl;
        return;
    }

    running_ = true;
    should_stop_ = false;

    // Display current algorithm
    std::string algorithm_name;
    if (gameOptions.getAlphaBetaAlgorithm()) {
        algorithm_name = "Alpha-Beta";
    } else if (gameOptions.getPvsAlgorithm()) {
        algorithm_name = "PVS (Principal Variation Search)";
    } else if (gameOptions.getMtdfAlgorithm()) {
        algorithm_name = "MTD(f)";
    } else {
        algorithm_name = "Unknown traditional algorithm";
    }

    std::cout << "Starting SPSA parameter tuning for " << algorithm_name
              << " algorithm..." << std::endl;
    std::cout << "Parameters: " << parameters_.size() << std::endl;
    std::cout << "Max iterations: " << config_.max_iterations << std::endl;
    std::cout << "Games per evaluation: " << config_.games_per_evaluation
              << std::endl;

    // Set baseline parameters for testing
    test_framework_->set_baseline_parameters(parameters_);

    // Main tuning loop
    for (int iter = current_iteration_;
         iter < config_.max_iterations && !should_stop_; ++iter) {
        current_iteration_ = iter;

        std::cout << "\n=== Iteration " << iter + 1 << " ===" << std::endl;

        spsa_iteration();

        // Save checkpoint periodically
        if ((iter + 1) % config_.checkpoint_frequency == 0) {
            save_checkpoint(config_.checkpoint_file);
            save_parameters("best_parameters.txt");
        }

        // Check for convergence
        if (check_convergence()) {
            std::cout << "Convergence detected. Stopping tuning." << std::endl;
            break;
        }
    }

    running_ = false;

    std::cout << "\nTuning completed!" << std::endl;
    std::cout << "Best score achieved: " << best_score_ << std::endl;
    std::cout << "Best parameters saved to best_parameters.txt" << std::endl;

    // Save final results
    save_parameters("final_parameters.txt");
    save_checkpoint("final_checkpoint.txt");
}

void SPSATuner::stop_tuning()
{
    should_stop_ = true;
    running_ = false;

    // Wait for worker threads to finish
    for (auto &thread : worker_threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    worker_threads_.clear();
}

void SPSATuner::spsa_iteration()
{
    // Generate perturbation vector
    std::vector<double> delta = generate_perturbation();

    // Create perturbed parameter sets
    std::vector<Parameter> params_plus = apply_perturbation(delta, +1.0);
    std::vector<Parameter> params_minus = apply_perturbation(delta, -1.0);

    // Evaluate both parameter sets
    std::cout << "Evaluating positive perturbation..." << std::endl;
    double score_plus = evaluate_parameters(params_plus);

    std::cout << "Evaluating negative perturbation..." << std::endl;
    double score_minus = evaluate_parameters(params_minus);

    // Calculate gradient estimate
    double gradient = (score_plus - score_minus) /
                      (2.0 * calculate_perturbation_size(current_iteration_));

    std::cout << "Score +: " << std::fixed << std::setprecision(4) << score_plus
              << std::endl;
    std::cout << "Score -: " << std::fixed << std::setprecision(4)
              << score_minus << std::endl;
    std::cout << "Gradient: " << std::fixed << std::setprecision(6) << gradient
              << std::endl;

    // Update parameters
    update_parameters(delta, gradient);

    // Update best parameters if improved
    double current_score = std::max(score_plus, score_minus);
    if (current_score > best_score_) {
        best_score_ = current_score;
        if (score_plus > score_minus) {
            best_parameters_ = params_plus;
        } else {
            best_parameters_ = params_minus;
        }
        std::cout << "New best score: " << best_score_ << std::endl;
    }

    // Add to score history
    score_history_.push_back(current_score);

    // Log iteration
    log_iteration(current_iteration_, score_plus, score_minus, gradient, delta);
}

std::vector<double> SPSATuner::generate_perturbation()
{
    std::vector<double> delta(parameters_.size());
    std::bernoulli_distribution dist(0.5);

    for (size_t i = 0; i < parameters_.size(); ++i) {
        delta[i] = dist(rng_) ? +1.0 : -1.0;
    }

    return delta;
}

std::vector<Parameter>
SPSATuner::apply_perturbation(const std::vector<double> &delta, double sign)
{
    std::vector<Parameter> perturbed_params = parameters_;
    double c_k = calculate_perturbation_size(current_iteration_);

    for (size_t i = 0; i < parameters_.size(); ++i) {
        double perturbation = sign * c_k * delta[i] *
                              parameters_[i].perturbation_size;
        perturbed_params[i].value += perturbation;
        perturbed_params[i].clamp();
    }

    return perturbed_params;
}

double SPSATuner::evaluate_parameters(const std::vector<Parameter> &params)
{
    GameResult result = test_framework_->evaluate_against_baseline(
        params, config_.games_per_evaluation);

    std::cout << "Games: " << result.total_games() << " (W:" << result.wins
              << " L:" << result.losses << " D:" << result.draws << ")"
              << std::endl;
    std::cout << "Win rate: " << std::fixed << std::setprecision(3)
              << result.win_rate() * 100 << "%" << std::endl;
    std::cout << "Score: " << std::fixed << std::setprecision(4)
              << result.score() << std::endl;

    return result.score();
}

void SPSATuner::update_parameters(const std::vector<double> &delta,
                                  double gradient)
{
    double a_k = calculate_learning_rate(current_iteration_);

    std::cout << "Learning rate: " << std::fixed << std::setprecision(6) << a_k
              << std::endl;

    for (size_t i = 0; i < parameters_.size(); ++i) {
        double update = a_k * gradient / delta[i];
        parameters_[i].value += update;
        parameters_[i].clamp();
    }

    std::cout << "Updated parameters:" << std::endl;
    for (size_t i = 0; i < parameters_.size(); ++i) {
        std::cout << "  " << parameters_[i].name << ": " << std::fixed
                  << std::setprecision(4) << parameters_[i].value << std::endl;
    }
}

double SPSATuner::calculate_learning_rate(int iteration) const
{
    return config_.a / std::pow(config_.A + iteration + 1, config_.alpha);
}

double SPSATuner::calculate_perturbation_size(int iteration) const
{
    return config_.c / std::pow(iteration + 1, config_.gamma);
}

bool SPSATuner::check_convergence()
{
    if (score_history_.size() <
        static_cast<size_t>(config_.convergence_window)) {
        return false;
    }

    // Check if the standard deviation of recent scores is below threshold
    auto recent_start = score_history_.end() - config_.convergence_window;
    double mean = 0.0;
    for (auto it = recent_start; it != score_history_.end(); ++it) {
        mean += *it;
    }
    mean /= config_.convergence_window;

    double variance = 0.0;
    for (auto it = recent_start; it != score_history_.end(); ++it) {
        variance += (*it - mean) * (*it - mean);
    }
    variance /= config_.convergence_window;

    double std_dev = std::sqrt(variance);

    std::cout << "Convergence check - std dev: " << std_dev
              << ", threshold: " << config_.convergence_threshold << std::endl;

    return std_dev < config_.convergence_threshold;
}

void SPSATuner::log_iteration(int iteration, double score_plus,
                              double score_minus, double gradient,
                              const std::vector<double> & /* delta */)
{
    std::ofstream log_file(config_.log_file, std::ios::app);
    if (log_file.is_open()) {
        log_file << Utils::get_timestamp() << " ";
        log_file << "Iter:" << iteration << " ";
        log_file << "Score+:" << std::fixed << std::setprecision(4)
                 << score_plus << " ";
        log_file << "Score-:" << std::fixed << std::setprecision(4)
                 << score_minus << " ";
        log_file << "Grad:" << std::fixed << std::setprecision(6) << gradient
                 << " ";
        log_file << "Best:" << std::fixed << std::setprecision(4) << best_score_
                 << " ";
        log_file << "Params:" << Utils::parameters_to_string(parameters_)
                 << std::endl;
    }
}

void SPSATuner::initialize_default_parameters()
{
    // IMPORTANT: This SPSA system is designed ONLY for traditional search
    // algorithms (Alpha-Beta, PVS, MTD(f)). It should NOT be used with MCTS!

    // Search algorithm parameters
    add_parameter(Parameter("max_search_depth", 8, 4, 16, 1.0, true));
    add_parameter(Parameter("quiescence_depth", 16, 8, 32, 2.0, true));
    add_parameter(Parameter("null_move_reduction", 3, 1, 6, 1.0, true));
    add_parameter(Parameter("late_move_reduction", 2, 1, 4, 1.0, true));
    add_parameter(Parameter("futility_margin", 100, 50, 300, 10.0, true));
    add_parameter(Parameter("razor_margin", 50, 20, 150, 5.0, true));

    // Basic evaluation parameters
    add_parameter(Parameter("piece_value", 5, 1, 20, 1.0, true));
    add_parameter(Parameter("piece_inhand_value", 5, 1, 20, 1.0, true));
    add_parameter(Parameter("piece_onboard_value", 5, 1, 20, 1.0, true));
    add_parameter(Parameter("piece_needremove_value", 5, 1, 20, 1.0, true));

    // Positional evaluation weights
    add_parameter(Parameter("mobility_weight", 1.0, 0.0, 3.0, 0.1));
    add_parameter(Parameter("center_control_weight", 0.8, 0.0, 2.0, 0.1));
    add_parameter(Parameter("mill_potential_weight", 1.2, 0.0, 3.0, 0.1));
    add_parameter(Parameter("blocking_weight", 0.9, 0.0, 2.0, 0.1));

    // Endgame and tempo parameters
    add_parameter(Parameter("endgame_piece_threshold", 6, 3, 10, 1.0, true));
    add_parameter(Parameter("endgame_mobility_bonus", 1.5, 0.5, 3.0, 0.1));
    add_parameter(Parameter("tempo_bonus", 0.1, 0.0, 0.5, 0.02));

    // Mill evaluation parameters
    add_parameter(Parameter("mill_value", 15, 5, 30, 2.0, true));
    add_parameter(Parameter("potential_mill_value", 3, 1, 10, 1.0, true));
    add_parameter(Parameter("broken_mill_penalty", 8, 2, 20, 1.0, true));
}

// TestFramework Implementation
TestFramework::TestFramework(int max_threads)
    : max_threads_(max_threads)
    , rng_(std::chrono::steady_clock::now().time_since_epoch().count())
{ }

TestFramework::~TestFramework() = default;

GameResult TestFramework::play_match(const std::vector<Parameter> &params1,
                                     const std::vector<Parameter> &params2,
                                     int num_games)
{
    GameResult total_result;
    std::mutex result_mutex;

    int games_per_thread = std::max(1, num_games / max_threads_);
    int remaining_games = num_games;

    std::vector<std::thread> threads;

    while (remaining_games > 0) {
        int games_this_thread = std::min(games_per_thread, remaining_games);

        threads.emplace_back(&TestFramework::game_worker, this,
                             std::cref(params1), std::cref(params2),
                             games_this_thread, std::ref(total_result),
                             std::ref(result_mutex));

        remaining_games -= games_this_thread;
    }

    // Wait for all threads to complete
    for (auto &thread : threads) {
        thread.join();
    }

    return total_result;
}

GameResult
TestFramework::evaluate_against_baseline(const std::vector<Parameter> &params,
                                         int num_games)
{
    return play_match(params, baseline_parameters_, num_games);
}

void TestFramework::set_baseline_parameters(
    const std::vector<Parameter> &baseline)
{
    baseline_parameters_ = baseline;
}

Color TestFramework::play_single_game(
    const std::vector<Parameter> &white_params,
    const std::vector<Parameter> &black_params, bool verbose)
{
    // Create game engines with specified parameters
    GameEngine white_engine(white_params);
    GameEngine black_engine(black_params);

    // Initialize position
    Position pos;
    pos.reset();

    int move_count = 0;
    const int max_moves = 200; // Prevent infinite games

    while (pos.get_phase() != Phase::gameOver && move_count < max_moves) {
        GameEngine &current_engine = (pos.side_to_move() == WHITE) ?
                                         white_engine :
                                         black_engine;

        Move best_move = current_engine.get_best_move(pos, 100); // 100ms per
                                                                 // move

        if (best_move == MOVE_NONE || !pos.legal(best_move)) {
            // No legal move found - game over
            break;
        }

        pos.do_move(best_move);
        move_count++;

        if (verbose && move_count % 10 == 0) {
            std::cout << "Move " << move_count << std::endl;
        }
    }

    // Determine game result
    if (pos.get_phase() == Phase::gameOver) {
        if (pos.piece_on_board_count(WHITE) < rule.piecesAtLeastCount) {
            return BLACK; // White loses
        } else if (pos.piece_on_board_count(BLACK) < rule.piecesAtLeastCount) {
            return WHITE; // Black loses
        }
    }

    // If max moves reached or other draw condition
    return DRAW;
}

void TestFramework::game_worker(const std::vector<Parameter> &params1,
                                const std::vector<Parameter> &params2,
                                int games_to_play, GameResult &result,
                                std::mutex &result_mutex)
{
    GameResult local_result;

    for (int game = 0; game < games_to_play; ++game) {
        Color winner;

        if (game % 2 == 0) {
            // params1 plays white
            winner = play_single_game(params1, params2);
        } else {
            // params2 plays white
            winner = play_single_game(params2, params1);
            // Flip perspective for params1
            if (winner == WHITE)
                winner = BLACK;
            else if (winner == BLACK)
                winner = WHITE;
        }

        // Update local results from params1 perspective
        if (winner == WHITE) {
            local_result.wins++;
        } else if (winner == BLACK) {
            local_result.losses++;
        } else {
            local_result.draws++;
        }
    }

    // Update shared results
    std::lock_guard<std::mutex> lock(result_mutex);
    result.wins += local_result.wins;
    result.losses += local_result.losses;
    result.draws += local_result.draws;
}

// GameEngine Implementation
GameEngine::GameEngine(const std::vector<Parameter> &params)
    : parameters_(params)
{
    apply_parameters();
}

Move GameEngine::get_best_move(Position &pos, int time_limit_ms)
{
    // Set time limit
    gameOptions.setMoveTime(time_limit_ms);

    Move best_move = MOVE_NONE;

    // Use the search engine to find best move
    SearchEngine search_engine;
    search_engine.setRootPosition(&pos);
    search_engine.executeSearch();
    best_move = search_engine.bestMove;

    return best_move;
}

void GameEngine::update_parameters(const std::vector<Parameter> &params)
{
    parameters_ = params;
    apply_parameters();
}

void GameEngine::apply_parameters()
{
    // Apply parameters to traditional search algorithms (NOT MCTS!)
    auto &param_manager = TunableParams::TraditionalParameterManager::instance();

    for (const auto &param : parameters_) {
        // Search algorithm parameters
        if (param.name == "max_search_depth") {
            param_manager.update_max_search_depth(
                static_cast<int>(param.value));
        } else if (param.name == "quiescence_depth") {
            param_manager.update_quiescence_depth(
                static_cast<int>(param.value));
        } else if (param.name == "null_move_reduction") {
            param_manager.update_null_move_reduction(
                static_cast<int>(param.value));
        } else if (param.name == "late_move_reduction") {
            param_manager.update_late_move_reduction(
                static_cast<int>(param.value));
        } else if (param.name == "futility_margin") {
            param_manager.update_futility_margin(static_cast<int>(param.value));
        } else if (param.name == "razor_margin") {
            param_manager.update_razor_margin(static_cast<int>(param.value));

            // Basic evaluation parameters
        } else if (param.name == "piece_value") {
            param_manager.update_piece_value(static_cast<int>(param.value));
        } else if (param.name == "piece_inhand_value") {
            param_manager.update_piece_inhand_value(
                static_cast<int>(param.value));
        } else if (param.name == "piece_onboard_value") {
            param_manager.update_piece_onboard_value(
                static_cast<int>(param.value));
        } else if (param.name == "piece_needremove_value") {
            param_manager.update_piece_needremove_value(
                static_cast<int>(param.value));

            // Positional evaluation weights
        } else if (param.name == "mobility_weight") {
            param_manager.update_mobility_weight(param.value);
        } else if (param.name == "center_control_weight") {
            param_manager.update_center_control_weight(param.value);
        } else if (param.name == "mill_potential_weight") {
            param_manager.update_mill_potential_weight(param.value);
        } else if (param.name == "blocking_weight") {
            param_manager.update_blocking_weight(param.value);

            // Endgame and tempo parameters
        } else if (param.name == "endgame_piece_threshold") {
            param_manager.update_endgame_piece_threshold(
                static_cast<int>(param.value));
        } else if (param.name == "endgame_mobility_bonus") {
            param_manager.update_endgame_mobility_bonus(param.value);
        } else if (param.name == "tempo_bonus") {
            param_manager.update_tempo_bonus(param.value);

            // Mill evaluation parameters
        } else if (param.name == "mill_value") {
            param_manager.update_mill_value(static_cast<int>(param.value));
        } else if (param.name == "potential_mill_value") {
            param_manager.update_potential_mill_value(
                static_cast<int>(param.value));
        } else if (param.name == "broken_mill_penalty") {
            param_manager.update_broken_mill_penalty(
                static_cast<int>(param.value));
        }
    }
}

// Utility Functions Implementation
namespace Utils {

std::vector<Parameter> parse_parameter_file(const std::string &filename)
{
    std::vector<Parameter> params;
    std::ifstream file(filename);

    if (!file.is_open()) {
        std::cerr << "Cannot open parameter file: " << filename << std::endl;
        return params; // Return empty vector
    }

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') {
            continue; // Skip empty lines and comments
        }

        std::istringstream iss(line);
        std::string name;
        double value, min_val, max_val, pert_size;
        int is_int;

        if (iss >> name >> value >> min_val >> max_val >> pert_size >> is_int) {
            params.emplace_back(name, value, min_val, max_val, pert_size,
                                is_int != 0);
        }
    }

    return params;
}

bool write_parameter_file(const std::string &filename,
                          const std::vector<Parameter> &params)
{
    std::ofstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    file << "# Parameter file generated by SPSA tuner" << std::endl;
    file << "# Format: name value min_value max_value perturbation_size "
            "is_integer"
         << std::endl;

    for (const auto &param : params) {
        file << param.name << " " << std::fixed << std::setprecision(6)
             << param.value << " " << param.min_value << " " << param.max_value
             << " " << param.perturbation_size << " "
             << (param.is_integer ? 1 : 0) << std::endl;
    }

    return true;
}

Position generate_random_position(std::mt19937 &rng)
{
    Position pos;
    pos.reset();

    // Play some random moves to get a non-trivial position
    std::uniform_int_distribution<int> move_dist(5, 15);
    int num_moves = move_dist(rng);

    for (int i = 0; i < num_moves && pos.get_phase() != Phase::gameOver; ++i) {
        // Generate legal moves (simplified)
        MovePicker mp(pos, MOVE_NONE);
        Move move = mp.next_move<LEGAL>();

        if (move == MOVE_NONE) {
            break;
        }

        // Count available moves
        int move_count = 0;
        MovePicker mp2(pos, MOVE_NONE);
        while (mp2.next_move<LEGAL>() != MOVE_NONE) {
            move_count++;
        }

        if (move_count == 0) {
            break;
        }

        // Pick a random move
        std::uniform_int_distribution<int> move_idx_dist(0, move_count - 1);
        int target_idx = move_idx_dist(rng);

        MovePicker mp3(pos, MOVE_NONE);
        Move selected_move = MOVE_NONE;
        for (int j = 0; j <= target_idx; ++j) {
            selected_move = mp3.next_move<LEGAL>();
            if (selected_move == MOVE_NONE)
                break;
        }

        if (selected_move != MOVE_NONE && pos.legal(selected_move)) {
            pos.do_move(selected_move);
        } else {
            break;
        }
    }

    return pos;
}

std::string parameters_to_string(const std::vector<Parameter> &params)
{
    std::ostringstream oss;
    for (size_t i = 0; i < params.size(); ++i) {
        if (i > 0)
            oss << ",";
        oss << params[i].name << "=" << std::fixed << std::setprecision(4)
            << params[i].value;
    }
    return oss.str();
}

double win_rate_to_elo(double win_rate)
{
    if (win_rate <= 0.0)
        return -1000.0;
    if (win_rate >= 1.0)
        return 1000.0;

    return -400.0 * std::log10((1.0 / win_rate) - 1.0);
}

std::string get_timestamp()
{
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);

    std::ostringstream oss;
    oss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    return oss.str();
}

} // namespace Utils

} // namespace SPSA
