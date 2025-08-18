# Perfect Database Integration for NNUE PyTorch

This document describes the Perfect Database integration for generating optimal training data for Nine Men's Morris NNUE models.

## Overview

The Perfect Database integration provides:

- **Optimal Training Data**: All training positions are evaluated using perfect play
- **16-Fold Symmetry Support**: Automatic data augmentation using geometric and color symmetries
- **Coordinate System Mapping**: Seamless conversion between ml/game and nnue-pytorch coordinate systems
- **Efficient Data Generation**: Batch processing and caching for performance

## Quick Start

### 1. Generate Training Data

```bash
# Basic training data generation
python generate_training_data.py --perfect-db /path/to/database --output training_data.txt --positions 50000

# With symmetry augmentation (16x more data)
python generate_training_data.py --perfect-db /path/to/database --output training_data.txt --positions 10000 --symmetries

# Quick test
python scripts/generate_perfect_db_data.py --perfect-db /path/to/database --quick-test
```

### 2. Train NNUE Model

```bash
# Train with Perfect DB data
python train.py training_data.txt --features NineMill --batch-size 8192 --max_epochs 400

# Train with factorized features
python train.py training_data.txt --features NineMill^ --batch-size 8192 --max_epochs 400
```

### 3. Validate Integration

```bash
# Test Perfect DB integration
python example_perfect_db_training.py --perfect-db /path/to/database --validate --train
```

## Architecture

### Components

1. **generate_training_data.py**: Main data generation script
   - Uses `ml/perfect/perfect_db_reader.py` for Perfect Database access
   - Implements 16 symmetry transformations
   - Generates balanced training data across game phases

2. **data_loader.py**: Enhanced data loading
   - Supports Perfect DB generated format
   - Handles variable-length sparse features
   - Compatible with existing NNUE PyTorch training pipeline

3. **Symmetry System**: 16-fold symmetry transformations
   - Geometric transformations: rotations and reflections
   - Color swap transformations
   - Coordinate system mapping between different representations

### Coordinate Systems

The integration handles three coordinate systems:

1. **ml/game coordinates**: (x, y) pairs from Board.allowed_places
2. **Feature indices**: 0-23 mapping for NNUE features
3. **C++ engine squares**: 8-31 range used by Perfect Database

```python
# Example coordinate mappings
ml_game_coord = (0, 0)          # Top-left corner in ml/game
feature_index = 0               # First feature in NNUE
cpp_square = 24                 # SQ_A7 in C++ engine
```

## Symmetry Transformations

### 16 Symmetry Operations

The system supports all 16 symmetries used by the Perfect Database:

**Geometric Transformations (8):**
- `id_transform`: Identity (no change)
- `rotate90`, `rotate180`, `rotate270`: Rotations
- `mirror_vertical`, `mirror_horizontal`: Axis reflections  
- `mirror_backslash`, `mirror_slash`: Diagonal reflections

**Color Swap Transformations (8):**
- `swap`: Color swap only
- `swap_rotate90`, `swap_rotate180`, `swap_rotate270`: Swap + rotations
- `swap_mirror_vertical`, `swap_mirror_horizontal`: Swap + axis reflections
- `swap_mirror_backslash`, `swap_mirror_slash`: Swap + diagonal reflections

### Data Augmentation

```python
# Generate base position
base_position = generate_position_from_perfect_db()

# Generate all 16 symmetries
symmetries = symmetry_transforms.generate_all_symmetries(base_position)

# Result: 16x training data from single position
total_examples = 1 * 16 = 16
```

## Training Data Format

### Perfect DB Generated Format

```
# Nine Men's Morris NNUE Training Data
# Generated using Perfect Database: /path/to/database
# Format: FEN EVALUATION BEST_MOVE RESULT

O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1 125.000000 a1 0.0
@*@*@***/*******/*******/ b p p 0 9 3 6 0 0 0 0 0 0 0 0 2 -125.000000 b2 0.0
```

### FEN Format Components

```
board_state side phase action white_on_board white_in_hand black_on_board black_in_hand 
white_to_remove black_to_remove white_mill_from white_mill_to black_mill_from black_mill_to 
mills_bitmask rule50 fullmove EVALUATION BEST_MOVE RESULT
```

**Board State**: 24 characters with '/' separators
- `O` = white piece, `@` = black piece, `*` = empty, `X` = marked

**Game State**: Standard FEN format matching C++ Position class

**Training Data**: Evaluation score, best move token, game result

## Performance

### Generation Speed

- **Base positions**: ~1000-5000 positions/second
- **With symmetries**: ~200-1000 total examples/second
- **Perfect DB lookup**: ~10,000-50,000 evaluations/second (cached)

### Memory Usage

- **Base generation**: ~100-500 MB RAM
- **With symmetries**: ~500-2000 MB RAM  
- **Perfect DB cache**: ~50-200 MB RAM

### Recommended Settings

```bash
# For development/testing
--positions 1000 --batch-size 500

# For training
--positions 50000 --batch-size 2000

# For production with symmetries
--positions 10000 --symmetries --batch-size 1000
```

## Integration with Existing Workflow

### Training Pipeline

