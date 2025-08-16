#!/usr/bin/env python3
"""
Enhanced NNUE training pipeline with strict mode and parallelization
Uses Perfect Database for optimal training data generation
"""

import os
import sys
import argparse
import multiprocessing as mp
import logging
import time
from pathlib import Path

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def validate_environment(engine_path: str, perfect_db_path: str) -> bool:
    """
    Strict validation of training environment
    """
    logger.info("Validating training environment...")
    
    # Check engine executable
    if not os.path.exists(engine_path):
        logger.error(f"Engine not found: {engine_path}")
        return False
    
    if not os.access(engine_path, os.X_OK):
        logger.error(f"Engine is not executable: {engine_path}")
        return False
    
    # Check Perfect Database
    if not os.path.exists(perfect_db_path):
        logger.error(f"Perfect Database path not found: {perfect_db_path}")
        return False
    
    if not os.path.isdir(perfect_db_path):
        logger.error(f"Perfect Database path is not a directory: {perfect_db_path}")
        return False
    
    # Check for required database files (basic validation)
    db_files_found = any(
        f.endswith(('.db', '.dat', '.bin', '.idx')) 
        for f in os.listdir(perfect_db_path)
    )
    
    if not db_files_found:
        logger.warning(f"No database files found in {perfect_db_path}")
        logger.warning("Perfect Database may not be properly installed")
    
    logger.info("Environment validation passed")
    return True

def generate_training_data_parallel(engine_path: str,
                                  output_file: str, 
                                  num_positions: int,
                                  perfect_db_path: str,
                                  num_threads: int = 0) -> bool:
    """
    Generate training data with strict error checking
    """
    logger.info(f"Generating {num_positions} training positions using {num_threads} threads...")
    
    start_time = time.time()
    
    # Import here to avoid circular imports
    from generate_training_data import generate_training_data
    
    success = generate_training_data(
        engine_path=engine_path,
        output_file=output_file,
        num_positions=num_positions,
        perfect_db_path=perfect_db_path,
        num_threads=num_threads
    )
    
    end_time = time.time()
    
    if not success:
        logger.error("Training data generation failed")
        return False
    
    # Strict validation of generated data
    if not os.path.exists(output_file):
        logger.error(f"Training data file was not created: {output_file}")
        return False
    
    file_size = os.path.getsize(output_file)
    if file_size == 0:
        logger.error(f"Training data file is empty: {output_file}")
        return False
    
    logger.info(f"Training data generated successfully in {end_time - start_time:.2f}s")
    logger.info(f"Output file: {output_file} ({file_size} bytes)")
    
    return True

def train_nnue_model(data_file: str,
                    model_output: str,
                    epochs: int = 300,
                    batch_size: int = 8192,
                    learning_rate: float = 0.002,
                    lr_scheduler: str = "adaptive",
                    lr_auto_scale: bool = False,
                    device: str = "auto") -> bool:
    """
    Train NNUE model with strict error checking
    """
    logger.info(f"Training NNUE model for {epochs} epochs...")
    
    # Import here to avoid dependency issues
    try:
        from train_nnue import main as train_main
    except ImportError as e:
        logger.error(f"Failed to import training module: {e}")
        return False
    
    # Prepare arguments for training script
    train_args = [
        "train_nnue.py",
        "--data", data_file,
        "--output", model_output,
        "--epochs", str(epochs),
        "--batch-size", str(batch_size),
        "--lr", str(learning_rate),
        "--lr-scheduler", lr_scheduler,
        "--device", device
    ]
    
    if lr_auto_scale:
        train_args.append("--lr-auto-scale")
    
    # Mock sys.argv for the training script
    original_argv = sys.argv
    sys.argv = train_args
    
    try:
        result = train_main()
        success = (result == 0)
    except Exception as e:
        logger.error(f"Training failed with exception: {e}")
        success = False
    finally:
        sys.argv = original_argv
    
    if not success:
        logger.error("NNUE training failed")
        return False
    
    # Strict validation of trained model
    if not os.path.exists(model_output):
        logger.error(f"Model file was not created: {model_output}")
        return False
    
    model_size = os.path.getsize(model_output)
    if model_size == 0:
        logger.error(f"Model file is empty: {model_output}")
        return False
    
    logger.info(f"Model trained successfully: {model_output} ({model_size} bytes)")
    return True

