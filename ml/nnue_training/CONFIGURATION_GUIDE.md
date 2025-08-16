# NNUE Training Configuration Guide

## Overview

This guide covers the comprehensive configuration system for NNUE training, designed to eliminate the complexity of specifying numerous command-line parameters while providing flexibility for different training scenarios.

## Quick Start

### 🚀 Basic Usage

```bash
# Use default settings (recommended for most users)
python train_nnue.py --config configs/default.json --data training_data.txt

# Complete pipeline from data generation to trained model
python train_pipeline_parallel.py --config configs/pipeline_default.json --perfect-db /path/to/db
```

### ⚡ Generate Your Own Config

```bash
# Generate a template with all options
python train_nnue.py --save-config my_config.json

# Edit my_config.json, then use it
python train_nnue.py --config my_config.json --data training_data.txt
```

## Pre-built Configurations

### Training Configurations (`configs/`)

| File | Use Case | Training Time | Hardware Requirements |
|------|----------|---------------|----------------------|
| **`default.json`** | General purpose, balanced | 2-4 hours | 16+ GB RAM, GPU |
| **`fast.json`** | Quick experiments, prototyping | 30-60 min | 8+ GB RAM, GPU |
| **`high_quality.json`** | Production models, research | 6-12 hours | 32+ GB RAM, High-end GPU |
| **`cpu_only.json`** | CPU-only systems | 4-8 hours | 8+ core CPU, 16+ GB RAM |
| **`large_dataset.json`** | Massive datasets (1M+ samples) | 12-24 hours | 64+ GB RAM, Multiple GPUs |
| **`debug.json`** | Development, testing, CI/CD | 5-10 min | Any system |

### Pipeline Configurations

| File | Use Case | Description |
|------|----------|-------------|
| **`pipeline_default.json`** | Complete training pipeline | Data generation + training |
| **`pipeline_fast.json`** | Quick pipeline testing | Reduced dataset + fast training |

## Configuration File Format

### Basic Structure

```json
{
  "_description": "Human-readable description of this config",
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
  "save-csv": true
}
```

### Comment Fields

Fields starting with `_` are comments and are ignored during execution:

- `_description`: What this configuration is for
- `_use_case`: When to use this setup
- `_hardware`: Hardware recommendations
- `_notes`: Additional information

## Parameter Reference

### Core Training Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `data` | string | required | Training data file path |
| `output` | string | `nnue_model.bin` | Output model file |
| `epochs` | integer | 300 | Number of training epochs |
| `batch-size` | integer | 8192 | Training batch size |
| `lr` | float | 0.002 | Initial learning rate |
| `lr-scheduler` | string | `adaptive` | LR scheduler type |
| `lr-auto-scale` | boolean | false | Automatic LR scaling |

### Model Architecture

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `feature-size` | integer | 115 | Input feature dimensions |
| `hidden-size` | integer | 512 | Hidden layer size |
| `val-split` | float | 0.1 | Validation data ratio |
| `max-samples` | integer | null | Limit training samples |

### Training Control

| Parameter | Type | Options | Description |
|-----------|------|---------|-------------|
| `device` | string | `auto`, `cpu`, `cuda` | Training device |
| `lr-scheduler` | string | `adaptive`, `cosine`, `plateau`, `fixed` | LR scheduling strategy |

### Visualization

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `plot` | boolean | false | Enable training plots |
| `plot-dir` | string | `plots` | Plot output directory |
| `plot-interval` | integer | 5 | Plot update frequency |
| `show-plots` | boolean | false | Real-time plot display |
| `save-csv` | boolean | false | Save metrics to CSV |

### Pipeline-Specific Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `engine` | string | required | Sanmill engine path |
| `perfect-db` | string | required | Perfect database path |
| `output-dir` | string | `./nnue_output` | Output directory |
| `positions` | integer | 500000 | Training positions to generate |
| `threads` | integer | 0 | Parallel threads (0=auto) |

## Usage Patterns

### 1. Simple Training

```bash
# Use default configuration
python train_nnue.py --config configs/default.json --data my_data.txt
```

### 2. Override Specific Parameters

