#!/usr/bin/env python3
"""
Create a test NNUE model for GUI testing
This creates a small, functional NNUE model that can be used to test the GUI
"""

import torch
import os
import struct
import numpy as np
from train_nnue import MillNNUE

def create_test_pytorch_model(filename='test_nnue_model.pth'):
    """Create a test PyTorch NNUE model"""
    print(f"Creating test PyTorch model: {filename}")
    
    # Create model with small size for testing
    model = MillNNUE(feature_size=115, hidden_size=64)
    
    # Initialize with reasonable weights for testing
    with torch.no_grad():
        # Small random weights
        model.input_to_hidden.weight.normal_(0, 0.1)
        model.input_to_hidden.bias.zero_()
        model.hidden_to_output.weight.normal_(0, 0.1)
        model.hidden_to_output.bias.zero_()
    
    # Save model
    torch.save({
        'model_state_dict': model.state_dict(),
        'feature_size': 115,
        'hidden_size': 64,
        'epoch': 0,
        'test_model': True
    }, filename)
    
    print(f"✅ Created {filename} ({os.path.getsize(filename) / 1024:.1f} KB)")
    return filename

def create_test_binary_model(filename='test_nnue_model.bin'):
    """Create a test binary NNUE model with SANMILL header"""
    print(f"Creating test binary model: {filename}")
    
    feature_size = 115
    hidden_size = 64
    
    # Create small random weights for testing
    np.random.seed(42)  # For reproducible test models
    
    # Input layer weights and biases
    input_weights = np.random.randn(hidden_size, feature_size).astype(np.float32) * 0.1
    input_biases = np.zeros(hidden_size, dtype=np.float32)
    
    # Output layer weights and bias
    output_weights = np.random.randn(1, hidden_size * 2).astype(np.float32) * 0.1
    output_bias = 0.0
    
    # Quantize to integer formats (as expected by C++ engine)
    input_weights_int16 = (input_weights * 127).astype(np.int16)
    input_biases_int32 = (input_biases * 127).astype(np.int32)
    output_weights_int8 = (output_weights * 127).astype(np.int8)
    output_bias_int32 = int(output_bias * 127)
    
    with open(filename, 'wb') as f:
        # Write header
        f.write(b'SANMILL1')
        
        # Write dimensions
        f.write(struct.pack('<II', feature_size, hidden_size))
        
        # Write input weights (feature_size * hidden_size * int16)
        f.write(input_weights_int16.tobytes())
        
        # Write input biases (hidden_size * int32)
        f.write(input_biases_int32.tobytes())
        
        # Write output weights (hidden_size * 2 * int8)
        f.write(output_weights_int8.tobytes())
        
        # Write output bias (1 * int32)
        f.write(struct.pack('<i', output_bias_int32))
    
    print(f"✅ Created {filename} ({os.path.getsize(filename) / 1024:.1f} KB)")
    return filename

def create_fake_files():
    """Create some fake files that should be filtered out"""
    print("Creating fake files that should be filtered out...")
    
    fake_files = [
        'CMakeDetermineCompilerABI_C.bin',
        'AssetManifest.bin',
        'kernel_blob.bin',
        'graph.bin'
    ]
    
    for fake_file in fake_files:
        with open(fake_file, 'wb') as f:
            f.write(b'FAKE_FILE_NOT_NNUE' + b'\x00' * 1000)
        print(f"  Created fake file: {fake_file}")
    
    return fake_files

def test_model_detection():
    """Test the model detection function"""
    print("\nTesting model detection...")
    
    # Import the detection function
    import sys
    sys.path.insert(0, '.')
    from start_nnue_gui import find_nnue_models, _is_likely_nnue_model
    
    # Find models
    models = find_nnue_models(search_dirs=['.'])
    
    print(f"Found {len(models)} NNUE models:")
    for model in models:
        is_valid = _is_likely_nnue_model(model)
        size_kb = os.path.getsize(model) / 1024
        print(f"  ✅ {model} ({size_kb:.1f} KB) - Valid: {is_valid}")

def main():
    print("NNUE Test Model Creator")
    print("=" * 40)
    
    # Create test models
    pytorch_file = create_test_pytorch_model()
    binary_file = create_test_binary_model()
    
    # Create fake files to test filtering
    fake_files = create_fake_files()
    
    # Test detection
    test_model_detection()
    
    print("\nTest models created successfully!")
    print(f"You can now test the GUI with:")
    print(f"  python nnue_pit.py --model {pytorch_file} --gui")
    print(f"  python nnue_pit.py --model {binary_file} --gui")
    print(f"  python start_nnue_gui.py --list-models")
    
    print("\nTo clean up test files:")
    print(f"  del {pytorch_file} {binary_file}")
    for fake_file in fake_files:
        print(f"  del {fake_file}")

if __name__ == '__main__':
    main()
