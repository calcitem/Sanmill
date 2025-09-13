#!/usr/bin/env python3
"""
Progress tracking and display utilities for Katamill training and self-play.

Provides rich progress bars, statistics, and time estimation.
"""

import time
import sys
from typing import Dict, Optional, Any
from dataclasses import dataclass
from collections import deque
import logging

logger = logging.getLogger(__name__)

# Try to import tqdm for better progress bars
try:
    from tqdm import tqdm
    HAS_TQDM = True
except ImportError:
    HAS_TQDM = False


@dataclass
class ProgressStats:
    """Statistics for progress tracking."""
    total: int
    completed: int
    start_time: float
    last_update_time: float
    
    # Moving averages
    recent_times: deque  # Recent completion times
    recent_rates: deque  # Recent completion rates
    
    # Cumulative stats
    total_time: float = 0.0
    avg_time_per_item: float = 0.0
    current_rate: float = 0.0
    eta_seconds: float = 0.0
    
    def __post_init__(self):
        if not hasattr(self, 'recent_times') or self.recent_times is None:
            self.recent_times = deque(maxlen=20)
        if not hasattr(self, 'recent_rates') or self.recent_rates is None:
            self.recent_rates = deque(maxlen=10)


class ProgressTracker:
    """Enhanced progress tracker with statistics and ETA estimation."""
    
    def __init__(self, total: int, description: str = "Progress", 
                 update_interval: float = 1.0, use_tqdm: bool = None):
        """
        Initialize progress tracker.
        
        Args:
            total: Total number of items to process
            description: Description for progress display
            update_interval: Minimum seconds between updates
            use_tqdm: Force tqdm usage (None for auto-detect)
        """
        self.total = total
        self.description = description
        self.update_interval = update_interval
        self.start_time = time.time()
        
        self.stats = ProgressStats(
            total=total,
            completed=0,
            start_time=self.start_time,
            last_update_time=self.start_time,
            recent_times=deque(maxlen=20),
            recent_rates=deque(maxlen=10)
        )
        
        # Progress bar setup
        self.use_tqdm = use_tqdm if use_tqdm is not None else HAS_TQDM
        self.pbar = None
        
        if self.use_tqdm:
            self.pbar = tqdm(
                total=total,
                desc=description,
                unit="it",
                ncols=100,
                bar_format='{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}, {rate_fmt}]',
                mininterval=2.0,  # Minimum 2 seconds between updates
                maxinterval=10.0,  # Maximum 10 seconds between updates
                miniters=1  # Minimum iterations between updates
            )
        
        self._last_log_time = self.start_time
    
    def update(self, n: int = 1, **kwargs):
        """Update progress by n items."""
        current_time = time.time()
        self.stats.completed += n
        
        # Update timing statistics
        if len(self.stats.recent_times) > 0:
            time_diff = current_time - self.stats.last_update_time
            self.stats.recent_times.append(time_diff / n)
        
        self.stats.last_update_time = current_time
        self._update_stats()
        
        # Update progress bar
        if self.pbar:
            # Add custom stats to postfix
            postfix = {
                'rate': f"{self.stats.current_rate:.1f}/s",
                'eta': self._format_time(self.stats.eta_seconds)
            }
            postfix.update(kwargs)
            self.pbar.set_postfix(postfix)
            self.pbar.update(n)
        else:
            # Fallback to logging
            if current_time - self._last_log_time >= self.update_interval:
                self._log_progress(**kwargs)
                self._last_log_time = current_time
    
    def _update_stats(self):
        """Update internal statistics."""
        current_time = time.time()
        self.stats.total_time = current_time - self.stats.start_time
        
        if self.stats.completed > 0:
            self.stats.avg_time_per_item = self.stats.total_time / self.stats.completed
            
            # Calculate current rate using recent samples
            if len(self.stats.recent_times) > 0:
                recent_avg_time = sum(self.stats.recent_times) / len(self.stats.recent_times)
                self.stats.current_rate = 1.0 / recent_avg_time if recent_avg_time > 0 else 0.0
            else:
                self.stats.current_rate = self.stats.completed / self.stats.total_time
            
            # ETA calculation
            remaining = self.stats.total - self.stats.completed
            if self.stats.current_rate > 0:
                self.stats.eta_seconds = remaining / self.stats.current_rate
            else:
                self.stats.eta_seconds = 0.0
    
    def _log_progress(self, **kwargs):
        """Log progress information."""
        percent = (self.stats.completed / self.stats.total) * 100
        eta_str = self._format_time(self.stats.eta_seconds)
        elapsed_str = self._format_time(self.stats.total_time)
        
        extra_info = " | ".join([f"{k}: {v}" for k, v in kwargs.items()])
        extra_str = f" | {extra_info}" if extra_info else ""
        
        logger.info(f"{self.description}: {self.stats.completed}/{self.stats.total} "
                   f"({percent:.1f}%) | {self.stats.current_rate:.1f}/s | "
                   f"Elapsed: {elapsed_str} | ETA: {eta_str}{extra_str}")
    
    def _format_time(self, seconds: float) -> str:
        """Format seconds into human-readable time."""
        if seconds <= 0:
            return "00:00"
        
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        
        if hours > 0:
            return f"{hours:02d}:{minutes:02d}:{secs:02d}"
        else:
            return f"{minutes:02d}:{secs:02d}"
    
    def set_postfix(self, **kwargs):
        """Set additional information in progress display."""
        if self.pbar:
            self.pbar.set_postfix(kwargs)
    
    def set_description(self, desc: str):
        """Update progress description."""
        self.description = desc
        if self.pbar:
            self.pbar.set_description(desc)
    
    def close(self):
        """Close progress tracker and display final statistics."""
        if self.pbar:
            self.pbar.close()
        
        final_time = time.time() - self.stats.start_time
        avg_rate = self.stats.completed / final_time if final_time > 0 else 0
        
        logger.info(f"{self.description} completed: {self.stats.completed}/{self.stats.total} "
                   f"in {self._format_time(final_time)} "
                   f"(avg: {avg_rate:.1f}/s)")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get current statistics as dictionary."""
        return {
            'completed': self.stats.completed,
            'total': self.stats.total,
            'percentage': (self.stats.completed / self.stats.total) * 100,
            'elapsed_time': self.stats.total_time,
            'eta_seconds': self.stats.eta_seconds,
            'current_rate': self.stats.current_rate,
            'avg_time_per_item': self.stats.avg_time_per_item
        }


class TrainingProgressTracker:
    """Specialized progress tracker for training with loss tracking."""
    
    def __init__(self, total_epochs: int, batches_per_epoch: int):
        self.total_epochs = total_epochs
        self.batches_per_epoch = batches_per_epoch
        self.current_epoch = 0
        
        self.epoch_tracker = ProgressTracker(total_epochs, "Training Epochs")
        self.batch_tracker = None
        
        # Loss tracking
        self.epoch_losses = []
        self.best_loss = float('inf')
        self.best_epoch = 0
        
        # Timing
        self.epoch_start_time = None
        self.training_start_time = time.time()
    
    def start_epoch(self, epoch: int):
        """Start a new epoch."""
        self.current_epoch = epoch
        self.epoch_start_time = time.time()
        
        if self.batch_tracker:
            self.batch_tracker.close()
        
        self.batch_tracker = ProgressTracker(
            self.batches_per_epoch, 
            f"Epoch {epoch}/{self.total_epochs}"
        )
    
    def update_batch(self, loss: float, **kwargs):
        """Update batch progress with loss information."""
        if self.batch_tracker:
            self.batch_tracker.update(1, loss=f"{loss:.4f}", **kwargs)
    
    def end_epoch(self, avg_loss: float, val_loss: Optional[float] = None):
        """End current epoch and update statistics."""
        if self.batch_tracker:
            self.batch_tracker.close()
        
        epoch_time = time.time() - self.epoch_start_time if self.epoch_start_time else 0
        
        # Track losses
        self.epoch_losses.append(avg_loss)
        if avg_loss < self.best_loss:
            self.best_loss = avg_loss
            self.best_epoch = self.current_epoch
        
        # Update epoch progress
        postfix = {
            'loss': f"{avg_loss:.4f}",
            'best': f"{self.best_loss:.4f}@{self.best_epoch}",
            'time': f"{epoch_time:.1f}s"
        }
        if val_loss is not None:
            postfix['val_loss'] = f"{val_loss:.4f}"
        
        self.epoch_tracker.update(1, **postfix)
    
    def close(self):
        """Close training progress tracker."""
        if self.batch_tracker:
            self.batch_tracker.close()
        self.epoch_tracker.close()
        
        total_time = time.time() - self.training_start_time
        logger.info(f"Training completed in {self.epoch_tracker._format_time(total_time)}")
        logger.info(f"Best loss: {self.best_loss:.4f} at epoch {self.best_epoch}")
        
        # Display loss progression summary
        if len(self.epoch_losses) >= 2:
            first_loss = self.epoch_losses[0]
            last_loss = self.epoch_losses[-1]
            improvement = ((first_loss - last_loss) / first_loss) * 100
            trend_desc = "improved" if improvement > 0 else "degraded"
            logger.info(f"Loss change: {first_loss:.4f} → {last_loss:.4f} "
                       f"({improvement:+.1f}% {trend_desc})")


class SelfPlayProgressTracker:
    """Specialized progress tracker for self-play with game statistics."""
    
    def __init__(self, total_games: int, mcts_sims: int):
        self.total_games = total_games
        self.mcts_sims = mcts_sims
        
        self.tracker = ProgressTracker(total_games, "Self-Play Games")
        
        # Game statistics
        self.total_samples = 0
        self.total_moves = 0
        self.game_lengths = []
        self.outcomes = {'white_wins': 0, 'black_wins': 0, 'draws': 0}
        
        # Performance tracking
        self.games_completed = 0
        self.start_time = time.time()
    
    def update_game(self, samples: int, moves: int, outcome: str):
        """Update progress after completing a game."""
        self.games_completed += 1
        self.total_samples += samples
        self.total_moves += moves
        self.game_lengths.append(moves)
        
        if outcome in self.outcomes:
            self.outcomes[outcome] += 1
        
        # Calculate statistics
        avg_moves = sum(self.game_lengths) / len(self.game_lengths)
        elapsed = time.time() - self.start_time
        games_per_hour = (self.games_completed / elapsed) * 3600 if elapsed > 0 else 0
        
        self.tracker.update(1,
            samples=self.total_samples,
            avg_moves=f"{avg_moves:.1f}",
            games_per_hour=f"{games_per_hour:.1f}"
        )
    
    def get_outcome_stats(self) -> Dict[str, float]:
        """Get win/draw statistics."""
        total = sum(self.outcomes.values())
        if total == 0:
            return {k: 0.0 for k in self.outcomes.keys()}
        
        return {k: (v / total) * 100 for k, v in self.outcomes.items()}
    
    def close(self):
        """Close self-play progress tracker with final statistics."""
        self.tracker.close()
        
        if self.games_completed > 0:
            outcome_stats = self.get_outcome_stats()
            avg_length = sum(self.game_lengths) / len(self.game_lengths)
            samples_per_game = self.total_samples / self.games_completed
            
            logger.info(f"Self-play statistics:")
            logger.info(f"  Games: {self.games_completed}")
            logger.info(f"  Total samples: {self.total_samples} ({samples_per_game:.1f}/game)")
            logger.info(f"  Average game length: {avg_length:.1f} moves")
            logger.info(f"  Outcomes: W={outcome_stats['white_wins']:.1f}% "
                       f"D={outcome_stats['draws']:.1f}% "
                       f"B={outcome_stats['black_wins']:.1f}%")


def format_bytes(bytes_val: int) -> str:
    """Format bytes into human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:.1f}{unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:.1f}TB"


def format_number(num: int) -> str:
    """Format large numbers with K/M/B suffixes."""
    if num < 1000:
        return str(num)
    elif num < 1000000:
        return f"{num/1000:.1f}K"
    elif num < 1000000000:
        return f"{num/1000000:.1f}M"
    else:
        return f"{num/1000000000:.1f}B"
