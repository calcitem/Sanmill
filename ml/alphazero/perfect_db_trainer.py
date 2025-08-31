#!/usr/bin/env python3
"""
Perfect Database Direct Training for Alpha Zero

This module implements training directly from Perfect Database without MCTS simulation.
Key insights:
1. Perfect Database contains optimal play, no need for MCTS simulation
2. Direct enumeration vs intelligent sampling strategy
3. Focus on trap positions and critical game states
4. Two approaches: complete enumeration (if feasible) or strategic sampling
"""

import os
import sys
import time
import logging
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import List, Dict, Tuple, Optional, Iterator, Set
from collections import defaultdict, deque
from dataclasses import dataclass
import numpy as np
import torch
from pathlib import Path
import pickle

# Add local imports with robust path handling
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
game_dir = os.path.join(ml_dir, 'game')
perfect_dir = os.path.join(ml_dir, 'perfect')

# Add paths
for path in [game_dir, perfect_dir, current_dir]:
    if path not in sys.path:
        sys.path.insert(0, path)

# Import game modules
try:
    from game.Game import Game
    from game.GameLogic import Board
except ImportError:
    # Direct import fallback
    try:
        from Game import Game
        from GameLogic import Board
    except ImportError:
        print(f"Error: Cannot import Game modules. Checked paths:")
        print(f"  game_dir: {game_dir}")
        print(f"  perfect_dir: {perfect_dir}")
        print(f"  Files in game_dir: {os.listdir(game_dir) if os.path.exists(game_dir) else 'Directory not found'}")
        raise

# Import Perfect Database reader
try:
    from perfect_db_reader import PerfectDB
except ImportError:
    # Fallback import path
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from perfect.perfect_db_reader import PerfectDB
from neural_network import AlphaZeroNetworkWrapper
from progress_display import TrainingProgressDisplay, CompactProgressDisplay

logger = logging.getLogger(__name__)


@dataclass
class PerfectDBStats:
    """Statistics about Perfect Database contents."""
    total_sectors: int = 0
    total_positions: int = 0
    total_size_mb: int = 0
    sectors_by_phase: Dict[str, int] = None
    positions_by_wdl: Dict[str, int] = None
    trap_positions_found: int = 0

    def __post_init__(self):
        if self.sectors_by_phase is None:
            self.sectors_by_phase = defaultdict(int)
        if self.positions_by_wdl is None:
            self.positions_by_wdl = defaultdict(int)


@dataclass
class TrainingPosition:
    """Single training position from Perfect Database."""
    board_state: Dict
    evaluation: float  # WDL score
    best_move: str
    side_to_move: int
    game_phase: str
    is_trap: bool = False
    difficulty: float = 0.0  # How hard this position is to evaluate correctly

    # Extended sector information from sec2 files
    white_pieces_on_board: int = 0    # Number of white pieces on the board
    black_pieces_on_board: int = 0    # Number of black pieces on the board
    white_pieces_in_hand: int = 0     # Number of white pieces remaining in hand
    black_pieces_in_hand: int = 0     # Number of black pieces remaining in hand
    total_moves_played: int = 0       # Total number of moves played
    sector_filename: str = ""         # Source sector filename
    steps_to_result: int = -1         # Steps returned by Perfect DB (-1 for unknown)
    is_removal_phase: bool = False    # Is it the removal phase (period == 3)


class PerfectDBAnalyzer:
    """
    Analyzer for Perfect Database to understand scale and feasibility.

    Determines whether complete enumeration is possible or if we need sampling.
    """

    def __init__(self, perfect_db_path: str):
        """
        Initialize Perfect Database analyzer.

        Args:
            perfect_db_path: Path to Perfect Database directory
        """
        self.perfect_db_path = perfect_db_path
        self.stats = PerfectDBStats()

        # Game engine for position generation
        self.game = Game()

        # Perfect Database interface
        self.perfect_db = PerfectDB()

        logger.info(f"PerfectDBAnalyzer initialized: {perfect_db_path}")

    def analyze_database_scale(self) -> PerfectDBStats:
        """
        Analyze the scale of the Perfect Database.

        Returns:
            Statistics about database size and feasibility
        """
        logger.info("Analyzing Perfect Database scale...")

        # Find all sec2 files
        sec2_files = list(Path(self.perfect_db_path).glob("*.sec2"))
        self.stats.total_sectors = len(sec2_files)

        if not sec2_files:
            logger.error(f"No .sec2 files found in {self.perfect_db_path}")
            return self.stats

        # Analyze file sizes
        total_size = 0
        for sec2_file in sec2_files:
            file_size = sec2_file.stat().st_size
            total_size += file_size

            # Parse sector info from filename
            filename = sec2_file.name
            if filename.startswith('std_') and filename.endswith('.sec2'):
                # Extract W_B_WF_BF from std_W_B_WF_BF.sec2
                parts = filename[4:-5].split('_')
                if len(parts) == 4:
                    try:
                        W, B, WF, BF = map(int, parts)

                        # Classify game phase
                        if WF > 0 or BF > 0:
                            phase = 'placement'
                        elif W <= 3 or B <= 3:
                            phase = 'flying'
                        else:
                            phase = 'moving'

                        self.stats.sectors_by_phase[phase] += 1

                    except ValueError:
                        continue

        self.stats.total_size_mb = total_size // (1024 * 1024)

        # Estimate total positions
        # This is a rough estimate - actual count would require parsing each file
        avg_position_size = 32  # bytes (rough estimate)
        self.stats.total_positions = total_size // avg_position_size

        logger.info(f"Database analysis complete:")
        logger.info(f"  Total sectors: {self.stats.total_sectors}")
        logger.info(f"  Total size: {self.stats.total_size_mb} MB")
        logger.info(f"  Estimated positions: {self.stats.total_positions:,}")
        logger.info(f"  Phase distribution: {dict(self.stats.sectors_by_phase)}")

        # Determine feasibility
        feasible_for_complete_enumeration = self._is_complete_enumeration_feasible()

        if feasible_for_complete_enumeration:
            logger.info("✅ Complete enumeration appears FEASIBLE")
        else:
            logger.info("⚠️  Complete enumeration may be INFEASIBLE - recommend sampling approach")

        return self.stats

    def _is_complete_enumeration_feasible(self) -> bool:
        """
        Determine if complete enumeration is feasible.

        Criteria:
        - Total positions < 100M (manageable for training)
        - Total size < 50GB (reasonable storage/memory)
        - Processing time < 24 hours (reasonable for one-time setup)
        """
        # Conservative thresholds
        MAX_POSITIONS = 100_000_000  # 100M positions
        MAX_SIZE_MB = 50_000         # 50GB

        if self.stats.total_positions > MAX_POSITIONS:
            logger.warning(f"Too many positions: {self.stats.total_positions:,} > {MAX_POSITIONS:,}")
            return False

        if self.stats.total_size_mb > MAX_SIZE_MB:
            logger.warning(f"Database too large: {self.stats.total_size_mb} MB > {MAX_SIZE_MB} MB")
            return False

        # Estimate processing time (very rough)
        positions_per_second = 1000  # Conservative estimate
        estimated_hours = self.stats.total_positions / positions_per_second / 3600

        if estimated_hours > 24:
            logger.warning(f"Processing time too long: {estimated_hours:.1f} hours > 24 hours")
            return False

        return True


