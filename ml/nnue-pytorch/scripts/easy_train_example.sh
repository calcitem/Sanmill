#!/bin/bash

# Nine Men's Morris NNUE Training Example
# This script demonstrates how to train a Nine Men's Morris NNUE network

python easy_train.py \
    --training-dataset=mill_training_data.txt \
    --validation-dataset=mill_validation_data.txt \
    --num-workers=0 \
    --threads=2 \
    --gpus="0" \
    --batch-size=4096 \
    --max-epochs=200 \
    --lr=8.75e-4 \
    --gamma=0.992 \
    --lambda=1.0 \
    --workspace-path=./mill_train_data \
    --experiment-name=mill_test \
    --features="NineMill" \
    --factorized=false \
    --max-positions=1000000