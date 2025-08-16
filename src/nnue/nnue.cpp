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
#include <limits>

namespace NNUE {

// Build-time sanity checks to ensure feature dimensions remain consistent
static_assert(FEATURE_SIZE == FeatureIndices::TOTAL_FEATURES,
              "FEATURE_SIZE must match FeatureIndices::TOTAL_FEATURES");

// Global NNUE evaluator instance
NNUEEvaluator g_nnue_evaluator;

// Global debug control
static bool g_nnue_debug_enabled = true;

// Initialize NNUE system
bool init_nnue(const std::string& model_path) {
    NNUE_DEBUG_PRINT("Starting NNUE initialization...");
    NNUE_DEBUG_PRINT("Model path: " << model_path);
    
    bool result = g_nnue_evaluator.initialize(model_path);
    
    if (result) {
        NNUE_DEBUG_PRINT("NNUE initialization successful");
    } else {
        NNUE_DEBUG_PRINT("NNUE initialization FAILED");
    }
    
    return result;
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
    NNUE_DEBUG_PRINT("Constructing NNUEEvaluator...");
    NNUE_DEBUG_PRINTF("NNUE Network dimensions: %d features -> %d hidden -> %d output", 
                      FEATURE_SIZE, HIDDEN_SIZE, OUTPUT_SIZE);
    
    // Initialize symmetry transformations
    NNUE_DEBUG_PRINT("Initializing symmetry transformations...");
    SymmetryTransforms::initialize();
    
    // Initialize weights to small random values using Xavier initialization
    std::random_device rd;
    std::mt19937 gen(rd());
    
    // Xavier initialization for input weights: scale by sqrt(1/fan_in)
    const float input_scale = std::sqrt(1.0f / FEATURE_SIZE);
    std::normal_distribution<float> input_dist(0.0f, input_scale);
    
    NNUE_DEBUG_PRINTF("Initializing input weights with Xavier scale: %f", input_scale);
    
    // Initialize input layer weights
    for (int i = 0; i < FEATURE_SIZE * HIDDEN_SIZE; i++) {
        const float val = input_dist(gen);
        weights_.input_weights[i] = static_cast<int16_t>(std::max(-32767.0f, 
                                                                 std::min(32767.0f, val * 16384.0f)));
    }
    
    // Initialize input biases to zero
    std::memset(weights_.input_biases, 0, sizeof(weights_.input_biases));
    
    // Xavier initialization for output weights: scale by sqrt(1/fan_in)  
    const float output_scale = std::sqrt(1.0f / HIDDEN_SIZE);
    std::normal_distribution<float> output_dist(0.0f, output_scale);
    
    NNUE_DEBUG_PRINTF("Initializing output weights with Xavier scale: %f", output_scale);
    
    // Initialize output weights
    for (int i = 0; i < HIDDEN_SIZE * 2; i++) {
        const float val = output_dist(gen);
        weights_.output_weights[i] = static_cast<int8_t>(std::max(-127.0f, 
                                                                 std::min(127.0f, val * 127.0f)));
    }
    
    weights_.output_bias = 0;
    
    NNUE_DEBUG_PRINT("NNUEEvaluator construction completed");
}

bool NNUEEvaluator::initialize(const std::string& model_path) {
    NNUE_DEBUG_PRINT("NNUEEvaluator::initialize() called");
    NNUE_DEBUG_PRINT("Model path: " << model_path);
    
    // Initialize symmetry transformations first
    NNUE_DEBUG_PRINT("Re-initializing symmetry transformations...");
    initialize_symmetries();
    
    // Strict mode: NNUE requires a valid model file to be loaded
    if (model_path.empty()) {
        NNUE_DEBUG_PRINT("ERROR: Empty model path provided");
        std::cerr << "NNUE Error: No model path provided. NNUE requires a valid model file." << std::endl;
        model_loaded_ = false;
        enabled_ = false;
        return false;
    }
    
    NNUE_DEBUG_PRINT("Attempting to load model from: " << model_path);
    bool success = load_model(model_path);
    if (!success) {
        NNUE_DEBUG_PRINT("ERROR: Model loading failed");
        std::cerr << "NNUE Error: Failed to load model from " << model_path << std::endl;
        model_loaded_ = false;
        enabled_ = false;
        return false;
    }
    
    // Only enable NNUE if model is successfully loaded
    model_loaded_ = true;
    enabled_ = static_cast<bool>(Options["UseNNUE"]);
    
    NNUE_DEBUG_PRINTF("Model loaded successfully. Enabled: %s", enabled_ ? "true" : "false");
    NNUE_DEBUG_PRINTF("UseNNUE option value: %s", static_cast<bool>(Options["UseNNUE"]) ? "true" : "false");
    
    std::cout << "NNUE: Successfully initialized with model " << model_path << std::endl;
    return true;
}

Value NNUEEvaluator::evaluate(const Position& pos) {
    // Strict mode: Assert that NNUE is properly initialized
    assert(is_enabled() && "NNUE evaluation called but NNUE is not properly initialized");
    
    NNUE_DEBUG_PRINT("Starting NNUE evaluation...");
    NNUE_DEBUG_PRINTF("Position FEN: %s", pos.fen().c_str());
    NNUE_DEBUG_PRINTF("Side to move: %s", pos.side_to_move() == WHITE ? "WHITE" : "BLACK");
    NNUE_DEBUG_PRINTF("Phase: %d", static_cast<int>(pos.get_phase()));
    
    // Use symmetry-aware evaluation for better accuracy and efficiency
    Value result = evaluate_with_symmetries(pos);
    
    NNUE_DEBUG_PRINTF("NNUE evaluation result: %d", static_cast<int>(result));
    return result;
}

int32_t NNUEEvaluator::get_raw_output(const Position& pos) {
    // Strict mode: Assert that NNUE is properly initialized
    assert(is_enabled() && "NNUE get_raw_output called but NNUE is not properly initialized");
    
    return forward(pos);
}

int32_t NNUEEvaluator::forward(const Position& pos) {
    // Legacy forward method kept for compatibility
    // NOTE: This method uses basic color swapping only and does not leverage
    // full symmetry transformations. For improved evaluation, use evaluate_with_symmetries().
    
    NNUE_DEBUG_PRINT("Starting forward pass...");
    
    // Extract features into the working buffer
    // FeatureExtractor::extract_features requires a non-const Position
    // because it may consult internal cached state. We cast away const here
    // as we only perform read-only queries in practice.
    NNUE_DEBUG_PRINT("Extracting features...");
    extract_features(const_cast<Position&>(pos), features_);

    // Count active features for debugging
    int active_features = 0;
    for (int i = 0; i < FEATURE_SIZE; i++) {
        if (features_[i]) active_features++;
    }
    NNUE_DEBUG_PRINTF("Active features: %d/%d", active_features, FEATURE_SIZE);

    // Perspective A (as-is, from white's perspective)
    NNUE_DEBUG_PRINT("Computing white perspective hidden layer...");
    activate_hidden(features_, hidden_white_);

    // Perspective B (swap piece-placement features for black's perspective).
    // Keep all non-placement features identical so that phase/count/mobility
    // features remain consistent between perspectives.
    NNUE_DEBUG_PRINT("Creating color-swapped features for black perspective...");
    bool swapped_features[FEATURE_SIZE];
    std::memcpy(swapped_features, features_, sizeof(swapped_features));

    // Swap the 24-square piece placement features between white and black
    // indices defined in nnue_features.h
    for (int i = 0; i < SQUARE_NB; i++) {
        const int w_idx = FeatureIndices::WHITE_PIECES_START + i;
        const int b_idx = FeatureIndices::BLACK_PIECES_START + i;
        const bool tmp = swapped_features[w_idx];
        swapped_features[w_idx] = swapped_features[b_idx];
        swapped_features[b_idx] = tmp;
    }

    NNUE_DEBUG_PRINT("Computing black perspective hidden layer...");
    activate_hidden(swapped_features, hidden_black_);

    // Compute final output
    NNUE_DEBUG_PRINT("Computing final output...");
    int32_t result = compute_output(hidden_white_, hidden_black_, pos.side_to_move());
    
    NNUE_DEBUG_PRINTF("Forward pass raw output: %d", result);
    return result;
}

void NNUEEvaluator::extract_features(Position& pos, bool* features) {
    // Use the advanced feature extractor (requires non-const Position)
    FeatureExtractor::extract_features(pos, features);
}

void NNUEEvaluator::activate_hidden(const bool* features, int16_t* hidden) {
    // Compute hidden layer activation using SIMD-like operations
    int active_neurons = 0;
    int64_t total_activation = 0;
    
    for (int h = 0; h < HIDDEN_SIZE; h++) {
        int64_t sum = static_cast<int64_t>(weights_.input_biases[h]);  // Use 64-bit to prevent overflow
        
        // Accumulate weights for active features
        for (int f = 0; f < FEATURE_SIZE; f++) {
            if (features[f]) {
                sum += static_cast<int64_t>(weights_.input_weights[f * HIDDEN_SIZE + h]);
            }
        }
        
        // Apply ReLU activation with proper clamping
        hidden[h] = relu(static_cast<int32_t>(std::max<int64_t>(
            std::min<int64_t>(sum, std::numeric_limits<int32_t>::max()),
            std::numeric_limits<int32_t>::min())));
        
        if (hidden[h] > 0) {
            active_neurons++;
            total_activation += hidden[h];
        }
    }
    
    NNUE_DEBUG_PRINTF("Hidden layer: %d/%d active neurons, avg activation: %lld", 
                      active_neurons, HIDDEN_SIZE, 
                      active_neurons > 0 ? total_activation / active_neurons : 0);
}

int32_t NNUEEvaluator::compute_output(const int16_t* hidden_white, 
                                     const int16_t* hidden_black, 
                                     Color side_to_move) {
    NNUE_DEBUG_PRINTF("Computing output for side: %s", side_to_move == WHITE ? "WHITE" : "BLACK");
    
    // Accumulate in 64-bit to avoid overflow at extreme values, then clamp.
    int64_t sum = static_cast<int64_t>(weights_.output_bias);
    NNUE_DEBUG_PRINTF("Output bias: %d", weights_.output_bias);
    
    // Choose perspective based on side to move
    const int16_t* current_hidden = (side_to_move == WHITE) ? hidden_white : hidden_black;
    const int16_t* opponent_hidden = (side_to_move == WHITE) ? hidden_black : hidden_white;
    
    int64_t current_contribution = 0;
    int64_t opponent_contribution = 0;
    
    // Combine both perspectives
    for (int i = 0; i < HIDDEN_SIZE; i++) {
        int64_t current_term = static_cast<int64_t>(current_hidden[i]) * static_cast<int64_t>(weights_.output_weights[i]);
        int64_t opponent_term = static_cast<int64_t>(opponent_hidden[i]) * static_cast<int64_t>(weights_.output_weights[i + HIDDEN_SIZE]);
        
        current_contribution += current_term;
        opponent_contribution += opponent_term;
        sum += current_term + opponent_term;
    }

    NNUE_DEBUG_PRINTF("Current side contribution: %lld", current_contribution);
    NNUE_DEBUG_PRINTF("Opponent side contribution: %lld", opponent_contribution);
    NNUE_DEBUG_PRINTF("Total sum before clamping: %lld", sum);

    // Clamp to 32-bit range before returning
    bool clamped = false;
    if (sum > std::numeric_limits<int32_t>::max()) {
        sum = std::numeric_limits<int32_t>::max();
        clamped = true;
    }
    if (sum < std::numeric_limits<int32_t>::min()) {
        sum = std::numeric_limits<int32_t>::min();
        clamped = true;
    }
    
    if (clamped) {
        NNUE_DEBUG_PRINT("WARNING: Output sum was clamped to 32-bit range");
    }
    
    NNUE_DEBUG_PRINTF("Final output: %d", static_cast<int32_t>(sum));
    return static_cast<int32_t>(sum);
}

Value NNUEEvaluator::nnue_to_value(int32_t nnue_output) {
    // Convert NNUE output to centipawn scale
    // NNUE output is typically in range [-32768, 32767]
    // We want to map this to reasonable evaluation range
    
    constexpr int32_t NNUE_SCALE = 16;
    int32_t value_scaled = nnue_output / NNUE_SCALE;

    // Clamp to reasonable evaluation bounds using engine Value range
    // Cast carefully to avoid truncation before clamping
    int32_t clamped = std::max<int32_t>(-VALUE_MATE + 1,
                                        std::min<int32_t>(VALUE_MATE - 1,
                                                          value_scaled));
    return static_cast<Value>(clamped);
}

Value NNUEEvaluator::evaluate_with_symmetries(const Position& pos) {
    // Use symmetry-aware evaluation that finds the canonical form
    // and evaluates using the most representative transformation
    
    NNUE_DEBUG_PRINT("Starting symmetry-aware evaluation...");
    
    // Find the canonical symmetry operation for this position
    SymmetryOp canonical_op = SymmetryAwareNNUE::find_canonical_symmetry(pos);
    NNUE_DEBUG_PRINTF("Canonical symmetry operation: %d", static_cast<int>(canonical_op));
    
    // Extract features using the canonical transformation
    bool canonical_features[FEATURE_SIZE];
    Position pos_copy = pos;
    NNUE_DEBUG_PRINT("Extracting canonical features...");
    SymmetryTransforms::extract_symmetry_features(pos_copy, canonical_features, canonical_op);
    
    // Count canonical features
    int canonical_active = 0;
    for (int i = 0; i < FEATURE_SIZE; i++) {
        if (canonical_features[i]) canonical_active++;
    }
    NNUE_DEBUG_PRINTF("Canonical features active: %d/%d", canonical_active, FEATURE_SIZE);
    
    // Evaluate using canonical features
    int16_t hidden_white[HIDDEN_SIZE];
    int16_t hidden_black[HIDDEN_SIZE];
    
    // For canonical evaluation, we still need both perspectives
    NNUE_DEBUG_PRINT("Computing canonical white perspective...");
    activate_hidden(canonical_features, hidden_white);
    
    // Create color-swapped version for black perspective
    bool swapped_features[FEATURE_SIZE];
    std::memcpy(swapped_features, canonical_features, sizeof(swapped_features));
    
    // Swap the piece placement features between white and black
    for (int i = 0; i < SQUARE_NB; i++) {
        const int w_idx = FeatureIndices::WHITE_PIECES_START + i;
        const int b_idx = FeatureIndices::BLACK_PIECES_START + i;
        const bool tmp = swapped_features[w_idx];
        swapped_features[w_idx] = swapped_features[b_idx];
        swapped_features[b_idx] = tmp;
    }
    
    NNUE_DEBUG_PRINT("Computing canonical black perspective...");
    activate_hidden(swapped_features, hidden_black);
    
    // Compute final output
    NNUE_DEBUG_PRINT("Computing canonical output...");
    int32_t raw_output = compute_output(hidden_white, hidden_black, pos.side_to_move());
    
    // If we used a color-swapping transformation, negate the result
    bool color_swapped = SymmetryTransforms::swaps_colors(canonical_op);
    NNUE_DEBUG_PRINTF("Color swapped: %s", color_swapped ? "true" : "false");
    
    if (color_swapped) {
        NNUE_DEBUG_PRINTF("Negating output due to color swap: %d -> %d", raw_output, -raw_output);
        raw_output = -raw_output;
    }
    
    Value final_value = nnue_to_value(raw_output);
    NNUE_DEBUG_PRINTF("Final converted value: %d", static_cast<int>(final_value));
    
    return final_value;
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
    NNUE_DEBUG_PRINT("Loading NNUE model from: " << filepath);
    
    std::ifstream file(filepath, std::ios::binary);
    if (!file.is_open()) {
        NNUE_DEBUG_PRINT("ERROR: Failed to open model file");
        std::cerr << "Failed to open NNUE model file: " << filepath << std::endl;
        return false;
    }
    
    // Read model header
    char header[8];
    file.read(header, 8);
    if (!file || std::string(header, 8) != "SANMILL1") {
        NNUE_DEBUG_PRINT("ERROR: Invalid model header");
        std::cerr << "Invalid NNUE model format" << std::endl;
        file.close();
        return false;
    }
    NNUE_DEBUG_PRINT("Model header verified: SANMILL1");

    // Read and validate dimensions (feature_size, hidden_size)
    int32_t file_feature_size = 0;
    int32_t file_hidden_size = 0;
    file.read(reinterpret_cast<char*>(&file_feature_size), sizeof(int32_t));
    file.read(reinterpret_cast<char*>(&file_hidden_size), sizeof(int32_t));

    if (!file) {
        NNUE_DEBUG_PRINT("ERROR: Failed to read model dimensions");
        std::cerr << "Failed to read NNUE model dimensions" << std::endl;
        file.close();
        return false;
    }
    
    NNUE_DEBUG_PRINTF("Model dimensions: %d features, %d hidden", file_feature_size, file_hidden_size);
    NNUE_DEBUG_PRINTF("Expected dimensions: %d features, %d hidden", FEATURE_SIZE, HIDDEN_SIZE);

    if (file_feature_size != FEATURE_SIZE || file_hidden_size != HIDDEN_SIZE) {
        NNUE_DEBUG_PRINT("ERROR: Dimension mismatch");
        std::cerr << "NNUE model dimensions mismatch (model="
                  << file_feature_size << "," << file_hidden_size
                  << ", expected=" << FEATURE_SIZE << "," << HIDDEN_SIZE
                  << ")" << std::endl;
        file.close();
        return false;
    }
    
    NNUE_DEBUG_PRINT("Dimensions verified, loading weights...");
    
    // Read weights field-by-field to avoid issues with structure padding/alignment
    file.read(reinterpret_cast<char*>(weights_.input_weights), sizeof(weights_.input_weights));
    NNUE_DEBUG_PRINTF("Loaded %zu input weights", sizeof(weights_.input_weights) / sizeof(weights_.input_weights[0]));
    
    file.read(reinterpret_cast<char*>(weights_.input_biases), sizeof(weights_.input_biases));
    NNUE_DEBUG_PRINTF("Loaded %zu input biases", sizeof(weights_.input_biases) / sizeof(weights_.input_biases[0]));
    
    file.read(reinterpret_cast<char*>(weights_.output_weights), sizeof(weights_.output_weights));
    NNUE_DEBUG_PRINTF("Loaded %zu output weights", sizeof(weights_.output_weights) / sizeof(weights_.output_weights[0]));
    
    file.read(reinterpret_cast<char*>(&weights_.output_bias), sizeof(weights_.output_bias));
    NNUE_DEBUG_PRINTF("Loaded output bias: %d", weights_.output_bias);
    
    if (!file) {
        NNUE_DEBUG_PRINT("ERROR: Failed to read model weights");
        std::cerr << "Failed to read NNUE model weights" << std::endl;
        file.close();
        return false;
    }
    
    file.close();
    model_loaded_ = true;
    
    NNUE_DEBUG_PRINT("Model loaded successfully!");
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
    
    if (!file) {
        std::cerr << "Failed to write NNUE model" << std::endl;
        file.close();
        return false;
    }
    
    file.close();
    std::cout << "Successfully saved NNUE model to " << filepath << std::endl;
    return true;
}

// Debug control functions
void set_nnue_debug(bool enabled) {
    g_nnue_debug_enabled = enabled;
    NNUE_DEBUG_PRINTF("NNUE debug %s", enabled ? "ENABLED" : "DISABLED");
}

bool get_nnue_debug() {
    return g_nnue_debug_enabled;
}

} // namespace NNUE
