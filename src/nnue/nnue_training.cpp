// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_training.cpp - Training data generation using Perfect Database

#include "nnue_training.h"
#include "nnue_features.h"
#include "position.h"
#include "movegen.h"
#include "perfect/perfect_api.h"
#include <iostream>
#include <fstream>
#include <algorithm>
#include <random>
#include <chrono>
#include <iomanip>
#include "engine_commands.h"

namespace NNUE {

TrainingDataGenerator::TrainingDataGenerator() 
    : rng_(std::chrono::steady_clock::now().time_since_epoch().count()),
      generated_count_(0), valid_count_(0), perfect_db_hits_(0) {
}

bool TrainingDataGenerator::generate_training_set(const std::string& output_file,
                                                 int target_samples,
                                                 const std::vector<PhaseQuota>& phase_quotas,
                                                 int num_threads) {
    // Auto-detect thread count if not specified
    if (num_threads <= 0) {
        num_threads = std::max(1u, std::thread::hardware_concurrency());
    }
    
    std::cout << "Generating " << target_samples << " training samples using Perfect Database with " 
              << num_threads << " threads..." << std::endl;
    
    // Calculate phase distribution
    std::vector<PhaseQuota> final_quotas = calculate_phase_distribution(target_samples, phase_quotas);
    validate_phase_quotas(final_quotas, target_samples);
    
    // Print quota distribution
    std::cout << "Phase quota distribution:" << std::endl;
    for (const auto& quota : final_quotas) {
        std::cout << "  Phase " << static_cast<int>(quota.phase) 
                  << ": " << quota.target_count << " samples (min: " << quota.min_count 
                  << ", priority: " << quota.priority << ")" << std::endl;
    }
    
    std::vector<TrainingSample> samples;
    samples.reserve(target_samples);
    
    // Generate samples for each phase in parallel
    for (const auto& quota : final_quotas) {
        if (quota.target_count <= 0) continue;
        
        std::cout << "Generating " << quota.target_count << " samples for phase " 
                  << static_cast<int>(quota.phase) << "..." << std::endl;
        
        std::vector<TrainingSample> phase_samples;
        
        // Use parallel generation for larger batches
        if (quota.target_count >= num_threads * 100) {
            generate_random_positions_parallel(phase_samples, quota.target_count, num_threads);
        } else {
            generate_phase_data(quota.phase, phase_samples, quota.target_count);
        }
        
        // Assert minimum quota is met
        assert(static_cast<int>(phase_samples.size()) >= quota.min_count && 
               "Failed to meet minimum phase quota requirements");
        
        samples.insert(samples.end(), phase_samples.begin(), phase_samples.end());
    }
    
    // Assert total sample count meets requirements
    assert(static_cast<int>(samples.size()) >= target_samples * 0.8f && 
           "Failed to generate sufficient training samples");
    
    // Shuffle samples
    TrainingUtils::shuffle_samples(samples);
    
    // Validate generated data
    assert(TrainingUtils::validate_training_data(samples) && 
           "Generated training data failed validation");
    
    // Print statistics
    TrainingUtils::print_data_statistics(samples);
    
    // Save to file
    bool success = save_training_data_text(samples, output_file);
    assert(success && "Failed to save training data to file");
    
    std::cout << "Training data saved to " << output_file << std::endl;
    std::cout << "Generated: " << generated_count_.load() << " positions" << std::endl;
    std::cout << "Valid: " << valid_count_.load() << " positions" << std::endl;
    std::cout << "Perfect DB hits: " << perfect_db_hits_.load() << " positions" << std::endl;
    
    return true;
}

// Legacy methods removed - replaced with parallel versions

bool TrainingDataGenerator::generate_phase_data(Phase phase, std::vector<TrainingSample>& samples, int target_count) {
    int generated = 0;
    int attempts = 0;
    const int max_attempts = target_count * 20;
    
    while (generated < target_count && attempts < max_attempts) {
        attempts++;
        
        Position pos;
        if (generate_phase_position(pos, phase)) {
            if (is_valid_training_position(pos)) {
                TrainingSample sample;
                if (evaluate_with_perfect_db(pos, sample)) {
                    samples.push_back(sample);
                    generated++;
                    perfect_db_hits_++;
                }
            }
        }
        
        if (attempts % 1000 == 0) {
            log_progress(generated, target_count, "Phase-specific positions");
        }
    }
    
    return generated > 0;
}

bool TrainingDataGenerator::generate_random_position(Position& pos) {
    // Start with empty board
    pos.set("************************ 0 0");
    
    // Random number of pieces for each color (realistic distributions)
    std::uniform_int_distribution<int> pieces_dist(3, 9);
    int white_pieces = pieces_dist(rng_);
    int black_pieces = pieces_dist(rng_);
    
    // Place pieces randomly
    std::vector<Square> empty_squares;
    for (Square sq = SQ_A1; sq < SQUARE_NB; ++sq) {
        empty_squares.push_back(sq);
    }
    
    std::shuffle(empty_squares.begin(), empty_squares.end(), rng_);
    
    // Place white pieces
    for (int i = 0; i < white_pieces && i < static_cast<int>(empty_squares.size()); i++) {
        Square sq = empty_squares[i];
        pos.put_piece(W_PIECE, sq);
        // Maintain counts for correctness of derived features and DB queries
        pos.pieceOnBoardCount[WHITE]++;
    }
    
    // Place black pieces
    for (int i = white_pieces; i < white_pieces + black_pieces && i < static_cast<int>(empty_squares.size()); i++) {
        Square sq = empty_squares[i];
        pos.put_piece(B_PIECE, sq);
        pos.pieceOnBoardCount[BLACK]++;
    }
    
    // Set random side to move
    std::uniform_int_distribution<int> side_dist(0, 1);
    Color side = (side_dist(rng_) == 0) ? WHITE : BLACK;
    pos.set_side_to_move(side);
    
    // Set remaining pieces in hand based on rule
    pos.pieceInHandCount[WHITE] = std::max(0, rule.pieceCount - pos.pieceOnBoardCount[WHITE]);
    pos.pieceInHandCount[BLACK] = std::max(0, rule.pieceCount - pos.pieceOnBoardCount[BLACK]);

    // Set appropriate phase (derive from piece-in-hand)
    if (pos.pieceInHandCount[WHITE] > 0 || pos.pieceInHandCount[BLACK] > 0) {
        // Placing phase if any pieces remain to be placed
        // We approximate by updating internal phase directly
        pos.phase = Phase::placing;
    } else {
        pos.phase = Phase::moving;
    }

    // Rebuild Zobrist key if needed
    pos.construct_key();
    
    return true;
}

bool TrainingDataGenerator::generate_phase_position(Position& pos, Phase target_phase) {
    if (target_phase == Phase::placing) {
        // Generate placing phase position
        pos.set("************************ 0 0");
        
        // Place some pieces randomly (0-8 for each color)
        std::uniform_int_distribution<int> pieces_dist(0, 8);
        int white_pieces = pieces_dist(rng_);
        int black_pieces = pieces_dist(rng_);
        
        std::vector<Square> squares;
        for (Square sq = SQ_A1; sq < SQUARE_NB; ++sq) {
            squares.push_back(sq);
        }
        std::shuffle(squares.begin(), squares.end(), rng_);
        
        for (int i = 0; i < white_pieces; i++) {
            pos.put_piece(W_PIECE, squares[i]);
            pos.pieceOnBoardCount[WHITE]++;
        }
        for (int i = 0; i < black_pieces; i++) {
            pos.put_piece(B_PIECE, squares[white_pieces + i]);
            pos.pieceOnBoardCount[BLACK]++;
        }
        
        pos.phase = Phase::placing;

        pos.pieceInHandCount[WHITE] = std::max(0, rule.pieceCount - pos.pieceOnBoardCount[WHITE]);
        pos.pieceInHandCount[BLACK] = std::max(0, rule.pieceCount - pos.pieceOnBoardCount[BLACK]);
        pos.construct_key();
    } else if (target_phase == Phase::moving) {
        // Generate moving phase position
        return generate_random_position(pos);  // Most random positions are moving phase
    }
    
    return true;
}

bool TrainingDataGenerator::evaluate_with_perfect_db(const Position& pos, TrainingSample& sample) {
    // Get evaluation from Perfect Database
    PerfectEvaluation perfect_eval = PerfectAPI::getDetailedEvaluation(pos);
    
    if (!perfect_eval.isValid) {
        return false;  // Position not in Perfect Database
    }
    
    // Fill training sample
    sample.perfect_value = perfect_eval.value;
    sample.step_count = perfect_eval.stepCount;
    sample.phase = pos.get_phase();
    sample.side_to_move = pos.side_to_move();
    sample.fen = pos.fen();
    
    // Extract features
    extract_position_features(pos, sample);
    
    return true;
}

bool TrainingDataGenerator::is_valid_training_position(const Position& pos) {
    // Check if position is legal and interesting for training
    
    // Skip game over positions
    if (pos.get_phase() == Phase::gameOver) {
        return false;
    }
    
    // Skip positions with too few pieces
    int total_pieces = pos.piece_on_board_count(WHITE) + pos.piece_on_board_count(BLACK);
    if (total_pieces < 3) {
        return false;
    }
    
    // Skip positions where one side has already lost
    if (pos.piece_on_board_count(WHITE) < 3 && pos.piece_in_hand_count(WHITE) == 0) {
        return false;
    }
    if (pos.piece_on_board_count(BLACK) < 3 && pos.piece_in_hand_count(BLACK) == 0) {
        return false;
    }
    
    return true;
}

void TrainingDataGenerator::extract_position_features(const Position& pos, TrainingSample& sample) {
    sample.features.resize(FeatureIndices::TOTAL_FEATURES);
    
    bool feature_array[FeatureIndices::TOTAL_FEATURES];
    FeatureExtractor::extract_features(pos, feature_array);
    
    for (int i = 0; i < FeatureIndices::TOTAL_FEATURES; i++) {
        sample.features[i] = feature_array[i];
    }
}

float TrainingDataGenerator::value_to_training_target(Value value, int step_count) {
    // Convert game-theoretic values to training targets
    if (value == VALUE_MATE || value > VALUE_EACH_PIECE) {
        return 1.0f;  // Win
    } else if (value == -VALUE_MATE || value < -VALUE_EACH_PIECE) {
        return -1.0f; // Loss
    } else if (value == VALUE_DRAW) {
        return 0.0f;  // Draw
    } else {
        // Scale evaluation to [-1, 1] range
        float scaled = static_cast<float>(value) / static_cast<float>(VALUE_EACH_PIECE);
        return std::max(-1.0f, std::min(1.0f, scaled));
    }
}

bool TrainingDataGenerator::save_training_data_text(const std::vector<TrainingSample>& samples,
                                                   const std::string& filename) {
    std::ofstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Failed to open file for writing: " << filename << std::endl;
        return false;
    }
    
