// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue.h - NNUE (Efficiently Updatable Neural Network) evaluation
// Uses Perfect Database for optimal training data generation

#ifndef NNUE_H_INCLUDED
#define NNUE_H_INCLUDED

#include "types.h"
#include "perfect/perfect_api.h"
#include "nnue_symmetries.h"

class Position;

namespace NNUE {

// NNUE network dimensions for Mill game
constexpr int FEATURE_SIZE = 115;            // Total features from nnue_features.h
constexpr int HIDDEN_SIZE = 256;             // Hidden layer size
constexpr int OUTPUT_SIZE = 1;               // Single evaluation output

// Feature indices
constexpr int WHITE_PIECE_OFFSET = 0;
constexpr int BLACK_PIECE_OFFSET = 24;

// Network weights and biases
struct NNUEWeights {
    // Input to hidden layer
    alignas(64) int16_t input_weights[FEATURE_SIZE * HIDDEN_SIZE];
    alignas(64) int32_t input_biases[HIDDEN_SIZE];
    
    // Hidden to output layer
    alignas(64) int8_t output_weights[HIDDEN_SIZE * 2]; // 2 perspectives
    int32_t output_bias;
};

// NNUE evaluator
class NNUEEvaluator {
public:
    NNUEEvaluator();
    ~NNUEEvaluator() = default;
    
    // Initialize NNUE evaluator
    bool initialize(const std::string& model_path = "");
    
    // Evaluate position using NNUE
    Value evaluate(const Position& pos);
    
    // Get raw network output (for training)
    int32_t get_raw_output(const Position& pos);
    
    // Generate training data using Perfect Database
    bool generate_training_data(const std::string& output_file, int num_positions = 10000);
    
    // Load model from file
    bool load_model(const std::string& filepath);
    
    // Save model to file  
    bool save_model(const std::string& filepath) const;
    
    // Check if NNUE is available and loaded
    bool is_available() const { return model_loaded_; }
    
    // Enable/disable NNUE evaluation
    void set_enabled(bool enabled) { enabled_ = enabled; }
    bool is_enabled() const { return enabled_ && model_loaded_; }
    
    // Symmetry-aware evaluation
    Value evaluate_with_symmetries(const Position& pos);
    
    // Initialize symmetry transformations
    void initialize_symmetries() { SymmetryTransforms::initialize(); }

private:
    // Forward propagation (legacy method - use evaluate_with_symmetries for better results)
    int32_t forward(const Position& pos);
    
    // Feature extraction (requires non-const Position for some queries)
    void extract_features(Position& pos, bool* features);
    
    // Activate hidden layer
    void activate_hidden(const bool* features, int16_t* hidden);
    
    // Compute output
    int32_t compute_output(const int16_t* hidden_white, const int16_t* hidden_black, Color side_to_move);
    
    // Apply ReLU activation
    static int16_t relu(int32_t x) {
        return static_cast<int16_t>(std::max(0, std::min(32767, x / 64)));
    }
    
    // Convert NNUE output to centipawn value
    static Value nnue_to_value(int32_t nnue_output);

private:
    NNUEWeights weights_;
    bool model_loaded_;
    bool enabled_;
    
    // Temporary buffers for evaluation
    alignas(64) bool features_[FEATURE_SIZE];
    alignas(64) int16_t hidden_white_[HIDDEN_SIZE];
    alignas(64) int16_t hidden_black_[HIDDEN_SIZE];
};

// Global NNUE evaluator instance
extern NNUEEvaluator g_nnue_evaluator;

// Utility functions
bool is_nnue_available();
Value nnue_evaluate(const Position& pos);
void init_nnue(const std::string& model_path = "");

} // namespace NNUE

#endif // NNUE_H_INCLUDED
