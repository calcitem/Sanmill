#!/usr/bin/env python3
"""
Training Data Generator for NNUE PyTorch using Perfect Database

This script generates training data for Nine Men's Morris NNUE training by:
1. Using Perfect Database for optimal position evaluations
2. Supporting 16-fold symmetry transformations for data augmentation
3. Converting between coordinate systems (ml/game <-> nnue-pytorch)
4. Generating positions across different game phases

Usage:
    python generate_training_data.py --perfect-db /path/to/db --output training_data.txt --positions 50000
    python generate_training_data.py --perfect-db /path/to/db --output training_data.txt --positions 50000 --symmetries
"""

import os
import sys
import argparse
import random
import time
import logging
from pathlib import Path
from typing import List, Tuple, Dict, Optional
from collections import defaultdict
import numpy as np
from tqdm import tqdm

# Add paths for importing from ml/perfect and ml/game
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.join(current_dir, '..')
perfect_dir = os.path.join(current_dir, '..', 'perfect')
game_dir = os.path.join(current_dir, '..', 'game')

# Add ml directory first so that "game.standard_rules" import works
sys.path.insert(0, ml_dir)
sys.path.insert(0, perfect_dir)
sys.path.insert(0, game_dir)

# Set up logging first
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

try:
    from perfect_db_reader import PerfectDB
except ImportError as e:
    logger.error(f"Failed to import PerfectDB: {e}")
    logger.error(f"Perfect directory path: {perfect_dir}")
    logger.error("Please ensure perfect_db_reader.py is available in ml/perfect/")
    sys.exit(1)

try:
    from game.Game import Game
    from game.GameLogic import Board
except ImportError as e:
    # Try alternative import path
    try:
        sys.path.insert(0, os.path.join(current_dir, '..'))
        from game.Game import Game
        from game.GameLogic import Board
    except ImportError as e2:
        logger.error(f"Failed to import Game modules: {e}, {e2}")
        logger.error(f"Game directory path: {game_dir}")
        logger.error("Please ensure Game.py and GameLogic.py are available in ml/game/")
        sys.exit(1)

# Coordinate system mappings
def create_coordinate_mappings():
    """Create mappings between different coordinate systems."""
    # ml/game Board.allowed_places pattern
    allowed_places = np.array([
        [1, 0, 0, 1, 0, 0, 1],
        [0, 1, 0, 1, 0, 1, 0],
        [0, 0, 1, 1, 1, 0, 0],
        [1, 1, 1, 0, 1, 1, 1],
        [0, 0, 1, 1, 1, 0, 0],
        [0, 1, 0, 1, 0, 1, 0],
        [1, 0, 0, 1, 0, 0, 1]
    ], dtype=bool)
    
    # Create coordinate to feature index mapping
    coord_to_feature = {}
    feature_to_coord = {}
    feature_idx = 0
    
    for y in range(7):
        for x in range(7):
            if allowed_places[x][y]:
                coord_to_feature[(x, y)] = feature_idx
                feature_to_coord[feature_idx] = (x, y)
                feature_idx += 1
    
    return coord_to_feature, feature_to_coord

COORD_TO_FEATURE, FEATURE_TO_COORD = create_coordinate_mappings()