class TrapPositionDetector:
    """
    Detector for trap positions in Perfect Database.

    Based on Sanmill's existing trap awareness logic from search_engine.cpp.
    A trap position is where some moves lead to worse outcomes than others,
    creating opportunities for mistakes.
    """

    def __init__(self, perfect_db: PerfectDB):
        """
        Initialize trap position detector.

        Args:
            perfect_db: Perfect Database interface
        """
        self.perfect_db = perfect_db
        self.game = Game()

    def is_trap_position(self, board: Board, side_to_move: int) -> Tuple[bool, float]:
        """
        Determine if a position is a trap using Sanmill's trap awareness logic.

        Based on the algorithm from search_engine.cpp lines 938-1036:
        1. Evaluate all legal moves
        2. Categorize outcomes (win/draw/loss)
        3. Find trap moves (worse choices when better alternatives exist)

        Args:
            board: Board position
            side_to_move: Current player

        Returns:
            Tuple of (is_trap, difficulty_score)
        """
        try:
            # Get all valid moves
            valid_moves = self.game.getValidMoves(board, side_to_move)
            valid_actions = [i for i, valid in enumerate(valid_moves) if valid]

            if len(valid_actions) <= 1:
                return False, 0.0  # No choice, can't be a trap

            # Evaluate each possible move using Perfect Database
            move_evaluations = []

            for action in valid_actions:
                # Make the move
                next_board, next_player = self.game.getNextState(board, side_to_move, action)

                # Get Perfect Database evaluation
                try:
                    wdl, steps = self.perfect_db.evaluate(next_board, next_player, only_take=False)
                    # Convert to evaluation from current player's perspective
                    # Note: wdl is from next_player's perspective, so negate for current player
                    evaluation = -wdl
                    move_evaluations.append((action, evaluation, steps))
                except Exception:
                    continue

            if len(move_evaluations) < 2:
                return False, 0.0

            # === Sanmill's trap awareness algorithm ===
            # First pass: categorize outcomes (following search_engine.cpp logic)
            has_win = False
            has_draw = False
            has_loss = False

            for action, eval_score, steps in move_evaluations:
                if eval_score == 1:  # VALUE_MATE equivalent (win)
                    has_win = True
                elif eval_score == -1:  # -VALUE_MATE equivalent (loss)
                    has_loss = True
                else:  # Draw or other intermediate values
                    has_draw = True

            # Don't report traps if all moves have same outcome
            all_draw = not has_win and has_draw and not has_loss
            all_loss = not has_win and has_loss and not has_draw

            if all_draw or all_loss:
                return False, 0.0

            # Second pass: find trap moves (following search_engine.cpp logic)
            trap_moves = []
            total_difficulty = 0.0

            for action, eval_score, steps in move_evaluations:
                # Check if this move is worse than alternatives
                is_worse_choice = False
                move_difficulty = 0.0

                if eval_score == -1 and (has_win or has_draw):
                    # Loss when there are win/draw alternatives - worst trap
                    is_worse_choice = True
                    move_difficulty = 2.0 if has_win else 1.5
                elif eval_score != 1 and eval_score != -1 and has_win:
                    # Draw when there are win alternatives - moderate trap
                    is_worse_choice = True
                    move_difficulty = 1.0

                if is_worse_choice:
                    trap_moves.append((action, move_difficulty))
                    total_difficulty += move_difficulty

            # Determine if this is a trap position
            is_trap = len(trap_moves) > 0

            if is_trap:
                # Calculate overall difficulty score
                # Factor in both number of trap moves and their individual difficulty
                num_trap_ratio = len(trap_moves) / len(move_evaluations)
                avg_difficulty = total_difficulty / len(trap_moves)

                # Combine factors: more trap moves = more dangerous
                difficulty = avg_difficulty * (1.0 + num_trap_ratio)

                # Additional penalty for positions where most moves are traps
                if num_trap_ratio > 0.5:
                    difficulty *= 1.5

                return True, difficulty

            return False, 0.0

        except Exception as e:
            logger.debug(f"Error detecting trap position: {e}")
            return False, 0.0

    def get_trap_moves(self, board: Board, side_to_move: int) -> List[Tuple[int, float]]:
        """
        Get list of trap moves and their difficulty scores.

        Args:
            board: Board position
            side_to_move: Current player

        Returns:
            List of (action, difficulty) tuples for trap moves
        """
        try:
            # Get all valid moves
            valid_moves = self.game.getValidMoves(board, side_to_move)
            valid_actions = [i for i, valid in enumerate(valid_moves) if valid]

            if len(valid_actions) <= 1:
                return []

            # Evaluate each possible move
            move_evaluations = []

            for action in valid_actions:
                next_board, next_player = self.game.getNextState(board, side_to_move, action)

                try:
                    wdl, steps = self.perfect_db.evaluate(next_board, next_player, only_take=False)
                    evaluation = -wdl
                    move_evaluations.append((action, evaluation, steps))
                except Exception:
                    continue

            if len(move_evaluations) < 2:
                return []

            # Categorize outcomes
            has_win = any(eval_score == 1 for _, eval_score, _ in move_evaluations)
            has_draw = any(eval_score == 0 for _, eval_score, _ in move_evaluations)
            has_loss = any(eval_score == -1 for _, eval_score, _ in move_evaluations)

            # Find trap moves
            trap_moves = []

            for action, eval_score, steps in move_evaluations:
                move_difficulty = 0.0

                if eval_score == -1 and (has_win or has_draw):
                    move_difficulty = 2.0 if has_win else 1.5
                elif eval_score != 1 and eval_score != -1 and has_win:
                    move_difficulty = 1.0

                if move_difficulty > 0:
                    trap_moves.append((action, move_difficulty))

            return trap_moves

        except Exception as e:
            logger.debug(f"Error getting trap moves: {e}")
            return []