    // Write header
    file << "# Sanmill NNUE Training Data\n";
    file << "# Format: features(space-separated 0/1) | evaluation | step_count | phase | fen\n";
    file << samples.size() << "\n";
    
    for (const auto& sample : samples) {
        // Write features
        for (size_t i = 0; i < sample.features.size(); i++) {
            file << (sample.features[i] ? "1" : "0");
            if (i < sample.features.size() - 1) file << " ";
        }
        
        file << " | ";
        file << value_to_training_target(sample.perfect_value, sample.step_count);
        file << " | " << sample.step_count;
        file << " | " << static_cast<int>(sample.phase);
        file << " | " << sample.fen << "\n";
    }
    
    return !file.fail();
}

bool TrainingDataGenerator::generate_random_positions_parallel(std::vector<TrainingSample>& samples,
                                                             int count,
                                                             int num_threads) {
    assert(num_threads > 0 && "Invalid thread count for parallel generation");
    
    std::vector<std::future<std::vector<TrainingSample>>> futures;
    std::atomic<int> progress_counter(0);
    
    int samples_per_thread = count / num_threads;
    int remainder = count % num_threads;
    
    // Launch worker threads
    for (int i = 0; i < num_threads; ++i) {
        int thread_samples = samples_per_thread + (i < remainder ? 1 : 0);
        
        futures.emplace_back(std::async(std::launch::async, [this, thread_samples, &progress_counter]() {
            std::vector<TrainingSample> local_samples;
            std::mt19937 thread_rng(rng_() + std::hash<std::thread::id>{}(std::this_thread::get_id()));
            
            generate_samples_worker(Phase::moving, thread_samples, local_samples, progress_counter, thread_rng);
            
            return local_samples;
        }));
    }
    
    // Collect results from all threads
    for (auto& future : futures) {
        std::vector<TrainingSample> thread_samples = future.get();
        
        std::lock_guard<std::mutex> lock(samples_mutex_);
        samples.insert(samples.end(), thread_samples.begin(), thread_samples.end());
    }
    
    assert(static_cast<int>(samples.size()) >= count * 0.8f && 
           "Parallel generation failed to produce sufficient samples");
    
    return true;
}

