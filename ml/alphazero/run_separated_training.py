#!/usr/bin/env python3
"""
Automated script for separated sampling and training phases.
Note: main.py now defaults to auto-phases mode, so this script is mainly for custom control.
Usage: python run_separated_training.py --config win_config.yaml
"""

import os
import sys
import subprocess
import argparse
import logging

def run_command(cmd, description):
    """Run a command and handle errors."""
    print(f"\n{'='*50}")
    print(f"{description}")
    print(f"Command: {' '.join(cmd)}")
    print(f"{'='*50}")
    
    result = subprocess.run(cmd, capture_output=False)
    if result.returncode != 0:
        print(f"❌ {description} failed with exit code {result.returncode}")
        sys.exit(1)
    else:
        print(f"✅ {description} completed successfully")

def main():
    parser = argparse.ArgumentParser(description="Run separated sampling and training phases")
    parser.add_argument('--config', '-c', required=True, help='Configuration file path')
    parser.add_argument('--sampling-processes', type=int, default=None, 
                       help='Number of processes for sampling (default: auto-detect)')
    parser.add_argument('--skip-sampling', action='store_true', 
                       help='Skip sampling phase (use existing examples)')
    parser.add_argument('--skip-training', action='store_true', 
                       help='Skip training phase (only do sampling)')
    
    args = parser.parse_args()
    
    base_cmd = [sys.executable, 'main.py', '--config', args.config]
    
    if not args.skip_sampling:
        # Phase 1: Sampling (CPU multi-process)
        sampling_cmd = base_cmd + ['--sampling-only']
        if args.sampling_processes:
            env = os.environ.copy()
            env['SANMILL_TRAIN_PROCESSES'] = str(args.sampling_processes)
            subprocess.run(sampling_cmd, env=env)
        else:
            run_command(sampling_cmd, "🔍 SAMPLING PHASE (CPU multi-process)")
    
    if not args.skip_training:
        # Phase 2: Training (GPU single-process)
        training_cmd = base_cmd + ['--training-only']
        run_command(training_cmd, "🎯 TRAINING PHASE (GPU single-process)")
    
    print(f"\n{'='*50}")
    print("🎉 All phases completed successfully!")
    print(f"{'='*50}")

if __name__ == '__main__':
    main()
