# NNUE Training Configuration Files

This directory contains pre-configured training setups for different use cases. Using configuration files eliminates the need to specify many command-line parameters.

## Usage

```bash
# Use a configuration file
python train_nnue.py --config configs/default.json

# Override specific parameters
python train_nnue.py --config configs/fast.json --epochs 100 --batch-size 2048

# Generate a custom configuration template
python train_nnue.py --save-config my_config.json
```

## Available Configurations

### 🎯 `default.json` - Recommended for Most Users
- **Use case**: General purpose training
- **Hardware**: Modern system (16+ GB RAM, dedicated GPU)
- **Training time**: ~2-4 hours
- **Features**: Adaptive LR, visualization, balanced performance

```bash
python train_nnue.py --config configs/default.json --data training_data.txt
```

### ⚡ `fast.json` - Quick Experiments
- **Use case**: Rapid prototyping, hyperparameter testing
- **Hardware**: Any system with GPU
- **Training time**: ~30-60 minutes
- **Features**: Smaller network, fewer epochs, limited data

```bash
python train_nnue.py --config configs/fast.json --data training_data.txt
```

### 🏆 `high_quality.json` - Best Performance
- **Use case**: Production models, research, competition
- **Hardware**: High-end system (32+ GB RAM, RTX 4090+)
- **Training time**: ~6-12 hours
- **Features**: Large network, extended training, full dataset

```bash
python train_nnue.py --config configs/high_quality.json --data training_data.txt
```

### 💻 `cpu_only.json` - No GPU Required
- **Use case**: CPU-only systems, cloud instances without GPU
- **Hardware**: Multi-core CPU (8+ cores recommended)
- **Training time**: ~4-8 hours
- **Features**: CPU-optimized batch sizes, conservative settings

```bash
python train_nnue.py --config configs/cpu_only.json --data training_data.txt
```

### 📊 `large_dataset.json` - Massive Data
- **Use case**: Datasets > 1M samples, research projects
- **Hardware**: High-end system (64+ GB RAM, multiple GPUs)
- **Training time**: ~12-24 hours
- **Features**: Large batches, extended epochs, minimal validation split

```bash
python train_nnue.py --config configs/large_dataset.json --data training_data.txt
```

### 🐛 `debug.json` - Development & Testing
- **Use case**: Development, debugging, unit tests
- **Hardware**: Any system
- **Training time**: ~5-10 minutes
- **Features**: Minimal setup, quick validation, small dataset

```bash
python train_nnue.py --config configs/debug.json --data training_data.txt
```

## Configuration File Format

Configuration files use JSON format with the following structure:

```json
{
  "_description": "Human-readable description",
  "_use_case": "When to use this configuration",
  "_hardware": "Hardware recommendations",
  
  "data": "training_data.txt",
  "output": "nnue_model.bin",
  
  "epochs": 300,
  "batch-size": 8192,
  "lr": 0.002,
  "lr-scheduler": "adaptive",
  "lr-auto-scale": true,
  
  "feature-size": 115,
  "hidden-size": 512,
  "val-split": 0.1,
  
  "device": "auto",
  
  "plot": true,
  "plot-dir": "plots",
  "plot-interval": 5,
  "save-csv": true,
  "show-plots": false
}
```

## Customizing Configurations

### 1. Copy and Modify
```bash
cp configs/default.json my_config.json
# Edit my_config.json with your preferred settings
python train_nnue.py --config my_config.json
```

### 2. Generate Template
```bash
python train_nnue.py --save-config my_template.json
# Edit the generated template
```

### 3. Override Parameters
```bash
# Use config but override specific values
python train_nnue.py --config configs/fast.json --epochs 200 --lr 0.001
```

## Parameter Precedence

1. **Command line arguments** (highest priority)
2. **Configuration file values**
3. **Default values** (lowest priority)

This means you can use a configuration file as a base and override specific parameters via command line.

## Performance Guidance

| Configuration | GPU Memory | System RAM | Training Time | Use Case |
|---------------|------------|------------|---------------|----------|
| debug | 2+ GB | 4+ GB | 5-10 min | Testing |
| fast | 4+ GB | 8+ GB | 30-60 min | Experiments |
| default | 8+ GB | 16+ GB | 2-4 hours | General use |
| cpu_only | N/A | 16+ GB | 4-8 hours | No GPU |
| high_quality | 16+ GB | 32+ GB | 6-12 hours | Production |
| large_dataset | 24+ GB | 64+ GB | 12-24 hours | Research |

## Common Customizations

### Adjust for Your Hardware
```json
{
  "batch-size": 4096,  // Reduce if out of memory
  "hidden-size": 256,  // Reduce for faster training
  "epochs": 100,       // Reduce for quicker results
  "max-samples": 50000 // Limit dataset size
}
```

### Change Output Locations
```json
{
  "output": "models/my_model.bin",
  "plot-dir": "visualizations/my_run",
  "save-csv": true
}
```

### Experiment with Learning Rates
```json
{
  "lr": 0.001,
  "lr-scheduler": "cosine",
  "lr-auto-scale": false
}
```

## Best Practices

1. **Start with `fast.json`** for initial experiments
2. **Use `default.json`** for most training runs
3. **Try `high_quality.json`** for final models
4. **Keep custom configs** in version control
5. **Document your changes** in `_description` fields
6. **Test configurations** with `debug.json` first