bool TrainingDataGenerator::generate_from_self_play_parallel(std::vector<TrainingSample>& samples,
                                                           int num_games,
                                                           int num_threads) {
    assert(num_threads > 0 && "Invalid thread count for parallel self-play");
    
    std::vector<std::future<std::vector<TrainingSample>>> futures;
    std::atomic<int> progress_counter(0);
    
    int games_per_thread = num_games / num_threads;
    int remainder = num_games % num_threads;
    
    // Launch worker threads for self-play
    for (int i = 0; i < num_threads; ++i) {
        int thread_games = games_per_thread + (i < remainder ? 1 : 0);
        
        futures.emplace_back(std::async(std::launch::async, [this, thread_games, &progress_counter]() {
            std::vector<TrainingSample> thread_samples;
            std::mt19937 thread_rng(rng_() + std::hash<std::thread::id>{}(std::this_thread::get_id()));
            
            // Generate samples from self-play games
            for (int game = 0; game < thread_games; game++) {
                Position pos;
                EngineCommands::init_start_fen();
                pos.set(EngineCommands::StartFEN);
                
                std::vector<Position> game_positions;
                
                // Play one game and collect positions
                while (pos.get_phase() != Phase::gameOver && game_positions.size() < 200) {
                    game_positions.push_back(pos);
                    
                    MoveList<LEGAL> moves(pos);
                    if (moves.size() == 0) break;
                    
                    std::uniform_int_distribution<int> move_dist(0, static_cast<int>(moves.size()) - 1);
                    Move move = moves.getMove(move_dist(thread_rng)).move;
                    
                    pos.do_move(move);
                }
                
                // Evaluate all positions with Perfect Database
                for (const auto& game_pos : game_positions) {
                    if (is_valid_training_position(game_pos)) {
                        TrainingSample sample;
                        if (evaluate_with_perfect_db(game_pos, sample)) {
                            thread_samples.push_back(sample);
                            perfect_db_hits_++;
                        }
                    }
                }
                
                progress_counter++;
            }
            
            return thread_samples;
        }));
    }
    
    // Collect results from all threads
    for (auto& future : futures) {
        std::vector<TrainingSample> thread_samples = future.get();
        
        std::lock_guard<std::mutex> lock(samples_mutex_);
        samples.insert(samples.end(), thread_samples.begin(), thread_samples.end());
    }
    
    return true;
}

