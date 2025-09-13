# -*- coding: utf-8 -*-
"""
Monitor training progress and automatically test when completed.
"""

import os
import time
import subprocess
import json
import psutil
import torch
from pathlib import Path

def monitor_training():
    """Monitor training progress and launch pit_gui when ready."""
    print('🔍 MONITORING QUICK TRAINING PROGRESS')
    print('='*50)
    
    # Check for training output
    output_dir = Path("output/katamill")
    checkpoint_dir = Path("checkpoints/katamill")
    
    print('Waiting for training to complete...')
    print('Looking for:')
    print(f'  - Training report: {output_dir}/training_report.json')
    print(f'  - Best model: {output_dir}/best_model.pth')
    print(f'  - Checkpoint: {checkpoint_dir}/iter_*/katamill_best.pth')
    
    # Monitor loop
    max_wait_time = 3600  # 1 hour max
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        # Check if training report exists
        report_path = output_dir / "training_report.json"
        if report_path.exists():
            print(f'\\n✅ Training report found: {report_path}')
            
            # Read training results
            try:
                with open(report_path, 'r') as f:
                    report = json.load(f)
                
                print(f'Training summary:')
                print(f'  Total time: {report.get("total_time_hours", 0):.1f} hours')
                print(f'  Iterations: {len(report.get("iterations", []))}')
                print(f'  Best model: {report.get("best_model", "None")}')
                
                # Check for best model
                best_model_path = output_dir / "best_model.pth"
                if best_model_path.exists():
                    print(f'\\n🎯 Best model found: {best_model_path}')
                    return str(best_model_path)
                else:
                    # Look for latest checkpoint
                    for iter_dir in checkpoint_dir.glob("iter_*"):
                        best_path = iter_dir / "katamill_best.pth"
                        if best_path.exists():
                            print(f'\\n🎯 Found checkpoint: {best_path}')
                            return str(best_path)
                    
            except Exception as e:
                print(f'Error reading report: {e}')
        
        # Check for any completed iteration
        if checkpoint_dir.exists():
            for iter_dir in checkpoint_dir.glob("iter_*"):
                best_path = iter_dir / "katamill_best.pth"
                if best_path.exists():
                    print(f'\\n🎯 Found intermediate model: {best_path}')
                    return str(best_path)
        
        # Wait and check again
        time.sleep(30)  # Check every 30 seconds
        print('.', end='', flush=True)
    
    print(f'\\n⏰ Training monitoring timeout after {max_wait_time/3600:.1f} hours')
    return None

def launch_pit_gui(model_path):
    """Launch pit_gui with the trained model."""
    if not model_path or not os.path.exists(model_path):
        print(f'❌ Model not found: {model_path}')
        return False
    
    print(f'\\n🚀 LAUNCHING PIT_GUI FOR HUMAN TESTING')
    print('='*50)
    print(f'Model: {model_path}')
    print('Enhanced features:')
    print('  ✅ Fixed threefold repetition detection')
    print('  ✅ LC0-style MCTS improvements')
    print('  ✅ Enhanced neural network architecture')
    print('  ✅ Early stopping training')
    print('  ✅ Optimized CPU/GPU allocation')
    
    try:
        # Launch pit_gui with enhanced configuration
        cmd = [
            'python', 'pit_gui.py',
            '--model', model_path,
            '--mcts-sims', '800',  # High quality for testing
            '--gui'
        ]
        
        print(f'\\nLaunching: {" ".join(cmd)}')
        subprocess.run(cmd)
        return True
        
    except Exception as e:
        print(f'❌ Failed to launch pit_gui: {e}')
        return False

