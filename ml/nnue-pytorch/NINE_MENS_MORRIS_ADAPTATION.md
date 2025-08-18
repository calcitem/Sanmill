# Nine Men's Morris NNUE Adaptation

This document describes the adaptation of the NNUE PyTorch training system from chess to Nine Men's Morris.

## Overview

The original NNUE PyTorch system was designed for chess position evaluation. This adaptation modifies the system to work with Nine Men's Morris, a traditional strategy board game with different rules and board structure.

## Why Text Format Instead of Binpack?

The original NNUE PyTorch used `.binpack` files for chess training data. For Nine Men's Morris, we switched to text format because:

1. **Chess-specific design**: `.binpack` format is hardcoded for:
   - 64-square chess board
   - Chess piece types (pawn, knight, bishop, rook, queen, king)
   - Chess-specific move encoding
   - Castling rights and en passant

2. **Nine Men's Morris differences**:
   - 24-position board layout (not 64 squares)
   - Only 2 piece types (white/black stones)
   - Different game phases (placing/moving)
   - Different move types (place/move/remove)

3. **Advantages of text format**:
   - **Simplicity**: Easy to read, debug, and validate
   - **Flexibility**: Can easily add new fields for Nine Men's Morris
   - **Integration**: Direct compatibility with C++ engine FEN format
   - **Maintenance**: No need to maintain complex binary encoding/decoding

4. **Performance**: For Nine Men's Morris training data sizes, text format performance is adequate.

## Key Changes Made

### 1. Feature Representation (`features_mill.py`)

**Original**: Chess used HalfKP/HalfKA features with 64 squares and multiple piece types
**Adapted**: Nine Men's Morris uses custom features with:
- 24 board positions (instead of 64 squares)
- 2 piece types (white/black pieces only)
- Position-centric feature encoding
- Support for factorized features for enhanced training

**Classes**:
- `NineMillFeatures`: Basic feature set for Nine Men's Morris
- `FactorizedNineMillFeatures`: Enhanced version with virtual features

### 2. Model Architecture (`model.py`)

**Changes**:
- Reduced L1 layer size from 3072 to 1536 (smaller feature space)
- Adjusted loss parameters for Nine Men's Morris evaluation scale
- Reduced `nnue2score` scaling from 600.0 to 200.0
- Maintained L2 (15) and L3 (32) layer sizes

### 3. Training Data Loading (`data_loader.py`)

**New Components**:
- `MillPosition`: Represents Nine Men's Morris positions
- `MillTrainingDataset`: PyTorch dataset for training data
- `parse_mill_fen()`: Parses Nine Men's Morris FEN format (100% compatible with C++ Position class)
- `create_mill_data_loader()`: Creates optimized data loaders

**Data Format** (exactly matches C++ Position::fen()):
```
board_state side phase action white_on_board white_in_hand black_on_board black_in_hand 
white_to_remove black_to_remove white_mill_from white_mill_to black_mill_from black_mill_to 
mills_bitmask rule50 fullmove EVALUATION BEST_MOVE RESULT
```

**Key Consistency Features**:
- Position indices correctly mapped from C++ squares (8-31) to features (0-23)
- FEN parsing logic matches C++ Position::set() exactly
- Star position definitions match C++ Position::is_star_square()
- Board layout follows C++ file/rank organization

### 4. Training Scripts

**`train.py`** - Main training script (adapted from original):
- **Preserved original PyTorch Lightning architecture**: All sophisticated training features maintained
- **Nine Men's Morris data format**: Uses text-based training data (replaces chess .binpack format)
- **Simplified data loading**: Dedicated Nine Men's Morris data loader
- **Adjusted defaults**: Parameters optimized for Nine Men's Morris scale  
- **Full feature support**: All original features like multi-GPU, checkpointing, TensorBoard logging
- **Clean architecture**: Removed chess-specific binpack complexity

**`scripts/easy_train.py`** - Advanced automated training (adapted from original):
- **Preserved original architecture**: Maintains all sophisticated features of the original
- **Automated workspace management**: Creates organized directory structures
- **Multi-GPU parallel training**: Support for multiple GPUs and runs per GPU
- **Real-time monitoring**: TUI interface with progress tracking
- **Resource monitoring**: System resource usage tracking
- **Experiment management**: Organized experiment tracking and resuming
- **Adapted for Nine Men's Morris**: Updated defaults and parameters for Nine Men's Morris

### 5. Feature Module Integration (`features.py`)

**Changes**:
- Removed chess-specific imports (halfkp, halfka, etc.)
- Added Nine Men's Morris feature module
- Updated feature discovery system

### 6. Serialization (`serialize.py`)

