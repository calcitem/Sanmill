// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_training.h - Training data generation using Perfect Database

#ifndef NNUE_TRAINING_H_INCLUDED
#define NNUE_TRAINING_H_INCLUDED

#include "types.h"
#include "perfect/perfect_api.h"
#include <string>
#include <vector>
#include <fstream>

class Position;

namespace NNUE {

// Training sample structure
struct TrainingSample {
    // Position features as boolean array
    std::vector<bool> features;
    
    // Perfect evaluation from database
    Value perfect_value;
    
    // Step count to optimal result (for training weights)
    int step_count;
    
    // Game phase information
    Phase phase;
    
    // Side to move
    Color side_to_move;
    
    // FEN string for debugging
    std::string fen;
    
    TrainingSample() : perfect_value(VALUE_NONE), step_count(-1), 
                      phase(Phase::none), side_to_move(WHITE) {}
};

// Training data generator using Perfect Database
class TrainingDataGenerator {
public:
    TrainingDataGenerator();
    ~TrainingDataGenerator() = default;
    
    // Generate training data using Perfect Database
    bool generate_training_set(const std::string& output_file, 
                              int target_samples = 50000,
                              bool include_all_phases = true);
    
    // Generate specific phase training data
    bool generate_phase_data(Phase phase, std::vector<TrainingSample>& samples, 
                           int target_count = 10000);
    
    // Generate random positions and evaluate with Perfect DB
    bool generate_random_positions(std::vector<TrainingSample>& samples,
                                 int count = 10000);
    
    // Generate positions from self-play games
    bool generate_from_self_play(std::vector<TrainingSample>& samples,
                               int num_games = 1000);
    
    // Save training data to file (binary format)
    bool save_training_data(const std::vector<TrainingSample>& samples,
                          const std::string& filename);
    
    // Save training data in text format for Python training
    bool save_training_data_text(const std::vector<TrainingSample>& samples,
                               const std::string& filename);
    
    // Load training data from file
    bool load_training_data(std::vector<TrainingSample>& samples,
                          const std::string& filename);

private:
    // Generate random valid position
    bool generate_random_position(Position& pos);
    
    // Generate position for specific phase
    bool generate_phase_position(Position& pos, Phase target_phase);
    
    // Evaluate position using Perfect Database
    bool evaluate_with_perfect_db(const Position& pos, TrainingSample& sample);
    
    // Validate position is legal and interesting
    bool is_valid_training_position(const Position& pos);
    
    // Extract features from position
    void extract_position_features(const Position& pos, TrainingSample& sample);
    
    // Convert Value to training target
    float value_to_training_target(Value value, int step_count = -1);
    
    // Progress tracking
    void log_progress(int current, int total, const std::string& phase);

private:
    std::mt19937 rng_;  // Random number generator
    int generated_count_;
    int valid_count_;
    int perfect_db_hits_;
};

// Utility functions for training data management
namespace TrainingUtils {
    // Shuffle training samples
    void shuffle_samples(std::vector<TrainingSample>& samples);
    
    // Split samples into train/validation sets
    void split_samples(const std::vector<TrainingSample>& samples,
                      std::vector<TrainingSample>& train_samples,
                      std::vector<TrainingSample>& val_samples,
                      float validation_ratio = 0.1f);
    
    // Filter samples by phase
    void filter_by_phase(const std::vector<TrainingSample>& samples,
                        std::vector<TrainingSample>& filtered,
                        Phase target_phase);
    
    // Print statistics about training data
    void print_data_statistics(const std::vector<TrainingSample>& samples);
    
    // Validate training data integrity
    bool validate_training_data(const std::vector<TrainingSample>& samples);
}

} // namespace NNUE

#endif // NNUE_TRAINING_H_INCLUDED
