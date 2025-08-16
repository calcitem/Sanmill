# NNUE Training for Sanmill

This directory contains the NNUE (Efficiently Updatable Neural Network) training pipeline for the Sanmill Mill game engine.

## Overview

The NNUE training system uses the Perfect Database to generate optimal training data, ensuring the neural network learns from perfect play rather than approximations from traditional search algorithms.

## Files

- `train_nnue.py` - Main training script for the neural network
- `generate_training_data.py` - Script to generate training data using the Perfect Database
- `requirements.txt` - Python dependencies
- `README.md` - This file

## Setup

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Build the Sanmill engine with NNUE support:
```bash
cd ../..
make # or your preferred build method
```

3. Ensure you have access to the Perfect Database files.

## Usage

### Step 1: Generate Training Data

Generate training data using the Perfect Database:

```bash
python generate_training_data.py \
    --engine ../../sanmill \
    --output training_data.txt \
    --positions 100000 \
    --perfect-db /path/to/perfect/database \
    --validate
```

Parameters:
- `--engine`: Path to the Sanmill executable
- `--output`: Output file for training data
- `--positions`: Number of positions to generate (default: 50000)
- `--perfect-db`: Path to Perfect Database directory
- `--validate`: Validate the generated data

### Step 2: Train the NNUE Model

Train the neural network using the generated data:

```bash
python train_nnue.py \
    --data training_data.txt \
    --output nnue_model.bin \
    --epochs 200 \
    --batch-size 1024 \
    --lr 0.001 \
    --hidden-size 256
```

Parameters:
- `--data`: Training data file
- `--output`: Output model file (C++ compatible format)
- `--epochs`: Number of training epochs (default: 100)
- `--batch-size`: Training batch size (default: 1024)
- `--lr`: Learning rate (default: 0.001)
- `--hidden-size`: Hidden layer size (default: 256)
- `--max-samples`: Maximum training samples to use
- `--val-split`: Validation split ratio (default: 0.1)
- `--device`: Device to use (cpu/cuda/auto)

## Model Architecture

The NNUE model uses the following architecture:

1. **Input Features** (95 dimensions):
   - Piece placement features (48): 24 squares × 2 colors
   - Phase features (3): placing, moving, game over
   - Piece count features (12): pieces in hand and on board
   - Tactical features (32): mills, blocking, mobility

2. **Hidden Layer** (256 neurons):
   - ReLU activation
   - Separate processing for white and black perspectives

3. **Output Layer** (1 neuron):
   - Combines both perspectives based on side to move
   - Produces evaluation score

## Integration with Engine

Once trained, the model can be used in the Sanmill engine:

1. Copy the model file to the engine directory:
```bash
cp nnue_model.bin ../../
```

2. Configure the engine to use NNUE:
```
setoption name UseNNUE value true
setoption name NNUEModelPath value nnue_model.bin
setoption name NNUEWeight value 90
```

## Training Data Format

The training data file format:
```
# Sanmill NNUE Training Data
# Format: features(space-separated 0/1) | evaluation | step_count | phase | fen
50000
1 0 0 1 0 0 ... | 0.8 | 12 | 1 | ***w*b******************w*w 0 0
0 1 1 0 0 0 ... | -0.3 | 25 | 2 | w*b*w*b*****************w*w 0 0
...
```

Where:
- Features: 95 binary features representing the position
- Evaluation: Perfect evaluation from database (-1.0 to 1.0)
- Step count: Steps to optimal result from Perfect Database
- Phase: Game phase (1=placing, 2=moving, 3=game over)
- FEN: Position in Forsyth-Edwards Notation

## Performance Monitoring

The training script provides:
- Training and validation loss tracking
- Accuracy metrics for win/loss/draw predictions
- Early stopping based on validation loss
- Learning rate scheduling
- Model checkpointing

## Advanced Usage

### Custom Feature Engineering

To modify the feature set, update:
- `src/nnue/nnue_features.h` - Feature definitions
- `src/nnue/nnue_features.cpp` - Feature extraction
- `train_nnue.py` - Model input dimensions

### Hyperparameter Tuning

Recommended hyperparameter ranges:
- Learning rate: 0.0001 - 0.01
- Batch size: 512 - 4096
- Hidden size: 128 - 512
- NNUE weight: 80 - 100

### Multi-GPU Training

For large datasets, use multiple GPUs:
```bash
python -m torch.distributed.launch --nproc_per_node=4 train_nnue.py ...
```

## Troubleshooting

Common issues:

1. **Perfect Database not found**: Ensure the database path is correct and contains the required files.

2. **Training data generation fails**: Check engine logs and ensure NNUE options are properly set.

3. **CUDA out of memory**: Reduce batch size or use CPU training.

4. **Poor training convergence**: Try different learning rates or increase dataset size.

5. **Model not loading in engine**: Verify the model format and file permissions.

## References

- [NNUE Paper](https://arxiv.org/abs/2010.05982)
- [Stockfish NNUE Implementation](https://github.com/official-stockfish/nnue-pytorch)
- [Mill Game Rules](https://en.wikipedia.org/wiki/Nine_men's_morris)
