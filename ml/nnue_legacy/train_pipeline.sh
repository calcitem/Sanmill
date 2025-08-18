#!/bin/bash

# NNUE Training Pipeline for Sanmill
# This script demonstrates the complete training process

set -e  # Exit on any error

# Configuration
PERFECT_DB_PATH="."  # Adjust path to Perfect Database
TRAINING_POSITIONS=500000
MODEL_OUTPUT="nnue_model.bin"
TRAINING_DATA="training_data.txt"

echo "=== Sanmill NNUE Training Pipeline (Perfect DB Direct) ==="
echo "Perfect DB: $PERFECT_DB_PATH"
echo "Training positions: $TRAINING_POSITIONS"
echo "Note: Now using Perfect DB DLL directly, no engine executable required"
echo

# Check dependencies
echo "Checking dependencies..."

if [ ! -d "$PERFECT_DB_PATH" ]; then
    echo "Error: Perfect Database not found at $PERFECT_DB_PATH"
    echo "Please provide the correct path to Perfect Database"
    exit 1
fi

# Check Python dependencies
echo "Checking Python dependencies..."
python3 -c "import torch, numpy" || {
    echo "Installing Python dependencies..."
    pip3 install -r requirements.txt
}

echo "Dependencies OK"
echo

# Step 1: Generate training data
echo "=== Step 1: Generating Training Data ==="
echo "This may take a while depending on the number of positions..."
echo "Using Perfect DB DLL directly for optimal performance..."

python3 generate_training_data.py \
    --perfect-db "$PERFECT_DB_PATH" \
    --output "$TRAINING_DATA" \
    --positions $TRAINING_POSITIONS \
    --validate

if [ $? -ne 0 ]; then
    echo "Error: Training data generation failed"
    exit 1
fi

echo "Training data generated successfully"
echo

# Step 2: Train the NNUE model
echo "=== Step 2: Training NNUE Model ==="

python3 train_nnue.py \
    --data "$TRAINING_DATA" \
    --output "$MODEL_OUTPUT" \
    --epochs 300 \
    --batch-size 8192 \
    --lr 0.002 \
    --hidden-size 512 \
    --device auto

if [ $? -ne 0 ]; then
    echo "Error: NNUE training failed"
    exit 1
fi

echo "NNUE model trained successfully"
echo

# Step 3: Test the model
echo "=== Step 3: Testing the Model ==="

if [ -f "$MODEL_OUTPUT" ]; then
    echo "Model file created: $MODEL_OUTPUT"
    ls -lh "$MODEL_OUTPUT"
    echo
    
    # Copy model to engine directory for testing
    cp "$MODEL_OUTPUT" "../../$MODEL_OUTPUT"
    echo "Model copied to engine directory"
    
    # Test with engine
    echo "Testing model with engine..."
    echo -e "uci\nsetoption name UseNNUE value true\nsetoption name NNUEModelPath value $MODEL_OUTPUT\nposition startpos\nd\nquit" | "$ENGINE_PATH"
    
else
    echo "Error: Model file not created"
    exit 1
fi

echo
echo "=== Training Pipeline Completed Successfully! ==="
echo
echo "Next steps:"
echo "1. Copy $MODEL_OUTPUT to your engine directory"
echo "2. Configure the engine:"
echo "   setoption name UseNNUE value true"
echo "   setoption name NNUEModelPath value $MODEL_OUTPUT"
echo "   setoption name NNUEWeight value 90"
echo "3. Test the engine in games"
echo
echo "Training data: $TRAINING_DATA"
echo "Model file: $MODEL_OUTPUT"
