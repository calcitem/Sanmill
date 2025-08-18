# NNUE PyTorch for Nine Men's Morris

This is an adapted version of NNUE PyTorch specifically designed for training neural networks for Nine Men's Morris position evaluation.

## Overview

This project adapts the NNUE (Efficiently Updatable Neural Network) architecture for Nine Men's Morris, replacing chess-specific features and training data formats with Nine Men's Morris equivalents.

### Key Changes from Original NNUE PyTorch

- **Feature Representation**: Custom `NineMillFeatures` class for 24-position board representation
- **Training Data**: Support for Nine Men's Morris FEN format and training data
- **Model Architecture**: Adjusted network size and evaluation scaling for Nine Men's Morris
- **Data Loaders**: Custom data loading pipeline for Nine Men's Morris positions

## Setup

### Docker

Use Docker with the NVIDIA PyTorch container. This eliminates the need for local Python environment setup and C++ compilation.

#### Prerequisites

For AMD Users:
- Docker
- Up-to-date ROCm driver

For NVIDIA Users:
- Docker
- Up-to-date NVIDIA driver
- NVIDIA Container Toolkit

For driver requirements, check [Running ROCm Docker containers (AMD)](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html) or the [PyTorch container release notes (Nvidia)](https://docs.nvidia.com/deeplearning/frameworks/pytorch-release-notes/rel-25-04.html#rel-25-04).

The container includes CUDA 12.x / ROCm latest and all required dependencies. Your local CUDA/ROCm toolkit version doesn't matter.

### Running the container

Use the provided script to build and start the container:

```
./run_docker.sh
```

You'll be prompted to select the target GPU vendor and the path to your data directory, which will be mounted into the container. Once inside the container, you can run training commands directly.

_Building the container will take it's time and disk space (~30-60GB)_

## Nine Men's Morris Network Training

### Quick Start

1. Prepare training data in Nine Men's Morris format:
   ```
   FEN_STRING EVALUATION BEST_MOVE GAME_RESULT
   ```

2. Train a basic network (adapted train.py - recommended):
   ```bash
   python train.py training_data.txt --validation-data validation_data.txt --features "NineMill" --batch-size 8192 --max_epochs 400
   ```

3. Train with factorized features for better generalization:
   ```bash
   python train.py training_data.txt --validation-data validation_data.txt --features "NineMill^" --batch-size 8192
   ```

### Training Data Format

Nine Men's Morris uses text-based training data format (instead of chess's binary .binpack format) because:
- **Different board structure**: 24 positions vs 64 squares
- **Different game phases**: Placing and moving phases unique to Nine Men's Morris  
- **Simplicity**: Text format is easier to debug and validate
- **Integration**: Better compatibility with Nine Men's Morris C++ engine

The training data should contain one position per line in the following format:
```
board_state side phase action white_on_board white_in_hand black_on_board black_in_hand white_to_remove black_to_remove white_mill_from white_mill_to black_mill_from black_mill_to mills_bitmask rule50 fullmove EVALUATION BEST_MOVE RESULT
```

**FEN Format** (matches C++ Position class exactly):
- **board_state**: 24 characters separated by '/' (files A/B/C, ranks 1-8)
  - 'O' = white piece, '@' = black piece, '*' = empty, 'X' = marked
- **side**: 'w' (white) or 'b' (black) 
- **phase**: 'r' (ready), 'p' (placing), 'm' (moving), 'o' (gameOver)
- **action**: 'p' (place), 's' (select), 'r' (remove), '?' (none)
- **Piece counts and game state**: 10 integers for complete game state
- **Training data**: evaluation, best move, game result

Example:
```
O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1 50.0 a1 1.0
```

### Feature Sets

- **NineMill**: Basic feature set with position-piece encoding
- **NineMill^**: Factorized version with enhanced training capabilities

### Command Line Options

- `--features`: Feature set to use (NineMill)
- `--factorized`: Enable factorized features (recommended)
- `--batch_size`: Training batch size (default: 8192)
- `--max_epochs`: Maximum training epochs (default: 800)
- `--lr`: Learning rate (default: 8.75e-4)
- `--gpus`: GPU devices to use (e.g., "0,1")

### Easy Training Scripts

For automated training with full features, use the adapted easy_train.py:

```bash
# Full-featured training with easy_train.py (recommended)
python scripts/easy_train.py \
    --experiment-name my_mill_experiment \
    --training-dataset training_data.txt \
    --validation-dataset validation_data.txt \
    --workspace-path ./mill_train_data \
    --features "NineMill" \
    --batch-size 8192 \
    --max-epochs 400 \
    --gpus "0" \
    --tui true

# Simple shell script training
./scripts/train.sh training_data.txt validation_data.txt

# See mill_train_example.sh for comprehensive example
./scripts/mill_train_example.sh
```

#### Features of Adapted Scripts

**Adapted `train.py`** (recommended for most users):
- **Preserved original architecture**: All sophisticated PyTorch Lightning features
- **Nine Men's Morris data support**: Uses text-based training data format
- **Full PyTorch Lightning integration**: Advanced training features and callbacks
- **Multi-GPU support**: Native PyTorch Lightning multi-GPU training
- **TensorBoard logging**: Comprehensive training monitoring
- **Checkpointing**: Automatic saving and resuming
- **Flexible configuration**: Rich command-line interface optimized for Nine Men's Morris

**Adapted `easy_train.py`** (for advanced automated workflows):
- **Automated workspace setup**: Creates organized directory structure
- **Multi-GPU parallel runs**: Multiple training runs per GPU
- **Progress monitoring**: Real-time training progress with TUI
- **Resource monitoring**: System resource usage tracking
- **Experiment management**: Organized experiment tracking

## Legacy Documentation

For reference, the original chess-specific documentation:

## Logging

TODO: Move to wiki. Add setup for easy_train.py

```
tensorboard --logdir=logs
```
Then, go to http://localhost:6006/

## Automatically run matches to determine the best net generated by a (running) training

TODO: Move to wiki

```
python run_games.py --concurrency 16 --stockfish_exe ./stockfish.master --c_chess_exe ./c-chess-cli --ordo_exe ./ordo --book_file_name ./noob_3moves.epd run96
```

Automatically converts all `.ckpt` found under `run96` to `.nnue` and runs games to find the best net. Games are played using `c-chess-cli` and nets are ranked using `ordo`.
This script runs in a loop, and will monitor the directory for new checkpoints. Can be run in parallel with the training, if idle cores are available.


## Thanks

* Sopel - for the amazing fast sparse data loader
* connormcmonigle - https://github.com/connormcmonigle/seer-nnue, and loss function advice.
* syzygy - http://www.talkchess.com/forum3/viewtopic.php?f=7&t=75506
* https://github.com/DanielUranga/TensorFlowNNUE
* https://hxim.github.io/Stockfish-Evaluation-Guide/
* dkappe - Suggesting ranger (https://github.com/lessw2020/Ranger-Deep-Learning-Optimizer)
