#!/usr/bin/env python3

"""
Training data conversion utility for Nine Men's Morris NNUE.

This script helps convert training data from various formats to the format
expected by the Nine Men's Morris NNUE training system.
"""

import argparse
import os
import sys
import re
from pathlib import Path


def parse_mill_fen_line(line):
    """
    Parse a line from Nine Men's Morris training data.
    
    Expected format: "FEN evaluation best_move result"
    """
    line = line.strip()
    if not line or line.startswith('#'):
        return None
    
    parts = line.split()
    if len(parts) < 4:
        return None
    
    try:
        fen = parts[0]
        evaluation = float(parts[1])
        best_move = parts[2]
        result = float(parts[3])
        
        return {
            'fen': fen,
            'evaluation': evaluation,
            'best_move': best_move,
            'result': result
        }
    except (ValueError, IndexError):
        return None


def convert_sanmill_fen_format(input_file, output_file):
    """
    Convert Sanmill C++ engine FEN format to training format.
    
    Input format: Extended FEN with game state information
    Output format: "FEN evaluation best_move result"
    """
    converted_count = 0
    error_count = 0
    
    print(f"Converting {input_file} to {output_file}")
    
    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8') as outfile:
        
        for line_num, line in enumerate(infile, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            try:
                # Parse the extended FEN format from Sanmill
                # This is a simplified parser - you may need to adjust based on actual format
                parts = line.split()
                if len(parts) < 4:
                    continue
                
                # Extract FEN components
                board_state = parts[0]
                side_to_move = parts[1]
                phase = parts[2]
                action = parts[3]
                
                # Get additional state information if available
                if len(parts) >= 12:
                    white_on_board = parts[4]
                    white_in_hand = parts[5]
                    black_on_board = parts[6]
                    black_in_hand = parts[7]
                    white_to_remove = parts[8]
                    black_to_remove = parts[9]
                    # parts[10-11] might be mill positions
                    
                    # Construct basic FEN
                    basic_fen = f"{board_state} {side_to_move} {phase} {action} {white_on_board} {white_in_hand} {black_on_board} {black_in_hand} 0 0 0 0 0"
                else:
                    basic_fen = f"{board_state} {side_to_move} {phase} {action} 0 0 0 0 0 0 0 0 0"
                
                # For now, use placeholder values for evaluation and result
                # In practice, these would come from actual game analysis
                evaluation = 0.0  # Placeholder
                best_move = "a1"  # Placeholder
                result = 0.0      # Placeholder (draw)
                
                # Write converted line
                outfile.write(f"{basic_fen} {evaluation} {best_move} {result}\n")
                converted_count += 1
                
            except Exception as e:
                print(f"Error on line {line_num}: {e}")
                error_count += 1
                continue
    
    print(f"Conversion completed: {converted_count} positions converted, {error_count} errors")


def validate_training_data(filename):
    """Validate training data format."""
    print(f"Validating {filename}")
    
    valid_count = 0
    invalid_count = 0
    
    with open(filename, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            parsed = parse_mill_fen_line(line)
            if parsed:
                valid_count += 1
            else:
                if line.strip() and not line.startswith('#'):
                    print(f"Invalid line {line_num}: {line.strip()}")
                    invalid_count += 1
    
    print(f"Validation completed: {valid_count} valid, {invalid_count} invalid")
    return invalid_count == 0


def create_sample_data(filename, num_positions=1000):
    """Create sample training data for testing."""
    print(f"Creating {num_positions} sample positions in {filename}")
    
    import random
    import numpy as np
    
    # Set seed for reproducibility
    random.seed(42)
    np.random.seed(42)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write("# Sample Nine Men's Morris training data\n")
        f.write("# Format: FEN evaluation best_move result\n")
        f.write("#\n")
        
        for i in range(num_positions):
            # Create random board state (simplified)
            board = ['*'] * 24
            
            # Place some random pieces
            num_white = random.randint(3, 9)
            num_black = random.randint(3, 9)
            
            positions = list(range(24))
            random.shuffle(positions)
            
            for j in range(num_white):
                board[positions[j]] = 'O'
            
            for j in range(num_white, num_white + num_black):
                if j < len(positions):
                    board[positions[j]] = '@'
            
            board_str = ''.join(board)
            side = random.choice(['w', 'b'])
            phase = random.choice(['p', 'm'])
            action = 'p' if phase == 'p' else 's'
            
            white_on_board = board_str.count('O')
            white_in_hand = max(0, 9 - white_on_board)
            black_on_board = board_str.count('@')
            black_in_hand = max(0, 9 - black_on_board)
            
            fen = f"{board_str} {side} {phase} {action} {white_on_board} {white_in_hand} {black_on_board} {black_in_hand} 0 0 0 0 0"
            
            # Random evaluation and result
            evaluation = random.gauss(0, 50)  # Centered around 0
            result = random.choice([-1.0, 0.0, 1.0])
            best_move = random.choice(["a1", "b2", "c3"])  # Placeholder
            
            f.write(f"{fen} {evaluation:.1f} {best_move} {result}\n")
    
    print(f"Sample data created successfully")


def main():
    parser = argparse.ArgumentParser(
        description="Convert and validate Nine Men's Morris training data"
    )
    
    parser.add_argument(
        "command",
        choices=["convert", "validate", "sample"],
        help="Command to execute"
    )
    
    parser.add_argument(
        "--input",
        type=str,
        help="Input file path"
    )
    
    parser.add_argument(
        "--output",
        type=str,
        help="Output file path"
    )
    
    parser.add_argument(
        "--num-positions",
        type=int,
        default=1000,
        help="Number of sample positions to create"
    )
    
    args = parser.parse_args()
    
    if args.command == "convert":
        if not args.input or not args.output:
            print("Error: --input and --output required for convert command")
            sys.exit(1)
        
        if not os.path.exists(args.input):
            print(f"Error: Input file {args.input} not found")
            sys.exit(1)
        
        convert_sanmill_fen_format(args.input, args.output)
    
    elif args.command == "validate":
        if not args.input:
            print("Error: --input required for validate command")
            sys.exit(1)
        
        if not os.path.exists(args.input):
            print(f"Error: Input file {args.input} not found")
            sys.exit(1)
        
        if not validate_training_data(args.input):
            sys.exit(1)
    
    elif args.command == "sample":
        if not args.output:
            print("Error: --output required for sample command")
            sys.exit(1)
        
        create_sample_data(args.output, args.num_positions)
    
    print("Operation completed successfully")


if __name__ == "__main__":
    main()
