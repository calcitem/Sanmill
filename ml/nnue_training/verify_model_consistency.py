#!/usr/bin/env python3
"""
NNUE Model Consistency Verification Script for Sanmill

This script verifies that Python-exported NNUE models and C++-saved models
are byte-identical at the field level, ensuring end-to-end compatibility
between the training pipeline and the C++ engine.

Usage:
    python verify_model_consistency.py model1.bin model2.bin
    python verify_model_consistency.py --analyze model.bin
"""

import argparse
import struct
import sys
import os
import numpy as np
from typing import Tuple, Dict, Any, Optional
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class NNUEModelReader:
    """
    Reader for NNUE model binary files that matches the C++ NNUEWeights structure.
    
    Expected binary layout:
    1. Header: "SANMILL1" (8 bytes)
    2. Dimensions: feature_size (4 bytes), hidden_size (4 bytes)
    3. Input weights: feature_size * hidden_size * int16 (2 bytes each)
    4. Input biases: hidden_size * int32 (4 bytes each)
    5. Output weights: hidden_size * 2 * int8 (1 byte each)
    6. Output bias: 1 * int32 (4 bytes)
    """
    
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.header = None
        self.feature_size = None
        self.hidden_size = None
        self.input_weights = None
        self.input_biases = None
        self.output_weights = None
        self.output_bias = None
        self.file_size = None
        
    def read_model(self) -> bool:
        """
        Read and parse the NNUE model file.
        
        Returns:
            True if the model was successfully read, False otherwise.
        """
        try:
            if not os.path.exists(self.filepath):
                logger.error(f"Model file not found: {self.filepath}")
                return False
                
            self.file_size = os.path.getsize(self.filepath)
            logger.info(f"Reading model file: {self.filepath} ({self.file_size} bytes)")
            
            with open(self.filepath, 'rb') as f:
                # Read header
                self.header = f.read(8)
                if self.header != b'SANMILL1':
                    logger.error(f"Invalid header: {self.header}")
                    return False
                    
                # Read dimensions
                dimensions_data = f.read(8)
                if len(dimensions_data) != 8:
                    logger.error("Failed to read dimensions")
                    return False
                    
                self.feature_size, self.hidden_size = struct.unpack('<II', dimensions_data)
                logger.info(f"Model dimensions: feature_size={self.feature_size}, hidden_size={self.hidden_size}")
                
                # Calculate expected sizes
                input_weights_size = self.feature_size * self.hidden_size * 2  # int16
                input_biases_size = self.hidden_size * 4  # int32
                output_weights_size = self.hidden_size * 2 * 1  # int8
                output_bias_size = 4  # int32
                
                expected_total_size = 8 + 8 + input_weights_size + input_biases_size + output_weights_size + output_bias_size
                
                if self.file_size != expected_total_size:
                    logger.warning(f"File size mismatch: expected {expected_total_size}, got {self.file_size}")
                
                # Read input weights
                input_weights_data = f.read(input_weights_size)
                if len(input_weights_data) != input_weights_size:
                    logger.error(f"Failed to read input weights: expected {input_weights_size}, got {len(input_weights_data)}")
                    return False
                    
                self.input_weights = np.frombuffer(input_weights_data, dtype=np.int16)
                self.input_weights = self.input_weights.reshape(self.feature_size, self.hidden_size)
                
                # Read input biases
                input_biases_data = f.read(input_biases_size)
                if len(input_biases_data) != input_biases_size:
                    logger.error(f"Failed to read input biases: expected {input_biases_size}, got {len(input_biases_data)}")
                    return False
                    
                self.input_biases = np.frombuffer(input_biases_data, dtype=np.int32)
                
                # Read output weights
                output_weights_data = f.read(output_weights_size)
                if len(output_weights_data) != output_weights_size:
                    logger.error(f"Failed to read output weights: expected {output_weights_size}, got {len(output_weights_data)}")
                    return False
                    
                self.output_weights = np.frombuffer(output_weights_data, dtype=np.int8)
                
                # Read output bias
                output_bias_data = f.read(output_bias_size)
                if len(output_bias_data) != output_bias_size:
                    logger.error(f"Failed to read output bias: expected {output_bias_size}, got {len(output_bias_data)}")
                    return False
                    
                self.output_bias = struct.unpack('<i', output_bias_data)[0]
                
                # Check if we've read the entire file
                remaining_data = f.read()
                if remaining_data:
                    logger.warning(f"Extra data at end of file: {len(remaining_data)} bytes")
                    
                return True
                
        except Exception as e:
            logger.error(f"Error reading model file {self.filepath}: {e}")
            return False
    
    def get_statistics(self) -> Dict[str, Any]:
        """
        Get statistics about the loaded model.
        
        Returns:
            Dictionary containing model statistics.
        """
        if self.input_weights is None:
            return {}
            
        stats = {
            'file_size': self.file_size,
            'feature_size': self.feature_size,
            'hidden_size': self.hidden_size,
            'input_weights_shape': self.input_weights.shape,
            'input_weights_range': (int(self.input_weights.min()), int(self.input_weights.max())),
            'input_weights_mean': float(self.input_weights.mean()),
            'input_weights_std': float(self.input_weights.std()),
            'input_biases_shape': self.input_biases.shape,
            'input_biases_range': (int(self.input_biases.min()), int(self.input_biases.max())),
            'input_biases_mean': float(self.input_biases.mean()),
            'input_biases_std': float(self.input_biases.std()),
            'output_weights_shape': self.output_weights.shape,
            'output_weights_range': (int(self.output_weights.min()), int(self.output_weights.max())),
            'output_weights_mean': float(self.output_weights.mean()),
            'output_weights_std': float(self.output_weights.std()),
            'output_bias': int(self.output_bias),
        }
        
        return stats


