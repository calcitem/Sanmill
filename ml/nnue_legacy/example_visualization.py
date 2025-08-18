#!/usr/bin/env python3
"""
Example script demonstrating NNUE training visualization features
This script shows different ways to enable and configure training plots
"""

import subprocess
import sys
import os
from pathlib import Path

def run_command(cmd, description):
    """Run a command and show output"""
    print(f"\n{'='*60}")
    print(f"Running: {description}")
    print(f"Command: {' '.join(cmd)}")
    print('='*60)
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print("✓ Command completed successfully")
        if result.stdout:
            print("Output:", result.stdout[-500:])  # Last 500 chars
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Command failed with return code {e.returncode}")
        if e.stderr:
            print("Error:", e.stderr)
        return False
    except FileNotFoundError:
        print(f"✗ Command not found: {cmd[0]}")
        return False

def main():
    """Demonstrate different visualization configurations"""
    
    # Check if we're in the right directory
    if not os.path.exists("train_nnue.py"):
        print("Error: Please run this script from the ml/nnue_training directory")
        return 1
    
    # Create sample data (you would normally have real training data)
    sample_data = "sample_training_data.txt"
    if not os.path.exists(sample_data):
        print(f"Creating sample data file: {sample_data}")
        # Create minimal sample data for demo
        with open(sample_data, 'w') as f:
            f.write("# Sample training data for visualization demo\n")
            f.write("# Format: features(95) target(1) side_to_move(1)\n")
            for i in range(100):  # Minimal dataset for quick demo
                features = ' '.join(['0.5' if j % 2 == 0 else '0.0' for j in range(95)])
                target = '0.3'
                side = '1' if i % 2 == 0 else '0'
                f.write(f"{features} {target} {side}\n")
    
    print("NNUE Training Visualization Examples")
    print("="*50)
    
    # Example 1: Basic visualization
    print("\n1. Basic Visualization (Default Settings)")
    cmd1 = [
        sys.executable, "train_nnue.py",
        "--data", sample_data,
        "--output", "demo_model_1.bin",
        "--epochs", "10",  # Short for demo
        "--batch-size", "32",
        "--plot"  # Enable basic plotting
    ]
    
    success1 = run_command(cmd1, "Basic visualization with default settings")
    
    # Example 2: Custom visualization settings
    print("\n2. Custom Visualization Settings")
    cmd2 = [
        sys.executable, "train_nnue.py",
        "--data", sample_data,
        "--output", "demo_model_2.bin",
        "--epochs", "15",
        "--batch-size", "32",
        "--plot",
        "--plot-dir", "./custom_plots",
        "--plot-interval", "3",  # Update every 3 epochs
        "--save-csv"  # Also save CSV data
    ]
    
    success2 = run_command(cmd2, "Custom visualization with CSV export")
    
    # Example 3: Training with adaptive LR and visualization
    print("\n3. Adaptive Learning Rate + Visualization")
    cmd3 = [
        sys.executable, "train_nnue.py",
        "--data", sample_data,
        "--output", "demo_model_3.bin",
        "--epochs", "20",
        "--batch-size", "64",
        "--lr-scheduler", "adaptive",
        "--lr-auto-scale",
        "--plot",
        "--plot-dir", "./adaptive_plots",
        "--save-csv"
    ]
    
    success3 = run_command(cmd3, "Adaptive LR with comprehensive visualization")
    
    # Example 4: Pipeline with visualization (if data generation possible)
    print("\n4. Complete Pipeline with Visualization")
    print("Note: This would require a real engine and perfect database")
    print("Command would be:")
    pipeline_cmd = [
        "python", "train_pipeline_parallel.py",
        "--engine", "../../sanmill",
        "--perfect-db", "/path/to/perfect/database",
        "--output-dir", "./pipeline_output",
        "--positions", "1000",  # Small for demo
        "--epochs", "20",
        "--plot",
        "--plot-dir", "./pipeline_plots",
        "--save-csv"
    ]
    print(" ".join(pipeline_cmd))
    
    # Summary
    print("\n" + "="*60)
    print("VISUALIZATION DEMO SUMMARY")
    print("="*60)
    
    results = [
        ("Basic visualization", success1),
        ("Custom settings", success2),
        ("Adaptive LR + plots", success3)
    ]
    
    for desc, success in results:
        status = "✓ SUCCESS" if success else "✗ FAILED"
        print(f"{desc:30} {status}")
    
    print(f"\nGenerated files:")
    plot_dirs = ["plots", "custom_plots", "adaptive_plots"]
    for plot_dir in plot_dirs:
        if os.path.exists(plot_dir):
            files = list(Path(plot_dir).glob("*.png"))
            if files:
                print(f"\n{plot_dir}/:")
                for f in files:
                    print(f"  - {f.name}")
            
            csv_files = list(Path(plot_dir).glob("*.csv"))
            if csv_files:
                for f in csv_files:
                    print(f"  - {f.name}")
    
    print(f"\nTo view plots, open the PNG files in your preferred image viewer.")
    print(f"CSV files can be opened in Excel, LibreOffice, or analyzed with pandas.")
    
    # Cleanup demo files
    cleanup = input("\nClean up demo files? (y/N): ").lower().strip()
    if cleanup == 'y':
        files_to_remove = [
            "demo_model_1.bin", "demo_model_2.bin", "demo_model_3.bin",
            "sample_training_data.txt"
        ]
        
        for f in files_to_remove:
            if os.path.exists(f):
                os.remove(f)
                print(f"Removed {f}")
        
        print("Demo files cleaned up.")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
