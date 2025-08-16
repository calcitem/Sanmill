#!/usr/bin/env python3
"""
Example usage of NNUE training for Sanmill
Demonstrates the basic workflow
"""

import os
import sys

def main():
    """Example workflow for NNUE training"""
    
    print("=== Sanmill NNUE Training Example ===")
    print()
    
    # Check if we're in the right directory
    if not os.path.exists("train_nnue.py"):
        print("Error: Please run this script from the ml/nnue_training/ directory")
        return 1
    
    print("1. Generate Training Data (NEW: Using Perfect DB DLL directly)")
    print("   Command: python generate_training_data.py --perfect-db /path/to/perfect/db --output training_data.txt --positions 10000")
    print("   Note: No longer requires sanmill executable - uses Perfect DB DLL directly")
    print()
    
    print("2. Train NNUE Model")
    print("   Command: python train_nnue.py --data training_data.txt --output nnue_model.bin --epochs 50")
    print()
    
    print("3. Configure Engine")
    print("   Copy nnue_model.bin to engine directory")
    print("   Configure engine:")
    print("     setoption name UseNNUE value true")
    print("     setoption name NNUEModelPath value nnue_model.bin")
    print("     setoption name NNUEWeight value 90")
    print()
    
    print("4. Test with Engine")
    print("   Example UCI commands:")
    print("     uci")
    print("     position startpos")
    print("     go depth 6")
    print()
    
    print("For full training pipeline, run:")
    print("   ./train_pipeline.sh")
    print()
    
    print("Training Features:")
    print("  - 95 input features covering position, phase, piece counts, and tactics")
    print("  - Perfect Database integration for optimal training labels")
    print("  - 256-neuron hidden layer with dual perspective architecture")
    print("  - Hybrid evaluation blending traditional and NNUE")
    print()
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
