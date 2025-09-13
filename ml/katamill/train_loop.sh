#!/bin/bash
# Katamill iterative training loop script
# This script demonstrates a complete training pipeline with resume capability

# Configuration
DATA_DIR="data/katamill"
CHECKPOINT_DIR="checkpoints/katamill"
NUM_ITERATIONS=10
GAMES_PER_ITER=5000
MCTS_SIMS=400
EPOCHS_PER_ITER=50
WORKERS=8
BATCH_SIZE=32

# Create directories
mkdir -p $DATA_DIR
mkdir -p $CHECKPOINT_DIR

echo "Starting Katamill training loop..."

# Iteration 0: Bootstrap with random play
if [ ! -f "$DATA_DIR/iter_0.npz" ]; then
    echo "Iteration 0: Generating bootstrap data with random play..."
    python -m ml.katamill.selfplay \
        --output $DATA_DIR/iter_0.npz \
        --games $GAMES_PER_ITER \
        --workers $WORKERS \
        --mcts-sims 100
fi

if [ ! -f "$CHECKPOINT_DIR/iter_0_final.pth" ]; then
    echo "Iteration 0: Training initial model..."
    python -m ml.katamill.train \
        --data $DATA_DIR/iter_0.npz \
        --epochs $EPOCHS_PER_ITER \
        --batch-size $BATCH_SIZE \
        --checkpoint-dir $CHECKPOINT_DIR/iter_0
    
    # Copy final model for next iteration
    cp $CHECKPOINT_DIR/iter_0/katamill_final.pth $CHECKPOINT_DIR/iter_0_final.pth
fi

# Main training loop
for ((i=1; i<=$NUM_ITERATIONS; i++)); do
    echo "========================================"
    echo "Iteration $i/$NUM_ITERATIONS"
    echo "========================================"
    
    PREV_MODEL="$CHECKPOINT_DIR/iter_$((i-1))_final.pth"
    CURR_DATA="$DATA_DIR/iter_$i.npz"
    CURR_CHECKPOINT_DIR="$CHECKPOINT_DIR/iter_$i"
    CURR_MODEL="$CHECKPOINT_DIR/iter_${i}_final.pth"
    
    # Generate self-play data with current best model
    if [ ! -f "$CURR_DATA" ]; then
        echo "Generating self-play data..."
        python -m ml.katamill.selfplay \
            --model $PREV_MODEL \
            --output $CURR_DATA \
            --games $GAMES_PER_ITER \
            --workers $WORKERS \
            --mcts-sims $MCTS_SIMS
    fi
    
    # Merge with previous data (optional - keeps recent history)
    if [ $i -gt 1 ]; then
        MERGED_DATA="$DATA_DIR/merged_up_to_$i.npz"
        if [ ! -f "$MERGED_DATA" ]; then
            echo "Merging data from recent iterations..."
            # Keep last 3 iterations of data
            START_ITER=$((i-2))
            if [ $START_ITER -lt 0 ]; then
                START_ITER=0
            fi
            
            DATA_FILES=""
            for ((j=$START_ITER; j<=$i; j++)); do
                DATA_FILES="$DATA_FILES $DATA_DIR/iter_$j.npz"
            done
            
            python -m ml.katamill.data_loader merge \
                -i $DATA_FILES \
                -o $MERGED_DATA
            
            CURR_DATA=$MERGED_DATA
        fi
    fi
    
    # Split data for validation
    TRAIN_DATA="$DATA_DIR/iter_${i}_train.npz"
    VAL_DATA="$DATA_DIR/iter_${i}_val.npz"
    
    if [ ! -f "$TRAIN_DATA" ]; then
        echo "Splitting data for training/validation..."
        python -m ml.katamill.data_loader split \
            -i $CURR_DATA \
            -o $DATA_DIR/iter_${i}
    fi
    
    # Train model (resume from previous iteration)
    if [ ! -f "$CURR_MODEL" ]; then
        echo "Training model..."
        
        # Check if we should resume from a checkpoint
        RESUME_ARG=""
        if [ -f "$CURR_CHECKPOINT_DIR/katamill_latest.pth" ]; then
            echo "Resuming from latest checkpoint..."
            RESUME_ARG="--resume $CURR_CHECKPOINT_DIR/katamill_latest.pth"
        elif [ -f "$PREV_MODEL" ]; then
            echo "Starting from previous iteration's model..."
            RESUME_ARG="--resume $PREV_MODEL"
        fi
        
        python -m ml.katamill.train \
            --data $TRAIN_DATA \
            --val-data $VAL_DATA \
            --epochs $EPOCHS_PER_ITER \
            --batch-size $BATCH_SIZE \
            --checkpoint-dir $CURR_CHECKPOINT_DIR \
            $RESUME_ARG
        
        # Copy final model for next iteration
        cp $CURR_CHECKPOINT_DIR/katamill_final.pth $CURR_MODEL
    fi
    
    # Evaluate model performance
    echo "Evaluating model..."
    python -m ml.katamill.evaluate \
        --model $CURR_MODEL \
        --command selfplay \
        --num-games 20
    
    # Optional: Clean up old checkpoints to save space
    if [ $i -gt 3 ]; then
        OLD_ITER=$((i-3))
        echo "Cleaning up old checkpoints from iteration $OLD_ITER..."
        # Keep only final models, remove intermediate checkpoints
        find $CHECKPOINT_DIR/iter_$OLD_ITER -name "katamill_epoch_*.pth" -delete
        find $CHECKPOINT_DIR/iter_$OLD_ITER -name "katamill_latest.pth" -delete
    fi
done

echo "Training loop completed!"
echo "Final model: $CHECKPOINT_DIR/iter_${NUM_ITERATIONS}_final.pth"

# Final evaluation
echo "Running final evaluation..."
python -m ml.katamill.evaluate \
    --model $CHECKPOINT_DIR/iter_${NUM_ITERATIONS}_final.pth \
    --command selfplay \
    --num-games 100

# Create symlink to best model
ln -sf iter_${NUM_ITERATIONS}_final.pth $CHECKPOINT_DIR/katamill_best.pth
echo "Best model linked to: $CHECKPOINT_DIR/katamill_best.pth"
