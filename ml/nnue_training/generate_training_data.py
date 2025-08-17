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
from tqdm import tqdm
from collections import defaultdict

# Add parent directories to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from game.Game import Game
from game.GameLogic import Board  
from game.engine_adapter import move_to_engine_token
from perfect.perfect_db_reader import PerfectDB

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def print_statistics_tables(stats: dict, valid_positions: int, discarded_positions: int, 
                           total_time: float) -> None:
    """
    Print comprehensive statistics in well-formatted tables.
    """
    total_positions = valid_positions + discarded_positions
    
    print("\n" + "="*80)
    print("                    TRAINING DATA GENERATION STATISTICS")
    print("="*80)
    
    # Summary Statistics Table
    print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
    print("│                            SUMMARY STATISTICS                              │")
    print("├─────────────────────────────────────────────────────────────────────────────┤")
    print(f"│ Total Positions Processed    │ {total_positions:>10,} │ 100.0%          │")
    print(f"│ Valid Positions Generated    │ {valid_positions:>10,} │ {valid_positions/total_positions*100:>6.1f}%          │")
    print(f"│ Discarded Positions          │ {discarded_positions:>10,} │ {discarded_positions/total_positions*100:>6.1f}%          │")
    print(f"│ Processing Time              │ {total_time:>10.2f}s │ {valid_positions/total_time:>6.0f} pos/s     │")
    print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    # WDL Distribution Table
    wdl = stats['wdl_distribution']
    wdl_total = wdl['wins'] + wdl['losses'] + wdl['draws']
    if wdl_total > 0:
        print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
        print("│                        WIN/DRAW/LOSS DISTRIBUTION                           │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        print(f"│ Winning Positions            │ {wdl['wins']:>10,} │ {wdl['wins']/wdl_total*100:>6.1f}%          │")
        print(f"│ Losing Positions             │ {wdl['losses']:>10,} │ {wdl['losses']/wdl_total*100:>6.1f}%          │")
        print(f"│ Draw Positions               │ {wdl['draws']:>10,} │ {wdl['draws']/wdl_total*100:>6.1f}%          │")
        print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    # Evaluation Statistics Table
    if stats['evaluation_stats']['values']:
        evals = np.array(stats['evaluation_stats']['values'])
        wins = evals[evals > 0]
        losses = evals[evals < 0]
        draws = evals[evals == 0]
        
        print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
        print("│                        EVALUATION SCORE ANALYSIS                           │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        print(f"│ Overall Range                │ [{np.min(evals):>7.1f}, {np.max(evals):>7.1f}] │ σ = {np.std(evals):>6.2f}      │")
        if len(wins) > 0:
            print(f"│ Win Score Range              │ [{np.min(wins):>7.1f}, {np.max(wins):>7.1f}] │ μ = {np.mean(wins):>6.1f}      │")
        if len(losses) > 0:
            print(f"│ Loss Score Range             │ [{np.min(losses):>7.1f}, {np.max(losses):>7.1f}] │ μ = {np.mean(losses):>6.1f}      │")
        if len(draws) > 0:
            print(f"│ Draw Positions               │ {len(draws):>10,} positions │ Score = 0.0    │")
        print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    # Hash Access Distribution (All sectors, sorted by hash name)
    if stats['hash_access_count']:
        print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
        print("│                       DATABASE SECTORS ACCESSED                            │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        sorted_hashes = sorted(stats['hash_access_count'].items(), key=lambda x: x[0])
        for i, (hash_name, count) in enumerate(sorted_hashes):
            percentage = count / sum(stats['hash_access_count'].values()) * 100
            print(f"│ {i+1:>2}. {hash_name:<16} │ {count:>10,} │ {percentage:>6.1f}%          │")
        print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    # Steps Distribution (All steps, sorted by step value)
    if stats['steps_distribution']:
        print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
        print("│                         STEPS TO WIN/LOSS DISTRIBUTION                     │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        # Sort by step value (numeric), excluding 'unknown'
        sorted_steps = sorted([(k, v) for k, v in stats['steps_distribution'].items() if k != 'unknown'], 
                             key=lambda x: x[0])
        for i, (steps, count) in enumerate(sorted_steps):
            percentage = count / sum(stats['steps_distribution'].values()) * 100
            print(f"│ {steps:>3} steps                  │ {count:>10,} │ {percentage:>6.1f}%          │")
        # Add unknown steps at the end
        if 'unknown' in stats['steps_distribution']:
            unknown_count = stats['steps_distribution']['unknown']
            unknown_pct = unknown_count / sum(stats['steps_distribution'].values()) * 100
            print(f"│ Unknown steps              │ {unknown_count:>10,} │ {unknown_pct:>6.1f}%          │")
        print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    # Error Types (if any)
    if stats['error_types']:
        print("\n┌─────────────────────────────────────────────────────────────────────────────┐")
        print("│                            ERROR BREAKDOWN                                  │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        print("│ Error Type               │      Count │ % of Total │ % of Errors        │")
        print("├─────────────────────────────────────────────────────────────────────────────┤")
        for error_type, count in sorted(stats['error_types'].items(), key=lambda x: x[1], reverse=True):
            # Show percentage relative to total positions processed
            percentage_of_total = count / max(1, total_positions) * 100
            # Show percentage within error types (for reference)
            percentage_of_errors = count / max(1, discarded_positions) * 100
            print(f"│ {error_type:<24} │ {count:>10,} │ {percentage_of_total:>9.1f}% │ {percentage_of_errors:>16.1f}% │")
        print("└─────────────────────────────────────────────────────────────────────────────┘")
    
    print("\n" + "="*80)

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
    Generate random game positions following Nine Men's Morris actual game distribution.
    Uses stratified sampling to ensure diverse position types with realistic proportions.
    Returns list of (board, current_player) tuples.
    """
    positions = []
    attempts = 0
    max_attempts = num_samples * 3
    
    # Define game phase distributions based on actual Nine Men's Morris games
    phase_distribution = {
        'early_placement': 0.15,    # First 4 rounds of placing phase (8 pieces placed)
        'late_placement': 0.25,     # Remaining rounds of placing phase (10 more pieces)
        'moving_phase': 0.35,      # Moving phase excluding flying (both players >3 pieces)
        'flying_phase': 0.25       # Flying phase: when any player has ≤3 pieces on board
    }
    
    # Track samples per phase
    phase_targets = {phase: int(num_samples * ratio) for phase, ratio in phase_distribution.items()}
    phase_counts = {phase: 0 for phase in phase_targets.keys()}
    
    logger.info(f"Sampling {num_samples} positions with realistic game distribution:")
    for phase, target in phase_targets.items():
        logger.info(f"  {phase}: {target} positions ({phase_distribution[phase]*100:.0f}%)")
    
    while sum(phase_counts.values()) < num_samples and attempts < max_attempts:
        attempts += 1
        
        # Choose target phase based on remaining needs
        available_phases = [p for p, count in phase_counts.items() 
                          if count < phase_targets[p]]
        if not available_phases:
            break
            
        target_phase = random.choice(available_phases)
        
        # Generate position for target phase
        board = game.getInitBoard()
        player = 1
        
        # Define ply ranges for each phase
        if target_phase == 'early_placement':
            # First 4 rounds (8 pieces): 2-8 plies
            num_plies = random.randint(2, 8)
        elif target_phase == 'late_placement':
            # Remaining placement rounds: 9-18 plies  
            num_plies = random.randint(9, 18)
        elif target_phase == 'moving_phase':
            # Moving phase without flying: 19-50 plies
            num_plies = random.randint(19, 50)
        else:  # flying_phase
            # Flying phase: 30+ plies to reach flying conditions
            num_plies = random.randint(30, max_plies)
        
        # Play random game
        game_ended = False
        for ply in range(num_plies):
            if game.getGameEnded(board, player) != 0:
                game_ended = True
                break
                
            valid_moves = game.getValidMoves(board, player)
            legal_actions = np.where(valid_moves == 1)[0]
            
            if len(legal_actions) == 0:
                game_ended = True
                break
                
            action = random.choice(legal_actions)
            board, player = game.getNextState(board, player, action)
        
        # Validate position matches target phase
        w_count = board.count(1)
        b_count = board.count(-1)
        total_pieces = w_count + b_count
        w_in_hand = max(0, 9 - ((board.put_pieces + 1) // 2))
        b_in_hand = max(0, 9 - (board.put_pieces // 2))
        
        phase_valid = False
        if target_phase == 'early_placement' and board.period == 0 and board.put_pieces <= 8:
            # Early placement: first 4 rounds (8 pieces total)
            phase_valid = True
        elif target_phase == 'late_placement' and board.period == 0 and board.put_pieces > 8:
            # Late placement: remaining placement rounds 
            phase_valid = True
        elif target_phase == 'moving_phase' and board.period in [1, 2] and w_count > 3 and b_count > 3:
            # Moving phase: both players have >3 pieces (no flying yet)
            phase_valid = True
        elif target_phase == 'flying_phase' and board.period in [1, 2] and (w_count <= 3 or b_count <= 3) and w_count >= 2 and b_count >= 2:
            # Flying phase: at least one player has ≤3 pieces on board
            phase_valid = True
        
        # Accept position with some tolerance for phase boundaries
        if phase_valid or (not game_ended and total_pieces >= 4):
            # Apply balanced acceptance rate - stricter for overrepresented phases
            current_ratio = phase_counts[target_phase] / max(1, sum(phase_counts.values()))
            target_ratio = phase_distribution[target_phase]
            
            # Higher acceptance rate if we're behind target, lower if ahead
            acceptance_rate = min(0.8, target_ratio / max(0.1, current_ratio))
            
            if random.random() < acceptance_rate:
                positions.append((board, player))
                phase_counts[target_phase] += 1
        
        # Progress logging
        total_generated = sum(phase_counts.values())
        if total_generated % 1000 == 0 and total_generated > 0:
            logger.info(f"Generated {total_generated}/{num_samples} positions")
            for phase, count in phase_counts.items():
                percentage = count / max(1, total_generated) * 100
                logger.info(f"  {phase}: {count} ({percentage:.1f}%)")
    
    total_generated = sum(phase_counts.values())
    logger.info(f"Final distribution from {attempts} attempts:")
    for phase, count in phase_counts.items():
        percentage = count / max(1, total_generated) * 100
        target_pct = phase_distribution[phase] * 100
        logger.info(f"  {phase}: {count}/{phase_targets[phase]} ({percentage:.1f}%, target {target_pct:.1f}%)")
    
    return positions

def evaluate_positions_batch(pdb: 'PerfectDB', positions_data: List[Tuple], logger, stats: dict) -> List[str]:
    """
    Batch evaluate positions grouped by sector to minimize file switching.
    
    Args:
        pdb: PerfectDB instance
        positions_data: List of (board, player, features) tuples
        logger: Logger instance
        stats: Statistics dictionary to update
    
    Returns:
        List of training data lines for valid positions
    """
    # Group positions by sector hash to minimize file switching
    sector_groups = defaultdict(list)
    
    for i, (board, player, features) in enumerate(positions_data):
        w_count = board.count(1)
        b_count = board.count(-1)
        w_place = max(0, 9 - ((board.put_pieces + 1) // 2))
        b_place = max(0, 9 - (board.put_pieces // 2))
        sector_hash = f"std_{w_count}_{b_count}_{w_place}_{b_place}"
        sector_groups[sector_hash].append((i, board, player, features))
    
    logger.info(f"Batch processing {len(positions_data)} positions across {len(sector_groups)} sectors")
    logger.debug(f"Sector distribution: {[(k, len(v)) for k, v in sector_groups.items()]}")
    
    # Process each sector group
    results = {}
    valid_count = 0
    
    for sector_hash, sector_positions in sector_groups.items():
        logger.debug(f"Processing sector {sector_hash} with {len(sector_positions)} positions")
        
        for pos_idx, board, player, features in sector_positions:
            try:
                # Get Perfect DB evaluation
                only_take = (board.period == 3)
                wdl, steps = pdb.evaluate(board, player, only_take)
                
                # Update WDL statistics
                if wdl > 0:
                    stats['wdl_distribution']['wins'] += 1
                elif wdl < 0:
                    stats['wdl_distribution']['losses'] += 1
                else:
                    stats['wdl_distribution']['draws'] += 1
                
                # Update steps statistics
                if steps > 0:
                    stats['steps_distribution'][steps] += 1
                else:
                    stats['steps_distribution']['unknown'] += 1
                
                # Convert WDL and steps to evaluation score using enhanced method
                BASE_SCORE = 500.0
                
                if wdl > 0:  # Win
                    if steps > 0:
                        # Win: BASE_SCORE - steps (closer win = higher score)
                        evaluation = BASE_SCORE - float(steps)
                    else:
                        # Unknown steps - minimal positive score
                        evaluation = 1.0
                elif wdl < 0:  # Loss
                    if steps > 0:
                        # Loss: -(BASE_SCORE - steps) (farther loss = higher score)
                        evaluation = -(BASE_SCORE - float(steps))
                    else:
                        # Unknown steps - high negative score
                        evaluation = -499.0
                else:  # Draw
                    evaluation = 0.0
                
                # Track evaluation values for statistics
                stats['evaluation_stats']['values'].append(evaluation)
                
                # Categorize evaluation ranges based on WDL result, not evaluation score
                if wdl > 0:  # Win
                    if steps > 0 and steps <= 10:
                        stats['evaluation_stats']['ranges']['strong_win'] += 1
                    elif steps > 0 and steps <= 50:
                        stats['evaluation_stats']['ranges']['weak_win'] += 1
                    else:
                        stats['evaluation_stats']['ranges']['win_unknown_steps'] += 1
                elif wdl < 0:  # Loss
                    if steps > 0 and steps <= 10:
                        stats['evaluation_stats']['ranges']['strong_loss'] += 1
                    elif steps > 0 and steps <= 50:
                        stats['evaluation_stats']['ranges']['weak_loss'] += 1
                    else:
                        stats['evaluation_stats']['ranges']['loss_unknown_steps'] += 1
                else:  # Draw (wdl == 0)
                    stats['evaluation_stats']['ranges']['draw'] += 1
                
                # Create training data line in the expected format
                # Format: features | evaluation | phase | fen
                feature_str = ' '.join(str(int(f)) for f in features)  # Convert to integers as expected
                target_str = f'{evaluation:.6f}'
                phase_str = str(board.period)
                fen_str = board.to_fen(player)
                training_line = f"{feature_str} | {target_str} | {phase_str} | {fen_str}\n"
                
                results[pos_idx] = training_line
                valid_count += 1
                
            except Exception as e:
                logger.warning(f"Failed to evaluate position {pos_idx} in sector {sector_hash}: {e}")
                continue
    
    # Return results in original order
    training_data = []
    for i in range(len(positions_data)):
        if i in results:
            training_data.append(results[i])
    
    logger.info(f"Batch processing completed: {valid_count}/{len(positions_data)} positions valid")
    logger.debug(f"Final training_data length: {len(training_data)}")
    if training_data:
        logger.debug(f"Sample training line: {training_data[0][:100]}...")
    return training_data

def generate_training_data_with_perfect_db(perfect_db_path: str, 
                                         output_file: str,
                                         num_positions: int = 50000,
                                         num_threads: int = 0,
                                         batch_size: int = 1000) -> bool:
    """
    Generate training data using Perfect Database DLL directly.
    Uses enhanced evaluation with Distance to Victory/Loss (DTV/DTL) for fine-grained scoring.
    Optimized with batch processing to reduce sector file switching.
    No longer depends on sanmill executable.
    """
    logger.info(f"Generating {num_positions} training positions using Perfect DB...")
    logger.info(f"Using batch processing with batch size: {batch_size}")
    
    # Initialize game and Perfect DB
    game = Game()
    pdb = PerfectDB()
    
    try:
        pdb.init(perfect_db_path)
        logger.info(f"Perfect DB initialized with path: {perfect_db_path}")
    except Exception as e:
        logger.error(f"Failed to initialize Perfect DB: {e}")
        return False
    
    # Set up error logging for failed positions
    error_log_dir = Path(__file__).parent / "training_data"
    error_log_dir.mkdir(exist_ok=True)
    error_log_file = error_log_dir / f"error_log_{time.strftime('%Y%m%d_%H%M%S')}.txt"
    
    # Create error logger
    error_logger = logging.getLogger('error_logger')
    error_logger.setLevel(logging.WARNING)
    # Clear any existing handlers
    error_logger.handlers.clear()
    error_handler = logging.FileHandler(error_log_file)
    error_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    error_handler.setFormatter(error_formatter)
    error_logger.addHandler(error_handler)
    
    start_time = time.time()
    discarded_positions = 0
    
    # Statistics tracking
    stats = {
        'hash_access_count': defaultdict(int),
        'wdl_distribution': {'wins': 0, 'losses': 0, 'draws': 0},
        'steps_distribution': defaultdict(int),
        'error_types': defaultdict(int),
        'evaluation_stats': {
            'values': [], 
            'ranges': {
                'strong_win': 0,      # Win in ≤10 steps
                'weak_win': 0,        # Win in 11-50 steps  
                'win_unknown_steps': 0, # Win with unknown steps
                'draw': 0,            # Draw (wdl == 0)
                'weak_loss': 0,       # Loss in 11-50 steps
                'strong_loss': 0,     # Loss in ≤10 steps
                'loss_unknown_steps': 0 # Loss with unknown steps
            }
        }
    }
    
    try:
        # Phase 1: Generate random positions
        logger.info("Phase 1: Generating random positions...")
        positions = []
        with tqdm(total=num_positions, desc="Generating positions", 
                 unit="pos", ncols=100, ascii=True) as pbar:
            positions = sample_random_positions(game, num_positions)
            pbar.update(num_positions)
        
        if not positions:
            logger.error("No positions were generated")
            return False
        
        logger.info(f"✓ Generated {len(positions)} random positions")
        
        # Phase 2: Evaluate positions with Perfect DB (using batch processing)
        training_data = []
        valid_positions = 0
        
        logger.info("Phase 2: Evaluating positions with Perfect Database...")
        logger.info(f"Using batch processing with batch size: {batch_size}")
        
        # Process positions in batches to optimize sector file access
        total_batches = (len(positions) + batch_size - 1) // batch_size
        
        with tqdm(total=len(positions), desc="Evaluating positions", 
                 unit="pos", ncols=100, ascii=True) as pbar:
            
            for batch_idx in range(total_batches):
                start_idx = batch_idx * batch_size
                end_idx = min(start_idx + batch_size, len(positions))
                batch_positions = positions[start_idx:end_idx]
                
                logger.debug(f"Processing batch {batch_idx + 1}/{total_batches} "
                           f"(positions {start_idx}-{end_idx-1})")
                
                # Prepare batch data with feature extraction
                batch_data = []
                for i, (board, player) in enumerate(batch_positions):
                    try:
                        # Extract features
                        features = extract_features_from_board(board, player)
                        batch_data.append((board, player, features))
                        
                        # Track hash access for statistics
                        w_count = board.count(1)
                        b_count = board.count(-1)
                        w_place = max(0, 9 - ((board.put_pieces + 1) // 2))
                        b_place = max(0, 9 - (board.put_pieces // 2))
                        sector_hash = f"std_{w_count}_{b_count}_{w_place}_{b_place}"
                        stats['hash_access_count'][sector_hash] += 1
                        
                    except Exception as e:
                        discarded_positions += 1
                        stats['error_types'][str(type(e).__name__)] += 1
                        
                        # Log detailed error information
                        error_logger.warning(f"Position {start_idx + i}: Failed to extract features. "
                                           f"Error: {e}. Board state: period={board.period}, "
                                           f"put_pieces={board.put_pieces}, "
                                           f"W={board.count(1)}, B={board.count(-1)}")
                        continue
                
                # Batch evaluate positions
                if batch_data:
                    try:
                        batch_results = evaluate_positions_batch(pdb, batch_data, logger, stats)
                        training_data.extend(batch_results)
                        valid_positions += len(batch_results)
                        
                    except Exception as e:
                        logger.error(f"Batch evaluation failed for batch {batch_idx + 1}: {e}")
                        discarded_positions += len(batch_data)
                        stats['error_types']['batch_evaluation_error'] += 1
                
                # Update progress bar
                batch_processed = end_idx - start_idx
                pbar.update(batch_processed)
                pbar.set_postfix({
                    'Valid': valid_positions,
                    'Discarded': discarded_positions,
                    'Success%': f"{(valid_positions/end_idx*100):.1f}" if end_idx > 0 else "0.0",
                    'Batch': f"{batch_idx + 1}/{total_batches}"
                })
        

        
        # Phase 3: Write training data file
        logger.info("Phase 3: Writing training data to file...")
        
        with tqdm(total=valid_positions + 5, desc="Writing data file", 
                 unit="lines", ncols=100, ascii=True) as pbar:
            with open(output_file, 'w') as f:
                # Write header
                f.write(f"# NNUE Training Data Generated by Perfect DB\n")
                pbar.update(1)
                f.write(f"# Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                pbar.update(1)
                f.write(f"# Perfect DB Path: {perfect_db_path}\n")
                pbar.update(1)
                f.write(f"# Feature count: 115\n")
                pbar.update(1)
                f.write(f"{valid_positions}\n")  # Number of valid positions
                pbar.update(1)
                
                # Write training data
                for line in training_data:
                    f.write(line)
                    pbar.update(1)
        
        # Print comprehensive statistics tables
        print_statistics_tables(stats, valid_positions, discarded_positions, 
                               time.time() - start_time)
        
        end_time = time.time()
        logger.info(f"Training data generation completed in {end_time - start_time:.2f} seconds")
        logger.info(f"Generated {valid_positions} valid training positions")
        logger.info(f"Discarded {discarded_positions} positions due to evaluation failures")
        if discarded_positions > 0:
            logger.info(f"Error details saved to: {error_log_file}")
        
        if os.path.exists(output_file):
            file_size = os.path.getsize(output_file)
            logger.info(f"Training data saved to {output_file} ({file_size} bytes)")
            
            # Quick diagnostic: check first few lines of the file
            with open(output_file, 'r') as f:
                lines = f.readlines()
                logger.info(f"File contains {len(lines)} total lines")
                if len(lines) > 5:
                    logger.info("First 3 data lines:")
                    for i, line in enumerate(lines[:3]):
                        if not line.startswith('#'):
                            logger.info(f"  Line {i}: {line.strip()[:100]}...")
            
            return True
        else:
            logger.error("Training data file was not created")
            return False
            
    finally:
        try:
            pdb.deinit()
        except:
            pass
        
        # Clean up error logger
        try:
            for handler in error_logger.handlers[:]:
                handler.close()
                error_logger.removeHandler(handler)
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
    return generate_training_data_with_perfect_db(perfect_db_path, output_file, num_positions, num_threads, batch_size=1000)

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
    
    logger.info("Using enhanced evaluation with DTV/DTL steps for fine-grained scoring")
    
    # Generate training data using Perfect DB
    success = generate_training_data_with_perfect_db(
        args.perfect_db,
        args.output, 
        args.positions, 
        args.threads,
        batch_size=1000  # Add batch processing optimization
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