def compare_models(model1_path: str, model2_path: str) -> bool:
    """
    Compare two NNUE model files for byte-level consistency.
    
    Args:
        model1_path: Path to the first model file
        model2_path: Path to the second model file
        
    Returns:
        True if models are identical, False otherwise
    """
    logger.info(f"Comparing models:")
    logger.info(f"  Model 1: {model1_path}")
    logger.info(f"  Model 2: {model2_path}")
    
    # Read both models
    reader1 = NNUEModelReader(model1_path)
    reader2 = NNUEModelReader(model2_path)
    
    if not reader1.read_model():
        logger.error(f"Failed to read model 1: {model1_path}")
        return False
        
    if not reader2.read_model():
        logger.error(f"Failed to read model 2: {model2_path}")
        return False
    
    # Compare dimensions
    if reader1.feature_size != reader2.feature_size:
        logger.error(f"Feature size mismatch: {reader1.feature_size} vs {reader2.feature_size}")
        return False
        
    if reader1.hidden_size != reader2.hidden_size:
        logger.error(f"Hidden size mismatch: {reader1.hidden_size} vs {reader2.hidden_size}")
        return False
    
    # Compare input weights
    if not np.array_equal(reader1.input_weights, reader2.input_weights):
        logger.error("Input weights are not identical")
        diff_mask = reader1.input_weights != reader2.input_weights
        num_diffs = np.sum(diff_mask)
        total_elements = reader1.input_weights.size
        logger.error(f"  Differences: {num_diffs}/{total_elements} elements ({100.0 * num_diffs / total_elements:.2f}%)")
        
        # Show first few differences
        diff_indices = np.where(diff_mask)
        if len(diff_indices[0]) > 0:
            for i in range(min(5, len(diff_indices[0]))):
                idx = (diff_indices[0][i], diff_indices[1][i])
                val1 = reader1.input_weights[idx]
                val2 = reader2.input_weights[idx]
                logger.error(f"    Position {idx}: {val1} vs {val2}")
        return False
    
    # Compare input biases
    if not np.array_equal(reader1.input_biases, reader2.input_biases):
        logger.error("Input biases are not identical")
        diff_mask = reader1.input_biases != reader2.input_biases
        num_diffs = np.sum(diff_mask)
        logger.error(f"  Differences: {num_diffs}/{len(reader1.input_biases)} elements")
        return False
    
    # Compare output weights
    if not np.array_equal(reader1.output_weights, reader2.output_weights):
        logger.error("Output weights are not identical")
        diff_mask = reader1.output_weights != reader2.output_weights
        num_diffs = np.sum(diff_mask)
        logger.error(f"  Differences: {num_diffs}/{len(reader1.output_weights)} elements")
        return False
    
    # Compare output bias
    if reader1.output_bias != reader2.output_bias:
        logger.error(f"Output bias mismatch: {reader1.output_bias} vs {reader2.output_bias}")
        return False
    
    logger.info("✓ Models are byte-identical at field level")
    return True