```bash
# Use config but change epochs and batch size
python train_nnue.py \
    --config configs/default.json \
    --data my_data.txt \
    --epochs 500 \
    --batch-size 16384
```

### 3. Custom Configuration

```bash
# Generate template
python train_nnue.py --save-config my_custom.json

# Edit my_custom.json with your settings
# Then use it
python train_nnue.py --config my_custom.json --data my_data.txt
```

### 4. Complete Pipeline

```bash
# Full pipeline with configuration
python train_pipeline_parallel.py \
    --config configs/pipeline_default.json \
    --perfect-db /path/to/perfect/database
```

## Configuration Recommendations

### 🎯 For Beginners
- Start with `configs/fast.json` for experimentation
- Use `configs/default.json` for real training
- Enable visualization with `"plot": true`

### ⚡ For Quick Testing
- Use `configs/debug.json` for development
- Set `"max-samples": 10000` to limit dataset size
- Use `"epochs": 10` for quick validation

### 🏆 For Production
- Use `configs/high_quality.json` as baseline
- Increase `"hidden-size"` for better accuracy
- Use `"lr-auto-scale": true` for optimal LR
- Enable `"save-csv": true` for analysis

### 💻 For Limited Hardware
- Use `configs/cpu_only.json` for CPU training
- Reduce `"batch-size"` if out of memory
- Decrease `"hidden-size"` for faster training
- Set `"max-samples"` to limit dataset

## Advanced Customization

### Custom Learning Rate Schedule

```json
{
  "lr": 0.001,
  "lr-scheduler": "cosine",
  "lr-auto-scale": false
}
```

### Memory Optimization

```json
{
  "batch-size": 2048,
  "hidden-size": 256,
  "max-samples": 100000,
  "val-split": 0.15
}
```

### High-Performance Setup

```json
{
  "batch-size": 32768,
  "hidden-size": 1024,
  "lr": 0.0008,
  "lr-auto-scale": true,
  "device": "cuda"
}
```

### Debugging Configuration

```json
{
  "epochs": 5,
  "batch-size": 32,
  "max-samples": 1000,
  "plot-interval": 1,
  "save-csv": true
}
```

## Parameter Priority

The system uses the following priority order:

1. **Command-line arguments** (highest priority)
2. **Configuration file values**
3. **Default values** (lowest priority)

This allows flexible overriding:

```bash
# Config sets epochs=300, but command line overrides to 500
python train_nnue.py --config configs/default.json --epochs 500
```

## Best Practices

### 📁 File Organization
```
my_project/
├── configs/
│   ├── my_config.json
│   └── experiment_configs/
├── data/
│   └── training_data.txt
├── models/
│   └── nnue_model.bin
└── plots/
    └── training_progress.png
```

### 🔄 Version Control
- Keep configuration files in version control
- Use descriptive names: `experiment_2024_01_15.json`
- Document changes in `_description` field

### 🧪 Experimentation
- Create config variants for A/B testing
- Use different `plot-dir` for each experiment
- Save results with `save-csv: true`

### 📊 Monitoring
- Enable visualization for all training runs
- Use meaningful `output` filenames
- Monitor `plot-interval` vs training time

## Troubleshooting

### Configuration Loading Issues

```bash
# Check if config file exists and is valid JSON
python -m json.tool configs/my_config.json

# Generate fresh template if needed
python train_nnue.py --save-config fresh_template.json
```

### Parameter Conflicts

```bash
# See what values are actually being used
python train_nnue.py --config configs/default.json --help
```

### Memory Issues

```json
{
  "batch-size": 1024,    // Reduce from 8192
  "hidden-size": 256,    // Reduce from 512
  "max-samples": 50000   // Limit dataset size
}
```

### Training Too Slow

```json
{
  "epochs": 100,         // Reduce from 300
  "plot-interval": 20,   // Update plots less often
  "val-split": 0.05      // Smaller validation set
}
```

## Examples Repository

See the `configs/` directory for production-ready configurations:

- **Learning**: Start with `default.json`
- **Development**: Use `debug.json`
- **Production**: Try `high_quality.json`
- **Research**: Adapt `large_dataset.json`

Each configuration includes detailed comments explaining the parameter choices and expected hardware requirements.
