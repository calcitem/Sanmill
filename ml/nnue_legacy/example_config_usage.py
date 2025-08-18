#!/usr/bin/env python3
"""
Example script demonstrating NNUE configuration file usage
Shows how to use different pre-configured settings
"""

import subprocess
import sys
import os
from pathlib import Path

def run_example(description, command):
    """Show an example command without actually running it"""
    print(f"\n{'='*60}")
    print(f"Example: {description}")
    print('='*60)
    print(f"Command: {' '.join(command)}")
    print("\nWhat this does:")
    
    # Parse the config file to show what settings are used
    if "--config" in command:
        config_index = command.index("--config") + 1
        if config_index < len(command):
            config_file = command[config_index]
            try:
                import json
                with open(config_file, 'r') as f:
                    config = json.load(f)
                
                print("Configuration settings:")
                for key, value in config.items():
                    if not key.startswith('_'):
                        print(f"  {key}: {value}")
                        
                if '_description' in config:
                    print(f"\nDescription: {config['_description']}")
                if '_use_case' in config:
                    print(f"Use case: {config['_use_case']}")
                if '_hardware' in config:
                    print(f"Hardware: {config['_hardware']}")
                    
            except Exception as e:
                print(f"  Could not read config file: {e}")
    
    print("\nNote: This is just an example. Update paths and data files as needed.")

def main():
    """Show examples of using configuration files"""
    
    print("NNUE Training Configuration Examples")
    print("="*50)
    
    # Check if we're in the right directory
    if not os.path.exists("configs"):
        print("Warning: 'configs' directory not found. Please run from ml/nnue_training/")
        print("Creating example assuming correct directory structure...")
    
    print("\n🎯 Configuration files eliminate the need for many command-line parameters!")
    print("   Instead of typing 15+ arguments, just specify a config file.\n")
    
    # Example 1: Basic training
    run_example(
        "Basic Training with Default Settings",
        ["python", "train_nnue.py", "--config", "configs/default.json", "--data", "training_data.txt"]
    )
    
    # Example 2: Fast experimentation
    run_example(
        "Quick Experimentation",
        ["python", "train_nnue.py", "--config", "configs/fast.json", "--data", "training_data.txt"]
    )
    
    # Example 3: High quality training
    run_example(
        "High-Quality Production Training",
        ["python", "train_nnue.py", "--config", "configs/high_quality.json", "--data", "training_data.txt"]
    )
    
    # Example 4: CPU-only training
    run_example(
        "CPU-Only Training (No GPU Required)",
        ["python", "train_nnue.py", "--config", "configs/cpu_only.json", "--data", "training_data.txt"]
    )
    
    # Example 5: Config with overrides
    run_example(
        "Using Config with Parameter Overrides",
        ["python", "train_nnue.py", "--config", "configs/default.json", "--data", "training_data.txt", 
         "--epochs", "500", "--batch-size", "16384"]
    )
    
    # Example 6: Pipeline configuration
    run_example(
        "Complete Pipeline with Configuration",
        ["python", "train_pipeline_parallel.py", "--config", "configs/pipeline_default.json", 
         "--perfect-db", "/path/to/perfect/database"]
    )
    
    # Example 7: Generate custom config
    run_example(
        "Generate Custom Configuration Template",
        ["python", "train_nnue.py", "--save-config", "my_custom_config.json"]
    )
    
    print(f"\n{'='*60}")
    print("Configuration Benefits")
    print('='*60)
    print("✅ Fewer command-line arguments needed")
    print("✅ Reproducible training runs")
    print("✅ Easy sharing of training setups")
    print("✅ Version control friendly")
    print("✅ Pre-optimized settings for different scenarios")
    print("✅ Can still override specific parameters")
    
    print(f"\n{'='*60}")
    print("Getting Started")
    print('='*60)
    print("1. Choose a config file from configs/ directory")
    print("2. Update the 'data' field or use --data parameter")
    print("3. Run training with --config <file>")
    print("4. Monitor training with automatic visualization")
    
    print(f"\n{'='*60}")
    print("Available Configurations")
    print('='*60)
    
    configs = [
        ("default.json", "General purpose, most users", "2-4 hours"),
        ("fast.json", "Quick experiments, prototyping", "30-60 min"),
        ("high_quality.json", "Production models, research", "6-12 hours"),
        ("cpu_only.json", "CPU-only systems", "4-8 hours"),
        ("large_dataset.json", "Massive datasets", "12-24 hours"),
        ("debug.json", "Development, testing", "5-10 min")
    ]
    
    for config, use_case, time in configs:
        print(f"📁 {config:20} - {use_case:30} ({time})")
    
    print(f"\n{'='*60}")
    print("Next Steps")
    print('='*60)
    print("1. Copy configs/default.json to create your own settings")
    print("2. Edit the JSON file with your preferred parameters")
    print("3. Use your config with: python train_nnue.py --config my_config.json")
    print("4. Share your configs with teammates for consistent training")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
