# NNUE Training for Sanmill

This directory contains the NNUE (Efficiently Updatable Neural Network) training pipeline for the Sanmill Mill game engine.

## Overview

The NNUE training system uses the Perfect Database to generate optimal training data, ensuring the neural network learns from perfect play rather than approximations from traditional search algorithms.

### Key Features

- **Strict Mode**: No fallback behavior - failures result in assertions rather than silent degradation
- **Parallel Training Data Generation**: Multi-threaded position generation for faster data collection
- **Phase Quota Control**: Precise control over training data distribution across game phases
- **Perfect Database Integration**: All training labels come from theoretically optimal evaluations
- **Robust Validation**: Comprehensive error checking at every stage

## Files

- `train_nnue.py` - Main training script for the neural network
- `generate_training_data.py` - Script to generate training data using the Perfect Database
- `train_pipeline_parallel.py` - Enhanced pipeline with strict mode and parallelization
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

### Step 1: Generate Training Data (Parallel)

Generate training data using the Perfect Database with parallelization:

```bash
python generate_training_data.py \
    --engine ../../sanmill \
    --output training_data.txt \
    --positions 100000 \
    --perfect-db /path/to/perfect/database \
    --threads 8 \
    --validate
```

Parameters:
- `--engine`: Path to the Sanmill executable
- `--output`: Output file for training data
- `--positions`: Number of positions to generate (default: 50000)
- `--perfect-db`: Path to Perfect Database directory
- `--threads`: Number of threads for parallel generation (0=auto-detect)
- `--validate`: Validate the generated data

### Enhanced Pipeline (Recommended)

Use the enhanced pipeline with strict mode and comprehensive validation:

```bash
python train_pipeline_parallel.py \
    --engine ../../sanmill \
    --perfect-db /path/to/perfect/database \
    --output-dir ./nnue_models \
    --positions 500000 \
    --epochs 300 \
    --batch-size 8192 \
    --learning-rate 0.002 \
    --lr-scheduler adaptive \
    --lr-auto-scale \
    --plot \
    --save-csv \
    --threads 24
```

Enhanced Parameters:
- `--output-dir`: Directory for all training artifacts
- `--threads`: Number of parallel threads (auto-detected if 0)
- `--validate-only`: Only validate environment without training
- `--device`: Training device (cpu/cuda/auto)

### Step 2: Train the NNUE Model

Train the neural network using the generated data:

```bash
python train_nnue.py \
    --data training_data.txt \
    --output nnue_model.bin \
    --epochs 300 \
    --batch-size 8192 \
    --lr 0.002 \
    --lr-scheduler adaptive \
    --lr-auto-scale \
    --plot \
    --plot-interval 10 \
    --save-csv \
    --hidden-size 512
```

Parameters:
- `--data`: Training data file
- `--output`: Output model file (C++ compatible format)
- `--epochs`: Number of training epochs (default: 300)
- `--batch-size`: Training batch size (default: 8192)
- `--lr`: Learning rate (default: 0.002)
- `--hidden-size`: Hidden layer size (default: 512)
- `--max-samples`: Maximum training samples to use
- `--val-split`: Validation split ratio (default: 0.1)
- `--device`: Device to use (cpu/cuda/auto)
- `--lr-scheduler`: Learning rate scheduler type (adaptive/cosine/plateau/fixed)
- `--lr-auto-scale`: Automatically scale learning rate based on batch size and dataset size

### Training Visualization

The training system includes comprehensive real-time visualization capabilities:

#### Visualization Options
- `--plot`: Enable training visualization plots
- `--plot-dir`: Directory to save plots (default: 'plots')
- `--plot-interval`: Update plots every N epochs (default: 5)
- `--show-plots`: Display plots in real-time (requires GUI environment)
- `--save-csv`: Save training metrics to CSV file for analysis

#### Generated Plots

**Real-time Training Dashboard** (updated every `--plot-interval` epochs):
1. **Loss Curves**: Training and validation loss with trend lines
2. **Validation Accuracy**: Accuracy progression with best performance markers
3. **Learning Rate Schedule**: LR changes over time with adjustment annotations
4. **Gradient Norms**: Gradient health monitoring with warning zones
5. **Training Speed**: Epoch timing with average indicators
6. **Overfitting Indicator**: Validation/Training loss ratio analysis

**Final Training Summary** (generated at completion):
- Comprehensive loss analysis with moving averages
- Learning progress metrics and improvement rates
- Performance timeline with dual metrics
- Complete training statistics and summary

#### Example Visualizations

```bash
# Enable visualization with default settings
python train_nnue.py --data training_data.txt --plot

# Custom visualization settings
python train_nnue.py \
    --data training_data.txt \
    --plot \
    --plot-dir ./my_plots \
    --plot-interval 10 \
    --save-csv

# Pipeline with visualization
python train_pipeline_parallel.py \
    --engine ../../sanmill \
    --perfect-db /path/to/db \
    --plot \
    --plot-dir ./training_plots
```

#### Output Files
- `training_progress_latest.png`: Most recent training dashboard
- `training_progress_epoch_XXXX.png`: Periodic snapshots
- `training_summary.png`: Final comprehensive summary
- `training_metrics.csv`: Raw data for custom analysis

#### Dependencies
Install visualization dependencies:
```bash
pip install matplotlib seaborn
```

### Learning Rate Scheduling

The training system supports multiple adaptive learning rate strategies:

#### Adaptive Scheduler (Recommended)
Automatically adjusts learning rate based on:
- Training and validation loss trends
- Gradient norm patterns
- Learning progress indicators
- Warmup and cooldown phases

```bash
--lr-scheduler adaptive
```

Features:
- **Warmup Phase**: Gradually increases LR during first 5 epochs
- **Auto Reduction**: Reduces LR when validation loss plateaus
- **Smart Boosting**: Increases LR during consistent improvement periods
- **Gradient Analysis**: Monitors gradient norms for optimization health
- **Trend Detection**: Uses statistical analysis to detect training patterns

#### Auto-scaling
Automatically calculates optimal initial learning rate based on:
- Batch size (linear scaling rule)
- Dataset size (sqrt scaling for generalization)
- Conservative safety factors

```bash
--lr-auto-scale
```

Formula: `lr = base_lr * (batch_size/1024) * sqrt(dataset_size/100k) * 0.8`

#### Other Schedulers
- **Cosine Annealing**: Smooth cyclic learning rate changes
- **Plateau**: Reduces LR when validation loss stops improving
- **Fixed**: Uses constant learning rate throughout training

## Model Architecture

The NNUE model uses the following architecture:

1. **Input Features** (95 dimensions):
   - Piece placement features (48): 24 squares × 2 colors
   - Phase features (3): placing, moving, game over
   - Piece count features (12): pieces in hand and on board
   - Tactical features (32): mills, blocking, mobility

2. **Hidden Layer** (512 neurons):
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

2. Configure the engine to use NNUE (Strict Mode):
```
setoption name UseNNUE value true
setoption name NNUEModelPath value nnue_model.bin
setoption name NNUEWeight value 90
```

**Important Notes for Strict Mode**:
- Model file must exist and be valid - no fallback to traditional evaluation
- Model dimensions must match compiled constants exactly
- Failed model loading will prevent engine startup
- NNUE evaluation failures trigger assertions instead of silent fallbacks

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

Recommended hyperparameter ranges for high-end hardware:
- Learning rate: 0.001 - 0.005
- Batch size: 4096 - 16384
- Hidden size: 256 - 1024
- NNUE weight: 80 - 100
- Training positions: 500K - 2M
- Epochs: 300 - 800

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
