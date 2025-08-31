# Nine Men's Morris Alpha Zero

## 🎯 Quick Start Training (Only 2 Steps)

### Method 1: Windows Users (Recommended)
```bash
# Double-click to run, or execute in command line:
train.bat
```

### Method 2: Direct Python Execution
```bash
cd ml\alphazero
python train.py
```

## 📊 Training Modes

The program automatically displays 3 training modes to choose from:

1. **Quick Test** (5-10 minutes) - Verify environment setup
2. **Standard Training** (1-2 hours) - Recommended for daily training
3. **Full Training** (4-8 hours) - Achieve best results

## 🔧 Encountering Issues?

If training fails, run the diagnostic tool:
```bash
python diagnose.py
```

## 📁 Output Files

After training completion, model files are saved in:
- `checkpoints_quick/` - Quick test mode
- `checkpoints_standard/` - Standard training mode
- `checkpoints_full/` - Full training mode

## 💡 Important Notes

- **Perfect Database**: Program automatically detects `E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted`
- **No Perfect Database**: Program automatically switches to pure self-play mode, training can still proceed normally
- **Interrupt Training**: Press `Ctrl+C` to safely interrupt, trained models will be saved

That's it! 🚀

---

## 🚀 Complete High-Speed Preprocessing Command

```bash
cd ml/alphazero

# Complete preprocessing of all sec2 files (no data loss)
set AZ_PREFETCH_DB=1
python perfect_db_preprocessor.py \
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" \
    --output-dir "J:\preprocessed_data" \
    --max-workers 24 \
    --force
```

### 📋 Parameter Description

- `--max-workers 8`: Use 8 threads for parallel processing (adjust based on CPU cores)
- `--force`: Force reprocess all files (ensure completeness)
- **No `--max-positions`**: This will process **all positions** in each sector, no data loss

## ⚡ High-Performance Optimized Version

If you have more CPU cores and memory, further optimization is possible:

```bash
# High-performance version (adjust based on your hardware)
python perfect_db_preprocessor.py \
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" \
    --output-dir "preprocessed_data" \
    --max-workers 16 \
    --force

# Set environment variable to enable memory prefetch
set AZ_PREFETCH_DB=1
python perfect_db_preprocessor.py \
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" \
    --output-dir "preprocessed_data" \
    --max-workers 16 \
    --force
```

## 📊 Expected Processing Results

Based on your previous data:
- **1714 sec2 files**
- **~400GB raw data**
- **Expected output: 1-2TB preprocessed data**

```
Processing progress example:
🎯 Nine Men's Morris Alpha Zero Training Progress
================================================================================

📊 Overall Progress:
🗂️  Files |████████████████████████████████████████████████████░░░░░░░░░░░░|  45.2% 775/1714
💾 Size: 180.5 GB / 400.0 GB processed
⏱️  Time: 2h 15m elapsed, 2h 45m remaining

🛠️  Operation: DLL Real Iteration + Neural Network Tensor Conversion
   Position extraction |██████████████████████████████████████████████████|  78.3% 1,250,000/1,597,000

📈 Statistics:
🎯 Files: ✅ 774 completed, 🔄 1 processing, ⏳ 939 pending, ❌ 0 errors
⚡ Speed: 15.2 MB/s (parallel processing)
📊 Success Rate: 100.0%
```

## 🔧 System Resource Optimization

### 1. Set Thread Count Based on CPU Cores

```bash
# Check CPU core count
echo %NUMBER_OF_PROCESSORS%

# Recommended setting: 1-2 times the core count
# 4 cores → --max-workers 4-8
# 8 cores → --max-workers 8-16
# 16 cores → --max-workers 16-32
```

### 2. Memory Optimization Settings

```bash
# Enable memory prefetch cache (if sufficient memory >32GB)
set AZ_PREFETCH_DB=1

# If insufficient memory, disable prefetch
set AZ_PREFETCH_DB=0
```

### 3. Disk Optimization

```bash
# If output directory is on SSD, can improve IO performance
--output-dir "D:\SSD_Drive\preprocessed_data"

# If on mechanical hard drive, reduce concurrency to avoid disk thrashing
--max-workers 4
```

## 📈 Verification After Processing

```bash
# View processing result statistics
python perfect_db_preprocessor.py \
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" \
    --output-dir "preprocessed_data" \
    --stats
```

Expected output:
```
📊 Preprocessing Statistics:
  Total sectors: 1714
  Total positions: 50,000,000+  (actual count depends on database)
  Error positions: 25,000
  Error rate: 0.05%
  Source file size: 400.0 GB
  Output directory: preprocessed_data

📈 Game phase distribution:
  placement: 800 sectors, 20,000,000 positions
  moving: 750 sectors, 25,000,000 positions
  flying: 164 sectors, 8,000,000 positions
```

## 🚨 Important Considerations

### 1. Disk Space Check
```bash
# Check available space before preprocessing
dir "preprocessed_data"
# Ensure at least 1-2TB available space
```

### 2. Process Monitoring
```bash
# Monitor processes in another terminal
tasklist | findstr python
# Monitor memory and CPU usage
```

### 3. Resume from Checkpoint
```bash
# If processing is interrupted, run the same command again
# System will automatically skip processed files and continue with remaining ones
python perfect_db_preprocessor.py \
    --perfect-db "E:\Malom\..." \
    --output-dir "preprocessed_data" \
    --max-workers 8
    # Note: Don't use --force, let system automatically skip processed files
```

## 🎯 Final Verification and Usage

After processing completion:

```bash
# 1. Verify data integrity
python test_fast_training.py \
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" \
    --output-dir "preprocessed_data" \
    --skip-preprocessing

# 2. Benchmark loading speed
python fast_data_loader.py \
    --data-dir "preprocessed_data" \
    --benchmark

# 3. Start ultra-high-speed training!
python train.py --use-preprocessed-data "preprocessed_data"
```

Now you can enjoy **complete and ultra-fast** training data! 🚀