class SymmetryTransforms:
    """
    Implements 16 symmetry transformations for Nine Men's Morris positions.
    
    Based on the Perfect Database symmetry system (perfect_symmetries_slow.cpp).
    Supports geometric transformations (rotations, reflections) and color swaps.
    """
    
    # 16 symmetry operations matching perfect_symmetries_slow.cpp
    TRANSFORM_NAMES = [
        "rotate90", "rotate180", "rotate270",
        "mirror_vertical", "mirror_horizontal", 
        "mirror_backslash", "mirror_slash",
        "swap", "swap_rotate90", "swap_rotate180", "swap_rotate270",
        "swap_mirror_vertical", "swap_mirror_horizontal",
        "swap_mirror_backslash", "swap_mirror_slash",
        "id_transform"  # Identity transform
    ]
    
    def __init__(self):
        """Initialize symmetry transformation tables."""
        self.transform_tables = {}
        self._build_all_transform_tables()
    
    def _build_all_transform_tables(self):
        """Build transformation tables for all 16 symmetries."""
        for i, transform_name in enumerate(self.TRANSFORM_NAMES):
            self.transform_tables[i] = self._build_transform_table(transform_name)
    
    def _build_transform_table(self, transform_name: str) -> List[int]:
        """Build transformation table for a specific symmetry operation."""
        transform_table = [0] * 24
        
        for feature_idx in range(24):
            x, y = FEATURE_TO_COORD[feature_idx]
            
            # Apply geometric transformation
            if transform_name == "id_transform":
                new_x, new_y = x, y
            elif transform_name == "rotate90":
                new_x, new_y = 6 - y, x
            elif transform_name == "rotate180":
                new_x, new_y = 6 - x, 6 - y
            elif transform_name == "rotate270":
                new_x, new_y = y, 6 - x
            elif transform_name == "mirror_vertical":
                new_x, new_y = x, 6 - y
            elif transform_name == "mirror_horizontal":
                new_x, new_y = 6 - x, y
            elif transform_name == "mirror_backslash":
                new_x, new_y = y, x
            elif transform_name == "mirror_slash":
                new_x, new_y = 6 - y, 6 - x
            else:
                # For swap operations, apply base geometric transformation
                base_transform = transform_name.replace("swap_", "")
                if base_transform == "swap":
                    new_x, new_y = x, y  # No geometric transformation for pure swap
                elif base_transform == "rotate90":
                    new_x, new_y = 6 - y, x
                elif base_transform == "rotate180":
                    new_x, new_y = 6 - x, 6 - y
                elif base_transform == "rotate270":
                    new_x, new_y = y, 6 - x
                elif base_transform == "mirror_vertical":
                    new_x, new_y = x, 6 - y
                elif base_transform == "mirror_horizontal":
                    new_x, new_y = 6 - x, y
                elif base_transform == "mirror_backslash":
                    new_x, new_y = y, x
                elif base_transform == "mirror_slash":
                    new_x, new_y = 6 - y, 6 - x
                else:
                    new_x, new_y = x, y
            
            # Map transformed coordinates back to feature index
            if (new_x, new_y) in COORD_TO_FEATURE:
                transform_table[feature_idx] = COORD_TO_FEATURE[(new_x, new_y)]
            else:
                # Invalid transformation - keep original
                transform_table[feature_idx] = feature_idx
        
        return transform_table
    
    def apply_transform(self, board_state: Dict, transform_idx: int) -> Dict:
        """
        Apply a symmetry transformation to a board state.
        
        Args:
            board_state: Dictionary with piece positions and game state
            transform_idx: Index of transformation (0-15)
            
        Returns:
            Transformed board state
        """
        if not (0 <= transform_idx < 16):
            raise ValueError(f"Invalid transform index: {transform_idx}")
        
        transform_name = self.TRANSFORM_NAMES[transform_idx]
        transform_table = self.transform_tables[transform_idx]
        
        # Apply geometric transformation to piece positions
        new_white_pieces = [transform_table[pos] for pos in board_state.get('white_pieces', [])]
        new_black_pieces = [transform_table[pos] for pos in board_state.get('black_pieces', [])]
        
        # Handle color swapping for swap operations
        if transform_name.startswith("swap"):
            new_white_pieces, new_black_pieces = new_black_pieces, new_white_pieces
            new_side_to_move = 1 - board_state.get('side_to_move', 0)
            # Swap piece counts as well
            new_white_in_hand = board_state.get('black_in_hand', 0)
            new_black_in_hand = board_state.get('white_in_hand', 0)
        else:
            new_side_to_move = board_state.get('side_to_move', 0)
            new_white_in_hand = board_state.get('white_in_hand', 0)
            new_black_in_hand = board_state.get('black_in_hand', 0)
        
        return {
            'white_pieces': sorted(new_white_pieces),
            'black_pieces': sorted(new_black_pieces),
            'side_to_move': new_side_to_move,
            'phase': board_state.get('phase', 0),
            'white_in_hand': new_white_in_hand,
            'black_in_hand': new_black_in_hand
        }
    
    def generate_all_symmetries(self, board_state: Dict) -> List[Dict]:
        """Generate all 16 symmetry variants of a position."""
        symmetries = []
        for i in range(16):
            transformed = self.apply_transform(board_state, i)
            symmetries.append(transformed)
        return symmetries