def analyze_model(model_path: str) -> None:
    """
    Analyze and display detailed information about a single model file.
    
    Args:
        model_path: Path to the model file to analyze
    """
    logger.info(f"Analyzing model: {model_path}")
    
    reader = NNUEModelReader(model_path)
    if not reader.read_model():
        logger.error(f"Failed to read model: {model_path}")
        return
    
    stats = reader.get_statistics()
    
    print("\n" + "="*60)
    print(f"NNUE Model Analysis: {os.path.basename(model_path)}")
    print("="*60)
    
    print(f"File size: {stats['file_size']:,} bytes")
    print(f"Feature size: {stats['feature_size']}")
    print(f"Hidden size: {stats['hidden_size']}")
    
    print(f"\nInput Weights:")
    print(f"  Shape: {stats['input_weights_shape']}")
    print(f"  Range: [{stats['input_weights_range'][0]}, {stats['input_weights_range'][1]}]")
    print(f"  Mean: {stats['input_weights_mean']:.2f}")
    print(f"  Std: {stats['input_weights_std']:.2f}")
    
    print(f"\nInput Biases:")
    print(f"  Shape: {stats['input_biases_shape']}")
    print(f"  Range: [{stats['input_biases_range'][0]}, {stats['input_biases_range'][1]}]")
    print(f"  Mean: {stats['input_biases_mean']:.2f}")
    print(f"  Std: {stats['input_biases_std']:.2f}")
    
    print(f"\nOutput Weights:")
    print(f"  Shape: {stats['output_weights_shape']}")
    print(f"  Range: [{stats['output_weights_range'][0]}, {stats['output_weights_range'][1]}]")
    print(f"  Mean: {stats['output_weights_mean']:.2f}")
    print(f"  Std: {stats['output_weights_std']:.2f}")
    
    print(f"\nOutput Bias: {stats['output_bias']}")
    
    # Calculate total parameters
    total_params = (stats['feature_size'] * stats['hidden_size'] + 
                   stats['hidden_size'] + 
                   stats['hidden_size'] * 2 + 
                   1)
    print(f"\nTotal parameters: {total_params:,}")
    
    print("="*60)


def verify_file_integrity(model_path: str) -> bool:
    """
    Verify the basic integrity of a model file (header, dimensions, size).
    
    Args:
        model_path: Path to the model file
        
    Returns:
        True if file passes basic integrity checks
    """
    reader = NNUEModelReader(model_path)
    success = reader.read_model()
    
    if success:
        logger.info(f"✓ File integrity check passed: {model_path}")
    else:
        logger.error(f"✗ File integrity check failed: {model_path}")
    
    return success


def main():
    parser = argparse.ArgumentParser(
        description='Verify NNUE model consistency between Python and C++ implementations',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compare two model files for byte-level consistency
  python verify_model_consistency.py model_python.bin model_cpp.bin
  
  # Analyze a single model file
  python verify_model_consistency.py --analyze model.bin
  
  # Check file integrity only
  python verify_model_consistency.py --verify model.bin
        """
    )
    
    parser.add_argument('model_files', nargs='*', help='Model file paths')
    parser.add_argument('--analyze', action='store_true', 
                       help='Analyze a single model file in detail')
    parser.add_argument('--verify', action='store_true',
                       help='Verify file integrity only')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    if args.analyze:
        if len(args.model_files) != 1:
            parser.error("--analyze requires exactly one model file")
        analyze_model(args.model_files[0])
        return 0
    
    if args.verify:
        if len(args.model_files) != 1:
            parser.error("--verify requires exactly one model file")
        success = verify_file_integrity(args.model_files[0])
        return 0 if success else 1
    
    # Default behavior: compare two models
    if len(args.model_files) != 2:
        parser.error("Comparison mode requires exactly two model files")
    
    success = compare_models(args.model_files[0], args.model_files[1])
    
    if success:
        print(f"\n✓ SUCCESS: Model files are byte-identical")
        return 0
    else:
        print(f"\n✗ FAILURE: Model files differ")
        return 1


if __name__ == '__main__':
    sys.exit(main())
