#!/bin/bash

# Example usage of the adapted train.py for Nine Men's Morris
# This demonstrates how the original train.py architecture is preserved
# while supporting Nine Men's Morris data formats

echo "Nine Men's Morris NNUE Training with Adapted train.py"
echo "===================================================="

# Example 1: Basic training with Nine Men's Morris text data
echo "Example 1: Basic training with text data"
python train.py \
    mill_training_data.txt \
    --validation-data mill_validation_data.txt \
    --features "NineMill" \
    --batch-size 8192 \
    --max_epochs 400 \
    --gpus "0" \
    --lr 8.75e-4 \
    --gamma 0.992 \
    --lambda 1.0

echo ""
echo "Example 2: Training with factorized features"
python train.py \
    mill_training_data.txt \
    --validation-data mill_validation_data.txt \
    --features "NineMill^" \
    --batch-size 8192 \
    --max_epochs 400 \
    --gpus "0" \
    --lr 8.75e-4

echo ""
echo "Example 3: Training with custom loss parameters"
python train.py \
    mill_training_data.txt \
    --validation-data mill_validation_data.txt \
    --features "NineMill" \
    --batch-size 4096 \
    --max_epochs 200 \
    --in-offset 80 \
    --out-offset 80 \
    --in-scaling 120 \
    --out-scaling 120 \
    --lambda 0.8

echo ""
echo "Key advantages of adapted train.py:"
echo "- Preserves all original sophisticated PyTorch Lightning features"
echo "- Dedicated Nine Men's Morris text data format support"
echo "- Simplified and clean architecture (no chess binpack complexity)"
echo "- Full PyTorch Lightning integration"
echo "- Advanced checkpointing and resuming"
echo "- TensorBoard logging"
echo "- Multi-GPU support"
echo "- Optimized defaults for Nine Men's Morris"
