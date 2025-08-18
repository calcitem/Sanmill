#!/bin/bash
# Perfect Database Training Workflow Example for NNUE PyTorch
# This script demonstrates the complete workflow from data generation to model training

set -e  # Exit on any error

# Configuration
PERFECT_DB_PATH="${1:-/path/to/perfect/database}"
OUTPUT_DIR="perfect_db_training_example"
POSITIONS=10000
BATCH_SIZE=4096
MAX_EPOCHS=100

echo "=============================================="
echo "Perfect Database NNUE Training Workflow"
echo "=============================================="
echo "Perfect DB Path: $PERFECT_DB_PATH"
echo "Output Directory: $OUTPUT_DIR"
echo "Positions: $POSITIONS"
echo "=============================================="

# Check if Perfect Database path is provided
if [ "$PERFECT_DB_PATH" = "/path/to/perfect/database" ]; then
    echo "❌ Please provide Perfect Database path as first argument:"
    echo "   $0 /actual/path/to/perfect/database"
    exit 1
fi

# Check if Perfect Database exists
if [ ! -d "$PERFECT_DB_PATH" ]; then
    echo "❌ Perfect Database directory not found: $PERFECT_DB_PATH"
    exit 1
fi

# Check for .sec2 files
SEC2_COUNT=$(find "$PERFECT_DB_PATH" -name "*.sec2" | wc -l)
if [ "$SEC2_COUNT" -eq 0 ]; then
    echo "❌ No .sec2 files found in Perfect Database directory"
    exit 1
fi

echo "✅ Perfect Database validated: $SEC2_COUNT .sec2 files found"

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo ""
echo "📊 Step 1: Generate training data..."
echo "=========================================="

# Generate base training data
python ../generate_training_data.py \
    --perfect-db "$PERFECT_DB_PATH" \
    --output "training_data.txt" \
    --positions $POSITIONS \
    --batch-size 1000 \
    --seed 42

if [ $? -ne 0 ]; then
    echo "❌ Training data generation failed"
    exit 1
fi

echo "✅ Training data generated successfully"

echo ""
echo "📊 Step 2: Generate validation data..."
echo "=========================================="

# Generate smaller validation dataset
VAL_POSITIONS=$((POSITIONS / 10))
python ../generate_training_data.py \
    --perfect-db "$PERFECT_DB_PATH" \
    --output "validation_data.txt" \
    --positions $VAL_POSITIONS \
    --batch-size 500 \
    --seed 123

if [ $? -ne 0 ]; then
    echo "❌ Validation data generation failed"
    exit 1
fi

echo "✅ Validation data generated successfully"

echo ""
echo "🔍 Step 3: Validate generated data..."
echo "=========================================="

# Validate the generated data
python ../example_perfect_db_training.py \
    --perfect-db "$PERFECT_DB_PATH" \
    --output "training_data.txt" \
    --validate-only

if [ $? -ne 0 ]; then
    echo "❌ Data validation failed"
    exit 1
fi

echo "✅ Data validation successful"

echo ""
echo "🚀 Step 4: Train NNUE model..."
echo "=========================================="

# Train NNUE model with Perfect DB data
python ../train.py "training_data.txt" \
    --validation-data "validation_data.txt" \
    --features "NineMill" \
    --batch-size $BATCH_SIZE \
    --max_epochs $MAX_EPOCHS \
    --lr 8.75e-4 \
    --gpus "0" \
    --precision 16

if [ $? -ne 0 ]; then
    echo "❌ NNUE training failed"
    exit 1
fi

echo "✅ NNUE training completed successfully"

echo ""
echo "🎉 Perfect Database NNUE Training Workflow Completed!"
echo "=========================================="
echo "Generated files in $OUTPUT_DIR:"
ls -la
echo ""
echo "📋 Summary:"
echo "  - Training data: $(wc -l < training_data.txt) lines"
echo "  - Validation data: $(wc -l < validation_data.txt) lines"
echo "  - Model checkpoints: $(find . -name "*.ckpt" | wc -l) files"
echo ""
echo "🎯 Next steps:"
echo "  1. Evaluate model performance with test games"
echo "  2. Generate larger datasets with symmetries:"
echo "     python ../generate_training_data.py --perfect-db '$PERFECT_DB_PATH' --positions 50000 --symmetries"
echo "  3. Train with factorized features:"
echo "     python ../train.py training_data.txt --features 'NineMill^' --batch-size 8192"
echo ""
echo "✅ Workflow completed successfully!"
