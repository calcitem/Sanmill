#!/usr/bin/env python3
"""
Training data generation script for Sanmill NNUE
Interfaces with the C++ engine to generate training data using Perfect Database
"""

import subprocess
import argparse
import os
import time
import logging
from pathlib import Path

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def run_engine_command(engine_path: str, commands: list, timeout: int = 300) -> str:
    """
    Run engine with UCI commands and return output
    """
    try:
        # Start engine process
        process = subprocess.Popen(
            [engine_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        
        # Send commands
        command_str = '\n'.join(commands) + '\nquit\n'
        stdout, stderr = process.communicate(input=command_str, timeout=timeout)
        
        if process.returncode != 0:
            logger.error(f"Engine returned non-zero exit code: {process.returncode}")
            logger.error(f"Stderr: {stderr}")
        
        return stdout
        
    except subprocess.TimeoutExpired:
        logger.error(f"Engine command timed out after {timeout} seconds")
        process.kill()
        return ""
    except Exception as e:
        logger.error(f"Error running engine: {e}")
        return ""

def generate_training_data(engine_path: str, 
                         output_file: str,
                         num_positions: int = 50000,
                         perfect_db_path: str = ".") -> bool:
    """
    Generate training data using the C++ engine
    """
    logger.info(f"Generating {num_positions} training positions...")
    
    # Configure engine for training data generation
    commands = [
        "uci",
        f"setoption name UsePerfectDatabase value true",
        f"setoption name PerfectDatabasePath value {perfect_db_path}",
        f"setoption name GenerateTrainingData value true",
        f"generate_nnue_data {output_file} {num_positions}",
    ]
    
    start_time = time.time()
    output = run_engine_command(engine_path, commands, timeout=3600)  # 1 hour timeout
    end_time = time.time()
    
    logger.info(f"Training data generation completed in {end_time - start_time:.2f} seconds")
    
    # Check if output file was created
    if os.path.exists(output_file):
        file_size = os.path.getsize(output_file)
        logger.info(f"Training data saved to {output_file} ({file_size} bytes)")
        return True
    else:
        logger.error("Training data file was not created")
        return False

def validate_training_data(data_file: str) -> bool:
    """
    Validate the generated training data file
    """
    if not os.path.exists(data_file):
        logger.error(f"Training data file not found: {data_file}")
        return False
    
    try:
        with open(data_file, 'r') as f:
            lines = f.readlines()
        
        # Check for header
        if len(lines) < 2:
            logger.error("Training data file is too short")
            return False
        
        # Skip comments and get sample count
        data_lines = [line for line in lines if not line.startswith('#')]
        if len(data_lines) == 0:
            logger.error("No data lines found")
            return False
        
        try:
            sample_count = int(data_lines[0].strip())
            actual_lines = len(data_lines) - 1
            
            logger.info(f"Training data validation:")
            logger.info(f"  Expected samples: {sample_count}")
            logger.info(f"  Actual data lines: {actual_lines}")
            
            if actual_lines < sample_count * 0.9:  # Allow 10% tolerance
                logger.warning(f"Fewer samples than expected ({actual_lines} vs {sample_count})")
            
            # Validate a few sample lines
            for i, line in enumerate(data_lines[1:6]):  # Check first 5 data lines
                parts = line.strip().split(' | ')
                if len(parts) < 4:
                    logger.error(f"Malformed line {i+1}: {line.strip()}")
                    return False
                
                # Check features
                features = parts[0].split()
                if len(features) != 95:  # Expected feature count
                    logger.error(f"Incorrect feature count on line {i+1}: {len(features)}")
                    return False
            
            logger.info("Training data validation passed")
            return True
            
        except ValueError as e:
            logger.error(f"Error parsing sample count: {e}")
            return False
            
    except Exception as e:
        logger.error(f"Error validating training data: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Generate NNUE training data for Sanmill')
    parser.add_argument('--engine', required=True, help='Path to Sanmill engine executable')
    parser.add_argument('--output', default='training_data.txt', help='Output training data file')
    parser.add_argument('--positions', type=int, default=50000, help='Number of positions to generate')
    parser.add_argument('--perfect-db', default='.', help='Path to Perfect Database')
    parser.add_argument('--validate', action='store_true', help='Validate generated data')
    
    args = parser.parse_args()
    
    # Check if engine exists
    if not os.path.exists(args.engine):
        logger.error(f"Engine not found: {args.engine}")
        return 1
    
    # Check if Perfect Database path exists
    if not os.path.exists(args.perfect_db):
        logger.error(f"Perfect Database path not found: {args.perfect_db}")
        return 1
    
    # Generate training data
    success = generate_training_data(
        args.engine, 
        args.output, 
        args.positions, 
        args.perfect_db
    )
    
    if not success:
        logger.error("Failed to generate training data")
        return 1
    
    # Validate if requested
    if args.validate:
        if not validate_training_data(args.output):
            logger.error("Training data validation failed")
            return 1
    
    logger.info("Training data generation completed successfully")
    return 0

if __name__ == '__main__':
    exit(main())