class PerfectDBDirectTrainer:
    """
    Direct trainer using Perfect Database without MCTS simulation.

    Two modes:
    1. Complete enumeration (if feasible)
    2. Strategic sampling (focusing on trap positions and critical states)
    """

    def __init__(self,
                 perfect_db_path: str,
                 neural_network: AlphaZeroNetworkWrapper,
                 use_complete_enumeration: bool = None):
        """
        Initialize Perfect Database direct trainer.

        Args:
            perfect_db_path: Path to Perfect Database
            neural_network: Neural network to train
            use_complete_enumeration: Force enumeration mode (None = auto-detect)
        """
        self.perfect_db_path = perfect_db_path
        self.neural_network = neural_network

        # Initialize components
        self.game = Game()
        self.perfect_db = PerfectDB()
        self.perfect_db.init(perfect_db_path)

        self.analyzer = PerfectDBAnalyzer(perfect_db_path)
        self.trap_detector = TrapPositionDetector(self.perfect_db)
        # Optional prefetch: Control whether to prefetch sector files into memory via environment variables to reduce IO jitter
        self._prefetch_enabled = os.environ.get('AZ_PREFETCH_DB', '0') == '1'

        # Trap detection switch: Off by default (time-consuming), can be enabled via environment variable or parameter
        self._trap_detection_enabled = os.environ.get('AZ_ENABLE_TRAP_DETECTION', '0') == '1'

        # Analyze database scale
        self.stats = self.analyzer.analyze_database_scale()

        # Determine training mode
        if use_complete_enumeration is None:
            self.use_complete_enumeration = self.analyzer._is_complete_enumeration_feasible()
        else:
            self.use_complete_enumeration = use_complete_enumeration

        logger.info(f"Training mode: {'Complete Enumeration' if self.use_complete_enumeration else 'Strategic Sampling'}")
        logger.info(f"Trap detection: {'Enabled' if self._trap_detection_enabled else 'Disabled (default, for speed)'}")
        if not self._trap_detection_enabled:
            logger.info("💡 To enable trap detection, set the environment variable: AZ_ENABLE_TRAP_DETECTION=1")

        # Training data storage
        self.training_positions: List[TrainingPosition] = []
        self.trap_positions: List[TrainingPosition] = []

    def extract_all_positions(self,
                              max_positions: Optional[int] = None,
                              complete_sector_enumeration: bool = False) -> List[TrainingPosition]:
        """
        Extract all positions from Perfect Database (complete enumeration).

        Args:
            max_positions: Maximum positions to extract (None = all)
            complete_sector_enumeration: If True, sequentially read all positions within each sector
                                         If False, use sampling within sectors (current behavior)

        Returns:
            List of training positions
        """
        if not self.use_complete_enumeration:
            logger.warning("Complete enumeration not recommended for this database size")

        logger.info("Starting complete enumeration of Perfect Database...")
        start_time = time.time()

        # Get all sec2 files
        sector_files = list(Path(self.perfect_db_path).glob("*.sec2"))
        if not sector_files:
            logger.error("No .sec2 files found in Perfect Database")
            return []

        # Initialize progress display
        progress_display = TrainingProgressDisplay(show_file_details=True, update_interval=1.0)
        progress_display.start_display()
        progress_display.set_total_files(sector_files)
        progress_display.set_current_operation(
            'Sampling training positions by sector' if not complete_sector_enumeration else 'Sequential sector traversal (real DLL iteration)'
        )

        print(f"\n📊 Perfect Database Analysis:")
        print(f"    - Found {len(sector_files)} .sec2 files")
        print(f"    - Total size: {sum(f.stat().st_size for f in sector_files) / 1024 / 1024:.1f} MB")
        print(f"    - Target board states to extract: {max_positions or 'All'}")
        print(f"    - Each state includes: Optimal move + WDL evaluation")
        print(f"    - Starting processing...\n")

        positions = []
        total_processed = 0
        trap_count = 0

        try:
            # Process each sector
            for sector_file in sector_files:
                if max_positions and len(positions) >= max_positions:
                    break

                # Start processing file
                progress_display.start_file(sector_file.name)
                print(f"\n🔄 Processing: {sector_file.name}")
                print(f"📁 File size: {sector_file.stat().st_size / 1024 / 1024:.1f} MB")
                logger.info(f"Processing sector: {sector_file.name}")

                # Extract positions
                sector_positions = self._extract_positions_from_sector(
                    sector_file, progress_display, complete_enumeration=complete_sector_enumeration
                )

                total_in_sector = len(sector_positions)
                for idx, pos in enumerate(sector_positions, start=1):
                    if max_positions and len(positions) >= max_positions:
                        break

                    # Check if it's a trap position (optional, disabled by default for speed)
                    if self._trap_detection_enabled:
                        try:
                            board = self._create_board_from_state(pos.board_state)
                            # Annotate current high-level operation to help user understand where it's stuck
                            progress_display.set_current_operation('Trap Detection & Annotation')
                            progress_display.update_subtask_progress('Trap Detection', idx, total_in_sector)
                            is_trap, difficulty = self.trap_detector.is_trap_position(
                                board, pos.side_to_move
                            )
                            pos.is_trap = is_trap
                            pos.difficulty = difficulty

                            if is_trap:
                                trap_count += 1

                        except Exception as e:
                            logger.debug(f"Error checking trap position: {e}")
                    else:
                        # Default to no trap detection, set as non-trap
                        pos.is_trap = False
                        pos.difficulty = 0.0

                    positions.append(pos)
                    total_processed += 1

                # Finish file processing
                # Clear subtask display
                progress_display.clear_subtask()
                progress_display.complete_file(sector_file.name, success=True)
                print(f"✅ Completed: {sector_file.name} - Extracted {len(sector_positions)} board states")

                # Report progress periodically
                if total_processed % 5000 == 0 and total_processed > 0:
                    elapsed = time.time() - start_time
                    rate = total_processed / elapsed
                    logger.debug(f"Processed {total_processed:,} positions "
                                 f"({rate:.1f} pos/s, {trap_count} traps)")

        finally:
            progress_display.stop_display()

        elapsed_time = time.time() - start_time
        logger.info(f"Complete enumeration finished:")
        logger.info(f"  Total positions: {len(positions):,}")
        logger.info(f"  Trap positions: {trap_count:,} ({trap_count/len(positions)*100:.1f}%)")
        logger.info(f"  Processing time: {elapsed_time:.2f}s ({len(positions)/elapsed_time:.1f} pos/s)")

        return positions

    def sample_strategic_positions(self,
                                   num_positions: int,
                                   trap_ratio: float = 0.3,
                                   phase_weights: Dict[str, float] = None,
                                   enable_trap_detection: bool = None) -> List[TrainingPosition]:
        """
        Sample positions strategically focusing on traps and critical states.

        Args:
            num_positions: Number of positions to sample
            trap_ratio: Ratio of trap positions to include
            phase_weights: Weights for different game phases
            enable_trap_detection: Override trap detection setting (None = use instance setting)

        Returns:
            List of strategically sampled training positions
        """
        # Check for None parameter
        if num_positions is None:
            logger.error("CRITICAL: num_positions cannot be None")
            raise ValueError("num_positions parameter cannot be None")

        if phase_weights is None:
            phase_weights = {
                'placement': 0.4,
                'moving': 0.4,
                'flying': 0.2
            }

        # Override trap detection setting (if specified)
        original_trap_setting = self._trap_detection_enabled
        if enable_trap_detection is not None:
            self._trap_detection_enabled = enable_trap_detection

        try:
            logger.info(f"Strategic sampling of {num_positions:,} positions...")
            logger.info(f"  Target trap ratio: {trap_ratio:.1%}")
            logger.info(f"  Phase weights: {phase_weights}")
            logger.info(f"  Trap detection: {'Enabled' if self._trap_detection_enabled else 'Disabled (default)'}")

            start_time = time.time()

            # Get relevant sec2 files and initialize progress display
            relevant_files = self._get_relevant_sector_files(phase_weights)

            # Use compact progress display
            compact_display = CompactProgressDisplay()

            # Calculate target counts
            target_traps = int(num_positions * trap_ratio)
            target_regular = num_positions - target_traps

            positions = []
            trap_positions = []

            # Phase-based sampling
            phase_targets = {
                phase: int(num_positions * weight)
                for phase, weight in phase_weights.items()
            }

            processed_files = 0
            total_files = len(relevant_files)

            for phase, target_count in phase_targets.items():
                if target_count == 0:
                    continue

                logger.info(f"Sampling {target_count:,} positions from '{phase}' phase...")

                phase_positions = self._sample_positions_from_phase(
                    phase, target_count, seek_traps=True,
                    progress_callback=lambda: compact_display.update(
                        processed_files, total_files,
                        current_file=f"Phase: {phase}",
                        extra_info=f"Traps: {len(trap_positions)}"
                    )
                )

                # Separate traps from regular positions
                phase_traps = [p for p in phase_positions if p.is_trap]
                phase_regular = [p for p in phase_positions if not p.is_trap]

                trap_positions.extend(phase_traps)
                positions.extend(phase_regular)

                processed_files += len([f for f in relevant_files if self._get_phase_from_filename(f.name) == phase])

            # Balance trap/regular ratio
            compact_display.update(processed_files, total_files,
                                   current_file="Balancing samples",
                                   extra_info=f"Traps: {len(trap_positions)}")

            if len(trap_positions) > target_traps:
                # Too many traps - select best ones
                trap_positions.sort(key=lambda p: p.difficulty, reverse=True)
                trap_positions = trap_positions[:target_traps]
            elif len(trap_positions) < target_traps:
                # Too few traps - add more regular positions
                deficit = target_traps - len(trap_positions)
                target_regular += deficit

            # Select regular positions
            if len(positions) > target_regular:
                # Random sampling of regular positions
                np.random.shuffle(positions)
                positions = positions[:target_regular]

            # Combine and shuffle
            all_positions = trap_positions + positions
            np.random.shuffle(all_positions)

            compact_display.finish(f"Sampled {len(all_positions):,} positions")

            elapsed_time = time.time() - start_time
            actual_trap_ratio = len(trap_positions) / len(all_positions) if all_positions else 0

            logger.info(f"Strategic sampling completed:")
            logger.info(f"  Total positions: {len(all_positions):,}")
            logger.info(f"  Trap positions: {len(trap_positions):,} ({actual_trap_ratio:.1%})")
            logger.info(f"  Regular positions: {len(positions):,}")
            logger.info(f"  Sampling time: {elapsed_time:.2f}s")

            return all_positions[:num_positions]

        finally:
            # Restore original trap detection setting
            self._trap_detection_enabled = original_trap_setting

    def _extract_positions_from_sector(self,
                                       sector_file: Path,
                                       progress_display: Optional[TrainingProgressDisplay] = None,
                                       complete_enumeration: bool = False) -> List[TrainingPosition]:
        """
        Extract positions from a specific sector file.

        Args:
            sector_file: Path to the .sec2 file
            progress_display: Optional progress display
            complete_enumeration: If True, read all positions sequentially from file
                                  If False, use sampling approach (current behavior)
        """
        if complete_enumeration:
            return self._extract_all_positions_from_sector_file(sector_file, progress_display)
        else:
            return self._extract_sample_positions_from_sector(sector_file, progress_display)

    def _extract_sample_positions_from_sector(self,
                                              sector_file: Path,
                                              progress_display: Optional[TrainingProgressDisplay] = None) -> List[TrainingPosition]:
        """Extract sample positions from a sector file (current simplified implementation)."""
        positions = []

        # Parse sector info from filename
        filename = sector_file.name
        if not (filename.startswith('std_') and filename.endswith('.sec2')):
            if progress_display:
                progress_display.complete_file(filename, success=False)
            return positions

        try:
            # Extract W_B_WF_BF from std_W_B_WF_BF.sec2
            parts = filename[4:-5].split('_')
            if len(parts) != 4:
                if progress_display:
                    progress_display.complete_file(filename, success=False)
                return positions

            W, B, WF, BF = map(int, parts)

            # Determine game phase
            if WF > 0 or BF > 0:
                phase = 'placement'
            elif W <= 3 or B <= 3:
                phase = 'flying'
            else:
                phase = 'moving'

            # Get file size for progress tracking
            file_size = sector_file.stat().st_size

            # Generate sample positions for this sector
            # This is simplified - actual implementation would read from file
            num_samples = min(1000, file_size // 32)

            processed_bytes = 0
            bytes_per_sample = file_size // num_samples if num_samples > 0 else 0

            for i in range(num_samples):
                try:
                    board = self._generate_random_position_for_sector(W, B, WF, BF)
                    if board is None:
                        continue

                    side_to_move = np.random.choice([1, -1])

                    # Get Perfect Database evaluation
                    # Removal phase (period=3) requires passing only_take=True;
                    # After forming a mill in the Placing phase, it enters period=3, synchronize this
                    only_take = (board.period == 3)
                    wdl, steps = self.perfect_db.evaluate(board, side_to_move, only_take=only_take)
                    best_moves = self.perfect_db.good_moves_tokens(board, side_to_move, only_take=only_take)
                    best_move = best_moves[0] if best_moves else "none"

                    # Prepare extended info (complete fields parsed from sec2 file)
                    additional_info = {
                        'white_pieces_on_board': W,       # Number of white pieces on board
                        'black_pieces_on_board': B,       # Number of black pieces on board
                        'white_pieces_in_hand': WF,       # Number of white pieces in hand
                        'black_pieces_in_hand': BF,       # Number of black pieces in hand
                        'total_moves_played': W + B,      # Total moves played
                        'sector_filename': filename,      # Source sector filename
                    }

                    # Create training position (including complete sec2 field info)
                    position = TrainingPosition(
                        board_state=self._board_to_state(board, additional_info),
                        evaluation=float(wdl),
                        best_move=best_move,
                        side_to_move=side_to_move,
                        game_phase=phase,
                        # Set extended fields
                        white_pieces_on_board=W,
                        black_pieces_on_board=B,
                        white_pieces_in_hand=WF,
                        black_pieces_in_hand=BF,
                        total_moves_played=W + B,
                        sector_filename=filename,
                        steps_to_result=int(steps),
                        is_removal_phase=only_take
                    )

                    positions.append(position)

                    # Update progress
                    if progress_display:
                        processed_bytes = min(processed_bytes + bytes_per_sample, file_size)
                        progress_display.update_file_progress(filename, processed_bytes)

                    # Display progress every 1000 states
                    if len(positions) % 1000 == 0 and len(positions) > 0:
                        progress_pct = (processed_bytes / file_size * 100) if file_size > 0 else 0
                        print(f"    📍 Extracted {len(positions)} board states ({progress_pct:.1f}%)", end='\r')

                except Exception as e:
                    logger.debug(f"Error processing position in {filename}: {e}")
                    continue

            # Ensure file is displayed as fully processed
            if progress_display:
                progress_display.update_file_progress(filename, file_size)

        except Exception as e:
            logger.error(f"❌ Failed to process sector: {filename}")
            logger.error(f"❌ Error details: {e}")
            if progress_display:
                progress_display.complete_file(filename, success=False)
            raise

        return positions

    def _extract_all_positions_from_sector_file(self,
                                                sector_file: Path,
                                                progress_display: Optional[TrainingProgressDisplay] = None) -> List[TrainingPosition]:
        """
        Extract ALL positions from a sector file by sequentially reading the actual .sec2 format.

        Args:
            sector_file: Path to the .sec2 file
            progress_display: Optional progress display

        Returns:
            List of all training positions in the sector file

        Note:
            This method would need to implement the actual .sec2 file format parsing.
            For now, it's a placeholder that explains the required implementation.
        """
        positions = []
        filename = sector_file.name

        # Parse sector info from filename
        if not (filename.startswith('std_') and filename.endswith('.sec2')):
            logger.warning(f"Invalid sector file format: {filename}")
            if progress_display:
                progress_display.complete_file(filename, success=False)
            return positions

        try:
            # Extract W_B_WF_BF from std_W_B_WF_BF.sec2
            parts = filename[4:-5].split('_')
            if len(parts) != 4:
                logger.warning(f"Cannot parse sector parameters from filename: {filename}")
                if progress_display:
                    progress_display.complete_file(filename, success=False)
                return positions

            W, B, WF, BF = map(int, parts)

            # Determine game phase
            if WF > 0 or BF > 0:
                phase = 'placement'
            elif W <= 3 or B <= 3:
                phase = 'flying'
            else:
                phase = 'moving'

            logger.info(f"🔄 Starting full traversal of sector: {filename}")
            logger.info(f"    - Game phase: {phase}")
            logger.info(f"    - Parameters: W={W}, B={B}, WF={WF}, BF={BF}")
            logger.info(f"    - File size: {sector_file.stat().st_size / 1024 / 1024:.1f} MB")

            # Get file size for progress tracking
            file_size = sector_file.stat().st_size
            processed_bytes = 0

            # Attempting to parse using the real .sec2 file iterator
            logger.info("🔧 Attempting real .sec2 parsing using DLL iteration API...")

            try:
                # Optional prefetch: Cache file pages in memory to reduce subsequent IO jitter
                if self._prefetch_enabled:
                    try:
                        import mmap as _mmap
                        with open(sector_file, 'rb') as _f:
                            mm = _mmap.mmap(_f.fileno(), 0, access=_mmap.ACCESS_READ)
                            # Trigger prefetch for the first few MB (or the entire small file)
                            _ = mm[:min(file_size, 16 * 1024 * 1024)]
                            mm.close()
                        if progress_display:
                            progress_display.set_current_operation('Prefetching file to memory to accelerate DLL iteration')
                    except Exception:
                        pass
                # Use the new perfect_db iteration API
                sector_handle = self.perfect_db.open_sector(W, B, WF, BF)
                if sector_handle == 0:
                    error_msg = f"❌ Cannot open sector {filename}"
                    logger.error(error_msg)
                    raise RuntimeError(error_msg)

                total_positions = self.perfect_db.sector_count(sector_handle)
                logger.info(f"📊 Total positions in sector: {total_positions:,}")
                logger.info("🚀 Starting real DLL sequential iteration...")

                processed_count = 0
                skipped_count = 0  # Skipped position count

                # Add stack overflow protection mechanism (threshold adjustable via environment variable)
                consecutive_failures = 0
                max_consecutive_failures = int(os.environ.get('AZ_SECTOR_MAX_FAIL', '5'))  # Consecutive failure threshold
                if max_consecutive_failures < 1:
                    max_consecutive_failures = 1

                while True:
                    try:
                        # Get next position from DLL
                        result = self.perfect_db.sector_next(sector_handle)
                        if result is None:
                            break  # End of iteration

                        # Reset failure counter (position successfully retrieved)
                        consecutive_failures = 0

                        white_bits, black_bits, wdl, steps = result

                        # Convert bitboards to Board object
                        board = self.perfect_db.bitboards_to_board(white_bits, black_bits, WF, BF)
                        if board is None:
                            skipped_count += 1
                            continue

                        # Determine side to move (inferred from piece count)
                        total_pieces = bin(white_bits).count('1') + bin(black_bits).count('1')
                        side_to_move = 1 if (total_pieces % 2 == 0) else -1

                        # Get best move (with enhanced error handling, allowing some positions to have no best move)
                        only_take = (board.period == 3)
                        try:
                            best_moves = self.perfect_db.good_moves_tokens(board, side_to_move, only_take=only_take)
                            best_move = best_moves[0] if best_moves else "none"
                        except Exception as e:
                            # If getting best move fails, use "none" but continue processing
                            # This can be normal (game over, no legal moves, etc.)
                            logger.debug(f"Failed to get best move for position: {e}")
                            best_move = "none"

                        # Prepare extended info (fields from real DLL parsing)
                        additional_info = {
                            'white_pieces_on_board': W,       # Number of white pieces on board
                            'black_pieces_on_board': B,       # Number of black pieces on board
                            'white_pieces_in_hand': WF,       # Number of white pieces in hand
                            'black_pieces_in_hand': BF,       # Number of black pieces in hand
                            'total_moves_played': W + B,      # Total moves played
                            'sector_filename': filename,      # Source sector filename
                        }

                        # Create training position (from real .sec2 parsing)
                        position = TrainingPosition(
                            board_state=self._board_to_state(board, additional_info),
                            evaluation=float(wdl),
                            best_move=best_move,
                            side_to_move=side_to_move,
                            game_phase=phase,
                            # Set extended fields
                            white_pieces_on_board=W,
                            black_pieces_on_board=B,
                            white_pieces_in_hand=WF,
                            black_pieces_in_hand=BF,
                            total_moves_played=W + B,
                            sector_filename=filename,
                            steps_to_result=int(steps),
                            is_removal_phase=only_take
                        )

                        positions.append(position)
                        processed_count += 1

                        # Update progress (convert position ratio to bytes to avoid the illusion of being stuck at 100%)
                        if progress_display and total_positions > 0:
                            processed_bytes = int(min(file_size, (processed_count / total_positions) * file_size))
                            progress_display.update_file_progress(filename, processed_bytes)

                        # Display progress periodically
                        if processed_count % 1000 == 0:
                            progress_pct = (processed_count / total_positions * 100) if total_positions > 0 else 0
                            error_rate = (skipped_count / (processed_count + skipped_count) * 100) if (processed_count + skipped_count) > 0 else 0
                            print(f"    📍 Truly read {processed_count:,} positions ({progress_pct:.1f}%, Error rate: {error_rate:.1f}%)", end='\r')

                            # Update operation description in progress display
                            if progress_display:
                                if error_rate > 5:  # Warn when error rate exceeds 5%
                                    progress_display.set_current_operation(f'Real DLL Iteration (Error rate: {error_rate:.1f}%)')
                                else:
                                    progress_display.set_current_operation('Real DLL Iteration')
                                progress_display.update_subtask_progress('Position Extraction', processed_count, total_positions)

                    except RuntimeError as e:
                        if "stack overflow" in str(e).lower():
                            consecutive_failures += 1
                            logger.warning(f"🔥 Stack overflow detected: {consecutive_failures} consecutive failures at position {processed_count + skipped_count + 1}")

                            if consecutive_failures >= max_consecutive_failures:
                                logger.error(f"❌ {max_consecutive_failures} consecutive stack overflows, this sector has a serious recursion problem")
                                logger.error(f"💡 Suggestion: Skip this sector {filename} or update the Perfect Database DLL")
                                break  # Break the loop, abandoning this sector but not terminating the entire training

                            # Retry after a short delay (adjustable via environment variable)
                            import time
                            delay_ms = int(os.environ.get('AZ_SECTOR_RETRY_MS', '50'))
                            time.sleep(max(0, delay_ms) / 1000.0)
                            skipped_count += 1
                            continue
                        else:
                            # Other RuntimeErrors are still raised
                            logger.error(f"❌ Error during DLL iteration: {e}")
                            logger.error(f"❌ Error at position: {processed_count + skipped_count + 1}")
                            raise
                    except Exception as e:
                        consecutive_failures += 1
                        logger.warning(f"⚠️ DLL iteration exception: {e} ({consecutive_failures} consecutive failures)")

                        if consecutive_failures >= max_consecutive_failures:
                            logger.error(f"❌ {max_consecutive_failures} consecutive exceptions, abandoning this sector")
                            break

                        skipped_count += 1
                        continue

                # Clean up resources
                self.perfect_db.close_sector(sector_handle)

                logger.info(f"✅ Real DLL iteration completed: {filename}")
                logger.info(f"    - Total positions: {total_positions:,}")
                logger.info(f"    - Successfully extracted: {len(positions):,}")
                logger.info(f"    - Skipped positions: {skipped_count:,} (invalid/error positions)")
                logger.info(f"    - Processing mode: Real .sec2 sequential iteration")
                if skipped_count > 0:
                    success_rate = (processed_count / (processed_count + skipped_count)) * 100 if (processed_count + skipped_count) > 0 else 0
                    logger.info(f"    - Success rate: {success_rate:.1f}%")

            except Exception as e:
                logger.error(f"❌ DLL iteration failed: {e}")
                error_msg = str(e).lower()

                # Provide diagnostic information for common errors
                if "pd_best_move failed" in error_msg:
                    logger.error("❌ Perfect Database failed to get best move")
                    logger.error("💡 Possible reason: Incompatible position format or corrupted database")
                elif "return code 0" in error_msg:
                    logger.error("❌ DLL returned error code 0")
                    logger.error("💡 Possible reason: Position out of database range or incorrect parameters")
                elif "allocation" in error_msg:
                    logger.error("❌ Memory allocation failed")
                    logger.error("💡 Possible reason: Insufficient memory or system limits")

                logger.error("❌ Program terminated, please check the Perfect Database status")
                raise

            # Finish file processing
            if progress_display:
                progress_display.update_file_progress(filename, file_size)

            logger.info(f"✅ Completed sector traversal: {filename}")
            logger.info(f"    - Number of positions extracted: {len(positions):,}")
            logger.info(f"    - Processing mode: Sequential read (full traversal)")

        except Exception as e:
            logger.error(f"❌ Failed to fully enumerate sector: {filename}")
            logger.error(f"❌ Error details: {e}")
            if progress_display:
                progress_display.complete_file(filename, success=False)
            raise

        return positions

    def _sample_positions_from_phase(self, phase: str, count: int, seek_traps: bool = True, progress_callback=None) -> List[TrainingPosition]:
        """Sample positions from a specific game phase."""
        positions = []

        # Find relevant sector files for this phase
        sector_files = []
        for sector_file in Path(self.perfect_db_path).glob("*.sec2"):
            filename = sector_file.name
            if filename.startswith('std_') and filename.endswith('.sec2'):
                try:
                    parts = filename[4:-5].split('_')
                    if len(parts) == 4:
                        W, B, WF, BF = map(int, parts)

                        # Check if this sector matches the phase
                        if phase == 'placement' and (WF > 0 or BF > 0):
                            sector_files.append(sector_file)
                        elif phase == 'flying' and WF == 0 and BF == 0 and (W <= 3 or B <= 3):
                            sector_files.append(sector_file)
                        elif phase == 'moving' and WF == 0 and BF == 0 and W > 3 and B > 3:
                            sector_files.append(sector_file)

                except ValueError:
                    continue

        if not sector_files:
            logger.warning(f"No sector files found for phase '{phase}'")
            return positions

        # Sample from each sector
        positions_per_sector = max(1, count // len(sector_files))

        for i, sector_file in enumerate(sector_files):
            if len(positions) >= count:
                break

            # Call progress callback
            if progress_callback:
                progress_callback()

            sector_positions = self._extract_positions_from_sector(sector_file)

            # If seeking traps, check each position (only when trap detection is enabled)
            if seek_traps and self._trap_detection_enabled:
                for pos in sector_positions:
                    if len(positions) >= count:
                        break

                    try:
                        board = self._create_board_from_state(pos.board_state)
                        is_trap, difficulty = self.trap_detector.is_trap_position(
                            board, pos.side_to_move
                        )
                        pos.is_trap = is_trap
                        pos.difficulty = difficulty
                        # Synchronize removal phase flag (period==3)
                        pos.is_removal_phase = (board.period == 3)

                    except Exception:
                        pos.is_trap = False
                        pos.difficulty = 0.0

                    positions.append(pos)
            else:
                # Random sampling (no trap detection, sample directly)
                sample_size = min(positions_per_sector, len(sector_positions))
                if len(sector_positions) > 0:
                    if sample_size >= len(sector_positions):
                        sampled = sector_positions
                    else:
                        sampled = np.random.choice(sector_positions, size=sample_size, replace=False)

                    # Ensure position has a basic trap flag (default is non-trap)
                    for pos in sampled:
                        if not hasattr(pos, 'is_trap') or pos.is_trap is None:
                            pos.is_trap = False
                        if not hasattr(pos, 'difficulty') or pos.difficulty is None:
                            pos.difficulty = 0.0

                    positions.extend(sampled)

        return positions[:count]

    def _get_relevant_sector_files(self, phase_weights: Dict[str, float]) -> List[Path]:
        """Get a list of relevant sector files."""
        return list(Path(self.perfect_db_path).glob("std*.sec2"))

    def _get_phase_from_filename(self, filename: str) -> str:
        """Get game phase from filename."""
        if not filename.startswith('std_') or not filename.endswith('.sec2'):
            return 'unknown'

        try:
            parts = filename[4:-5].split('_')
            if len(parts) == 4:
                W, B, WF, BF = map(int, parts)
                if WF > 0 or BF > 0:
                    return 'placement'
                elif W <= 3 or B <= 3:
                    return 'flying'
                else:
                    return 'moving'
        except ValueError:
            pass

        return 'unknown'

    def _generate_random_position_for_sector(self, W: int, B: int, WF: int, BF: int) -> Optional[Board]:
        """Generate a random position matching sector parameters."""
        try:
            board = self.game.getInitBoard()

            # Set game phase
            if WF > 0 or BF > 0:
                board.period = 0  # Placement
            elif W <= 3 or B <= 3:
                board.period = 2  # Flying
            else:
                board.period = 1  # Moving

            # Get valid positions
            valid_positions = []
            for x in range(7):
                for y in range(7):
                    if board.allowed_places[x][y]:
                        valid_positions.append((x, y))

            if len(valid_positions) < W + B:
                return None

            # Clear board
            for x in range(7):
                for y in range(7):
                    board.pieces[x][y] = 0

            # Randomly place pieces
            selected_positions = np.random.choice(
                len(valid_positions),
                size=W + B,
                replace=False
            )

            # Place white pieces
            for i in range(W):
                pos_idx = selected_positions[i]
                x, y = valid_positions[pos_idx]
                board.pieces[x][y] = 1

            # Place black pieces
            for i in range(W, W + B):
                pos_idx = selected_positions[i]
                x, y = valid_positions[pos_idx]
                board.pieces[x][y] = -1

            # Set piece counts
            board.put_pieces = W + B

            return board

        except Exception:
            return None

    def _board_to_state(self, board: Board, additional_info: Dict = None) -> Dict:
        """
        Convert board to state dictionary with complete information.

        Args:
            board: Game board object
            additional_info: Additional sector/position information from sec2 file
        """
        state = {
            'pieces': [row[:] for row in board.pieces],
            'period': board.period,
            'put_pieces': board.put_pieces
        }

        # Add additional sector information if available
        if additional_info:
            state.update({
                'white_pieces_on_board': additional_info.get('white_pieces_on_board', 0),
                'black_pieces_on_board': additional_info.get('black_pieces_on_board', 0),
                'white_pieces_in_hand': additional_info.get('white_pieces_in_hand', 0),
                'black_pieces_in_hand': additional_info.get('black_pieces_in_hand', 0),
                'total_moves_played': additional_info.get('total_moves_played', 0),
                'sector_filename': additional_info.get('sector_filename', ''),
            })

        return state

    def _create_board_from_state(self, state: Dict) -> Board:
        """Create board from state dictionary."""
        board = self.game.getInitBoard()
        board.pieces = [row[:] for row in state['pieces']]
        board.period = state['period']
        board.put_pieces = state['put_pieces']
        return board

    def train_neural_network(self,
                             positions: List[TrainingPosition],
                             batch_size: int = 64,
                             epochs: int = 10,
                             learning_rate: float = 1e-3,
                             trap_weight: float = 2.0,
                             removal_weight: float = 1.5,
                             steps_alpha: float = 1.0) -> Dict[str, float]:
        """
        Train neural network on extracted positions.

        Args:
            positions: Training positions
            batch_size: Training batch size
            epochs: Number of epochs
            learning_rate: Learning rate
            trap_weight: Extra weight for trap positions

        Returns:
            Training statistics
        """
        if not positions:
            logger.warning("No training positions provided")
            return {'loss': 0.0}

        logger.info(f"Training neural network on {len(positions):,} positions...")

        # Prepare training data
        board_tensors = []
        policy_targets = []
        value_targets = []
        sample_weights = []

        for pos in positions:
            try:
                # Create board
                board = self._create_board_from_state(pos.board_state)

                # Encode board with enhanced state information
                board_tensor = self.neural_network.encoder.encode_board(board, pos.side_to_move, pos.board_state)
                board_tensors.append(board_tensor)

                # Create policy target (simplified - uniform over valid moves)
                valid_moves = self.game.getValidMoves(board, pos.side_to_move)
                policy_target = valid_moves / np.sum(valid_moves)
                policy_targets.append(policy_target)

                # Value target from Perfect Database
                value_targets.append(pos.evaluation)

                # Sample weight (trap/removing/steps-aware)
                weight = 1.0
                if getattr(pos, 'is_trap', False):
                    weight *= max(1.0, float(trap_weight))
                if getattr(pos, 'is_removal_phase', False):
                    weight *= max(1.0, float(removal_weight))
                steps_val = getattr(pos, 'steps_to_result', -1)
                if isinstance(steps_val, (int, float)) and steps_val >= 0:
                    # Shorter steps have higher weight: 1 + alpha/(1+steps), with an upper cap
                    weight *= (1.0 + float(steps_alpha) / (1.0 + float(steps_val)))
                # Prevent abnormal amplification/illegal values
                if not np.isfinite(weight) or weight <= 0:
                    weight = 1.0
                weight = float(min(weight, 10.0))
                sample_weights.append(weight)

            except Exception as e:
                logger.debug(f"Error preparing training example: {e}")
                continue

        if not board_tensors:
            logger.error("No valid training examples created")
            return {'loss': 0.0}

        # Convert to tensors
        board_tensors = torch.stack(board_tensors)
        policy_targets = torch.stack([torch.FloatTensor(p) for p in policy_targets])
        value_targets = torch.FloatTensor(value_targets)
        sample_weights = torch.FloatTensor(sample_weights)

        # Training loop
        self.neural_network.net.train()
        optimizer = torch.optim.Adam(self.neural_network.net.parameters(), lr=learning_rate)

        total_loss = 0.0
        total_policy_loss = 0.0
        total_value_loss = 0.0
        num_batches = 0

        # Use a weighted sampler to focus on key samples (removals/short steps/traps)
        try:
            from torch.utils.data import WeightedRandomSampler
            dataset = torch.utils.data.TensorDataset(board_tensors, policy_targets, value_targets)
            sampler = WeightedRandomSampler(weights=sample_weights,
                                              num_samples=len(sample_weights),
                                              replacement=True)
            dataloader = torch.utils.data.DataLoader(dataset,
                                                     batch_size=batch_size,
                                                     sampler=sampler,
                                                     shuffle=False)
        except Exception:
            # Degrade to a normal DataLoader (in extreme cases)
            dataset = torch.utils.data.TensorDataset(board_tensors, policy_targets, value_targets)
            dataloader = torch.utils.data.DataLoader(dataset,
                                                     batch_size=batch_size,
                                                     shuffle=True)

        # Calculate total number of batches for progress display (consistent with dataloader)
        total_batches_per_epoch = len(dataloader)

        print(f"\n🧠 Starting neural network training...")
        print(f"📊 Training parameters: {epochs} epochs, {len(positions)} states, batch size {batch_size}")
        print(f"🎯 Device: {self.neural_network.device}")
        print()

        # Create progress display
        from progress_display import CompactProgressDisplay

        for epoch in range(epochs):
            epoch_start_time = time.time()
            epoch_loss = 0.0
            batch_count = 0

            print(f"Epoch {epoch + 1}/{epochs}:")

            # Create progress display for each epoch
            progress_display = CompactProgressDisplay()

            # Mini-batch training
            for i in range(0, len(board_tensors), batch_size):
                end_idx = min(i + batch_size, len(board_tensors))

                batch_boards = board_tensors[i:end_idx].to(self.neural_network.device)
                batch_policies = policy_targets[i:end_idx].to(self.neural_network.device)
                batch_values = value_targets[i:end_idx].to(self.neural_network.device)
                batch_weights = sample_weights[i:end_idx].to(self.neural_network.device)

                # Forward pass
                pred_policies, pred_values = self.neural_network.net(batch_boards)

                # Calculate weighted losses
                policy_loss = torch.nn.functional.cross_entropy(
                    pred_policies, batch_policies, reduction='none'
                )
                policy_loss = (policy_loss * batch_weights).mean()

                value_loss = torch.nn.functional.mse_loss(
                    pred_values.squeeze(), batch_values, reduction='none'
                )
                value_loss = (value_loss * batch_weights).mean()

                total_loss_batch = policy_loss + value_loss

                # Backward pass
                optimizer.zero_grad()
                total_loss_batch.backward()
                optimizer.step()

                # Statistics
                total_loss += total_loss_batch.item()
                total_policy_loss += policy_loss.item()
                total_value_loss += value_loss.item()
                num_batches += 1
                epoch_loss += total_loss_batch.item()
                batch_count += 1

                # Update progress display - update every 10 batches to reduce overhead
                if batch_count % 10 == 0 or batch_count == total_batches_per_epoch:
                    current_loss = epoch_loss / batch_count
                    extra_info = f"Loss: {current_loss:.6f}"
                    progress_display.update(
                        current=batch_count,
                        total=total_batches_per_epoch,
                        current_file=f"Epoch {epoch + 1}/{epochs}",
                        extra_info=extra_info
                    )

            # Finish epoch progress display
            epoch_time = time.time() - epoch_start_time
            avg_epoch_loss = epoch_loss / total_batches_per_epoch
            progress_display.finish(f"Epoch {epoch + 1} completed!")
            print(f"  ✅ Epoch {epoch + 1}/{epochs} completed: Loss = {avg_epoch_loss:.6f}, Time = {epoch_time:.1f}s")
            print()

        # Calculate averages
        avg_loss = total_loss / num_batches if num_batches > 0 else 0.0
        avg_policy_loss = total_policy_loss / num_batches if num_batches > 0 else 0.0
        avg_value_loss = total_value_loss / num_batches if num_batches > 0 else 0.0

        # Count trap positions in training
        trap_count = sum(1 for pos in positions if pos.is_trap)

        logger.info(f"Training completed:")
        logger.info(f"  Total loss: {avg_loss:.6f}")
        logger.info(f"  Policy loss: {avg_policy_loss:.6f}")
        logger.info(f"  Value loss: {avg_value_loss:.6f}")
        logger.info(f"  Trap positions: {trap_count:,} ({trap_count/len(positions)*100:.1f}%)")

        return {
            'loss': avg_loss,
            'policy_loss': avg_policy_loss,
            'value_loss': avg_value_loss,
            'trap_positions': trap_count,
            'trap_ratio': trap_count / len(positions)
        }


def main():
    """Example usage of Perfect Database direct training."""
    import argparse
    from neural_network import AlphaZeroNetworkWrapper

    parser = argparse.ArgumentParser(description='Perfect Database Direct Training')
    parser.add_argument('--perfect-db', required=True, help='Path to Perfect Database')
    parser.add_argument('--mode', choices=['analyze', 'enumerate', 'sample'],
                        default='analyze', help='Training mode')
    parser.add_argument('--positions', type=int, default=50000,
                        help='Number of positions to extract/sample')
    parser.add_argument('--trap-ratio', type=float, default=0.3,
                        help='Ratio of trap positions in sampling')
    parser.add_argument('--epochs', type=int, default=10, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=64, help='Training batch size')

    args = parser.parse_args()

    # Set up logging
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(levelname)s - %(message)s')

    # Initialize neural network
    from game.Game import Game
    game = Game()
    model_args = {'action_size': game.getActionSize()}
    neural_network = AlphaZeroNetworkWrapper(model_args)

    # Initialize trainer
    trainer = PerfectDBDirectTrainer(args.perfect_db, neural_network)

    if args.mode == 'analyze':
        # Just analyze the database
        stats = trainer.stats
        print(f"\nPerfect Database Analysis:")
        print(f"  Sectors: {stats.total_sectors}")
        print(f"  Size: {stats.total_size_mb} MB")
        print(f"  Estimated positions: {stats.total_positions:,}")
        print(f"  Feasible for enumeration: {trainer.use_complete_enumeration}")

    elif args.mode == 'enumerate':
        # Complete enumeration
        positions = trainer.extract_all_positions(max_positions=args.positions)
        if positions:
            train_stats = trainer.train_neural_network(positions,
                                                       epochs=args.epochs,
                                                       batch_size=args.batch_size)
            print(f"Training completed: {train_stats}")

    elif args.mode == 'sample':
        # Strategic sampling
        positions = trainer.sample_strategic_positions(args.positions,
                                                       trap_ratio=args.trap_ratio)
        if positions:
            train_stats = trainer.train_neural_network(positions,
                                                       epochs=args.epochs,
                                                       batch_size=args.batch_size)
            print(f"Training completed: {train_stats}")


if __name__ == '__main__':
    main()
