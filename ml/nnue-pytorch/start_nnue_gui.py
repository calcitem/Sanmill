#!/usr/bin/env python3
"""
Quick start script for NNUE GUI
Automatically detects available models and starts the GUI
"""

import os
import sys
import glob
import argparse
from pathlib import Path

def find_nnue_models(search_dirs=None):
    """Find available NNUE model files"""
    if search_dirs is None:
        search_dirs = ['.', 'models', '../models', 'checkpoints', '../checkpoints', 
                      'trained_models', '../trained_models', '..', '../..']
    
    model_files = []
    
    # Define file patterns that are likely to be NNUE models
    nnue_patterns = [
        '*nnue*.bin', '*nnue*.pth', '*nnue*.tar',
        'model*.bin', 'model*.pth', 'model*.tar',
        'best*.bin', 'best*.pth', 'best*.tar',
        'checkpoint*.pth', 'checkpoint*.tar',
        'trained*.bin', 'trained*.pth', 'trained*.tar',
        'mill*.bin', 'mill*.pth', 'mill*.tar',
        'sanmill*.bin', 'sanmill*.pth', 'sanmill*.tar'
    ]
    
    # Exclude patterns that are definitely not NNUE models
    exclude_patterns = [
        'CMake*', 'cmake*', '*flutter*', '*android*', '*ios*', '*windows*',
        '*build*', '*debug*', '*release*', '*intermediate*', '*tmp*', '*temp*',
        '*gradle*', '*dart*', '*dex*', '*jar*', '*assets*', '*kernel*',
        '*manifest*', '*graph*', '*compilation*', '*bucket*'
    ]
    
    for search_dir in search_dirs:
        if os.path.exists(search_dir):
            for pattern in nnue_patterns:
                # Search in current directory
                full_pattern = os.path.join(search_dir, pattern)
                candidates = glob.glob(full_pattern)
                
                # Search in subdirectories (limited depth to avoid build dirs)
                if search_dir in ['.', 'models', '../models']:
                    full_pattern_recursive = os.path.join(search_dir, '**', pattern)
                    candidates.extend(glob.glob(full_pattern_recursive, recursive=True))
                
                # Filter out excluded patterns
                for candidate in candidates:
                    candidate_name = os.path.basename(candidate).lower()
                    candidate_path = candidate.lower()
                    
                    # Check if file should be excluded
                    should_exclude = False
                    for exclude_pattern in exclude_patterns:
                        if exclude_pattern.replace('*', '') in candidate_path:
                            should_exclude = True
                            break
                    
                    if not should_exclude:
                        model_files.append(candidate)
    
    # Additional validation: check file size and try to validate model format
    validated_files = []
    for model_file in model_files:
        try:
            file_size = os.path.getsize(model_file)
            # NNUE models should be at least 1KB and typically less than 100MB
            if 1024 <= file_size <= 100 * 1024 * 1024:
                if _is_likely_nnue_model(model_file):
                    validated_files.append(model_file)
        except OSError:
            continue
    
    # Remove duplicates and sort
    validated_files = sorted(list(set(validated_files)))
    return validated_files

def _is_likely_nnue_model(file_path):
    """Check if file is likely a NNUE model by examining its content"""
    try:
        with open(file_path, 'rb') as f:
            # Check for binary NNUE format (SANMILL header)
            header = f.read(8)
            if header == b'SANMILL1':
                return True
            
            # Reset and check for PyTorch format
            f.seek(0)
            first_bytes = f.read(512)
            
            # PyTorch files often start with these patterns
            pytorch_patterns = [b'PK\x03\x04', b'PK\x05\x06', b'PK\x06\x06']  # ZIP signatures
            for pattern in pytorch_patterns:
                if first_bytes.startswith(pattern):
                    return True
            
            # Check for pickle format (PyTorch models are pickled)
            if first_bytes.startswith(b'\x80\x02') or first_bytes.startswith(b'\x80\x03'):
                return True
                
            return False
    except Exception:
        # If we can't read the file, assume it might be valid
        # (better to include a questionable file than exclude a valid one)
        return True