class PerfectDBTrainingDataGenerator:
    """
    Training data generator using Perfect Database for NNUE PyTorch.
    
    This class generates training positions with optimal evaluations using
    the Perfect Database, with support for symmetry augmentation.
    """
    
    def __init__(self, perfect_db_path: str):
        """
        Initialize training data generator.
        
        Args:
            perfect_db_path: Path to Perfect Database directory
        """
        self.perfect_db_path = perfect_db_path
        self.game = Game()
        self.perfect_db = PerfectDB()
        self.symmetry_transforms = SymmetryTransforms()
        
        # Statistics tracking
        self.stats = {
            'positions_generated': 0,
            'positions_evaluated': 0,
            'positions_failed': 0,
            'symmetries_generated': 0,
            'wdl_distribution': {'wins': 0, 'losses': 0, 'draws': 0},
            'phase_distribution': defaultdict(int),
            'error_types': defaultdict(int)
        }
    
    def initialize(self) -> bool:
        """Initialize Perfect Database connection."""
        try:
            self.perfect_db.init(self.perfect_db_path)
            logger.info(f"Perfect Database initialized: {self.perfect_db_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to initialize Perfect Database: {e}")
            return False
    
    def cleanup(self):
        """Clean up Perfect Database connection."""
        try:
            self.perfect_db.deinit()
            logger.info("Perfect Database deinitialized")
        except Exception as e:
            logger.error(f"Error during cleanup: {e}")
    
    def board_to_board_state(self, board: Board, player: int) -> Dict:
        """
        Convert ml/game Board to board state dictionary.
        
        Args:
            board: ml/game Board object
            player: Current player (1 for white, -1 for black)
            
        Returns:
            Board state dictionary compatible with Perfect DB
        """
        white_pieces = []
        black_pieces = []
        
        # Extract piece positions using coordinate mapping
        for (x, y), feature_idx in COORD_TO_FEATURE.items():
            piece = board.pieces[x][y]
            if piece == 1:  # White piece
                white_pieces.append(feature_idx)
            elif piece == -1:  # Black piece
                black_pieces.append(feature_idx)
        
        # Calculate pieces in hand based on game state
        if hasattr(board, 'put_pieces'):
            white_in_hand = max(0, 9 - ((board.put_pieces + 1) // 2))
            black_in_hand = max(0, 9 - (board.put_pieces // 2))
        else:
            # Fallback calculation
            white_in_hand = max(0, 9 - len(white_pieces))
            black_in_hand = max(0, 9 - len(black_pieces))
        
        return {
            'white_pieces': white_pieces,
            'black_pieces': black_pieces,
            'side_to_move': 0 if player == 1 else 1,
            'phase': getattr(board, 'period', 0),
            'white_in_hand': white_in_hand,
            'black_in_hand': black_in_hand
        }
    
    def create_random_board_for_sector(self, W: int, B: int, WF: int, BF: int) -> Optional[Board]:
        """
        Create a random board position matching sector parameters.
        
        Args:
            W: White pieces on board
            B: Black pieces on board
            WF: White pieces in hand
            BF: Black pieces in hand
            
        Returns:
            Board object or None if generation failed
        """
        board = self.game.getInitBoard()
        
        # Set board state based on sector parameters
        total_placed = W + B
        
        if WF > 0 or BF > 0:
            # Placement phase
            board.period = 0
            board.put_pieces = total_placed
        else:
            # Moving/Flying phase
            if W <= 3 or B <= 3:
                board.period = 2  # Flying phase
            else:
                board.period = 1  # Moving phase
            board.put_pieces = 18  # All pieces placed
        
        # Get valid positions from coordinate mapping
        valid_positions = list(COORD_TO_FEATURE.keys())
        
        if len(valid_positions) < total_placed:
            return None
        
        # Clear board
        for x in range(7):
            for y in range(7):
                board.pieces[x][y] = 0
        
        # Randomly place pieces
        selected_positions = random.sample(valid_positions, total_placed)
        white_positions = selected_positions[:W]
        black_positions = selected_positions[W:W+B]
        
        # Place white pieces
        for x, y in white_positions:
            board.pieces[x][y] = 1
        
        # Place black pieces
        for x, y in black_positions:
            board.pieces[x][y] = -1
        
        # Validate board state
        if board.count(1) != W or board.count(-1) != B:
            return None
        
        return board
    
    def scan_perfect_db_sectors(self) -> Dict[str, List[Tuple[int, int, int, int]]]:
        """
        Scan Perfect Database directory for available sectors.
        
        Returns:
            Dictionary mapping phase names to sector parameter lists
        """
        import glob
        import re
        
        # Find all .sec2 files
        sec2_pattern = os.path.join(self.perfect_db_path, "*.sec2")
        sec2_files = glob.glob(sec2_pattern)
        
        # Parse filename pattern: std_W_B_WF_BF.sec2
        filename_pattern = re.compile(r'std_(\d+)_(\d+)_(\d+)_(\d+)\.sec2$')
        
        phase_sectors = defaultdict(list)
        
        for filepath in sec2_files:
            filename = os.path.basename(filepath)
            match = filename_pattern.match(filename)
            
            if match:
                W, B, WF, BF = map(int, match.groups())
                
                # Skip invalid sectors (game would be over)
                if W < 2 or B < 2:
                    continue
                
                # Classify game phase
                if WF > 0 or BF > 0:
                    phase = 'placement'
                elif W <= 3 or B <= 3:
                    phase = 'flying'
                else:
                    phase = 'moving'
                
                phase_sectors[phase].append((W, B, WF, BF))
        
        logger.info(f"Scanned {len(sec2_files)} .sec2 files")
        for phase, sectors in phase_sectors.items():
            logger.info(f"  {phase}: {len(sectors)} sectors")
        
        return dict(phase_sectors)
    
    def generate_positions_from_sectors(self, sectors_by_phase: Dict, num_positions: int) -> List[Tuple[Board, int]]:
        """
        Generate random positions by sampling from Perfect Database sectors.
        
        Args:
            sectors_by_phase: Dictionary mapping phases to sector parameters
            num_positions: Total number of positions to generate
            
        Returns:
            List of (board, current_player) tuples
        """
        # Phase distribution for balanced training data
        phase_weights = {
            'placement': 0.45,
            'moving': 0.35,
            'flying': 0.20
        }
        
        # Calculate target counts per phase
        phase_targets = {}
        for phase, weight in phase_weights.items():
            if phase in sectors_by_phase and len(sectors_by_phase[phase]) > 0:
                phase_targets[phase] = int(num_positions * weight)
            else:
                logger.warning(f"No sectors found for phase '{phase}', skipping")
        
        # Redistribute missing phases
        total_target = sum(phase_targets.values())
        if total_target < num_positions:
            remaining = num_positions - total_target
            for phase in phase_targets:
                phase_targets[phase] += remaining // len(phase_targets)
        
        logger.info(f"Target distribution for {num_positions} positions:")
        for phase, target in phase_targets.items():
            percentage = target / num_positions * 100
            logger.info(f"  {phase}: {target} positions ({percentage:.1f}%)")
        
        positions = []
        
        # Generate positions for each phase
        for phase, target_count in phase_targets.items():
            if target_count == 0:
                continue
            
            available_sectors = sectors_by_phase[phase]
            logger.info(f"Generating {target_count} positions from {len(available_sectors)} '{phase}' sectors")
            
            phase_positions = []
            max_attempts = target_count * 3
            attempts = 0
            
            while len(phase_positions) < target_count and attempts < max_attempts:
                attempts += 1
                
                # Randomly select a sector
                W, B, WF, BF = random.choice(available_sectors)
                
                try:
                    # Generate random board for this sector
                    board = self.create_random_board_for_sector(W, B, WF, BF)
                    if board is not None:
                        # Random side to move
                        player = random.choice([1, -1])
                        phase_positions.append((board, player))
                        
                        # Update statistics
                        self.stats['positions_generated'] += 1
                        self.stats['phase_distribution'][phase] += 1
                        
                except Exception as e:
                    logger.debug(f"Failed to generate position for sector std_{W}_{B}_{WF}_{BF}: {e}")
                    continue
            
            logger.info(f"Generated {len(phase_positions)}/{target_count} positions for '{phase}' phase")
            positions.extend(phase_positions)
        
        logger.info(f"Total positions generated: {len(positions)}")
        return positions
    
    def evaluate_position_with_perfect_db(self, board: Board, player: int) -> Tuple[float, str]:
        """
        Evaluate position using Perfect Database.
        
        Args:
            board: ml/game Board object
            player: Current player (1 for white, -1 for black)
            
        Returns:
            Tuple of (evaluation_score, best_move_token)
        """
        try:
            # Convert to board state format
            board_state = self.board_to_board_state(board, player)
            
            # Determine if only capture moves allowed
            only_take = (board.period == 3)
            
            # Evaluate with Perfect Database
            wdl, steps = self.perfect_db.evaluate(board, player, only_take)
            
            # Update WDL statistics
            if wdl > 0:
                self.stats['wdl_distribution']['wins'] += 1
            elif wdl < 0:
                self.stats['wdl_distribution']['losses'] += 1
            else:
                self.stats['wdl_distribution']['draws'] += 1
            
            # Convert WDL and steps to evaluation score
            evaluation = self._wdl_steps_to_evaluation(wdl, steps)
            
            # Get best move tokens (simplified - just return first good move)
            try:
                best_moves = self.perfect_db.good_moves_tokens(board, player, only_take)
                best_move = best_moves[0] if best_moves else "none"
            except Exception:
                best_move = "none"
            
            self.stats['positions_evaluated'] += 1
            return evaluation, best_move
            
        except Exception as e:
            self.stats['positions_failed'] += 1
            self.stats['error_types'][type(e).__name__] += 1
            raise
    
    def _wdl_steps_to_evaluation(self, wdl: int, steps: int) -> float:
        """Convert WDL and steps to evaluation score for NNUE training."""
        BASE_SCORE = 500.0
        
        if wdl > 0:  # Win
            if steps > 0:
                return BASE_SCORE - float(steps)
            else:
                return 1.0
        elif wdl < 0:  # Loss
            if steps > 0:
                return -(BASE_SCORE - float(steps))
            else:
                return -499.0
        else:  # Draw
            return 0.0
    
    def board_state_to_fen_format(self, board_state: Dict) -> str:
        """
        Convert board state to FEN format compatible with nnue-pytorch.
        
        Args:
            board_state: Board state dictionary
            
        Returns:
            FEN string in format expected by nnue-pytorch training
        """
        # Create board representation
        board_chars = ['*'] * 24
        
        # Place white pieces
        for pos in board_state.get('white_pieces', []):
            if 0 <= pos < 24:
                board_chars[pos] = 'O'
        
        # Place black pieces
        for pos in board_state.get('black_pieces', []):
            if 0 <= pos < 24:
                board_chars[pos] = '@'
        
        # Format as FEN with '/' separators every 8 positions (matching C++ format)
        board_str = ''.join(board_chars[:8]) + '/' + \
                   ''.join(board_chars[8:16]) + '/' + \
                   ''.join(board_chars[16:24]) + '/'
        
        # Add game state information
        side = 'w' if board_state.get('side_to_move', 0) == 0 else 'b'
        
        # Map phase to character
        phase_map = {0: 'r', 1: 'p', 2: 'm', 3: 'o'}
        phase = phase_map.get(board_state.get('phase', 0), 'r')
        
        action = 'p'  # Default action
        
        # Piece counts
        white_on_board = len(board_state.get('white_pieces', []))
        white_in_hand = board_state.get('white_in_hand', 0)
        black_on_board = len(board_state.get('black_pieces', []))
        black_in_hand = board_state.get('black_in_hand', 0)
        
        # Additional state information (simplified)
        fen = (f"{board_str} {side} {phase} {action} {white_on_board} {white_in_hand} "
               f"{black_on_board} {black_in_hand} 0 0 0 0 0 0 0 0 1")
        
        return fen
    
    def generate_training_data(self, num_positions: int, output_file: str, 
                             use_symmetries: bool = False, batch_size: int = 1000) -> bool:
        """
        Generate training data using Perfect Database.
        
        Args:
            num_positions: Number of base positions to generate
            output_file: Output file path
            use_symmetries: Whether to include symmetry augmentation
            batch_size: Batch size for processing
            
        Returns:
            True if successful, False otherwise
        """
        if not self.initialize():
            return False
        
        try:
            # Scan available sectors
            logger.info("Scanning Perfect Database sectors...")
            sectors_by_phase = self.scan_perfect_db_sectors()
            
            if not sectors_by_phase:
                logger.error("No valid sectors found in Perfect Database")
                return False
            
            # Generate base positions
            logger.info(f"Generating {num_positions} base positions...")
            positions = self.generate_positions_from_sectors(sectors_by_phase, num_positions)
            
            if not positions:
                logger.error("No positions were generated")
                return False
            
            # Process positions and generate training data
            training_data = []
            
            logger.info("Evaluating positions with Perfect Database...")
            
            # Process in batches to manage memory
            total_batches = (len(positions) + batch_size - 1) // batch_size
            
            with tqdm(total=len(positions), desc="Evaluating positions", 
                     unit="pos", ascii=True, ncols=80) as pbar:
                
                for batch_idx in range(total_batches):
                    start_idx = batch_idx * batch_size
                    end_idx = min(start_idx + batch_size, len(positions))
                    batch_positions = positions[start_idx:end_idx]
                    
                    for board, player in batch_positions:
                        try:
                            # Evaluate base position
                            evaluation, best_move = self.evaluate_position_with_perfect_db(board, player)
                            board_state = self.board_to_board_state(board, player)
                            
                            # Add base position
                            fen = self.board_state_to_fen_format(board_state)
                            training_data.append(f"{fen} {evaluation:.6f} {best_move} 0.0")
                            
                            # Add symmetries if requested
                            if use_symmetries:
                                symmetries = self.symmetry_transforms.generate_all_symmetries(board_state)
                                for sym_state in symmetries[1:]:  # Skip identity (already added)
                                    try:
                                        # Create temporary board for symmetry evaluation
                                        sym_board = self._board_state_to_board(sym_state)
                                        sym_player = 1 if sym_state['side_to_move'] == 0 else -1
                                        
                                        sym_eval, sym_best_move = self.evaluate_position_with_perfect_db(sym_board, sym_player)
                                        sym_fen = self.board_state_to_fen_format(sym_state)
                                        training_data.append(f"{sym_fen} {sym_eval:.6f} {sym_best_move} 0.0")
                                        
                                        self.stats['symmetries_generated'] += 1
                                        
                                    except Exception as e:
                                        logger.debug(f"Failed to evaluate symmetry: {e}")
                                        continue
                            
                        except Exception as e:
                            logger.debug(f"Failed to evaluate position: {e}")
                            self.stats['positions_failed'] += 1
                            continue
                        
                        pbar.update(1)
            
            # Write training data to file
            logger.info(f"Writing {len(training_data)} training examples to {output_file}")
            
            with open(output_file, 'w', encoding='utf-8') as f:
                # Write header
                f.write("# Nine Men's Morris NNUE Training Data\n")
                f.write(f"# Generated using Perfect Database: {self.perfect_db_path}\n")
                f.write(f"# Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"# Base positions: {len(positions)}\n")
                f.write(f"# Symmetries included: {use_symmetries}\n")
                f.write(f"# Total examples: {len(training_data)}\n")
                f.write("#\n")
                f.write("# Format: FEN EVALUATION BEST_MOVE RESULT\n")
                f.write("#\n")
                
                # Write training data
                for line in training_data:
                    f.write(line + "\n")
            
            # Print statistics
            self._print_generation_statistics(len(training_data))
            
            logger.info(f"Training data generation completed: {output_file}")
            return True
            
        finally:
            self.cleanup()
    
    def _board_state_to_board(self, board_state: Dict) -> Board:
        """Convert board state dictionary back to ml/game Board object."""
        board = self.game.getInitBoard()
        
        # Clear board
        for x in range(7):
            for y in range(7):
                board.pieces[x][y] = 0
        
        # Place pieces
        for pos in board_state.get('white_pieces', []):
            if pos in FEATURE_TO_COORD:
                x, y = FEATURE_TO_COORD[pos]
                board.pieces[x][y] = 1
        
        for pos in board_state.get('black_pieces', []):
            if pos in FEATURE_TO_COORD:
                x, y = FEATURE_TO_COORD[pos]
                board.pieces[x][y] = -1
        
        # Set game state
        board.period = board_state.get('phase', 0)
        white_on_board = len(board_state.get('white_pieces', []))
        black_on_board = len(board_state.get('black_pieces', []))
        board.put_pieces = white_on_board + black_on_board
        
        return board
    
    def _print_generation_statistics(self, total_examples: int):
        """Print comprehensive generation statistics."""
        print("\n" + "="*80)
        print("                    TRAINING DATA GENERATION STATISTICS")
        print("="*80)
        
        # Summary statistics
        print(f"\n📊 Generation Summary:")
        print(f"  Base positions generated: {self.stats['positions_generated']:,}")
        print(f"  Positions evaluated: {self.stats['positions_evaluated']:,}")
        print(f"  Positions failed: {self.stats['positions_failed']:,}")
        print(f"  Symmetries generated: {self.stats['symmetries_generated']:,}")
        print(f"  Total training examples: {total_examples:,}")
        
        # WDL distribution
        wdl = self.stats['wdl_distribution']
        wdl_total = sum(wdl.values())
        if wdl_total > 0:
            print(f"\n🎯 WDL Distribution:")
            print(f"  Wins: {wdl['wins']:,} ({wdl['wins']/wdl_total*100:.1f}%)")
            print(f"  Draws: {wdl['draws']:,} ({wdl['draws']/wdl_total*100:.1f}%)")
            print(f"  Losses: {wdl['losses']:,} ({wdl['losses']/wdl_total*100:.1f}%)")
        
        # Phase distribution
        if self.stats['phase_distribution']:
            print(f"\n🎮 Phase Distribution:")
            total_phases = sum(self.stats['phase_distribution'].values())
            for phase, count in self.stats['phase_distribution'].items():
                percentage = count / total_phases * 100
                print(f"  {phase}: {count:,} ({percentage:.1f}%)")
        
        # Error types
        if self.stats['error_types']:
            print(f"\n⚠️  Error Types:")
            for error_type, count in self.stats['error_types'].items():
                print(f"  {error_type}: {count:,}")
        
        print("="*80)


def main():
    """Main function for command-line usage."""
    parser = argparse.ArgumentParser(
        description='Generate NNUE training data using Perfect Database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate basic training data
  python generate_training_data.py --perfect-db /path/to/db --output training_data.txt --positions 50000
  
  # Generate with symmetry augmentation (16x more data)
  python generate_training_data.py --perfect-db /path/to/db --output training_data.txt --positions 10000 --symmetries
  
  # Generate with custom batch size
  python generate_training_data.py --perfect-db /path/to/db --output training_data.txt --positions 50000 --batch-size 2000
        """
    )
    
    parser.add_argument('--perfect-db', 
                       default='E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted',
                       help='Path to Perfect Database directory (default: E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted)')
    parser.add_argument('--output', default='mill_training_data.txt',
                       help='Output training data file (default: mill_training_data.txt)')
    parser.add_argument('--positions', type=int, default=50000,
                       help='Number of base positions to generate (default: 50000)')
    parser.add_argument('--symmetries', action='store_true',
                       help='Include all 16 symmetry transformations (16x more data)')
    parser.add_argument('--batch-size', type=int, default=1000,
                       help='Batch size for processing (default: 1000)')
    parser.add_argument('--validate', action='store_true',
                       help='Validate Perfect Database installation before generation')
    parser.add_argument('--seed', type=int, default=42,
                       help='Random seed for reproducible generation (default: 42)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Set random seed for reproducibility
    random.seed(args.seed)
    np.random.seed(args.seed)
    
    # Validate Perfect Database if requested
    if args.validate:
        logger.info("Validating Perfect Database installation...")
        if not os.path.exists(args.perfect_db):
            logger.error(f"Perfect Database path not found: {args.perfect_db}")
            return 1
        
        # Check for .sec2 files
        sec2_files = list(Path(args.perfect_db).glob("*.sec2"))
        if not sec2_files:
            logger.error(f"No .sec2 files found in: {args.perfect_db}")
            return 1
        
        logger.info(f"Validation successful: found {len(sec2_files)} .sec2 files")
    
    # Generate training data
    logger.info("Starting training data generation...")
    logger.info(f"Perfect Database: {args.perfect_db}")
    logger.info(f"Output file: {args.output}")
    logger.info(f"Base positions: {args.positions:,}")
    logger.info(f"Symmetries: {'enabled' if args.symmetries else 'disabled'}")
    logger.info(f"Expected total examples: {args.positions * (16 if args.symmetries else 1):,}")
    
    generator = PerfectDBTrainingDataGenerator(args.perfect_db)
    
    start_time = time.time()
    success = generator.generate_training_data(
        num_positions=args.positions,
        output_file=args.output,
        use_symmetries=args.symmetries,
        batch_size=args.batch_size
    )
    
    if success:
        elapsed_time = time.time() - start_time
        logger.info(f"Training data generation completed in {elapsed_time:.2f} seconds")
        
        # Validate output file
        if os.path.exists(args.output):
            file_size = os.path.getsize(args.output) / (1024 * 1024)  # MB
            logger.info(f"Output file size: {file_size:.1f} MB")
            
            # Count lines
            with open(args.output, 'r') as f:
                line_count = sum(1 for line in f if not line.startswith('#'))
            logger.info(f"Total training examples: {line_count:,}")
        
        return 0
    else:
        logger.error("Training data generation failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())
