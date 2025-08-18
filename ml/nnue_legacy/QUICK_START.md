# NNUE Training Quick Start Guide

## 🚀 Get Started in 3 Steps

### Step 1: Choose Your Use Case

**Already have training data?** → Use Training Mode  
**Need complete workflow?** → Use Pipeline Mode

### Step 2: Pick a Configuration

**For Training Mode:**
- `configs/fast.json` - Quick experiments (30-60 min)
- `configs/default.json` - General purpose (2-4 hours)  
- `configs/high_quality.json` - Best results (6-12 hours)

**For Pipeline Mode:**
- `configs/pipeline_fast.json` - Quick test (1-2 hours)
- `configs/pipeline.json` - Full workflow (3-5 hours)

### Step 3: Run Training

**Training Mode:**
```bash
python train_nnue.py --config configs/default.json --data training_data.txt
```

**Pipeline Mode:**
```bash
python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/database
```

## 🎯 Examples

### Quick Experiment
```bash
# Fast training for testing
python train_nnue.py --config configs/fast.json --data training_data.txt
```

### Production Quality
```bash
# Best quality model
python train_nnue.py --config configs/high_quality.json --data training_data.txt
```

### Complete Pipeline
```bash
# End-to-end training
python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/perfect/database
```

### Custom Parameters
```bash
# Override specific settings
python train_nnue.py --config configs/default.json --data training_data.txt --epochs 500 --lr 0.001
```

## 🔧 Generate Custom Config

```bash
# Create template with all options
python train_nnue.py --save-config my_config.json

# Edit my_config.json, then use it
python train_nnue.py --config my_config.json --data training_data.txt
```

## 📊 Monitor Training

All configurations include visualization by default:
- Real-time loss curves
- Learning rate schedule
- Gradient health monitoring
- Training speed metrics

Check the `plots/` directory for generated visualizations!

## ❓ Need Help?

**Check environment (Pipeline Mode):**
```bash
python train_nnue.py --config configs/pipeline.json --perfect-db /path/to/db --validate-only
```

**Test with minimal setup:**
```bash
python train_nnue.py --config configs/debug.json --data training_data.txt
```

**See all options:**
```bash
python train_nnue.py --help
```

That's it! The system handles everything else automatically. 🎉
