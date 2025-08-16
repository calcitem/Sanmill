#!/usr/bin/env python3
"""
Training data generation script for Sanmill NNUE
Directly interfaces with Perfect Database DLL for training data generation
"""

import argparse
import os
import time
import logging
import random
import numpy as np
import sys
from pathlib import Path
from typing import List, Tuple, Dict

# Add parent directories to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from game.Game import Game
from game.GameLogic import Board  
from game.engine_adapter import move_to_engine_token
from perfect.perfect_db_reader import PerfectDB

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def extract_features_from_board(board: Board, player: int) -> List[float]:
    """
    Extract NNUE features from board position.
    Returns a feature vector compatible with Sanmill NNUE training format.
    """
    features = []
    
    # Basic position features (95 features total)
    
    # 1. Piece positions (24 features for white, 24 for black)
    white_positions = []
    black_positions = []
    
    for y in range(7):
        for x in range(7):
            if board.allowed_places[x][y]:
                if board.pieces[x][y] == 1:
                    white_positions.append(1.0)
                    black_positions.append(0.0)
                elif board.pieces[x][y] == -1:
                    white_positions.append(0.0)
                    black_positions.append(1.0)
                else:
                    white_positions.append(0.0)
                    black_positions.append(0.0)
    
    features.extend(white_positions)  # 24 features
    features.extend(black_positions)  # 24 features
    
    # 2. Game phase features (4 features)
    phase_features = [0.0] * 4
    phase_features[board.period] = 1.0
    features.extend(phase_features)
    
    # 3. Piece counts (6 features)
    white_count = board.count(1)
    black_count = board.count(-1)
    white_in_hand = max(0, 9 - ((board.put_pieces + 1) // 2))
    black_in_hand = max(0, 9 - (board.put_pieces // 2))
    
    features.extend([
        white_count / 9.0,
        black_count / 9.0,
        white_in_hand / 9.0,
        black_in_hand / 9.0,
        board.put_pieces / 18.0,
        min(board.rule50_counter / 50.0, 1.0) if hasattr(board, 'rule50_counter') else 0.0
    ])
    
    # 4. Side to move feature (1 feature)
    features.append(1.0 if player == 1 else 0.0)
    
    # 5. Mill detection features (24 features - one per position)
    mill_features = []
    for y in range(7):
        for x in range(7):
            if board.allowed_places[x][y]:
                # Check if this position is part of a mill
                is_mill = board._is_piece_in_mill([x, y], board.pieces[x][y]) if board.pieces[x][y] != 0 else False
                mill_features.append(1.0 if is_mill else 0.0)
    
    features.extend(mill_features)  # 24 features
    
    # 6. Mobility features (12 features)
    white_mobility = len(board.get_legal_moves(1)) if board.period not in [0, 3] else 0
    black_mobility = len(board.get_legal_moves(-1)) if board.period not in [0, 3] else 0
    
    # Normalize mobility
    max_mobility = 24 if board.period == 2 and (white_count <= 3 or black_count <= 3) else 16
    features.extend([
        white_mobility / max_mobility,
        black_mobility / max_mobility,
        1.0 if white_mobility == 0 and board.period in [1, 2] else 0.0,  # White blocked
        1.0 if black_mobility == 0 and board.period in [1, 2] else 0.0,  # Black blocked
        1.0 if white_count <= 3 and white_in_hand == 0 else 0.0,  # White can fly
        1.0 if black_count <= 3 and black_in_hand == 0 else 0.0,  # Black can fly
    ])
    
    # Additional tactical features (6 features)
    features.extend([
        1.0 if board.period == 3 else 0.0,  # Capture phase
        (white_count - black_count) / 9.0,   # Material balance
        (white_in_hand - black_in_hand) / 9.0,  # Hand balance
        board.move_counter / 100.0 if hasattr(board, 'move_counter') else 0.0,  # Move count
        1.0 if hasattr(board, '_threefold_detected') and board._threefold_detected else 0.0,  # Repetition
        1.0 if board.is_endgame() else 0.0,  # Endgame flag
    ])
    
    # Ensure we have exactly 115 features as expected
    while len(features) < 115:
        features.append(0.0)
    
    features = features[:115]  # Truncate if too many
    
    return features

def sample_random_positions(game: Game, num_samples: int, max_plies: int = 80) -> List[Tuple[Board, int]]:
    """
    Generate random game positions by playing random games from the initial position.
    Returns list of (board, current_player) tuples.
    """
    positions = []
    attempts = 0
    max_attempts = num_samples * 3  # Allow some failed attempts
    
    logger.info(f"Sampling {num_samples} random positions...")
    
    while len(positions) < num_samples and attempts < max_attempts:
        attempts += 1
        board = game.getInitBoard()
        player = 1
        
        # Play random moves for a random number of plies
        num_plies = random.randint(10, max_plies)
        
        for _ in range(num_plies):
            # Check if game ended
            if game.getGameEnded(board, player) != 0:
                break
                
            # Get valid moves
            valid_moves = game.getValidMoves(board, player)
            legal_actions = np.where(valid_moves == 1)[0]
            
            if len(legal_actions) == 0:
                break
                
            # Choose random action
            action = random.choice(legal_actions)
            board, player = game.getNextState(board, player, action)
        
        # Filter out positions that are too early or problematic
        if board.put_pieces >= 8:  # At least some pieces placed
            positions.append((board, player))
        
        if len(positions) % 1000 == 0 and len(positions) > 0:
            logger.info(f"Sampled {len(positions)} positions...")
    
    logger.info(f"Generated {len(positions)} random positions from {attempts} attempts")
    return positions

def generate_training_data_with_perfect_db(perfect_db_path: str, 
                                         output_file: str,
                                         num_positions: int = 50000,
                                         num_threads: int = 0) -> bool:
    """
    Generate training data using Perfect Database DLL directly.
    No longer depends on sanmill executable.
    """
    logger.info(f"Generating {num_positions} training positions using Perfect DB...")
    
    # Initialize game and Perfect DB
    game = Game()
    pdb = PerfectDB()
    
    try:
        pdb.init(perfect_db_path)
        logger.info(f"Perfect DB initialized with path: {perfect_db_path}")
    except Exception as e:
        logger.error(f"Failed to initialize Perfect DB: {e}")
        return False
    
    start_time = time.time()
    
    try:
        # Generate random positions
        positions = sample_random_positions(game, num_positions)
        
        if not positions:
            logger.error("No positions were generated")
            return False
        
        training_data = []
        valid_positions = 0
        
        logger.info("Evaluating positions with Perfect DB...")
        
        for i, (board, player) in enumerate(positions):
            try:
                # Extract features
                features = extract_features_from_board(board, player)
                
                # Get Perfect DB evaluation
                only_take = (board.period == 3)
                wdl, steps = pdb.evaluate(board, player, only_take)
                
                # Convert WDL to evaluation score
                if wdl > 0:
                    evaluation = 1.0  # Win
                elif wdl < 0:
                    evaluation = -1.0  # Loss
                else:
                    evaluation = 0.0  # Draw
                
                # Get best move if available
                best_move_token = ""
                try:
                    best_moves = pdb.good_moves_tokens(board, player, only_take)
                    if best_moves:
                        best_move_token = best_moves[0]
                except:
                    pass  # Best move not critical for NNUE training
                
                # Format: features | evaluation | phase | fen  (to match train_nnue.py expectation)
                # Features should be integers (0 or 1), not floats
                feature_str = " ".join(str(int(f)) for f in features)
                # Generate a simple FEN-like representation for the position
                fen_str = f"board_period_{board.period}_player_{player}"
                line = f"{feature_str} | {evaluation:.6f} | {board.period} | {fen_str}\n"
                training_data.append(line)
                valid_positions += 1
                
                if (i + 1) % 1000 == 0:
                    logger.info(f"Processed {i + 1}/{len(positions)} positions, {valid_positions} valid")
                    
            except Exception as e:
                logger.debug(f"Skipping position {i}: {e}")
                continue
        
        # Write training data file
        with open(output_file, 'w') as f:
            # Write header
            f.write(f"# NNUE Training Data Generated by Perfect DB\n")
            f.write(f"# Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# Perfect DB Path: {perfect_db_path}\n")
            f.write(f"# Feature count: 115\n")
            f.write(f"{valid_positions}\n")  # Number of valid positions
            
            # Write training data
            for line in training_data:
                f.write(line)
        
        end_time = time.time()
        logger.info(f"Training data generation completed in {end_time - start_time:.2f} seconds")
        logger.info(f"Generated {valid_positions} valid training positions")
        
        if os.path.exists(output_file):
            file_size = os.path.getsize(output_file)
            logger.info(f"Training data saved to {output_file} ({file_size} bytes)")
            return True
        else:
            logger.error("Training data file was not created")
            return False
            
    finally:
        try:
            pdb.deinit()
        except:
            pass

# Legacy function for backward compatibility
def generate_training_data(engine_path: str, 
                         output_file: str,
                         num_positions: int = 50000,
                         perfect_db_path: str = ".",
                         num_threads: int = 0) -> bool:
    """
    Legacy function for backward compatibility.
    Now redirects to Perfect DB implementation.
    """
    logger.warning("Legacy generate_training_data called - redirecting to Perfect DB implementation")
    return generate_training_data_with_perfect_db(perfect_db_path, output_file, num_positions, num_threads)

def validate_training_data(data_file: str, feature_size: int) -> bool:
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
                if len(features) != feature_size:  # Expected feature count
                    logger.error(f"Incorrect feature count on line {i+1}: got {len(features)}, expected {feature_size}")
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
    parser = argparse.ArgumentParser(description='Generate NNUE training data for Sanmill using Perfect Database')
    parser.add_argument('--perfect-db', required=True, help='Path to Perfect Database directory')
    parser.add_argument('--output', default='training_data.txt', help='Output training data file')
    parser.add_argument('--positions', type=int, default=50000, help='Number of positions to generate')
    parser.add_argument('--threads', type=int, default=0, help='Number of threads (unused, kept for compatibility)')
    parser.add_argument('--validate', action='store_true', help='Validate generated data')
    parser.add_argument('--feature-size', type=int, default=115, help='Expected feature size for validation')
    
    # Legacy arguments for backward compatibility (will be ignored)
    parser.add_argument('--engine', help='Legacy: Path to Sanmill engine executable (ignored)')
    
    args = parser.parse_args()
    
    # Check if Perfect Database path exists
    if not os.path.exists(args.perfect_db):
        logger.error(f"Perfect Database path not found: {args.perfect_db}")
        return 1
    
    # Show deprecation warning if engine argument is used
    if args.engine:
        logger.warning("--engine argument is deprecated. Now using Perfect DB DLL directly.")
    
    # Generate training data using Perfect DB
    success = generate_training_data_with_perfect_db(
        args.perfect_db,
        args.output, 
        args.positions, 
        args.threads
    )
    
    if not success:
        logger.error("Failed to generate training data")
        return 1
    
    # Validate if requested
    if args.validate:
        if not validate_training_data(args.output, args.feature_size):
            logger.error("Training data validation failed")
            return 1
    
    logger.info("Training data generation completed successfully")
    return 0

if __name__ == '__main__':
    exit(main())