**Changes**:
- Updated default description for Nine Men's Morris networks
- Compatible with existing NNUE format for C++ integration

### 7. Documentation (`README.md`)

**Added**:
- Nine Men's Morris specific training instructions
- Data format specifications
- Command-line examples
- Feature set descriptions

## Board Representation

Nine Men's Morris uses a 24-position board layout:

```
31 --- 24 --- 25
|      |      |
| 23 - 16 - 17 |
| |    |    | |
| | 15-08-09 | |
30-22-14   10-18-26
| | 13-12-11 | |
| |    |    | |
| 21 - 20 - 19 |
|      |      |
29 --- 28 --- 27
```

Positions 8-31 are used (0-7 are reserved), mapping to the standard Nine Men's Morris board.

## Feature Encoding

Each position is encoded relative to all other positions, creating a sparse representation where only occupied positions have non-zero features.

**Feature Index Calculation**:
```python
feature_idx = piece_type * NUM_SQ + piece_position
```

Where:
- `piece_type`: 0 for white, 1 for black (adjusted by perspective)
- `piece_position`: 0-23 board position
- Total features: 2 * 24 * 24 = 1,152

## Training Process

1. **Data Preparation**: Convert game data to training format
2. **Feature Extraction**: Use `NineMillFeatures` or `FactorizedNineMillFeatures`
3. **Training**: Run `train.py` with appropriate parameters
4. **Serialization**: Export trained model to `.nnue` format
5. **Integration**: Use in Nine Men's Morris engine

## Usage Examples

### Basic Training
```bash
python train.py training_data.txt --batch_size 8192 --max_epochs 400
```

### Advanced Training with Factorized Features
```bash
python train.py training_data.txt \
    --factorized true \
    --batch_size 8192 \
    --max_epochs 800 \
    --lr 8.75e-4 \
    --gpus "0,1"
```

### Demo and Testing
```bash
python example_usage.py
```

## Integration with C++ Engine

The trained `.nnue` files are compatible with the existing C++ engine infrastructure. The C++ code needs to:

1. Load the `.nnue` file using existing NNUE loading code
2. Convert Nine Men's Morris positions to feature indices
3. Use the network for position evaluation during search

## Performance Considerations

- **Batch Size**: Recommended 8192-16384 for GPU training
- **Learning Rate**: Start with 8.75e-4, adjust based on convergence
- **Epochs**: Typically 400-800 epochs for convergence
- **Memory**: Significantly lower than chess due to smaller feature space

## Future Improvements

1. **C++ Data Loader**: Implement native C++ training data loader for performance
2. **Advanced Features**: Experiment with mill-aware features
3. **Multi-Phase Networks**: Separate networks for placing/moving phases
4. **Quantization**: Optimize for embedded/mobile deployment

## File Structure

```
ml/nnue-pytorch/
├── features_mill.py           # Nine Men's Morris feature definitions
├── data_loader.py             # Training data loading
├── train.py                   # Training script (renamed from train_mill.py)
├── example_usage.py           # Usage demonstration
├── convert_training_data.py   # Data format conversion utility
├── model.py                   # Modified network architecture
├── features.py                # Updated feature module registry
├── serialize.py               # Model serialization
├── run_games.py               # Network testing (adapted for Nine Men's Morris)
├── scripts/
│   ├── easy_train.py          # Advanced automated training script (adapted from original)
│   ├── easy_train_example.bat # Windows training example
│   ├── easy_train_example.sh  # Linux training example
│   └── train.sh               # Shell training script
└── README.md                  # Updated documentation
```

## Modified Files

The following files have been adapted for Nine Men's Morris:

**Replaced completely**:
- `halfkp.py`, `halfka.py`, `halfka_v2.py`, `halfka_v2_hm.py` → `features_mill.py`
- Original `data_loader.py` → New Nine Men's Morris `data_loader.py`

**Adapted from original (preserving architecture)**:
- `train.py` - **Preserved full PyTorch Lightning architecture**, added hybrid data loading for Nine Men's Morris
- `scripts/easy_train.py` - **Preserved original sophisticated architecture**, adapted parameters and defaults
- `model.py` - Adjusted network architecture and scaling for Nine Men's Morris
- `features.py` - Updated feature module registry with Nine Men's Morris defaults
- `serialize.py` - Updated descriptions

## Dependencies

The adaptation maintains compatibility with the original NNUE PyTorch dependencies:
- PyTorch
- PyTorch Lightning
- NumPy
- Additional dependencies as per original requirements

## Testing

Run the example script to verify the adaptation:
```bash
cd ml/nnue-pytorch
python example_usage.py
```

This will create sample data, demonstrate feature extraction, run a small training loop, and serialize a model.
