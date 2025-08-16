# NNUE Model Verification Guide

This document describes the tools and procedures for verifying consistency between Python-exported NNUE models and C++-saved models to ensure end-to-end compatibility.

## Overview

The NNUE training pipeline involves:
1. **Python training**: Training the neural network using PyTorch
2. **Model export**: Converting PyTorch model to C++-compatible binary format
3. **C++ integration**: Loading the model in the Sanmill engine for evaluation

To ensure this pipeline works correctly, we provide verification tools that check byte-level consistency between Python and C++ model files.

## Verification Tools

### 1. Model Consistency Verifier (`verify_model_consistency.py`)

The main verification tool that can compare two model files or analyze a single model.

#### Usage Examples

```bash
# Compare two model files for byte-level consistency
python verify_model_consistency.py model_python.bin model_cpp.bin

# Analyze a single model file in detail
python verify_model_consistency.py --analyze model.bin

# Verify basic file integrity
python verify_model_consistency.py --verify model.bin

# Enable verbose logging
python verify_model_consistency.py -v model1.bin model2.bin
```

#### Features

- **Byte-level comparison**: Verifies that two model files are identical at the binary level
- **Model analysis**: Displays detailed statistics about model weights and structure
- **Integrity checking**: Validates file format, header, dimensions, and expected sizes
- **Error reporting**: Provides detailed information about any discrepancies found

### 2. Example Verification Script (`example_verification.py`)

A demonstration script that shows how to use the verification tools and runs automated tests.

```bash
# Run all verification tests
python example_verification.py
```

This script demonstrates:
- Export consistency (same model exported twice should be identical)
- Roundtrip verification (exported model can be read back correctly)
- Quantization range validation (all values within expected data type ranges)
- Model analysis functionality

## Model Binary Format

The NNUE model binary format follows this exact layout:

```
Header (8 bytes):           "SANMILL1"
Feature Size (4 bytes):     int32, number of input features (115)
Hidden Size (4 bytes):      int32, size of hidden layer (256)
Input Weights:              feature_size × hidden_size × int16
Input Biases:               hidden_size × int32
Output Weights:             (hidden_size × 2) × int8
Output Bias:                1 × int32
```

### Important Notes

- **Byte order**: Little-endian format is used for all multi-byte values
- **Alignment**: Fields are written sequentially without padding
- **Quantization**: 
  - Input weights/biases: scaled by 64.0 and converted to int16/int32
  - Output weights/bias: scaled by 127.0 and converted to int8/int32
- **Data types**: Must match exactly between Python export and C++ import

## Verification Workflow

### During Development

1. **Train a model** using `train_nnue.py`
2. **Export the model** to binary format (done automatically by training script)
3. **Verify export consistency** by running the verification tools
4. **Test in C++ engine** to ensure the model loads and evaluates correctly

### Before Release

1. **Run full verification suite**:
   ```bash
   python example_verification.py
   ```

2. **Cross-platform testing**: Verify models work across different platforms (Windows, Linux, macOS)

3. **Performance validation**: Ensure exported models produce expected evaluation results

### Debugging Issues

If verification fails, check these common issues:

1. **Dimension mismatch**: Ensure `FEATURE_SIZE` and `HIDDEN_SIZE` constants match between Python and C++
2. **Quantization errors**: Verify scaling factors are identical in both implementations
3. **Byte order issues**: Check that both sides use the same endianness
4. **Padding/alignment**: Ensure no unexpected padding is added to the binary format

## Integration with Training Pipeline

The verification tools integrate seamlessly with the existing training workflow:

```bash
# 1. Train a model
python train_nnue.py --data training_data.txt --output model.bin

# 2. Verify the exported model
python verify_model_consistency.py --analyze model.bin

# 3. Test consistency if you have a C++-saved reference
python verify_model_consistency.py model.bin reference_model.bin
```

## Error Messages and Troubleshooting

### Common Error Messages

- **"Invalid header"**: Model file doesn't start with "SANMILL1" - check file format
- **"Feature size mismatch"**: Python and C++ have different `FEATURE_SIZE` constants
- **"Input weights are not identical"**: Binary export/import mismatch - check quantization
- **"File size mismatch"**: Model file is truncated or has extra data

### Debugging Steps

1. **Check file sizes**: Compare expected vs actual file sizes
2. **Verify dimensions**: Ensure feature_size and hidden_size match expectations
3. **Examine statistics**: Use `--analyze` to see weight ranges and distributions
4. **Binary comparison**: Use hex editors to examine raw file contents if needed

## Continuous Integration

For automated testing, include verification in your CI pipeline:

```bash
# In your CI script
python example_verification.py
if [ $? -ne 0 ]; then
    echo "Model verification failed!"
    exit 1
fi
```

This ensures that any changes to the training or export pipeline are automatically validated.

## Future Enhancements

Potential improvements to the verification system:

1. **Cross-platform binary compatibility testing**
2. **Performance benchmark comparison**
3. **Automated regression testing with known-good models**
4. **Integration with C++ unit tests**
5. **Version compatibility checking for model format evolution**
