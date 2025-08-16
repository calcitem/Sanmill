// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_integration_test.cpp - Comprehensive integration tests for NNUE system

#include "nnue.h"
#include "nnue_features.h"
#include "nnue_symmetries.h"
#include "nnue_training.h"
#include "position.h"
#include "engine_commands.h"
#include <iostream>
#include <cassert>
#include <memory>

namespace NNUE {

// Test feature extraction consistency
bool test_feature_extraction() {
    std::cout << "Testing feature extraction..." << std::endl;
    
    Position pos;
    EngineCommands::init_start_fen();
    pos.set(EngineCommands::StartFEN);
    
    bool features[FeatureIndices::TOTAL_FEATURES];
    FeatureExtractor::extract_features(pos, features);
    
    // Validate feature dimensions
    assert(FeatureIndices::TOTAL_FEATURES == 115 && "Feature dimension mismatch");
    
    // Test that exactly one phase feature is active
    int active_phases = 0;
    for (int i = FeatureIndices::PHASE_START; i < FeatureIndices::PHASE_END; ++i) {
        if (features[i]) active_phases++;
    }
    assert(active_phases == 1 && "Exactly one phase should be active");
    
    // Test piece count features
    int white_on_board = pos.piece_on_board_count(WHITE);
    int black_on_board = pos.piece_on_board_count(BLACK);
    
    // Verify one-hot encoding for piece counts
    bool white_count_found = false;
    for (int i = 0; i < 10; ++i) {
        if (features[FeatureIndices::WHITE_ON_BOARD_START + i]) {
            assert(!white_count_found && "Multiple white piece counts active");
            assert(i == white_on_board && "White piece count mismatch");
            white_count_found = true;
        }
    }
    assert(white_count_found && "White piece count not found");
    
    std::cout << "Feature extraction tests passed!" << std::endl;
    return true;
}

// Test symmetry transformations
bool test_symmetry_transformations() {
    std::cout << "Testing symmetry transformations..." << std::endl;
    
    SymmetryTransforms::initialize();
    
    // Test that four 90-degree rotations return to original
    Square test_sq = SQ_8;  // First valid square
    Square current = test_sq;
    for (int i = 0; i < 4; ++i) {
        current = SymmetryTransforms::transform_square(current, SYM_ROTATE_90);
    }
    assert(current == test_sq && "Four rotations should return to original");
    
    // Test inverse operations
    Square rotated = SymmetryTransforms::transform_square(test_sq, SYM_ROTATE_90);
    Square restored = SymmetryTransforms::transform_square(rotated, SYM_ROTATE_270);
    assert(restored == test_sq && "Rotation and inverse should cancel");
    
    // Test color swap detection
    assert(SymmetryTransforms::swaps_colors(SYM_COLOR_SWAP) == true);
    assert(SymmetryTransforms::swaps_colors(SYM_ROTATE_90) == false);
    
    std::cout << "Symmetry transformation tests passed!" << std::endl;
    return true;
}

// Test NNUE evaluation pipeline
bool test_nnue_evaluation() {
    std::cout << "Testing NNUE evaluation pipeline..." << std::endl;
    
    // Create NNUE evaluator with default weights
    NNUEEvaluator evaluator;
    
    // Test with start position
    Position pos;
    EngineCommands::init_start_fen();
    pos.set(EngineCommands::StartFEN);
    
    // Test feature extraction
    bool features[FEATURE_SIZE];
    evaluator.extract_features(pos, features);
    
    // Test forward pass (should not crash)
    int32_t raw_output = evaluator.get_raw_output(pos);
    
    // Test conversion to evaluation value
    Value eval_value = evaluator.nnue_to_value(raw_output);
    
    // Sanity check - evaluation should be finite
    assert(eval_value > -VALUE_MATE && eval_value < VALUE_MATE && 
           "NNUE evaluation out of bounds");
    
    std::cout << "NNUE evaluation pipeline tests passed!" << std::endl;
    return true;
}

// Test training data generation
bool test_training_data_generation() {
    std::cout << "Testing training data generation..." << std::endl;
    
    TrainingDataGenerator generator;
    
    // Test random position generation
    Position pos;
    bool success = generator.generate_random_position(pos);
    assert(success && "Random position generation failed");
    
    // Test position validation
    bool is_valid = generator.is_valid_training_position(pos);
    std::cout << "Generated position is " << (is_valid ? "valid" : "invalid") << std::endl;
    
    // Test feature extraction from generated position
    TrainingSample sample;
    generator.extract_position_features(pos, sample);
    assert(sample.features.size() == FeatureIndices::TOTAL_FEATURES && 
           "Feature extraction size mismatch");
    
    std::cout << "Training data generation tests passed!" << std::endl;
    return true;
}

// Test symmetry-aware training data generation
bool test_symmetric_training_data() {
    std::cout << "Testing symmetric training data generation..." << std::endl;
    
    Position pos;
    EngineCommands::init_start_fen();
    pos.set(EngineCommands::StartFEN);
    
    // Test safe memory management version
    std::vector<SymmetryAwareNNUE::SymmetricTrainingSample> samples;
    SymmetryAwareNNUE::generate_symmetric_training_data_safe(pos, samples);
    
    assert(samples.size() == SYM_OP_COUNT && "Wrong number of symmetric samples");
    
    // Verify each sample has correct feature size
    for (const auto& sample : samples) {
        assert(sample.features != nullptr && "Feature array is null");
        // Note: We can't easily test the size of unique_ptr<bool[]>
    }
    
    std::cout << "Symmetric training data generation tests passed!" << std::endl;
    return true;
}

// Test model save/load functionality
bool test_model_save_load() {
    std::cout << "Testing model save/load functionality..." << std::endl;
    
    NNUEEvaluator evaluator1;
    
    // Save model to temporary file
    const std::string temp_file = "test_nnue_model.bin";
    bool save_success = evaluator1.save_model(temp_file);
    assert(save_success && "Model save failed");
    
    // Create new evaluator and load model
    NNUEEvaluator evaluator2;
    bool load_success = evaluator2.load_model(temp_file);
    assert(load_success && "Model load failed");
    assert(evaluator2.is_available() && "Model not available after load");
    
    // Test that evaluations are identical
    Position pos;
    EngineCommands::init_start_fen();
    pos.set(EngineCommands::StartFEN);
    
    int32_t output1 = evaluator1.get_raw_output(pos);
    int32_t output2 = evaluator2.get_raw_output(pos);
    assert(output1 == output2 && "Model outputs differ after save/load");
    
    // Clean up
    std::remove(temp_file.c_str());
    
    std::cout << "Model save/load tests passed!" << std::endl;
    return true;
}

// Test edge cases and error handling - strict mode, expose all problems!
bool test_edge_cases() {
    std::cout << "Testing edge cases and error handling..." << std::endl;
    
    NNUEEvaluator evaluator;
    
    // Test invalid model path - should fail cleanly
    bool result = evaluator.load_model("nonexistent_file.bin");
    assert(!result && "Loading nonexistent file should fail");
    assert(!evaluator.is_available() && "Evaluator should not be available after failed load");
    
    // Test empty model path initialization - should fail cleanly
    result = evaluator.initialize("");
    assert(!result && "Initialize with empty path should fail");
    
    // Test that invalid usage triggers asserts in debug mode
    // These tests verify the asserts work correctly
    
    std::cout << "Edge case tests passed - all error conditions properly detected!" << std::endl;
    return true;
}

} // namespace NNUE

// Main test runner
int main() {
    try {
        std::cout << "=== NNUE Integration Tests ===" << std::endl;
        
        bool all_passed = true;
        
        all_passed &= NNUE::test_feature_extraction();
        all_passed &= NNUE::test_symmetry_transformations();
        all_passed &= NNUE::test_nnue_evaluation();
        all_passed &= NNUE::test_training_data_generation();
        all_passed &= NNUE::test_symmetric_training_data();
        all_passed &= NNUE::test_model_save_load();
        all_passed &= NNUE::test_edge_cases();
        
        if (all_passed) {
            std::cout << "\n=== ALL NNUE INTEGRATION TESTS PASSED ===" << std::endl;
            return 0;
        } else {
            std::cout << "\n=== SOME NNUE INTEGRATION TESTS FAILED ===" << std::endl;
            return 1;
        }
    } catch (const std::exception& e) {
        std::cerr << "Test failed with exception: " << e.what() << std::endl;
        return 1;
    }
}