void TrainingDataGenerator::generate_samples_worker(Phase target_phase,
                                                   int samples_per_thread,
                                                   std::vector<TrainingSample>& thread_samples,
                                                   std::atomic<int>& progress_counter,
                                                   std::mt19937& thread_rng) {
    int generated = 0;
    int attempts = 0;
    const int max_attempts = samples_per_thread * 20;  // Prevent infinite loops
    
    while (generated < samples_per_thread && attempts < max_attempts) {
        attempts++;
        generated_count_++;
        
        Position pos;
        
        // Generate position based on target phase
        bool position_generated = false;
        if (target_phase == Phase::placing) {
            position_generated = generate_phase_position(pos, Phase::placing);
        } else {
            position_generated = generate_random_position(pos);
        }
        
        if (position_generated && is_valid_training_position(pos)) {
            TrainingSample sample;
            if (evaluate_with_perfect_db(pos, sample)) {
                thread_samples.push_back(sample);
                generated++;
                valid_count_++;
                perfect_db_hits_++;
            }
        }
        
        if (attempts % 1000 == 0) {
            progress_counter++;
        }
    }
    
    // Assert that worker generated sufficient samples
    assert(generated >= samples_per_thread * 0.5f && 
           "Worker thread failed to generate sufficient training samples");
}

std::vector<PhaseQuota> TrainingDataGenerator::calculate_phase_distribution(int total_samples,
                                                                          const std::vector<PhaseQuota>& user_quotas) {
    std::vector<PhaseQuota> result;
    
    if (user_quotas.empty()) {
        // Default distribution: 70% moving phase, 30% placing phase
        result.emplace_back(Phase::moving, static_cast<int>(total_samples * 0.7f), 
                           static_cast<int>(total_samples * 0.5f), 2.0f);
        result.emplace_back(Phase::placing, static_cast<int>(total_samples * 0.3f), 
                           static_cast<int>(total_samples * 0.2f), 1.0f);
        return result;
    }
    
    // Calculate total priority weight
    float total_priority = 0.0f;
    for (const auto& quota : user_quotas) {
        total_priority += quota.priority;
    }
    
    assert(total_priority > 0.0f && "Total priority weight must be positive");
    
    // Distribute samples based on priority weights
    int allocated_samples = 0;
    for (size_t i = 0; i < user_quotas.size(); ++i) {
        const auto& quota = user_quotas[i];
        
        int target_count;
        if (i == user_quotas.size() - 1) {
            // Last quota gets remaining samples
            target_count = total_samples - allocated_samples;
        } else {
            target_count = static_cast<int>((quota.priority / total_priority) * total_samples);
        }
        
        // Ensure minimum requirements are met
        target_count = std::max(target_count, quota.min_count);
        
        result.emplace_back(quota.phase, target_count, quota.min_count, quota.priority);
        allocated_samples += target_count;
    }
    
    return result;
}