def validate_final_model(model_path: str, engine_path: str) -> bool:
    """
    Validate the trained model works with the engine
    """
    logger.info("Validating trained model with engine...")
    
    if not os.path.exists(model_path):
        logger.error(f"Model file not found: {model_path}")
        return False
    
    # Test basic model loading with engine
    test_commands = [
        "uci",
        f"setoption name UseNNUE value true",
        f"setoption name NNUEModelPath value {model_path}",
        "position startpos",
        "d",
        "quit"
    ]
    
    try:
        import subprocess
        result = subprocess.run(
            [engine_path],
            input='\n'.join(test_commands),
            text=True,
            capture_output=True,
            timeout=30
        )
        
        if result.returncode != 0:
            logger.error(f"Engine failed to load model: {result.stderr}")
            return False
        
        # Check for NNUE initialization messages
        if "NNUE: Successfully initialized" not in result.stdout:
            logger.warning("NNUE initialization message not found in engine output")
        
        logger.info("Model validation passed")
        return True
        
    except subprocess.TimeoutExpired:
        logger.error("Engine validation timed out")
        return False
    except Exception as e:
        logger.error(f"Model validation failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Enhanced NNUE training pipeline with strict mode')
    parser.add_argument('--engine', required=True, help='Path to Sanmill engine executable')
    parser.add_argument('--perfect-db', required=True, help='Path to Perfect Database directory')
    parser.add_argument('--output-dir', default='./nnue_output', help='Output directory for training artifacts')
    parser.add_argument('--positions', type=int, default=500000, help='Number of training positions')
    parser.add_argument('--epochs', type=int, default=300, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=8192, help='Batch size')
    parser.add_argument('--learning-rate', type=float, default=0.002, help='Initial learning rate')
    parser.add_argument('--lr-scheduler', default='adaptive', choices=['adaptive', 'cosine', 'plateau', 'fixed'],
                       help='Learning rate scheduler type')
    parser.add_argument('--lr-auto-scale', action='store_true', help='Auto-scale LR based on batch size')
    parser.add_argument('--threads', type=int, default=0, help='Number of threads (0=auto)')
    parser.add_argument('--device', default='auto', help='Training device (cpu/cuda/auto)')
    parser.add_argument('--validate-only', action='store_true', help='Only validate environment')
    
    args = parser.parse_args()
    
    # Auto-detect thread count
    if args.threads <= 0:
        args.threads = max(1, mp.cpu_count() - 1)
    
    logger.info("=== Enhanced NNUE Training Pipeline ===")
    logger.info(f"Engine: {args.engine}")
    logger.info(f"Perfect DB: {args.perfect_db}")
    logger.info(f"Output directory: {args.output_dir}")
    logger.info(f"Positions: {args.positions}")
    logger.info(f"Threads: {args.threads}")
    logger.info(f"Epochs: {args.epochs}")
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Step 1: Strict environment validation
    if not validate_environment(args.engine, args.perfect_db):
        logger.error("Environment validation failed")
        return 1
    
    if args.validate_only:
        logger.info("Environment validation completed successfully")
        return 0
    
    # Define file paths
    training_data_file = os.path.join(args.output_dir, "training_data.txt")
    model_output_file = os.path.join(args.output_dir, "nnue_model.bin")
    
    # Step 2: Generate training data with parallelization
    logger.info("=== Step 1: Generating Training Data ===")
    success = generate_training_data_parallel(
        args.engine,
        training_data_file,
        args.positions,
        args.perfect_db,
        args.threads
    )
    
    if not success:
        logger.error("Training data generation failed")
        return 1
    
    # Step 3: Train NNUE model
    logger.info("=== Step 2: Training NNUE Model ===")
    success = train_nnue_model(
        training_data_file,
        model_output_file,
        args.epochs,
        args.batch_size,
        args.learning_rate,
        args.lr_scheduler,
        args.lr_auto_scale,
        args.device
    )
    
    if not success:
        logger.error("NNUE training failed")
        return 1
    
    # Step 4: Validate final model
    logger.info("=== Step 3: Validating Trained Model ===")
    success = validate_final_model(model_output_file, args.engine)
    
    if not success:
        logger.error("Model validation failed")
        return 1
    
    # Success!
    logger.info("=== Training Pipeline Completed Successfully ===")
    logger.info(f"Training data: {training_data_file}")
    logger.info(f"Trained model: {model_output_file}")
    logger.info("")
    logger.info("To use the trained model:")
    logger.info(f"  setoption name UseNNUE value true")
    logger.info(f"  setoption name NNUEModelPath value {model_output_file}")
    logger.info(f"  setoption name NNUEWeight value 90")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