```bash
# 1. Generate Perfect DB training data
python generate_training_data.py \
    --perfect-db /path/to/database \
    --output perfect_training_data.txt \
    --positions 50000 \
    --symmetries

# 2. Split into training and validation sets
head -n 400000 perfect_training_data.txt > train_data.txt
tail -n 400000 perfect_training_data.txt > val_data.txt

# 3. Train NNUE model
python train.py train_data.txt \
    --validation-data val_data.txt \
    --features NineMill \
    --batch-size 8192 \
    --max_epochs 400 \
    --lr 8.75e-4

# 4. Train with factorized features for better generalization
python train.py train_data.txt \
    --validation-data val_data.txt \
    --features NineMill^ \
    --batch-size 8192 \
    --max_epochs 400
```

### Docker Integration

```bash
# Inside Docker container
./run_docker.sh

# Generate data
python generate_training_data.py --perfect-db /workspace/perfect_db --positions 50000 --symmetries

# Train model
python train.py perfect_training_data.txt --features NineMill --batch-size 8192
```

## Troubleshooting

### Common Issues

1. **Perfect Database DLL not found**
   ```
   FileNotFoundError: Perfect DB DLL not found: /path/to/perfect_db.dll
   ```
   **Solution**: Build the Perfect Database DLL or set `SANMILL_PERFECT_DLL` environment variable

2. **No .sec2 files found**
   ```
   No .sec2 files found in: /path/to/database
   ```
   **Solution**: Ensure Perfect Database directory contains .sec2 sector files

3. **Coordinate system mismatch**
   ```
   Invalid position index: 25
   ```
   **Solution**: Verify coordinate mapping between systems (should be 0-23)

4. **Memory issues with symmetries**
   ```
   RuntimeError: CUDA out of memory
   ```
   **Solution**: Reduce batch size or disable symmetries for large datasets

### Validation

```bash
# Validate Perfect Database installation
python example_perfect_db_training.py --perfect-db /path/to/database --validate-only

# Test symmetry transformations
python -c "
from generate_training_data import SymmetryTransforms
transforms = SymmetryTransforms()
test_board = {'white_pieces': [0, 1, 2], 'black_pieces': [21, 22, 23], 'side_to_move': 0}
symmetries = transforms.generate_all_symmetries(test_board)
print(f'Generated {len(symmetries)} symmetries')
"

# Validate training data format
python -c "
from data_loader import load_perfect_db_training_data
positions = load_perfect_db_training_data(['training_data.txt'], max_positions=10)
print(f'Loaded {len(positions)} positions successfully')
"
```

## Best Practices

### Data Generation

1. **Start small**: Test with 1000 positions before generating large datasets
2. **Use symmetries wisely**: 16x data augmentation is powerful but memory-intensive
3. **Batch processing**: Use appropriate batch sizes based on available memory
4. **Validation**: Always validate generated data before training

### Training

1. **Balanced datasets**: Ensure good distribution across game phases
2. **Feature selection**: Try both `NineMill` and `NineMill^` (factorized) features
3. **Hyperparameters**: Start with proven settings and adjust based on results
4. **Monitoring**: Use TensorBoard to monitor training progress

### Performance

1. **Caching**: Perfect DB evaluations are cached for performance
2. **Parallel processing**: Use multiple processes for large datasets
3. **Memory management**: Monitor memory usage with large symmetry datasets
4. **Storage**: Consider compression for large training data files

## Examples

### Basic Usage

```python
# Generate training data programmatically
from generate_training_data import PerfectDBTrainingDataGenerator

generator = PerfectDBTrainingDataGenerator("/path/to/database")
success = generator.generate_training_data(
    num_positions=10000,
    output_file="my_training_data.txt",
    use_symmetries=True
)
```

### Custom Symmetry Usage

```python
# Apply specific symmetries
from generate_training_data import SymmetryTransforms

transforms = SymmetryTransforms()
board_state = {
    'white_pieces': [0, 8, 16],
    'black_pieces': [1, 9, 17], 
    'side_to_move': 0
}

# Apply rotation
rotated = transforms.apply_transform(board_state, 0)  # rotate90

# Apply color swap
swapped = transforms.apply_transform(board_state, 7)  # swap
```

### Integration with Training

```python
# Use Perfect DB data in training
from data_loader import create_perfect_db_data_loader
from features_mill import NineMillFeatures

feature_set = NineMillFeatures()
train_loader = create_perfect_db_data_loader(
    ["perfect_training_data.txt"],
    feature_set,
    batch_size=8192
)

# Train model
for batch in train_loader:
    # batch contains Perfect DB evaluated positions
    # ready for NNUE training
    pass
```

## Technical Details

### Coordinate System Mapping

The integration handles mapping between three coordinate systems:

```python
# ml/game Board coordinate (x, y)
ml_coord = (0, 0)  # Top-left corner

# NNUE feature index (0-23)
feature_idx = COORD_TO_FEATURE[ml_coord]  # 0

# C++ engine square (8-31) 
cpp_square = feature_idx + 8  # 8 (SQ_A1)
```

### Symmetry Implementation

Each symmetry transformation maps feature indices:

```python
# Rotation by 90 degrees
def rotate90_transform(feature_idx):
    x, y = FEATURE_TO_COORD[feature_idx]
    new_x, new_y = 6 - y, x
    return COORD_TO_FEATURE[(new_x, new_y)]
```

### Perfect Database Interface

Direct DLL calls for optimal performance:

```c
// C++ DLL interface
int pd_evaluate(int whiteBits, int blackBits, int whiteStonesToPlace,
                int blackStonesToPlace, int playerToMove, int onlyStoneTaking,
                int* outWdl, int* outSteps);
```

This integration provides a robust foundation for generating high-quality NNUE training data using the Perfect Database with full symmetry support.