void TrainingDataGenerator::validate_phase_quotas(const std::vector<PhaseQuota>& quotas, int total_samples) {
    int total_min_required = 0;
    int total_target = 0;
    
    for (const auto& quota : quotas) {
        assert(quota.target_count >= 0 && "Phase quota target count must be non-negative");
        assert(quota.min_count >= 0 && "Phase quota minimum count must be non-negative");
        assert(quota.min_count <= quota.target_count && "Minimum count cannot exceed target count");
        assert(quota.priority > 0.0f && "Phase priority must be positive");
        
        total_min_required += quota.min_count;
        total_target += quota.target_count;
    }
    
    assert(total_min_required <= total_samples && 
           "Total minimum requirements exceed total sample count");
    
    // Warn if total target significantly exceeds requested samples
    if (total_target > total_samples * 1.2f) {
        std::cerr << "Warning: Total phase targets (" << total_target 
                  << ") significantly exceed requested samples (" << total_samples << ")" << std::endl;
    }
}

void TrainingDataGenerator::log_progress(int current, int total, const std::string& phase) {
    double percentage = (static_cast<double>(current) / total) * 100.0;
    std::cout << phase << ": " << current << "/" << total 
              << " (" << std::fixed << std::setprecision(1) << percentage << "%)" << std::endl;
}

// TrainingUtils implementation
namespace TrainingUtils {

void shuffle_samples(std::vector<TrainingSample>& samples) {
    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(samples.begin(), samples.end(), g);
}

void split_samples(const std::vector<TrainingSample>& samples,
                  std::vector<TrainingSample>& train_samples,
                  std::vector<TrainingSample>& val_samples,
                  float validation_ratio) {
    size_t total_size = samples.size();
    size_t val_size = static_cast<size_t>(total_size * validation_ratio);
    size_t train_size = total_size - val_size;
    
    train_samples.assign(samples.begin(), samples.begin() + train_size);
    val_samples.assign(samples.begin() + train_size, samples.end());
}

void filter_by_phase(const std::vector<TrainingSample>& samples,
                    std::vector<TrainingSample>& filtered,
                    Phase target_phase) {
    for (const auto& sample : samples) {
        if (sample.phase == target_phase) {
            filtered.push_back(sample);
        }
    }
}

void print_data_statistics(const std::vector<TrainingSample>& samples) {
    if (samples.empty()) {
        std::cout << "No training samples to analyze." << std::endl;
        return;
    }
    
    int wins = 0, draws = 0, losses = 0;
    int placing_phase = 0, moving_phase = 0, other_phase = 0;
    
    for (const auto& sample : samples) {
        // Count evaluations
        if (sample.perfect_value > VALUE_EACH_PIECE) wins++;
        else if (sample.perfect_value < -VALUE_EACH_PIECE) losses++;
        else draws++;
        
        // Count phases
        if (sample.phase == Phase::placing) placing_phase++;
        else if (sample.phase == Phase::moving) moving_phase++;
        else other_phase++;
    }
    
    std::cout << "\n=== Training Data Statistics ===" << std::endl;
    std::cout << "Total samples: " << samples.size() << std::endl;
    std::cout << "Evaluations - Wins: " << wins << ", Draws: " << draws << ", Losses: " << losses << std::endl;
    std::cout << "Phases - Placing: " << placing_phase << ", Moving: " << moving_phase 
              << ", Other: " << other_phase << std::endl;
    std::cout << "================================\n" << std::endl;
}

bool validate_training_data(const std::vector<TrainingSample>& samples) {
    for (const auto& sample : samples) {
        // Check feature vector size
        if (sample.features.size() != FeatureIndices::TOTAL_FEATURES) {
            std::cerr << "Invalid feature vector size: " << sample.features.size() << std::endl;
            return false;
        }
        
        // Check evaluation is valid
        if (sample.perfect_value == VALUE_NONE) {
            std::cerr << "Invalid evaluation in training sample" << std::endl;
            return false;
        }
    }
    
    return true;
}

} // namespace TrainingUtils

} // namespace NNUE