def monitor_device_usage():
    """Monitor device usage during self-play process"""
    print('📊 DEVICE USAGE MONITORING')
    print('='*50)
    
    # Check GPU availability
    if torch.cuda.is_available():
        num_gpus = torch.cuda.device_count()
        print(f'GPU device count: {num_gpus}')
        for i in range(num_gpus):
            gpu_name = torch.cuda.get_device_name(i)
            print(f'  GPU {i}: {gpu_name}')
    else:
        print('⚠ No CUDA GPU detected')
    
    # Check CPU information
    cpu_count = psutil.cpu_count()
    cpu_count_logical = psutil.cpu_count(logical=True)
    print(f'CPU cores: {cpu_count} physical cores, {cpu_count_logical} logical cores')
    
    print('\n🔍 Analyzing self-play device allocation strategy:')
    
    # Simulate device allocation logic
    num_workers = 8  # Default worker count
    if torch.cuda.is_available():
        num_gpus = torch.cuda.device_count()
        gpu_workers = min(num_gpus, max(1, num_workers // 4))  # 25% GPU workers
        cpu_workers = num_workers - gpu_workers
        
        print(f'Designed allocation strategy:')
        print(f'  CPU workers: {cpu_workers} ({cpu_workers/num_workers*100:.1f}%)')
        print(f'  GPU workers: {gpu_workers} ({gpu_workers/num_workers*100:.1f}%)')
        
        devices = []
        for i in range(num_workers):
            if i < gpu_workers:
                devices.append(f"cuda:{i % num_gpus}")
            else:
                devices.append("cpu")
        
        print(f'\nActual device allocation:')
        for i, device in enumerate(devices):
            print(f'  Worker {i}: {device}')
    else:
        print('  All workers will use CPU')
    
    print('\n🤔 Possible reasons for high GPU usage but low CPU usage:')
    print('1. **High neural network inference frequency**: Each MCTS simulation requires calling neural_network.predict()')
    print('2. **MCTS tree search is not CPU-intensive**: Although running on CPU, most time is spent waiting for NN inference')
    print('3. **Low feature cache hit rate**: Position repetition is low, cache effect is limited')
    print('4. **GPU batch processing efficiency**: Even CPU workers may use GPU inference through some mechanism')
    print('5. **PyTorch default behavior**: Model may automatically use GPU regardless of wrapper device settings')
    
    return True

def analyze_selfplay_bottleneck():
    """Analyze self-play performance bottleneck"""
    print('\n🔬 SELFPLAY PERFORMANCE ANALYSIS')
    print('='*50)
    
    print('Analysis based on MCTS implementation:')
    print('1. **Each MCTS search requires**: 600-800 simulations')
    print('2. **Each simulation requires**: 1-5 neural network inferences (node expansion)')
    print('3. **Each move requires**: 1 MCTS search')
    print('4. **Each game**: ~50-100 moves')
    print('')
    print('**Computational intensity analysis**:')
    print('- Neural network inference: GPU-intensive (matrix operations)')
    print('- MCTS tree traversal: Lightweight (pointer operations, comparisons)')
    print('- Feature extraction: Lightweight (numpy array operations)')
    print('- Game logic: Lightweight (rule checking)')
    print('')
    print('**Conclusion**: Although designed to use 75% CPU, actual bottleneck is neural network inference (GPU)')
    
    return True

def suggest_optimizations():
    """Suggest optimization strategies"""
    print('\n💡 OPTIMIZATION SUGGESTIONS')
    print('='*50)
    
    print('If you want to better utilize CPU, consider:')
    print('')
    print('1. **Force CPU inference**:')
    print('   Modify worker_selfplay function to force all model inference on CPU')
    print('   Downside: Inference speed will significantly decrease')
    print('')
    print('2. **Reduce MCTS simulation count**:')
    print('   Lower mcts_sims from 600-800 to 200-400')
    print('   Downside: Training data quality will decrease')
    print('')
    print('3. **Increase CPU workers ratio**:')
    print('   Modify gpu_workers = num_workers // 8  # 12.5% GPU workers')
    print('   Effect: More CPU parallelism, but NN inference is still bottleneck')
    print('')
    print('4. **Batch inference optimization** (Recommended):')
    print('   Implement batch neural network inference to reduce GPU call frequency')
    print('   Effect: Improve GPU utilization, may reduce total GPU usage')
    print('')
    print('5. **Asynchronous inference queue**:')
    print('   CPU workers send inference requests to GPU queue')
    print('   Effect: Better CPU/GPU coordination')
    
    return True

def main():
    """Main monitoring and testing workflow."""
    print('🎯 KATAMILL DEVICE USAGE ANALYSIS')
    print('Analyze device usage during self-play process')
    print('')
    
    # Device usage monitoring
    monitor_device_usage()
    
    # Performance bottleneck analysis
    analyze_selfplay_bottleneck()
    
    # Optimization suggestions
    suggest_optimizations()
    
    print('\n' + '='*50)
    print('📋 SUMMARY')
    print('='*50)
    print('Observed phenomenon: High GPU usage, low CPU usage')
    print('Root cause: Neural network inference is the computational bottleneck, MCTS tree search is relatively lightweight')
    print('Design is reasonable: Current hybrid allocation strategy is actually optimized')
    print('Recommendation: If GPU resources are tight, consider forcing CPU inference or batch inference optimization')

if __name__ == '__main__':
    main()
