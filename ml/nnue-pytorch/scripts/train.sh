#!/bin/bash

# Nine Men's Morris NNUE Training Script
# Usage: ./train.sh [training_data] [validation_data]

TRAIN_DATA=${1:-"../data/mill_training_data.txt"}
VAL_DATA=${2:-"../data/mill_validation_data.txt"}

python train.py \
 $TRAIN_DATA \
 --val_data $VAL_DATA \
 --gpus 1 \
 --threads 2 \
 --batch_size 8192 \
 --features=NineMill \
 --factorized=false \
 --lambda=1.0 \
 --max_epochs=400 \
 --lr=8.75e-4 \
 --gamma=0.992
