#!/usr/bin/env python3
"""
Example script demonstrating NNUE model consistency verification

This script shows how to use the verify_model_consistency.py tool to ensure
that Python-exported models and C++-saved models are identical.
"""

import os
import sys
import tempfile
import numpy as np
import torch
import torch.nn as nn
from train_nnue import MillNNUE, save_model_c_format
from verify_model_consistency import NNUEModelReader, compare_models, analyze_model
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_test_model(feature_size: int = 115, hidden_size: int = 256) -> MillNNUE:
    """
    Create a test NNUE model with deterministic weights for verification.
    
    Args:
        feature_size: Number of input features
        hidden_size: Size of hidden layer
        
    Returns:
        Initialized MillNNUE model
    """
    # Set seed for reproducible weights
    torch.manual_seed(42)
    np.random.seed(42)
    
    model = MillNNUE(feature_size=feature_size, hidden_size=hidden_size)
    
    # Initialize with small, predictable values
    with torch.no_grad():
        # Input layer: small random values
        nn.init.uniform_(model.input_to_hidden.weight, -0.1, 0.1)
        nn.init.zeros_(model.input_to_hidden.bias)
        
        # Output layer: small random values
        nn.init.uniform_(model.hidden_to_output.weight, -0.1, 0.1)
        nn.init.zeros_(model.hidden_to_output.bias)
    
    return model


def test_model_export_consistency():
    """
    Test that a model exported twice produces identical binary files.
    """
    logger.info("Testing model export consistency...")
    
    # Create test model
    model = create_test_model()
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Export model twice
        model_path1 = os.path.join(temp_dir, "test_model_1.bin")
        model_path2 = os.path.join(temp_dir, "test_model_2.bin")
        
        save_model_c_format(model, model_path1)
        save_model_c_format(model, model_path2)
        
        # Compare the files
        if compare_models(model_path1, model_path2):
            logger.info("✓ Export consistency test PASSED")
            return True
        else:
            logger.error("✗ Export consistency test FAILED")
            return False


def test_model_roundtrip():
    """
    Test reading a model that was just exported to verify the format.
    """
    logger.info("Testing model roundtrip...")
    
    # Create test model with known properties
    feature_size, hidden_size = 115, 256
    model = create_test_model(feature_size, hidden_size)
    
    with tempfile.TemporaryDirectory() as temp_dir:
        model_path = os.path.join(temp_dir, "test_model.bin")
        
        # Export model
        save_model_c_format(model, model_path)
        
        # Read it back
        reader = NNUEModelReader(model_path)
        if not reader.read_model():
            logger.error("✗ Failed to read exported model")
            return False
        
        # Verify dimensions
        if reader.feature_size != feature_size:
            logger.error(f"✗ Feature size mismatch: {reader.feature_size} != {feature_size}")
            return False
            
        if reader.hidden_size != hidden_size:
            logger.error(f"✗ Hidden size mismatch: {reader.hidden_size} != {hidden_size}")
            return False
        
        # Verify shapes
        expected_input_shape = (feature_size, hidden_size)
        if reader.input_weights.shape != expected_input_shape:
            logger.error(f"✗ Input weights shape mismatch: {reader.input_weights.shape} != {expected_input_shape}")
            return False
        
        expected_output_shape = (hidden_size * 2,)
        if reader.output_weights.shape != expected_output_shape:
            logger.error(f"✗ Output weights shape mismatch: {reader.output_weights.shape} != {expected_output_shape}")
            return False
        
        logger.info("✓ Model roundtrip test PASSED")
        return True


def test_quantization_ranges():
    """
    Test that quantized values are within expected ranges.
    """
    logger.info("Testing quantization ranges...")
    
    model = create_test_model()
    
    with tempfile.TemporaryDirectory() as temp_dir:
        model_path = os.path.join(temp_dir, "test_model.bin")
        save_model_c_format(model, model_path)
        
        reader = NNUEModelReader(model_path)
        if not reader.read_model():
            logger.error("✗ Failed to read model for quantization test")
            return False
        
        # Check input weights (int16 range)
        if reader.input_weights.min() < -32767 or reader.input_weights.max() > 32767:
            logger.error(f"✗ Input weights out of int16 range: [{reader.input_weights.min()}, {reader.input_weights.max()}]")
            return False
        
        # Check input biases (int32 range - should be fine)
        if reader.input_biases.dtype != np.int32:
            logger.error(f"✗ Input biases wrong dtype: {reader.input_biases.dtype}")
            return False
        
        # Check output weights (int8 range)
        if reader.output_weights.min() < -127 or reader.output_weights.max() > 127:
            logger.error(f"✗ Output weights out of int8 range: [{reader.output_weights.min()}, {reader.output_weights.max()}]")
            return False
        
        # Check output bias (int32 - should be fine)
        if not (-2147483647 <= reader.output_bias <= 2147483647):
            logger.error(f"✗ Output bias out of int32 range: {reader.output_bias}")
            return False
        
        logger.info("✓ Quantization ranges test PASSED")
        return True


def demonstrate_analysis():
    """
    Demonstrate the model analysis functionality.
    """
    logger.info("Demonstrating model analysis...")
    
    model = create_test_model()
    
    with tempfile.TemporaryDirectory() as temp_dir:
        model_path = os.path.join(temp_dir, "demo_model.bin")
        save_model_c_format(model, model_path)
        
        # Analyze the model
        analyze_model(model_path)


def main():
    """
    Run all verification tests and demonstrations.
    """
    print("NNUE Model Consistency Verification Demo")
    print("=" * 50)
    
    tests = [
        test_model_export_consistency,
        test_model_roundtrip,
        test_quantization_ranges,
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            if test():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            logger.error(f"✗ Test {test.__name__} failed with exception: {e}")
            failed += 1
    
    print(f"\nTest Results: {passed} passed, {failed} failed")
    
    if failed == 0:
        print("\n🎉 All tests passed! The model export/import pipeline is working correctly.")
        
        print("\nDemonstrating model analysis:")
        demonstrate_analysis()
        
        print(f"\nUsage examples:")
        print(f"  # Compare two model files:")
        print(f"  python verify_model_consistency.py model1.bin model2.bin")
        print(f"  ")
        print(f"  # Analyze a single model:")
        print(f"  python verify_model_consistency.py --analyze model.bin")
        print(f"  ")
        print(f"  # Verify file integrity:")
        print(f"  python verify_model_consistency.py --verify model.bin")
        
    else:
        print(f"\n❌ Some tests failed. Please check the model export/import implementation.")
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
