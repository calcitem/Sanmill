# NNUE Training Visualization Guide

## Quick Start

Enable training visualization with a single flag:

```bash
python train_nnue.py --data training_data.txt --plot
```

## Visualization Features

### 📊 Real-time Training Dashboard

Updated every 5 epochs (configurable):

1. **Loss Curves**: Training vs validation loss with trend analysis
2. **Validation Accuracy**: Progress tracking with best performance markers  
3. **Learning Rate Schedule**: Automatic adjustments highlighted
4. **Gradient Health**: Monitoring for vanishing/exploding gradients
5. **Training Speed**: Epoch timing analysis
6. **Overfitting Detection**: Val/Train loss ratio monitoring

### 📈 Final Training Summary

Comprehensive analysis generated at completion:
- Loss curves with moving averages
- Learning progress metrics
- Performance timeline
- Complete training statistics

## Command Options

```bash
# Basic visualization
--plot                    # Enable plotting
--plot-dir DIR           # Save plots to directory (default: 'plots')
--plot-interval N        # Update every N epochs (default: 5)
--save-csv               # Export metrics to CSV
--show-plots             # Display real-time (requires GUI)
```

## Example Commands

### Basic Training with Plots
```bash
python train_nnue.py \
    --data training_data.txt \
    --epochs 100 \
    --plot
```

### Custom Visualization Settings
```bash
python train_nnue.py \
    --data training_data.txt \
    --plot \
    --plot-dir ./my_training_plots \
    --plot-interval 10 \
    --save-csv
```

### Complete Pipeline with Visualization
```bash
python train_pipeline_parallel.py \
    --engine ../../sanmill \
    --perfect-db /path/to/db \
    --plot \
    --save-csv \
    --epochs 200
```

### Adaptive Learning Rate + Plots
```bash
python train_nnue.py \
    --data training_data.txt \
    --lr-scheduler adaptive \
    --lr-auto-scale \
    --plot \
    --save-csv
```

## Output Files

| File | Description |
|------|-------------|
| `training_progress_latest.png` | Most recent dashboard |
| `training_progress_epoch_XXXX.png` | Periodic snapshots |
| `training_summary.png` | Final comprehensive analysis |
| `training_metrics.csv` | Raw data for custom analysis |

## Installation

Install visualization dependencies:

```bash
pip install matplotlib seaborn
```

## What the Plots Show

### 📉 Loss Curves
- **Blue line**: Training loss progression
- **Red line**: Validation loss progression  
- **Dashed lines**: Recent trend analysis
- **Key insight**: Gap indicates overfitting

### 📊 Learning Rate Schedule
- **Orange line**: LR changes over time
- **Red dotted lines**: Automatic adjustments
- **Log scale**: Better visualization of changes
- **Annotations**: Show exact LR values

### 🎯 Gradient Health
- **Purple line**: Gradient norm magnitude
- **Red threshold**: Vanishing gradient warning (< 1e-5)
- **Orange threshold**: Exploding gradient warning (> 10.0)
- **Trend**: Indicates optimization health

### ⚡ Training Efficiency
- **Brown line**: Time per epoch
- **Dashed line**: Average time
- **Insight**: Shows if training is getting slower

### 🔍 Overfitting Indicator
- **Teal line**: Validation/Training loss ratio
- **Green line**: Ideal ratio (1.0)
- **Orange/Red lines**: Warning thresholds
- **Monitor**: Values > 1.5 indicate overfitting

## Troubleshooting

### "Matplotlib not available"
```bash
pip install matplotlib seaborn
```

### Plots not updating
- Check `--plot-interval` setting
- Verify `--plot-dir` permissions
- Ensure sufficient disk space

### GUI display issues
- Use `--plot` without `--show-plots` for server environments
- Set `matplotlib.use('Agg')` for headless systems

### Large plot files
- Plots are saved at 150 DPI (real-time) and 300 DPI (summary)
- Reduce `--plot-interval` to save disk space
- Use `--save-csv` for lightweight metric storage

## Advanced Usage

### Custom Analysis with CSV
```python
import pandas as pd
import matplotlib.pyplot as plt

# Load training metrics
df = pd.read_csv('plots/training_metrics.csv')

# Custom plot
plt.figure(figsize=(10, 6))
plt.plot(df['Epoch'], df['Learning_Rate'])
plt.yscale('log')
plt.title('Learning Rate Schedule')
plt.show()
```

### Automated Reporting
```bash
# Generate plots and convert to PDF report
python train_nnue.py --data data.txt --plot --save-csv
convert plots/*.png training_report.pdf
```

### Monitoring Multiple Runs
```bash
# Use different plot directories for comparison
python train_nnue.py --data data.txt --plot --plot-dir run1_plots
python train_nnue.py --data data.txt --plot --plot-dir run2_plots --lr 0.001
```

## Benefits

- **Real-time monitoring**: See training progress as it happens
- **Early problem detection**: Identify overfitting, convergence issues
- **Hyperparameter validation**: Visualize the impact of different settings
- **Professional reporting**: Publication-ready plots and comprehensive summaries
- **Data export**: CSV files for custom analysis and further research

The visualization system makes NNUE training more transparent, easier to debug, and provides professional-quality documentation of your training runs.
