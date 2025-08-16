#!/usr/bin/env python3
"""
Check default thread and process settings.
"""

import os
import sys

def check_env_vars():
    print("🔧 Current Environment Variables:")
    print(f"  OMP_NUM_THREADS: {os.environ.get('OMP_NUM_THREADS', 'Not set')}")
    print(f"  MKL_NUM_THREADS: {os.environ.get('MKL_NUM_THREADS', 'Not set')}")
    print(f"  SANMILL_TRAIN_PROCESSES: {os.environ.get('SANMILL_TRAIN_PROCESSES', 'Not set')}")
    
    # Import and check PyTorch threads
    try:
        import torch
        print(f"  PyTorch threads: {torch.get_num_threads()}")
    except ImportError:
        print("  PyTorch: Not available")
    
    # Check logical CPU count
    try:
        cpu_count = os.cpu_count()
        print(f"  Logical CPU cores: {cpu_count}")
    except:
        print("  CPU cores: Unknown")

if __name__ == '__main__':
    check_env_vars()
