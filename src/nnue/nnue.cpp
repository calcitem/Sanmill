// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue.cpp - NNUE evaluation implementation

#include "nnue.h"
#include "nnue_features.h"
#include "nnue_training.h"
#include "position.h"
#include "option.h"
#include "uci.h"
#include <iostream>
#include <fstream>
#include <cstring>
#include <algorithm>
#include <random>

namespace NNUE {

// Global NNUE evaluator instance
NNUEEvaluator g_nnue_evaluator;

// Initialize NNUE system
void init_nnue(const std::string& model_path) {
    g_nnue_evaluator.initialize(model_path);
}

// Check if NNUE is available
bool is_nnue_available() {
    return g_nnue_evaluator.is_available();
}

// Evaluate position using NNUE
Value nnue_evaluate(const Position& pos) {
    return g_nnue_evaluator.evaluate(pos);
}

// NNUEEvaluator implementation
NNUEEvaluator::NNUEEvaluator() 
    : model_loaded_(false), enabled_(true) {
    // Initialize weights to small random values
    std::random_device rd;
    std::mt19937 gen(rd());
    std::normal_distribution<float> dist(0.0f, 0.1f);
    
    // Initialize input layer weights
    for (int i = 0; i < FEATURE_SIZE * HIDDEN_SIZE; i++) {
        weights_.input_weights[i] = static_cast<int16_t>(dist(gen) * 1000);
    }
    
    // Initialize input biases to zero
    std::memset(weights_.input_biases, 0, sizeof(weights_.input_biases));
    
    // Initialize output weights
    for (int i = 0; i < HIDDEN_SIZE * 2; i++) {
        weights_.output_weights[i] = static_cast<int8_t>(dist(gen) * 127);
    }
    
    weights_.output_bias = 0;
}

bool NNUEEvaluator::initialize(const std::string& model_path) {
    // Strict mode: NNUE requires a valid model file to be loaded
    if (model_path.empty()) {
        std::cerr << "NNUE Error: No model path provided. NNUE requires a valid model file." << std::endl;
        model_loaded_ = false;
        enabled_ = false;
        return false;
    }
    
    bool success = load_model(model_path);
    if (!success) {
        std::cerr << "NNUE Error: Failed to load model from " << model_path << std::endl;
        model_loaded_ = false;
        enabled_ = false;
        return false;
    }
    
    // Only enable NNUE if model is successfully loaded
    model_loaded_ = true;
    enabled_ = static_cast<bool>(Options["UseNNUE"]);
    
    std::cout << "NNUE: Successfully initialized with model " << model_path << std::endl;
    return true;
}

Value NNUEEvaluator::evaluate(const Position& pos) {
    // Strict mode: Assert that NNUE is properly initialized
    assert(is_enabled() && "NNUE evaluation called but NNUE is not properly initialized");
    
    int32_t nnue_output = forward(pos);
    return nnue_to_value(nnue_output);
}

int32_t NNUEEvaluator::get_raw_output(const Position& pos) {
    // Strict mode: Assert that NNUE is properly initialized
    assert(is_enabled() && "NNUE get_raw_output called but NNUE is not properly initialized");
    
    return forward(pos);
}

int32_t NNUEEvaluator::forward(const Position& pos) {
    // Extract features into the working buffer
    // FeatureExtractor::extract_features requires a non-const Position
    // because it may consult internal cached state. We cast away const here
    // as we only perform read-only queries in practice.
    extract_features(const_cast<Position&>(pos), features_);

    // Perspective A (as-is, from white's perspective)
    activate_hidden(features_, hidden_white_);

    // Perspective B (swap piece-placement features for black's perspective).
    // Keep all non-placement features identical so that phase/count/mobility
    // features remain consistent between perspectives.
    bool swapped_features[FEATURE_SIZE];
    std::memcpy(swapped_features, features_, sizeof(swapped_features));

    // Swap the 24-square piece placement features between white and black
    // indices defined in nnue_features.h
    for (int i = 0; i < 24; i++) {
        const int w_idx = 0 + i;
        const int b_idx = 24 + i;
        const bool tmp = swapped_features[w_idx];
        swapped_features[w_idx] = swapped_features[b_idx];
        swapped_features[b_idx] = tmp;
    }

    activate_hidden(swapped_features, hidden_black_);

    // Compute final output
    return compute_output(hidden_white_, hidden_black_, pos.side_to_move());
}

void NNUEEvaluator::extract_features(Position& pos, bool* features) {
    // Use the advanced feature extractor (requires non-const Position)
    FeatureExtractor::extract_features(pos, features);
}

void NNUEEvaluator::activate_hidden(const bool* features, int16_t* hidden) {
    // Compute hidden layer activation using SIMD-like operations
    for (int h = 0; h < HIDDEN_SIZE; h++) {
        int32_t sum = weights_.input_biases[h];
        
        // Accumulate weights for active features
        for (int f = 0; f < FEATURE_SIZE; f++) {
            if (features[f]) {
                sum += weights_.input_weights[f * HIDDEN_SIZE + h];
            }
        }
        
        // Apply ReLU activation
        hidden[h] = relu(sum);
    }
}

int32_t NNUEEvaluator::compute_output(const int16_t* hidden_white, 
                                     const int16_t* hidden_black, 
                                     Color side_to_move) {
    int32_t sum = weights_.output_bias;
    
    // Choose perspective based on side to move
    const int16_t* current_hidden = (side_to_move == WHITE) ? hidden_white : hidden_black;
    const int16_t* opponent_hidden = (side_to_move == WHITE) ? hidden_black : hidden_white;
    
    // Combine both perspectives
    for (int i = 0; i < HIDDEN_SIZE; i++) {
        sum += current_hidden[i] * weights_.output_weights[i];
        sum += opponent_hidden[i] * weights_.output_weights[i + HIDDEN_SIZE];
    }
    
    return sum;
}

Value NNUEEvaluator::nnue_to_value(int32_t nnue_output) {
    // Convert NNUE output to centipawn scale
    // NNUE output is typically in range [-32768, 32767]
    // We want to map this to reasonable evaluation range
    
    constexpr int32_t NNUE_SCALE = 16;
    int32_t value = nnue_output / NNUE_SCALE;
    
    // Clamp to reasonable evaluation bounds
    value = std::max(-VALUE_MATE + 1, std::min(VALUE_MATE - 1, static_cast<Value>(value)));
    
    return static_cast<Value>(value);
}

bool NNUEEvaluator::generate_training_data(const std::string& output_file, int num_positions) {
    TrainingDataGenerator generator;
    // Create default phase quotas
    std::vector<PhaseQuota> phase_quotas;
    phase_quotas.emplace_back(Phase::moving, static_cast<int>(num_positions * 0.7f), 
                             static_cast<int>(num_positions * 0.5f), 2.0f);
    phase_quotas.emplace_back(Phase::placing, static_cast<int>(num_positions * 0.3f), 
                             static_cast<int>(num_positions * 0.2f), 1.0f);
    
    return generator.generate_training_set(output_file, num_positions, phase_quotas, 0);
}

bool NNUEEvaluator::load_model(const std::string& filepath) {
    std::ifstream file(filepath, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open NNUE model file: " << filepath << std::endl;
        return false;
    }
    
    // Read model header
    char header[8];
    file.read(header, 8);
    if (std::string(header, 8) != "SANMILL1") {
        std::cerr << "Invalid NNUE model format" << std::endl;
        return false;
    }

    // Read and validate dimensions (feature_size, hidden_size)
    int32_t file_feature_size = 0;
    int32_t file_hidden_size = 0;
    file.read(reinterpret_cast<char*>(&file_feature_size), sizeof(int32_t));
    file.read(reinterpret_cast<char*>(&file_hidden_size), sizeof(int32_t));

    if (file.fail()) {
        std::cerr << "Failed to read NNUE model dimensions" << std::endl;
        return false;
    }

    if (file_feature_size != FEATURE_SIZE || file_hidden_size != HIDDEN_SIZE) {
        std::cerr << "NNUE model dimensions mismatch (model="
                  << file_feature_size << "," << file_hidden_size
                  << ", expected=" << FEATURE_SIZE << "," << HIDDEN_SIZE
                  << ")" << std::endl;
        return false;
    }
    
    // Read weights field-by-field to avoid issues with structure padding/alignment
    file.read(reinterpret_cast<char*>(weights_.input_weights), sizeof(weights_.input_weights));
    file.read(reinterpret_cast<char*>(weights_.input_biases), sizeof(weights_.input_biases));
    file.read(reinterpret_cast<char*>(weights_.output_weights), sizeof(weights_.output_weights));
    file.read(reinterpret_cast<char*>(&weights_.output_bias), sizeof(weights_.output_bias));
    
    if (file.fail()) {
        std::cerr << "Failed to read NNUE model weights" << std::endl;
        return false;
    }
    
    model_loaded_ = true;
    std::cout << "Successfully loaded NNUE model from " << filepath << std::endl;
    return true;
}

bool NNUEEvaluator::save_model(const std::string& filepath) const {
    std::ofstream file(filepath, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to create NNUE model file: " << filepath << std::endl;
        return false;
    }
    
    // Write model header
    const char header[9] = "SANMILL1";
    file.write(header, 8);

    // Write dimensions to ensure compatibility
    const int32_t feature_size = FEATURE_SIZE;
    const int32_t hidden_size = HIDDEN_SIZE;
    file.write(reinterpret_cast<const char*>(&feature_size), sizeof(int32_t));
    file.write(reinterpret_cast<const char*>(&hidden_size), sizeof(int32_t));
    
    // Write weights field-by-field to ensure a stable on-disk format independent of padding
    file.write(reinterpret_cast<const char*>(weights_.input_weights), sizeof(weights_.input_weights));
    file.write(reinterpret_cast<const char*>(weights_.input_biases), sizeof(weights_.input_biases));
    file.write(reinterpret_cast<const char*>(weights_.output_weights), sizeof(weights_.output_weights));
    file.write(reinterpret_cast<const char*>(&weights_.output_bias), sizeof(weights_.output_bias));
    
    if (file.fail()) {
        std::cerr << "Failed to write NNUE model" << std::endl;
        return false;
    }
    
    std::cout << "Successfully saved NNUE model to " << filepath << std::endl;
    return true;
}

} // namespace NNUE
