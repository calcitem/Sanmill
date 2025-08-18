#!/bin/bash

# Nine Men's Morris NNUE Training Example using adapted easy_train.py
# This demonstrates the full power of the original easy_train.py adapted for Nine Men's Morris

python easy_train.py \
    --experiment-name mill_experiment_001 \
    --training-dataset ../data/mill_training_data.txt \
    --validation-dataset ../data/mill_validation_data.txt \
    --workspace-path ./mill_train_data \
    --features "NineMill" \
    --batch-size 8192 \
    --max-epochs 400 \
    --lr 8.75e-4 \
    --gamma 0.992 \
    --lambda 1.0 \
    --num-workers 4 \
    --threads 2 \
    --gpus "0" \
    --runs-per-gpu 1 \
    --network-save-period 20 \
    --save-last-network true \
    --epoch-size 1000000 \
    --validation-size 100000 \
    --seed 42 \
    --do-network-training true \
    --do-network-testing false \
    --tui true \
    --resume-training false \
    --random-fen-skipping 1 \
    --smart-fen-skipping false \
    --wld-fen-skipping false \
    --early-fen-skipping -1
