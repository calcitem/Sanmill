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

namespace NNUE {

TrainingDataGenerator::TrainingDataGenerator() 
    : rng_(std::chrono::steady_clock::now().time_since_epoch().count()),
      generated_count_(0), valid_count_(0), perfect_db_hits_(0) {
}

bool TrainingDataGenerator::generate_training_set(const std::string& output_file,
                                                 int target_samples,
                                                 bool include_all_phases) {
    std::vector<TrainingSample> samples;
    samples.reserve(target_samples);
    
    std::cout << "Generating " << target_samples << " training samples using Perfect Database..." << std::endl;
    
    // Generate samples from different sources
    int samples_per_method = target_samples / 3;
    
    // 1. Generate from random positions
    std::cout << "Generating random positions..." << std::endl;
    generate_random_positions(samples, samples_per_method);
    
    // 2. Generate from self-play games
    std::cout << "Generating from self-play..." << std::endl;
    generate_from_self_play(samples, samples_per_method / 10);  // Fewer games, more positions per game
    
    // 3. Generate phase-specific positions
    if (include_all_phases) {
        std::cout << "Generating phase-specific positions..." << std::endl;
        std::vector<TrainingSample> phase_samples;
        generate_phase_data(Phase::placing, phase_samples, samples_per_method / 2);
        samples.insert(samples.end(), phase_samples.begin(), phase_samples.end());
        
        phase_samples.clear();
        generate_phase_data(Phase::moving, phase_samples, samples_per_method / 2);
        samples.insert(samples.end(), phase_samples.begin(), phase_samples.end());
    }
    
    // Shuffle samples
    TrainingUtils::shuffle_samples(samples);
    
    // Print statistics
    TrainingUtils::print_data_statistics(samples);
    
    // Save to file
    bool success = save_training_data_text(samples, output_file);
    
    if (success) {
        std::cout << "Training data saved to " << output_file << std::endl;
        std::cout << "Generated: " << generated_count_ << " positions" << std::endl;
        std::cout << "Valid: " << valid_count_ << " positions" << std::endl;
        std::cout << "Perfect DB hits: " << perfect_db_hits_ << " positions" << std::endl;
    }
    
    return success;
}

bool TrainingDataGenerator::generate_random_positions(std::vector<TrainingSample>& samples, int count) {
    int generated = 0;
    int attempts = 0;
    const int max_attempts = count * 10;  // Prevent infinite loops
    
    while (generated < count && attempts < max_attempts) {
        attempts++;
        generated_count_++;
        
        Position pos;
        if (generate_random_position(pos)) {
            if (is_valid_training_position(pos)) {
                TrainingSample sample;
                if (evaluate_with_perfect_db(pos, sample)) {
                    samples.push_back(sample);
                    generated++;
                    valid_count_++;
                    perfect_db_hits_++;
                }
            }
        }
        
        if (attempts % 1000 == 0) {
            log_progress(generated, count, "Random positions");
        }
    }
    
    return generated > 0;
}

bool TrainingDataGenerator::generate_from_self_play(std::vector<TrainingSample>& samples, int num_games) {
    for (int game = 0; game < num_games; game++) {
        // Initialize position for new game
        Position pos;
        pos.set("*********************w*w 0 0");  // Standard starting position
        
        std::vector<Position> game_positions;
        
        // Play one game and collect positions
        while (pos.get_phase() != Phase::gameOver) {
            game_positions.push_back(pos);
            
            // Generate legal moves
            MoveList<LEGAL> moves(pos);
            if (moves.size() == 0) break;
            
            // Choose random move
            std::uniform_int_distribution<int> move_dist(0, static_cast<int>(moves.size()) - 1);
            Move move = moves[move_dist(rng_)].move;
            
            pos.do_move(move);
            
            // Limit game length
            if (game_positions.size() > 200) break;
        }
        
        // Evaluate all positions with Perfect Database
        for (const auto& game_pos : game_positions) {
            if (is_valid_training_position(game_pos)) {
                TrainingSample sample;
                if (evaluate_with_perfect_db(game_pos, sample)) {
                    samples.push_back(sample);
                    perfect_db_hits_++;
                }
            }
        }
        
        if (game % 100 == 0) {
            log_progress(game, num_games, "Self-play games");
        }
    }
    
    return true;
}

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
        pos.put_piece(WHITE_PIECE, sq);
    }
    
    // Place black pieces
    for (int i = white_pieces; i < white_pieces + black_pieces && i < static_cast<int>(empty_squares.size()); i++) {
        Square sq = empty_squares[i];
        pos.put_piece(BLACK_PIECE, sq);
    }
    
    // Set random side to move
    std::uniform_int_distribution<int> side_dist(0, 1);
    Color side = (side_dist(rng_) == 0) ? WHITE : BLACK;
    pos.set_side_to_move(side);
    
    // Set appropriate phase
    if (white_pieces < 9 || black_pieces < 9) {
        pos.set_phase(Phase::placing);
    } else {
        pos.set_phase(Phase::moving);
    }
    
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
            pos.put_piece(WHITE_PIECE, squares[i]);
        }
        for (int i = 0; i < black_pieces; i++) {
            pos.put_piece(BLACK_PIECE, squares[white_pieces + i]);
        }
        
        pos.set_phase(Phase::placing);
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
    if (value == VALUE_MATE || value > VALUE_KNOWN_WIN) {
        return 1.0f;  // Win
    } else if (value == -VALUE_MATE || value < -VALUE_KNOWN_WIN) {
        return -1.0f; // Loss
    } else if (value == VALUE_DRAW) {
        return 0.0f;  // Draw
    } else {
        // Scale evaluation to [-1, 1] range
        float scaled = static_cast<float>(value) / static_cast<float>(VALUE_KNOWN_WIN);
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
        if (sample.perfect_value > VALUE_KNOWN_WIN) wins++;
        else if (sample.perfect_value < -VALUE_KNOWN_WIN) losses++;
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
