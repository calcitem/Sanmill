# High-Performance Training Guide for Ryzen 7950x + 192GB RAM + RTX4090

This guide explains how to use the optimized training configuration for your high-end hardware setup.

## Hardware Specifications
- **CPU**: AMD Ryzen 7950x (16 cores/32 threads)
- **RAM**: 192GB (128GB available for training)
- **GPU**: NVIDIA RTX4090 (24GB VRAM)
- **Dataset**: ~207GB preprocessed data (48,788 NPZ files)

## Configuration Overview

The `train_with_preprocessed_high_performance.json` configuration is specifically optimized for your hardware:

### Network Architecture
- **Filters**: 768 (increased from 512 for better capacity)
- **Residual Blocks**: 20 (increased from 15 for deeper learning)
- **Dropout Rate**: 0.2 (reduced for large dataset)

### Training Parameters
- **Epochs**: 30 (extended training for large dataset)
- **Batch Size**: 512 (maximizes RTX4090 utilization)
- **Learning Rate**: 0.002 (higher for large batches)
- **Full Dataset Traversal**: Enabled (uses entire 207GB dataset)

### Advanced Optimizations
- **Mixed Precision**: Enabled (essential for RTX4090)
- **Model Compilation**: Enabled (PyTorch 2.0+ optimization)
- **Data Loading Workers**: 12 (utilizes Ryzen 7950x cores)
- **Prefetch Factor**: 4 (aggressive prefetching with 192GB RAM)
- **Pin Memory**: Enabled for faster GPU transfer

### Incremental Training
- **Resume from Checkpoint**: Enabled by default
- **Save Frequency**: Every 2 epochs
- **Keep Checkpoints**: Last 5 checkpoints
- **Automatic Cleanup**: Old checkpoints are automatically removed

## Usage Examples

### 1. Start Fresh Training
```bash
python train_with_preprocessed.py \
  --config train_with_preprocessed_high_performance.json \
  --data-dir "G:\preprocessed_data"
```

### 2. Resume Training from Latest Checkpoint
```bash
python train_with_preprocessed.py \
  --config train_with_preprocessed_high_performance.json \
  --data-dir "G:\preprocessed_data" \
  --resume-training
```

### 3. Resume from Specific Checkpoint
```bash
python train_with_preprocessed.py \
  --config train_with_preprocessed_high_performance.json \
  --data-dir "G:\preprocessed_data" \
  --resume-checkpoint "checkpoints_preprocessed_hp/checkpoint_epoch_10.tar"
```

### 4. Override Configuration Settings
```bash
python train_with_preprocessed.py \
  --config train_with_preprocessed_high_performance.json \
  --data-dir "G:\preprocessed_data" \
  --batch-size 768 \
  --epochs 40 \
  --data-workers 16
```

### 5. Disable Advanced Features (if needed)
```bash
python train_with_preprocessed.py \
  --config train_with_preprocessed_high_performance.json \
  --data-dir "G:\preprocessed_data" \
  --no-mixed-precision \
  --no-compile-model
```

## Performance Expectations

### Memory Usage
- **Dataset Loading**: ~120-150GB RAM (with full traversal)
- **GPU Memory**: ~20-22GB VRAM (batch size 512)
- **System Reserve**: 32GB RAM kept free

### Training Speed
- **Estimated Speed**: 2-3 batches/second (RTX4090 + mixed precision)
- **Time per Epoch**: ~6-8 hours (depends on exact dataset size)
- **Total Training Time**: ~7-10 days for 30 epochs

### Checkpoint Management
- **Checkpoint Size**: ~6-8GB per checkpoint
- **Storage Required**: ~40-50GB for 5 checkpoints
- **Save Frequency**: Every 2 epochs (automatically managed)

## Monitoring and Optimization

### Memory Monitoring
The training script automatically monitors:
- Available RAM
- Memory usage percentage
- Swap usage (strict limits with `no_swap: true`)

### Performance Metrics
- Training loss (policy + value)
- Learning rate schedule (cosine annealing)
- Batch processing speed
- GPU utilization

### Troubleshooting

#### Out of Memory Issues
1. Reduce batch size: `--batch-size 256`
2. Increase gradient accumulation: `--gradient-accumulation 2`
3. Disable full traversal: `--no-full-traversal`

#### Slow Training
1. Check GPU utilization with `nvidia-smi`
2. Verify mixed precision is enabled
3. Ensure data workers are not bottlenecked

#### Checkpoint Issues
1. Check disk space in checkpoint directory
2. Verify write permissions
3. Monitor checkpoint cleanup logs

## Advanced Configuration

### Custom Data Loading
```bash
# Increase data workers for faster loading
--data-workers 16

# Adjust prefetch factor
--prefetch-factor 6

# Disable data shuffling for deterministic training
--no-shuffle
```

### Custom Training Parameters
```bash
# Save checkpoints more frequently
--save-every-n-epochs 1

# Use gradient accumulation for larger effective batch size
--gradient-accumulation 2
```

### Memory Optimization
```bash
# Force strict memory management
--no-swap

# Set custom memory threshold
--memory-threshold 40.0
```

## Expected Results

With this configuration and your hardware, you should expect:
- **High GPU Utilization**: 95%+ on RTX4090
- **Efficient Memory Usage**: ~75% of available RAM
- **Fast Convergence**: Improved training stability with large batch sizes
- **Robust Checkpointing**: Automatic resume capability

## Support

If you encounter issues:
1. Check the training logs for detailed error messages
2. Monitor system resources during training
3. Verify PyTorch and CUDA versions are compatible
4. Ensure sufficient disk space for checkpoints

The configuration automatically handles most optimization details, allowing you to focus on training quality and results.
