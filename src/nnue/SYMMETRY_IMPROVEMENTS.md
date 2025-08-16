# NNUE Symmetry Improvements

## Overview
This document describes the symmetry-aware improvements made to the NNUE (Efficiently Updatable Neural Network) evaluation system for the Mill game engine.

## Problem Statement
The original NNUE implementation only used basic color swapping for different perspectives, missing opportunities to:
- Leverage board symmetries (rotations, mirrors) for more efficient evaluation
- Reduce the size of the feature space through canonical transformations
- Improve training data quality through symmetry augmentation
- Match the sophisticated symmetry handling used in the perfect database system

## Solution: Comprehensive Symmetry Framework

### 1. Symmetry Transformation System (`nnue_symmetries.h/cpp`)

#### Supported Transformations
- **Geometric Transformations**: 90°, 180°, 270° rotations
- **Mirror Transformations**: Vertical, horizontal, diagonal (backslash/slash)
- **Color Swapping**: All geometric transformations combined with color swapping
- **Total**: 16 symmetry operations (D8 dihedral group × color swap)

#### Key Features
- **Fast Lookup Tables**: Pre-computed square transformations for O(1) performance
- **Feature Vector Transformation**: Efficient transformation of all NNUE features
- **Canonical Forms**: Find the lexicographically smallest representation
- **Inverse Operations**: Support for undoing transformations

### 2. Enhanced NNUE Evaluation

#### Symmetry-Aware Evaluation (`evaluate_with_symmetries`)
- Automatically finds the canonical form of each position
- Evaluates using the most representative transformation
- Handles color-swapping operations correctly
- Replaces the basic color-swap-only evaluation

#### Legacy Compatibility
- Original `forward()` method preserved for compatibility
- Clearly marked as legacy with recommendations to use symmetry-aware version

### 3. Training Data Improvements

#### Symmetry Augmentation
- Generates training samples for all valid symmetries of each position
- Increases effective training data size by up to 16x
- Maintains evaluation correctness with proper sign handling for color swaps
- Improves model generalization and reduces overfitting

#### Memory Management
- Proper cleanup of dynamically allocated feature arrays
- Safe handling of symmetric sample generation
- Thread-safe operations for parallel training

### 4. Code Quality Improvements

#### English Comments
- All new code uses English comments as requested
- Clear documentation of transformation logic
- Comprehensive function documentation

#### Maintainability
- Modular design with clear separation of concerns
- Extensive use of assertions for debugging
- Type-safe enumeration for symmetry operations

## Technical Details

### Mill Board Representation
The mill game uses a 24-square board with specific connectivity patterns:
```
8----9----10
|    |    |
| 16-17-18 |
| |  |  | |
|11-12-13|19
| |  |  | |
| 20-21-22 |
|    |    |
14---15---23
```

### Transformation Mapping
Each symmetry operation is implemented as a lookup table mapping source squares to destination squares, ensuring O(1) transformation time.

### Feature Vector Structure
- **Piece Placement**: 48 features (24 squares × 2 colors)
- **Game Phase**: 3 features (placing/moving/gameover)
- **Piece Counts**: 40 features (in-hand and on-board counts)
- **Tactical Features**: 24 features (mill potential, mobility)
- **Total**: 115 features

## Performance Benefits

1. **Evaluation Efficiency**: Canonical forms reduce redundant evaluations
2. **Training Quality**: 16x more diverse training data without additional position generation
3. **Model Accuracy**: Better generalization through symmetry-aware training
4. **Memory Usage**: Efficient transformation with pre-computed lookup tables

## Integration with Perfect Database

The symmetry system is designed to be compatible with the existing perfect database symmetries:
- Uses the same geometric transformation concepts
- Maintains consistency with perfect database lookup optimizations
- Enables seamless integration between NNUE and perfect evaluations

## Usage Examples

### Basic Evaluation
```cpp
NNUE::NNUEEvaluator evaluator;
Value eval = evaluator.evaluate_with_symmetries(position);
```

### Training Data Generation
```cpp
TrainingDataGenerator generator;
generator.generate_training_set("training.txt", 50000);
// Automatically includes symmetry augmentation
```

### Manual Symmetry Operations
```cpp
SymmetryTransforms::initialize();
Square transformed = SymmetryTransforms::transform_square(SQ_8, SYM_ROTATE_90);
```

## Future Enhancements

1. **SIMD Optimization**: Vectorize feature transformations for even better performance
2. **Incremental Updates**: Cache transformations for positions with small changes
3. **Advanced Canonicalization**: Use position-specific symmetry analysis
4. **Training Integration**: Direct integration with neural network training frameworks

## Testing

The implementation includes comprehensive tests in `test_symmetries.cpp`:
- Square transformation correctness
- Feature vector transformation accuracy
- Inverse operation verification
- Canonical form detection

## Conclusion

These symmetry improvements bring the NNUE evaluation system up to the same level of sophistication as the perfect database system, providing:
- Better evaluation accuracy through canonical forms
- Improved training data quality through augmentation
- Enhanced performance through efficient transformations
- Maintainable code with clear English documentation

The changes maintain full backward compatibility while providing significant improvements in evaluation quality and training efficiency.
