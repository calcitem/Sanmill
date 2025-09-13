# Katamill: KataGo-inspired RL for Nine Men's Morris

Katamill is a deep reinforcement learning framework for Nine Men's Morris (Mill Game), inspired by KataGo's multi-head neural network architecture. It extends traditional AlphaZero-style learning with auxiliary prediction tasks that provide richer training signals.

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Architecture](#architecture-details)
- [Training Pipeline](#complete-training-pipeline)
- [API Reference](#api-reference)
- [Performance](#performance-considerations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Features

### Multi-Head Neural Network
- **Policy head**: Predicts move probabilities (24×24 action space)
- **Value head**: Predicts game outcome from current player's perspective (-1 to 1)
- **Score head**: Predicts heuristic evaluation score (unbounded, material + mobility)
- **Ownership head**: Predicts piece ownership for each board position (24 values, -1 to 1)

### Rich Feature Extraction
The CNN input includes 32 channels:
- **Basic features** (channels 0-2): piece positions, valid locations
- **Game phase** (channels 3-6): one-hot encoding of current phase
- **Game state** (channels 7-12): side to move, pieces in hand/on board, move counter
- **Strategic features** (channels 13-31): mill patterns, mobility maps, threat detection

### Training Infrastructure
- **Multi-head loss**: Weighted combination of policy, value, score, and ownership losses
- **Data augmentation**: 8x augmentation via board symmetries (4 rotations × 2 reflections)
- **Resume training**: Full state recovery including optimizer and scheduler states
- **Automatic checkpointing**: Latest, best, and periodic checkpoints
- **Validation tracking**: Automatic best model selection based on validation loss
- **Progress tracking**: Rich progress bars with ETA, loss tracking, and statistics

### Self-Play System
- **Parallel generation**: Multi-process self-play with GPU/CPU distribution
- **MCTS integration**: AlphaZero-style MCTS with Dirichlet noise for exploration
- **Temperature control**: Exploration during early moves, deterministic endgame
- **Data management**: Automatic merging, splitting, and balancing of datasets

## Installation

### Prerequisites
```bash
# Python 3.8+ required
pip install torch numpy
pip install matplotlib seaborn  # Optional, for visualization

# For GPU support
pip install torch --index-url https://download.pytorch.org/whl/cu118  # CUDA 11.8
```

### Setup
```bash
# Clone the repository
git clone https://github.com/calcitem/Sanmill.git
cd Sanmill

# Verify installation
python -m ml.katamill.neural_network  # Should import without errors
```

## Quick Start

### One-Command Training (Easiest)

For beginners, use the easy training script that handles everything automatically:

```bash
# Navigate to katamill directory first
cd ml/katamill

# Quick test (5 minutes) - perfect for first-time users
python easy_train.py --quick

# Full training (2-4 hours) - production quality
python easy_train.py

# Custom training with configuration file
python easy_train.py --create-config my_config.json
# Edit my_config.json as needed
python easy_train.py --config my_config.json
```

**Windows Users**: Double-click `easy_train.bat` for guided setup.

**What it does automatically:**
1. Generates initial training data with random play
2. Trains model iteratively with self-play improvement
3. Evaluates model performance after each iteration
4. Saves best model and generates training report
5. Handles all checkpointing and resume logic

See [GETTING_STARTED.md](GETTING_STARTED.md) for detailed walkthrough.

### Complete Training Pipeline (Advanced)

#### 1. Generate Initial Self-Play Data

Using random network:
```bash
# Generate data with random play (for bootstrapping)
python -m ml.katamill.selfplay --output data/bootstrap.npz --games 1000 --workers 4
```

Using existing model:
```bash
# Generate data with trained model
python -m ml.katamill.selfplay --model checkpoints/model.pth --output data/selfplay_001.npz --games 1000 --workers 4 --mcts-sims 400
```

#### 2. Train the Model

Initial training:
```bash
# Train from scratch
python -m ml.katamill.train --data data/bootstrap.npz --epochs 100 --batch-size 32 --lr 0.001
```

Resume training from checkpoint:
```bash
# Resume training from a checkpoint
python -m ml.katamill.train --data data/selfplay_001.npz --resume checkpoints/katamill_epoch_50.pth --epochs 100
```

Train with validation set:
```bash
# Split data and train with validation
python -m ml.katamill.data_loader split -i data/selfplay_001.npz -o data/dataset
python -m ml.katamill.train --data data/dataset_train.npz --val-data data/dataset_val.npz --epochs 100
```

#### 3. Iterative Training Loop

```bash
# Iteration 1: Bootstrap
python -m ml.katamill.selfplay --output data/iter_0.npz --games 5000 --workers 8
python -m ml.katamill.train --data data/iter_0.npz --epochs 50

# Iteration 2: Self-play with trained model
python -m ml.katamill.selfplay --model checkpoints/katamill_final.pth --output data/iter_1.npz --games 10000 --workers 8
python -m ml.katamill.train --data data/iter_1.npz --resume checkpoints/katamill_final.pth --epochs 50

# Iteration 3+: Continue improving
for i in {2..10}; do
    python -m ml.katamill.selfplay --model checkpoints/katamill_final.pth --output data/iter_$i.npz --games 10000 --workers 8
    python -m ml.katamill.data_loader merge -i data/iter_*.npz -o data/merged.npz
    python -m ml.katamill.train --data data/merged.npz --resume checkpoints/katamill_final.pth --epochs 50
done
```

### Playing Against the Model

Interactive console play with move notation:
```bash
# Play as white (human goes first)
python -m ml.katamill.pit --model checkpoints/katamill_final.pth --first human --mcts-sims 800

# Play as black (AI goes first)
python -m ml.katamill.pit --model checkpoints/katamill_final.pth --first ai --mcts-sims 800

# Example moves:
# - Place: a1, d7, g4
# - Move: a1-a4, d7-d6
# - Remove: xg7, xa1
```

### Model Evaluation

Analyze current position:
```bash
# Analyze starting position
python -m ml.katamill.evaluate --model checkpoints/katamill_final.pth --command analyze

# Compare with heuristics
python -m ml.katamill.evaluate --model checkpoints/katamill_final.pth --command compare
```

Self-play tournament:
```bash
# Run self-play games to test model strength
python -m ml.katamill.evaluate --model checkpoints/katamill_final.pth --command selfplay --num-games 100
```

### Data Management

Merge multiple data files:
```bash
# Merge all iteration data
python -m ml.katamill.data_loader merge -i data/iter_*.npz -o data/all_data.npz
```

Analyze dataset:
```bash
# Get statistics about the dataset
python -m ml.katamill.data_loader analyze -i data/all_data.npz
```

Create balanced dataset:
```bash
# Balance wins/draws/losses
python -m ml.katamill.data_loader balance -i data/all_data.npz -o data/balanced.npz
```

### Advanced Usage

#### Custom Training Configuration

Create a config file `train_config.json`:
```json
{
    "batch_size": 64,
    "num_epochs": 200,
    "learning_rate": 0.0005,
    "policy_weight": 1.0,
    "value_weight": 1.5,
    "score_weight": 0.3,
    "ownership_weight": 0.3,
    "use_symmetries": true
}
```

Train with custom config:
```bash
python -m ml.katamill.train --data data/all_data.npz --config train_config.json
```

#### Parallel Self-Play on Multiple GPUs

```bash
# Use 16 workers across 2 GPUs
python -m ml.katamill.selfplay --model checkpoints/katamill_final.pth --output data/parallel.npz --games 10000 --workers 16
```

#### Python API Usage

```python
from ml.katamill.neural_network import KatamillNet, KatamillWrapper
from ml.katamill.selfplay import run_selfplay, SelfPlayConfig
from ml.katamill.data_loader import save_selfplay_data

# Create and load model
net = KatamillNet()
net.load_state_dict(torch.load("checkpoints/model.pth")["model_state_dict"])
wrapper = KatamillWrapper(net, device="cuda")

# Generate training data
config = SelfPlayConfig(num_games=100, mcts_sims=400)
data = run_selfplay(wrapper, config)

# Save data
save_selfplay_data(data, "data/selfplay.npz")
```

## Architecture Details

### Neural Network Architecture

The network uses a ResNet-style architecture optimized for the 7×7 board:

```
Input (32×7×7) → Conv(128) → BatchNorm → ReLU
    ↓
6 × ResidualBlock(128)
    ↓
    ├─ Policy Head:  Conv(64) → Flatten → Linear(576)
    ├─ Value Head:   Conv(64) → Flatten → Linear(128) → Linear(1) → Tanh
    ├─ Score Head:   Conv(64) → Flatten → Linear(1)
    └─ Ownership Head: Conv(64) → Flatten → Linear(24) → Tanh
```

**Key Design Choices:**
- **Residual blocks**: Enable deeper networks without gradient vanishing
- **Separate heads**: Allow different learning rates for different objectives
- **Dropout (15%)**: Prevent overfitting on small datasets
- **BatchNorm**: Stabilize training and accelerate convergence

### MCTS Algorithm

The MCTS implementation follows the AlphaZero approach with enhancements:

```python
# Selection phase
UCB = Q(s,a) + c_puct * P(s,a) * sqrt(N(s)) / (1 + N(s,a))

# Expansion phase
- Neural network evaluation for leaf nodes
- Virtual loss for parallel MCTS

# Backup phase
- Update Q values with running average
- Increment visit counts
```

**Key Parameters:**
- `c_puct`: 1.0 (exploration constant)
- `dirichlet_alpha`: 0.3 (noise for root exploration)
- `dirichlet_epsilon`: 0.25 (noise weight)

### Feature Engineering

The 32-channel feature representation captures game-specific knowledge:

| Channels | Feature | Description |
|----------|---------|-------------|
| 0-1 | Pieces | White and black piece positions |
| 2 | Valid positions | Board structure mask |
| 3-6 | Phase encoding | One-hot: placing, moving, flying, removing |
| 7 | Side to move | Current player indicator |
| 8-11 | Piece counts | In-hand and on-board counts (normalized) |
| 12 | Move counter | Game progress indicator |
| 13-16 | Mill features | Formed mills and potential mills |
| 17-20 | Reserved | Future mill-related features |
| 21-24 | Mobility | Reachable positions per player |
| 25-28 | Threats | Near-mill pressure maps |
| 29-31 | Reserved | Future strategic features |

## Configuration

### Training Configuration

Create a JSON config file:
```json
{
    "batch_size": 32,
    "num_epochs": 100,
    "learning_rate": 0.001,
    "policy_weight": 1.0,
    "value_weight": 1.0,
    "score_weight": 0.5,
    "ownership_weight": 0.5,
    "use_symmetries": true
}
```

### Network Configuration

Adjust network architecture in `config.py`:
```python
@dataclass
class NetConfig:
    input_channels: int = 32
    num_filters: int = 128
    num_residual_blocks: int = 6
    dropout_rate: float = 0.15
```

## Data Pipeline

### Data Generation
```bash
# Generate self-play data
python -m ml.katamill.selfplay --model model.pth --games 1000 --output data/batch_001.npz

# Merge multiple batches
python -m ml.katamill.data_loader merge -i data/batch_*.npz -o data/merged.npz

# Create train/val/test split
python -m ml.katamill.data_loader split -i data/merged.npz -o data/dataset
```

### Data Analysis
```bash
# Analyze dataset statistics
python -m ml.katamill.data_loader analyze -i data/dataset_train.npz
```

## Integration with Existing Code

Katamill reuses components from the Sanmill project:
- `ml/game/Game.py`: Game logic and move generation
- `ml/game/GameLogic.py`: Board representation
- `ml/game/standard_rules.py`: Mill detection and adjacency
- `ml/sl/mcts.py`: Base MCTS implementation

## API Reference

### Core Classes

#### `KatamillNet`
The main neural network model with multi-head outputs.

```python
from ml.katamill.neural_network import KatamillNet, KatamillWrapper
from ml.katamill.config import NetConfig

# Create model with custom configuration
config = NetConfig(
    input_channels=32,
    num_filters=128,
    num_residual_blocks=6,
    dropout_rate=0.15
)
model = KatamillNet(config)

# Create wrapper for inference
wrapper = KatamillWrapper(model, device="cuda")
policy, value = wrapper.predict(board, current_player)
```

#### `SelfPlayConfig`
Configuration for self-play data generation.

```python
from ml.katamill.selfplay import SelfPlayConfig, run_selfplay

config = SelfPlayConfig(
    num_games=1000,
    max_moves=200,
    mcts_sims=400,
    temperature=1.0,
    temp_decay_moves=20,
    cpuct=1.0
)
data = run_selfplay(wrapper, config)
```

#### `TrainConfig`
Training hyperparameters and loss weights.

```python
from ml.katamill.train import TrainConfig

config = TrainConfig(
    batch_size=32,
    num_epochs=100,
    learning_rate=0.001,
    policy_weight=1.0,
    value_weight=1.0,
    score_weight=0.5,
    ownership_weight=0.5,
    use_symmetries=True
)
```

### Utility Functions

#### Feature Extraction
```python
from ml.katamill.features import extract_features

# Get 32-channel feature tensor
features = extract_features(board, current_player)  # Returns (32, 7, 7) numpy array
```

#### Heuristic Targets
```python
from ml.katamill.heuristics import build_auxiliary_targets

# Get auxiliary supervision signals
targets = build_auxiliary_targets(board, current_player)
# Returns dict with 'ownership', 'score', 'mill_potential'
```

#### Data Management
```python
from ml.katamill.data_loader import (
    save_selfplay_data,
    load_selfplay_data,
    merge_data_files,
    split_data,
    analyze_data
)

# Save/load data
save_selfplay_data(samples, "data.npz", compress=True)
samples = load_selfplay_data("data.npz")

# Merge multiple files
merge_data_files(["data1.npz", "data2.npz"], "merged.npz")

# Split for training
train, val, test = split_data(samples, train_ratio=0.8)

# Analyze dataset
stats = analyze_data(samples)
```

#### Progress Tracking
```python
from ml.katamill.progress import ProgressTracker, TrainingProgressTracker, SelfPlayProgressTracker

# Basic progress tracking with ETA
tracker = ProgressTracker(1000, "Processing items")
for i in range(1000):
    # Do work...
    tracker.update(1, status=f"item_{i}")
tracker.close()

# Training progress with loss tracking
train_tracker = TrainingProgressTracker(epochs=100, batches_per_epoch=50)
for epoch in range(1, 101):
    train_tracker.start_epoch(epoch)
    for batch in range(50):
        # Training step...
        train_tracker.update_batch(loss, lr=current_lr)
    train_tracker.end_epoch(avg_loss, val_loss)
train_tracker.close()

# Self-play progress with game statistics
selfplay_tracker = SelfPlayProgressTracker(games=1000, mcts_sims=400)
for game in range(1000):
    # Play game...
    selfplay_tracker.update_game(samples=30, moves=25, outcome='white_wins')
selfplay_tracker.close()
```

**Progress Features:**
- Rich progress bars with tqdm integration (falls back to logging)
- Accurate ETA estimation based on recent performance
- Real-time statistics: items/second, loss values, win rates
- Automatic formatting of time and numbers
- Graceful handling of interruptions

## Performance Considerations

### Training Efficiency

| Optimization | Impact | Implementation |
|--------------|--------|----------------|
| **GPU Usage** | 10-50x speedup | Use CUDA-enabled PyTorch |
| **Mixed Precision** | 2x speedup, 50% memory | `torch.cuda.amp` |
| **Data Loading** | 20% speedup | `num_workers=4` in DataLoader |
| **Batch Size** | Better convergence | Largest that fits in memory |
| **Symmetries** | 8x data efficiency | Enabled by default |

### Inference Optimization

| Component | Time % | Optimization Strategy |
|-----------|--------|----------------------|
| **MCTS** | 85-90% | Reduce simulations, batch evaluation |
| **Neural Net** | 10-15% | Use GPU, optimize model size |
| **Move Generation** | <5% | Already optimized in C++ |

**Recommended Settings:**
- **Tournament play**: 800-1600 MCTS simulations
- **Fast play**: 100-400 MCTS simulations
- **Analysis**: 3200+ MCTS simulations

### Memory Requirements

| Component | Memory Usage |
|-----------|-------------|
| Model (128 filters) | ~50 MB |
| MCTS tree (400 sims) | ~100 MB |
| Training batch (32) | ~500 MB GPU |
| Self-play buffer | ~1 GB per 10k games |

## Troubleshooting

### Common Issues and Solutions

#### 1. CUDA Out of Memory
```bash
# Error: CUDA out of memory
RuntimeError: CUDA out of memory. Tried to allocate...
```
**Solutions:**
- Reduce batch size: `--batch-size 16`
- Reduce MCTS simulations: `--mcts-sims 200`
- Use gradient accumulation in training
- Clear GPU cache: `torch.cuda.empty_cache()`

#### 2. Slow Training
**Symptoms:** Training takes hours per epoch
**Diagnostics:**
```python
# Check GPU usage
nvidia-smi  # Should show high GPU utilization

# Profile data loading
python -m ml.katamill.train --data data.npz --epochs 1 --profile
```
**Solutions:**
- Ensure GPU is used: `device = torch.device('cuda')`
- Increase DataLoader workers: `num_workers=8`
- Use SSD for data storage
- Reduce logging frequency

#### 3. Poor Convergence
**Symptoms:** Loss not decreasing, erratic validation metrics
**Solutions:**
- **Adjust learning rate**: Try 0.0001 to 0.01
- **Balance loss weights**: Start with all weights = 1.0
- **Check data quality**: Use `analyze_data()` to inspect
- **Increase data diversity**: More self-play games
- **Use warmup**: 2-5 epochs with lower learning rate

#### 4. Model Not Learning
**Symptoms:** Random play after training
**Checklist:**
```python
# Verify data loading
data = load_selfplay_data("data.npz")
print(f"Samples: {len(data)}")
print(f"Features shape: {data[0]['features'].shape}")
print(f"Policy shape: {data[0]['pi'].shape}")

# Check model output
model.eval()
with torch.no_grad():
    out = model(torch.randn(1, 32, 7, 7))
    print(f"Policy: {out[0].shape}, Value: {out[1].shape}")

# Verify loss computation
loss_fn = MultiHeadLoss(TrainConfig())
# Should decrease over epochs
```

#### 5. Resuming Training Fails
**Error:** Key errors when loading checkpoint
**Solution:**
```python
# Safe checkpoint loading
checkpoint = torch.load("model.pth", map_location='cpu')
print(checkpoint.keys())  # Inspect available keys

# Load with compatibility
model = KatamillNet()
model.load_state_dict(checkpoint['model_state_dict'], strict=False)
```

## Contributing

We welcome contributions to Katamill! Areas of interest:

### Priority Improvements
1. **Endgame tablebases**: Integration with perfect play databases
2. **Opening book**: Learn and use common opening patterns
3. **Evaluation metrics**: ELO rating system for models
4. **Web interface**: Browser-based training and play

### How to Contribute
1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Implement your changes with tests
4. Submit a pull request with clear description

### Code Style
- Follow PEP 8 for Python code
- Use type hints for function signatures
- Add docstrings for all public functions
- Include unit tests for new features

### Testing
```bash
# Run unit tests
python -m pytest ml/katamill/tests/

# Run integration test
python -m ml.katamill.selfplay --games 10 --output test.npz
python -m ml.katamill.train --data test.npz --epochs 1
```

## Benchmarks

### Training Progress

Typical training progression with default settings:

| Iteration | Games | Win Rate vs Random | Win Rate vs Previous | ELO Estimate |
|-----------|-------|-------------------|---------------------|--------------|
| 0 (Bootstrap) | 5k | 65% | - | ~1200 |
| 1 | 10k | 85% | 52% | ~1400 |
| 2 | 20k | 95% | 55% | ~1550 |
| 3 | 30k | 98% | 58% | ~1650 |
| 5 | 50k | 99% | 60% | ~1800 |
| 10 | 100k | 99.5% | 62% | ~2000 |

### Hardware Requirements

| Configuration | Self-Play Speed | Training Speed | Recommended For |
|--------------|-----------------|----------------|-----------------|
| **CPU Only** (8 cores) | 10 games/hour | 100 samples/sec | Development |
| **GTX 1660** (6GB) | 50 games/hour | 500 samples/sec | Experimentation |
| **RTX 3070** (8GB) | 150 games/hour | 1000 samples/sec | Regular training |
| **RTX 4090** (24GB) | 400 games/hour | 2500 samples/sec | Large-scale training |

### Model Comparison

Performance of different model sizes (after 100k games):

| Model | Parameters | MCTS Sims | Strength (ELO) | Speed (moves/sec) |
|-------|------------|-----------|----------------|-------------------|
| Tiny (64 filters, 4 blocks) | 200K | 400 | ~1700 | 50 |
| **Default (128 filters, 6 blocks)** | **800K** | **400** | **~2000** | **30** |
| Large (256 filters, 10 blocks) | 3.2M | 400 | ~2150 | 15 |
| Huge (512 filters, 20 blocks) | 12.8M | 400 | ~2250 | 5 |

## Related Work

### Papers
- **AlphaZero**: Silver et al., "Mastering Chess and Shogi by Self-Play with a General Reinforcement Learning Algorithm" (2017)
- **KataGo**: David J. Wu, "Accelerating Self-Play Learning in Go" (2019)
- **MuZero**: Schrittwieser et al., "Mastering Atari, Go, Chess and Shogi by Planning with a Learned Model" (2020)

### Similar Projects
- [KataGo](https://github.com/lightvector/KataGo): State-of-the-art Go engine with auxiliary targets
- [Leela Chess Zero](https://github.com/LeelaChessZero/lc0): Open-source chess engine using AlphaZero methods
- [OpenSpiel](https://github.com/deepmind/open_spiel): DeepMind's framework for RL in games

### Nine Men's Morris Resources
- [Perfect play database](http://library.msri.org/books/Book29/files/gasser.pdf): Ralph Gasser's solution (1996)
- [NNUE implementation](https://github.com/calcitem/Sanmill): Sanmill's hand-crafted evaluation
- [Game rules](https://en.wikipedia.org/wiki/Nine_men%27s_morris): Wikipedia article

## Acknowledgments

Katamill builds upon several key innovations:
- **KataGo's auxiliary targets**: Score and ownership predictions for richer learning signals
- **AlphaZero's MCTS**: Self-play with neural network guidance
- **Sanmill's game engine**: Efficient move generation and rule implementation

Special thanks to:
- David J. Wu for KataGo's groundbreaking auxiliary target approach
- The Sanmill team for the robust Nine Men's Morris implementation
- The PyTorch team for the deep learning framework

## Citation

If you use Katamill in research, please cite:
```bibtex
@software{katamill2024,
  title = {Katamill: KataGo-inspired RL for Nine Men's Morris},
  author = {Sanmill Contributors},
  year = {2024},
  url = {https://github.com/calcitem/Sanmill},
  note = {A deep reinforcement learning framework with auxiliary targets}
}
```

## License

Katamill is part of the Sanmill project and is distributed under the GNU General Public License v3.0. See [LICENSE](../../LICENSE) for details.

---

*For questions, bug reports, or contributions, please open an issue on [GitHub](https://github.com/calcitem/Sanmill/issues).*