def main():
    parser = argparse.ArgumentParser(description='Quick start NNUE GUI')
    parser.add_argument('--model', type=str, help='Specific model file to use')
    parser.add_argument('--list-models', action='store_true', 
                       help='List available model files and exit')
    parser.add_argument('--first', choices=['human', 'ai'], default='human',
                       help='Who plays first')
    parser.add_argument('--depth', type=int, default=3, help='AI search depth')
    
    args = parser.parse_args()
    
    # Find available models
    model_files = find_nnue_models()
    
    if args.list_models:
        print("Available NNUE model files:")
        if not model_files:
            print("  No NNUE model files found!")
            print("  Search directories: ., models, ../models, checkpoints, ../checkpoints")
            print("  Looking for files matching: *nnue*.bin, model*.bin, best*.pth, etc.")
            print("  Excluding build/temp directories and non-model files")
            print("")
            print("  To use the program:")
            print("    1. Train a model: python train_nnue.py --config configs/fast.json")
            print("    2. Or download a pre-trained model and place it in current directory")
            print("    3. Then run: python nnue_pit.py --model your_model.bin --gui")
        else:
            for i, model_file in enumerate(model_files, 1):
                file_size_bytes = os.path.getsize(model_file)
                if file_size_bytes < 1024 * 1024:  # Less than 1MB, show in KB
                    file_size = file_size_bytes / 1024
                    size_unit = "KB"
                else:  # 1MB or larger, show in MB
                    file_size = file_size_bytes / (1024 * 1024)
                    size_unit = "MB"
                print(f"  {i}. {model_file} ({file_size:.1f} {size_unit})")
        return
    
    # Select model file
    if args.model:
        model_file = args.model
        if not os.path.exists(model_file):
            print(f"Error: Model file not found: {model_file}")
            return
    else:
        if not model_files:
            print("No NNUE model files found!")
            print("")
            print("Solutions:")
            print("  1. Specify a model file directly: --model path/to/your/model.bin")
            print("  2. Train a new model: python train_nnue.py --config configs/fast.json")
            print("  3. Place a model file in one of these directories:")
            print("     - Current directory (.)")
            print("     - models/")
            print("     - checkpoints/")
            print("")
            print("Use --list-models to see detailed search results")
            return
        
        if len(model_files) == 1:
            model_file = model_files[0]
            print(f"Using model: {model_file}")
        else:
            print("Multiple model files found:")
            for i, mf in enumerate(model_files, 1):
                print(f"  {i}. {mf}")
            
            try:
                choice = input(f"Select model (1-{len(model_files)}) or press Enter for default: ")
                if choice.strip() == "":
                    model_file = model_files[0]
                else:
                    choice = int(choice) - 1
                    if 0 <= choice < len(model_files):
                        model_file = model_files[choice]
                    else:
                        print("Invalid choice, using first model")
                        model_file = model_files[0]
            except (ValueError, KeyboardInterrupt):
                print("\nUsing first model")
                model_file = model_files[0]
    
    # Build command
    cmd_parts = [
        sys.executable, 'nnue_pit.py',
        '--model', model_file,
        '--gui',
        '--first', args.first,
        '--depth', str(args.depth)
    ]
    
    print(f"Starting NNUE GUI with:")
    print(f"  Model: {model_file}")
    print(f"  First player: {args.first}")
    print(f"  Search depth: {args.depth}")
    print()
    
    # Check if nnue_pit.py exists
    if not os.path.exists('nnue_pit.py'):
        print("Error: nnue_pit.py not found in current directory")
        print("Please run this script from the ml/nnue_training/ directory")
        return
    
    # Import and run
    try:
        import subprocess
        result = subprocess.run(cmd_parts)
        return result.returncode
    except KeyboardInterrupt:
        print("\nInterrupted by user")
        return 0
    except Exception as e:
        print(f"Error starting NNUE GUI: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
