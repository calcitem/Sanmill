#!/usr/bin/env python3
"""
Chunked Training Manager for Alpha Zero

This module implements memory-safe chunked training to prevent physical memory 
overflow and system crashes during large dataset training.

Key Features:
- Automatic memory monitoring and protection
- Intelligent data chunking based on available memory
- Gradient accumulation across chunks
- Memory cleanup between chunks
- Progress tracking and recovery
"""

import os
import sys
import time
import logging
import gc
from typing import List, Dict, Optional, Tuple, Iterator, Any
from pathlib import Path
from dataclasses import dataclass
from datetime import datetime, timedelta
import numpy as np
import torch
import psutil

# Add local imports
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from fast_data_loader import FastDataLoader
from neural_network import AlphaZeroNetworkWrapper
import json
import glob

logger = logging.getLogger(__name__)


@dataclass
class ChunkInfo:
    """Information about a training data chunk."""
    chunk_id: int
    start_position: int
    end_position: int
    estimated_memory_mb: float
    num_samples: int
    phase_filter: Optional[str] = None


@dataclass
class TrainingProgress:
    """Training progress tracking."""
    epoch: int
    total_epochs: int
    chunk_id: int
    total_chunks: int
    samples_processed: int
    total_samples: int
    current_loss: float = 0.0
    avg_loss: float = 0.0
    memory_usage_mb: float = 0.0
    time_elapsed: float = 0.0
    batches_processed: int = 0
    total_batches_per_epoch: int = 0


class ChunkedTrainingProgressDisplay:
    """Enhanced progress display for chunked training with ETA and detailed metrics."""
    
    def __init__(self, total_epochs: int, total_chunks: int, total_samples: int):
        """
        Initialize progress display for chunked training.
        
        Args:
            total_epochs: Total number of training epochs
            total_chunks: Total number of chunks per epoch  
            total_samples: Total number of training samples
        """
        self.total_epochs = total_epochs
        self.total_chunks = total_chunks
        self.total_samples = total_samples
        self.start_time = time.time()
        
        # Progress tracking
        self.current_epoch = 0
        self.current_chunk = 0
        self.current_batch = 0
        self.samples_processed = 0
        self.total_batches_per_epoch = 0
        
        # Performance metrics
        self.epoch_losses = []
        self.chunk_times = []
        self.batch_times = []
        self.samples_per_second_history = []
        
        # Time estimation refinement
        self.actual_samples_per_second = 1000  # Initial estimate
        self.time_estimate_updates = 0
        
        # Loss anomaly detection
        self.loss_history = []
        self.zero_loss_count = 0
        self.nan_loss_count = 0
        self.loss_warnings_shown = set()  # Track which warnings we've already shown
        
        # Extended anomaly detection
        self.batch_processing_times = []
        self.memory_warnings_count = 0
        self.gradient_anomaly_count = 0
        self.learning_rate_history = []
        self.accuracy_history = []  # If available
        self.last_checkpoint_time = time.time()
        
        # Warning statistics for display
        self.warning_stats = {
            'total_warnings': 0,
            'loss_warnings': 0,
            'performance_warnings': 0,
            'memory_warnings': 0,
            'system_warnings': 0,
            'critical_warnings': 0
        }
        
        # Game phase training statistics
        self.phase_stats = {
            'placement': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0, 'training_time': 0.0},
            'moving': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0, 'training_time': 0.0},
            'flying': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0, 'training_time': 0.0},
            'removal': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0, 'training_time': 0.0}
        }
        
        # Position type statistics
        self.position_type_stats = {
            'trap_positions': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0},
            'critical_positions': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0},
            'endgame_positions': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0},
            'opening_positions': {'samples_trained': 0, 'total_samples': 0, 'avg_loss': 0.0}
        }
        
        # Display settings
        self.last_update = 0
        self.update_interval = 1.0  # Update every 1 second
        self.progress_bar_width = 40
        
        logger.info(f"ChunkedTrainingProgressDisplay initialized:")
        logger.info(f"  Total epochs: {total_epochs}")
        logger.info(f"  Total chunks per epoch: {total_chunks}")
        logger.info(f"  Total samples: {total_samples:,}")
    
    def start_epoch(self, epoch: int, total_batches: int):
        """Start a new epoch."""
        self.current_epoch = epoch
        self.current_chunk = 0
        self.current_batch = 0
        self.total_batches_per_epoch = total_batches
        self.epoch_start_time = time.time()
        
        print(f"\n{'='*80}")
        print(f"🚀 Starting Epoch {epoch + 1}/{self.total_epochs}")
        print(f"{'='*80}")
        
    def start_chunk(self, chunk_id: int, chunk_samples: int, estimated_memory_mb: float,
                   chunk_metadata: Optional[Dict[str, Any]] = None):
        """Start processing a new chunk with phase analysis."""
        self.current_chunk = chunk_id
        self.chunk_start_time = time.time()
        self.chunk_samples = chunk_samples
        self.current_batch = 0
        
        # Memory status
        memory_status = self._get_memory_status()
        
        print(f"\n📦 Processing Chunk {chunk_id + 1}/{self.total_chunks}")
        print(f"   Samples: {chunk_samples:,} | Estimated Memory: {estimated_memory_mb:.1f} MB")
        print(f"   Available Memory: {memory_status['available_gb']:.1f} GB | "
              f"Memory Usage: {memory_status['usage_percent']:.1f}%")
        
        # Display chunk composition if metadata available
        if chunk_metadata:
            self._display_chunk_composition(chunk_metadata)
        
    def update_batch_progress(self, batch_idx: int, total_batches: int, 
                            current_loss: float, samples_in_batch: int,
                            batch_time: float = 0.0, learning_rate: float = None):
        """Update progress for current batch with comprehensive anomaly detection."""
        now = time.time()
        
        # Record batch processing time
        if batch_time > 0:
            self.batch_processing_times.append(batch_time)
            if len(self.batch_processing_times) > 50:  # Keep only recent times
                self.batch_processing_times = self.batch_processing_times[-50:]
        
        # Record learning rate if provided
        if learning_rate is not None:
            self.learning_rate_history.append(learning_rate)
            if len(self.learning_rate_history) > 100:
                self.learning_rate_history = self.learning_rate_history[-100:]
        
        # Comprehensive anomaly detection
        self._check_comprehensive_anomalies(current_loss, batch_time, learning_rate, now)
        
        # Throttle updates to avoid excessive output
        if now - self.last_update < self.update_interval:
            return
        
        self.last_update = now
        self.current_batch = batch_idx + 1
        self.samples_processed += samples_in_batch
        
        # Calculate progress percentages
        chunk_progress = (batch_idx + 1) / total_batches * 100
        epoch_progress = ((self.current_chunk * total_batches + batch_idx + 1) / 
                         (self.total_chunks * total_batches) * 100)
        overall_progress = ((self.current_epoch * self.total_chunks * total_batches + 
                           self.current_chunk * total_batches + batch_idx + 1) / 
                          (self.total_epochs * self.total_chunks * total_batches) * 100)
        
        # Time calculations
        elapsed_time = now - self.start_time
        
        # Update actual performance metrics
        if elapsed_time > 0:
            current_samples_per_second = self.samples_processed / elapsed_time
            self.samples_per_second_history.append(current_samples_per_second)
            
            # Use moving average for more stable estimates
            if len(self.samples_per_second_history) > 10:
                self.samples_per_second_history = self.samples_per_second_history[-10:]
            
            self.actual_samples_per_second = np.mean(self.samples_per_second_history)
        
        # Calculate refined time estimates based on actual performance
        remaining_samples = self.total_samples - self.samples_processed
        if self.actual_samples_per_second > 0 and remaining_samples > 0:
            estimated_remaining = remaining_samples / self.actual_samples_per_second
        else:
            # Fallback to progress-based estimate
            if overall_progress > 0:
                estimated_total_time = elapsed_time * 100 / overall_progress
                estimated_remaining = max(0, estimated_total_time - elapsed_time)
            else:
                estimated_remaining = 0
        
        # Chunk ETA
        chunk_elapsed = now - self.chunk_start_time
        if chunk_progress > 0:
            chunk_total_time = chunk_elapsed * 100 / chunk_progress
            chunk_remaining = max(0, chunk_total_time - chunk_elapsed)
        else:
            chunk_remaining = 0
        
        # Progress bars
        chunk_bar = self._create_progress_bar(chunk_progress)
        epoch_bar = self._create_progress_bar(epoch_progress)
        overall_bar = self._create_progress_bar(overall_progress)
        
        # Clear previous lines and display progress
        print(f"\r{' ' * 100}", end='\r')  # Clear line
        
        # Get warning statistics for display
        warning_summary = self._get_warning_summary()
        
        print(f"   Chunk  {chunk_bar} {chunk_progress:5.1f}% | "
              f"Batch {batch_idx + 1:4d}/{total_batches:4d} | "
              f"Loss: {current_loss:.6f} | "
              f"Remaining: {self._format_time(chunk_remaining)}")
        
        print(f"   Epoch  {epoch_bar} {epoch_progress:5.1f}% | "
              f"Chunk {self.current_chunk + 1:2d}/{self.total_chunks:2d} | "
              f"Memory: {self._get_memory_status()['available_gb']:.1f} GB | "
              f"Speed: {self.actual_samples_per_second:.0f} samples/s")
        
        print(f"   Overall{overall_bar} {overall_progress:5.1f}% | "
              f"Epoch {self.current_epoch + 1:2d}/{self.total_epochs:2d} | "
              f"Total Remaining: {self._format_time(estimated_remaining)} | "
              f"Warnings: {warning_summary}")
        
        # Move cursor back up to overwrite on next update
        print("\033[3A", end='', flush=True)
    
    def complete_chunk(self, chunk_loss: float):
        """Complete current chunk processing."""
        chunk_time = time.time() - self.chunk_start_time
        self.chunk_times.append(chunk_time)
        
        # Move cursor down and clear
        print("\033[3B", end='')
        print(f"\r{' ' * 100}", end='\r')
        
        # Calculate chunk statistics
        avg_batch_time = chunk_time / max(1, self.current_batch)
        samples_per_second = self.chunk_samples / chunk_time if chunk_time > 0 else 0
        
        print(f"   ✅ Chunk {self.current_chunk + 1} completed | "
              f"Loss: {chunk_loss:.6f} | "
              f"Time: {self._format_time(chunk_time)} | "
              f"Speed: {samples_per_second:.0f} samples/s")
        
    def complete_epoch(self, epoch_loss: float):
        """Complete current epoch."""
        epoch_time = time.time() - self.epoch_start_time
        self.epoch_losses.append(epoch_loss)
        
        # Calculate epoch statistics
        total_chunks_time = sum(self.chunk_times[-self.total_chunks:])
        avg_chunk_time = total_chunks_time / self.total_chunks
        samples_per_second = self.total_samples / epoch_time if epoch_time > 0 else 0
        
        # Memory status
        memory_status = self._get_memory_status()
        
        print(f"\n🎯 Epoch {self.current_epoch + 1} Summary:")
        print(f"   Average Loss: {epoch_loss:.6f}")
        print(f"   Total Time: {self._format_time(epoch_time)}")
        print(f"   Average Chunk Time: {self._format_time(avg_chunk_time)}")
        print(f"   Processing Speed: {samples_per_second:.0f} samples/s")
        print(f"   Memory Usage: {memory_status['usage_percent']:.1f}% "
              f"({memory_status['available_gb']:.1f} GB available)")
        
        # Warning statistics for this epoch
        warning_summary = self._get_detailed_warning_summary()
        if warning_summary:
            print(f"   Warnings This Session: {warning_summary}")
        
        # Learning progress indicator
        if len(self.epoch_losses) > 1:
            loss_change = epoch_loss - self.epoch_losses[-2]
            trend = "↓" if loss_change < 0 else "↑" if loss_change > 0 else "→"
            print(f"   Loss Trend: {trend} {abs(loss_change):+.6f}")
        
        # Loss anomaly summary for this epoch
        if self.loss_history:
            self._report_epoch_loss_summary()
        
        # Display phase training progress every few epochs
        if (self.current_epoch + 1) % 3 == 0:  # Every 3 epochs
            self.display_training_progress_by_phase()
        
        # Reset chunk tracking for next epoch
        self.current_chunk = 0
        
    def complete_training(self, final_stats: Dict[str, Any]):
        """Complete training and show final summary."""
        total_time = time.time() - self.start_time
        
        print(f"\n{'='*80}")
        print(f"🎉 Training Completed Successfully!")
        print(f"{'='*80}")
        
        print(f"📊 Final Statistics:")
        print(f"   Total Epochs: {final_stats.get('epochs_completed', 0)}")
        print(f"   Total Chunks: {final_stats.get('chunks_processed', 0)}")
        print(f"   Total Samples: {final_stats.get('samples_processed', 0):,}")
        print(f"   Total Time: {self._format_time(total_time)}")
        
        if self.epoch_losses:
            print(f"   Initial Loss: {self.epoch_losses[0]:.6f}")
            print(f"   Final Loss: {self.epoch_losses[-1]:.6f}")
            improvement = self.epoch_losses[0] - self.epoch_losses[-1]
            print(f"   Improvement: {improvement:+.6f}")
        
        # Performance metrics
        avg_samples_per_second = final_stats.get('samples_processed', 0) / total_time if total_time > 0 else 0
        print(f"   Average Speed: {avg_samples_per_second:.0f} samples/s")
        
        # Memory summary
        memory_status = self._get_memory_status()
        print(f"   Final Memory Usage: {memory_status['usage_percent']:.1f}%")
        
        # Final warning statistics
        warning_summary = self._get_detailed_warning_summary()
        if warning_summary:
            print(f"\n⚠️ Training Warnings Summary:")
            print(f"   {warning_summary}")
            if self.warning_stats['critical_warnings'] > 0:
                print(f"   🚨 CRITICAL: {self.warning_stats['critical_warnings']} critical warnings detected!")
                print(f"      Please review the training logs and apply suggested solutions.")
            elif self.warning_stats['total_warnings'] > 10:
                print(f"   ⚠️ HIGH: Many warnings detected - consider reviewing training setup.")
            else:
                print(f"   ℹ️ Some warnings detected but training completed successfully.")
        else:
            print(f"\n✅ Training completed with no anomaly warnings detected.")
        
        # Final loss analysis
        if self.loss_history:
            print(f"\n📊 Final Loss Analysis:")
            total_losses = len(self.loss_history)
            zero_losses = sum(1 for loss in self.loss_history if abs(loss) < 1e-8)
            
            print(f"   Total batches processed: {total_losses:,}")
            print(f"   Zero loss batches: {zero_losses:,} ({zero_losses/total_losses*100:.1f}%)")
            
            if zero_losses > 0:
                print(f"   🚨 ATTENTION: {zero_losses:,} batches had zero loss!")
                print(f"      This indicates potential training issues.")
                print(f"      Consider reviewing the training setup and applying suggested solutions.")
            else:
                print(f"   ✅ No zero loss batches detected - training appears stable.")
        
        # Final phase training summary
        self.display_training_progress_by_phase()
        
    def _create_progress_bar(self, percentage: float) -> str:
        """Create a text-based progress bar."""
        filled_length = int(self.progress_bar_width * percentage / 100)
        bar = '█' * filled_length + '░' * (self.progress_bar_width - filled_length)
        return f"|{bar}|"
    
    def _format_time(self, seconds: float) -> str:
        """Format time duration for display with full readability (days, hours, minutes, seconds)."""
        if seconds < 0:
            return "0s"
        
        # Calculate time components
        days = int(seconds // 86400)
        remaining = seconds % 86400
        hours = int(remaining // 3600)
        remaining = remaining % 3600
        minutes = int(remaining // 60)
        secs = int(remaining % 60)
        
        # Build time string with appropriate components
        time_parts = []
        
        if days > 0:
            time_parts.append(f"{days}d")
        if hours > 0:
            time_parts.append(f"{hours}h")
        if minutes > 0:
            time_parts.append(f"{minutes}m")
        if secs > 0 or not time_parts:  # Always show seconds if no other components
            time_parts.append(f"{secs}s")
        
        # Join components with space, but limit to most significant 3 components for readability
        if len(time_parts) > 3:
            time_parts = time_parts[:3]
        
        return " ".join(time_parts)
    
    def _get_warning_summary(self) -> str:
        """Get a compact warning summary for progress display."""
        stats = self.warning_stats
        total = stats['total_warnings']
        
        if total == 0:
            return "None"
        
        # Create color-coded summary
        summary_parts = []
        
        if stats['critical_warnings'] > 0:
            summary_parts.append(f"🚨{stats['critical_warnings']}")
        
        if stats['loss_warnings'] > 0:
            summary_parts.append(f"L:{stats['loss_warnings']}")
        
        if stats['memory_warnings'] > 0:
            summary_parts.append(f"M:{stats['memory_warnings']}")
        
        if stats['performance_warnings'] > 0:
            summary_parts.append(f"P:{stats['performance_warnings']}")
        
        if stats['system_warnings'] > 0:
            summary_parts.append(f"S:{stats['system_warnings']}")
        
        if summary_parts:
            return " ".join(summary_parts)
        else:
            return f"Total:{total}"
    
    def _get_detailed_warning_summary(self) -> str:
        """Get detailed warning summary for epoch/training completion."""
        stats = self.warning_stats
        total = stats['total_warnings']
        
        if total == 0:
            return ""
        
        parts = []
        
        if stats['critical_warnings'] > 0:
            parts.append(f"Critical: {stats['critical_warnings']}")
        
        if stats['loss_warnings'] > 0:
            parts.append(f"Loss: {stats['loss_warnings']}")
        
        if stats['memory_warnings'] > 0:
            parts.append(f"Memory: {stats['memory_warnings']}")
        
        if stats['performance_warnings'] > 0:
            parts.append(f"Performance: {stats['performance_warnings']}")
        
        if stats['system_warnings'] > 0:
            parts.append(f"System: {stats['system_warnings']}")
        
        result = f"Total: {total}"
        if parts:
            result += f" ({', '.join(parts)})"
        
        return result
    
    def _increment_warning_count(self, warning_type: str, is_critical: bool = False):
        """Increment warning counters for statistics."""
        self.warning_stats['total_warnings'] += 1
        
        if is_critical:
            self.warning_stats['critical_warnings'] += 1
        
        # Categorize warning types
        loss_related = ['frequent_zero', 'nan_loss', 'vanishing_gradients', 'loss_explosion', 
                       'loss_plateau', 'oscillating_loss', 'loss_spike']
        memory_related = ['critical_memory', 'memory_leak']
        performance_related = ['slow_batch', 'performance_degradation']
        system_related = ['high_cpu', 'low_disk', 'no_checkpoint', 'invalid_lr', 'high_lr', 'low_lr']
        
        if warning_type in loss_related:
            self.warning_stats['loss_warnings'] += 1
        elif warning_type in memory_related:
            self.warning_stats['memory_warnings'] += 1
        elif warning_type in performance_related:
            self.warning_stats['performance_warnings'] += 1
        elif warning_type in system_related:
            self.warning_stats['system_warnings'] += 1
    
    def _check_comprehensive_anomalies(self, current_loss: float, batch_time: float, 
                                     learning_rate: float, current_time: float):
        """Comprehensive anomaly detection covering multiple training aspects."""
        # 1. Loss anomalies (existing)
        self._check_loss_anomalies(current_loss)
        
        # 2. Performance anomalies
        self._check_performance_anomalies(batch_time, current_time)
        
        # 3. Memory anomalies
        self._check_memory_anomalies()
        
        # 4. Learning rate anomalies
        if learning_rate is not None:
            self._check_learning_rate_anomalies(learning_rate)
        
        # 5. Training stability anomalies
        self._check_training_stability_anomalies()
        
        # 6. System resource anomalies
        self._check_system_resource_anomalies(current_time)
    
    def _check_performance_anomalies(self, batch_time: float, current_time: float):
        """Check for performance-related anomalies."""
        if batch_time <= 0 or not self.batch_processing_times:
            return
        
        # Check for extremely slow batches
        if len(self.batch_processing_times) >= 10:
            avg_time = np.mean(self.batch_processing_times[-10:])
            
            # Batch taking much longer than average
            if batch_time > avg_time * 3 and "slow_batch" not in self.loss_warnings_shown:
                self._show_anomaly_warning("slow_batch", batch_time, avg_time)
                self.loss_warnings_shown.add("slow_batch")
        
        # Check for processing speed degradation
        if len(self.batch_processing_times) >= 30:
            recent_10 = np.mean(self.batch_processing_times[-10:])
            older_10 = np.mean(self.batch_processing_times[-30:-20])
            
            if recent_10 > older_10 * 2 and "performance_degradation" not in self.loss_warnings_shown:
                self._show_anomaly_warning("performance_degradation", recent_10, older_10)
                self.loss_warnings_shown.add("performance_degradation")
    
    def _check_memory_anomalies(self):
        """Check for memory-related anomalies."""
        memory_status = self._get_memory_status()
        
        # Critical memory usage
        if memory_status['usage_percent'] > 95 and "critical_memory" not in self.loss_warnings_shown:
            self._show_anomaly_warning("critical_memory", memory_status['usage_percent'], 
                                     memory_status['available_gb'])
            self.loss_warnings_shown.add("critical_memory")
            self.memory_warnings_count += 1
        
        # Rapid memory increase
        if hasattr(self, '_previous_memory_usage'):
            memory_increase = memory_status['usage_percent'] - self._previous_memory_usage
            if memory_increase > 10 and "memory_leak" not in self.loss_warnings_shown:
                self._show_anomaly_warning("memory_leak", memory_increase, 
                                         memory_status['usage_percent'])
                self.loss_warnings_shown.add("memory_leak")
        
        self._previous_memory_usage = memory_status['usage_percent']
    
    def _check_learning_rate_anomalies(self, learning_rate: float):
        """Check for learning rate related anomalies."""
        if learning_rate <= 0:
            if "invalid_lr" not in self.loss_warnings_shown:
                self._show_anomaly_warning("invalid_lr", learning_rate)
                self.loss_warnings_shown.add("invalid_lr")
        
        # Extremely high learning rate
        if learning_rate > 1.0 and "high_lr" not in self.loss_warnings_shown:
            self._show_anomaly_warning("high_lr", learning_rate)
            self.loss_warnings_shown.add("high_lr")
        
        # Extremely low learning rate
        if learning_rate < 1e-8 and "low_lr" not in self.loss_warnings_shown:
            self._show_anomaly_warning("low_lr", learning_rate)
            self.loss_warnings_shown.add("low_lr")
    
    def _check_training_stability_anomalies(self):
        """Check for training stability issues."""
        if len(self.loss_history) < 20:
            return
        
        recent_losses = self.loss_history[-20:]
        
        # Oscillating losses (high variance)
        loss_std = np.std(recent_losses)
        loss_mean = np.mean(recent_losses)
        
        if loss_mean > 0 and loss_std / loss_mean > 2.0 and "oscillating_loss" not in self.loss_warnings_shown:
            self._show_anomaly_warning("oscillating_loss", loss_std, loss_mean)
            self.loss_warnings_shown.add("oscillating_loss")
        
        # Sudden loss spikes
        if len(self.loss_history) >= 5:
            recent_5 = self.loss_history[-5:]
            prev_5 = self.loss_history[-10:-5] if len(self.loss_history) >= 10 else recent_5
            
            recent_avg = np.mean(recent_5)
            prev_avg = np.mean(prev_5)
            
            if recent_avg > prev_avg * 5 and recent_avg > 1.0 and "loss_spike" not in self.loss_warnings_shown:
                self._show_anomaly_warning("loss_spike", recent_avg, prev_avg)
                self.loss_warnings_shown.add("loss_spike")
    
    def _check_system_resource_anomalies(self, current_time: float):
        """Check for system resource anomalies."""
        try:
            import psutil
            
            # CPU usage check
            cpu_percent = psutil.cpu_percent(interval=0.1)
            if cpu_percent > 95 and "high_cpu" not in self.loss_warnings_shown:
                self._show_anomaly_warning("high_cpu", cpu_percent)
                self.loss_warnings_shown.add("high_cpu")
            
            # Disk space check
            disk_usage = psutil.disk_usage('/')
            free_gb = disk_usage.free / (1024**3)
            if free_gb < 5 and "low_disk" not in self.loss_warnings_shown:
                self._show_anomaly_warning("low_disk", free_gb)
                self.loss_warnings_shown.add("low_disk")
            
            # Check if training has been running too long without checkpoint
            time_since_checkpoint = current_time - self.last_checkpoint_time
            if time_since_checkpoint > 3600 and "no_checkpoint" not in self.loss_warnings_shown:  # 1 hour
                self._show_anomaly_warning("no_checkpoint", time_since_checkpoint / 3600)
                self.loss_warnings_shown.add("no_checkpoint")
                
        except Exception:
            pass  # Ignore system resource check failures
    
    def _check_loss_anomalies(self, current_loss: float):
        """Check for loss anomalies and provide warnings with solutions."""
        import math
        
        # Add to loss history
        self.loss_history.append(current_loss)
        
        # Keep only recent history (last 100 losses)
        if len(self.loss_history) > 100:
            self.loss_history = self.loss_history[-100:]
        
        # Check for various anomalies
        is_zero = abs(current_loss) < 1e-8
        is_nan = math.isnan(current_loss) or math.isinf(current_loss)
        
        if is_zero:
            self.zero_loss_count += 1
        if is_nan:
            self.nan_loss_count += 1
        
        # Check for patterns and provide warnings
        if len(self.loss_history) >= 10:  # Need some history to analyze
            
            # Check for frequent zero losses
            recent_losses = self.loss_history[-10:]
            zero_count_recent = sum(1 for loss in recent_losses if abs(loss) < 1e-8)
            
            if zero_count_recent >= 5 and "frequent_zero" not in self.loss_warnings_shown:
                self._show_loss_warning("frequent_zero", zero_count_recent, 10)
                self.loss_warnings_shown.add("frequent_zero")
            
            # Check for NaN/Inf losses
            if is_nan and "nan_loss" not in self.loss_warnings_shown:
                self._show_loss_warning("nan_loss", current_loss)
                self.loss_warnings_shown.add("nan_loss")
            
            # Check for extremely small losses (might indicate vanishing gradients)
            if len(self.loss_history) >= 20:
                recent_20 = self.loss_history[-20:]
                small_loss_count = sum(1 for loss in recent_20 if 0 < loss < 1e-6)
                
                if small_loss_count >= 15 and "vanishing_gradients" not in self.loss_warnings_shown:
                    self._show_loss_warning("vanishing_gradients", small_loss_count, 20)
                    self.loss_warnings_shown.add("vanishing_gradients")
            
            # Check for loss explosion (very large values)
            if current_loss > 100 and "loss_explosion" not in self.loss_warnings_shown:
                self._show_loss_warning("loss_explosion", current_loss)
                self.loss_warnings_shown.add("loss_explosion")
            
            # Check for loss plateau (no improvement)
            if len(self.loss_history) >= 50:
                recent_50 = self.loss_history[-50:]
                loss_std = np.std(recent_50)
                loss_mean = np.mean(recent_50)
                
                # If standard deviation is very small relative to mean, might be stuck
                if loss_mean > 0 and loss_std / loss_mean < 0.01 and "loss_plateau" not in self.loss_warnings_shown:
                    self._show_loss_warning("loss_plateau", loss_std, loss_mean)
                    self.loss_warnings_shown.add("loss_plateau")
    
    def _show_anomaly_warning(self, warning_type: str, *args):
        """Display comprehensive training anomaly warnings with solutions."""
        # Determine if this is a critical warning
        critical_warnings = ['critical_memory', 'nan_loss', 'loss_explosion', 'low_disk', 'no_checkpoint']
        is_critical = warning_type in critical_warnings
        
        # Update warning statistics
        self._increment_warning_count(warning_type, is_critical)
        
        print(f"\n{'='*80}")
        if is_critical:
            print("🚨 CRITICAL TRAINING ANOMALY DETECTED")
        else:
            print("⚠️ TRAINING ANOMALY DETECTED")
        print(f"{'='*80}")
        
        # Performance anomalies
        if warning_type == "slow_batch":
            batch_time, avg_time = args
            print(f"⚠️  SLOW BATCH PROCESSING: Current batch took {batch_time:.2f}s vs average {avg_time:.2f}s")
            print("\n🔍 Possible Causes:")
            print("   1. System resource contention (CPU/GPU/Memory)")
            print("   2. Background processes consuming resources")
            print("   3. Thermal throttling due to overheating")
            print("   4. Storage I/O bottleneck")
            print("   5. Network latency (if using remote storage)")
            print("\n💡 Recommended Solutions:")
            print("   • Check system resource usage (Task Manager/htop)")
            print("   • Close unnecessary background applications")
            print("   • Monitor CPU/GPU temperatures")
            print("   • Check disk usage and available space")
            print("   • Consider reducing batch size temporarily")
            print("   • Verify data is stored on fast local storage")
            
        elif warning_type == "performance_degradation":
            recent_time, older_time = args
            print(f"⚠️  PERFORMANCE DEGRADATION: Batch time increased from {older_time:.2f}s to {recent_time:.2f}s")
            print("\n🔍 Possible Causes:")
            print("   1. Memory fragmentation over time")
            print("   2. Gradual memory leak")
            print("   3. System thermal throttling")
            print("   4. Background process interference")
            print("   5. Storage becoming fragmented")
            print("\n💡 Recommended Solutions:")
            print("   • Restart training from latest checkpoint")
            print("   • Monitor memory usage trends")
            print("   • Check system temperatures")
            print("   • Clear system caches and temporary files")
            print("   • Consider reducing data loading workers")
            
        # Memory anomalies
        elif warning_type == "critical_memory":
            usage_percent, available_gb = args
            print(f"⚠️  CRITICAL MEMORY USAGE: {usage_percent:.1f}% used, only {available_gb:.1f}GB available")
            print("\n🔍 Possible Causes:")
            print("   1. Memory leak in training code")
            print("   2. Batch size too large for available memory")
            print("   3. Data not being properly released after use")
            print("   4. Too many data loading workers")
            print("   5. Large model or intermediate activations")
            print("\n💡 Recommended Solutions:")
            print("   • IMMEDIATELY reduce batch size by 50%")
            print("   • Reduce number of data loading workers")
            print("   • Enable gradient checkpointing")
            print("   • Use mixed precision training")
            print("   • Clear unused variables and call gc.collect()")
            print("   • Consider model parallelism if available")
            
        elif warning_type == "memory_leak":
            increase, current_usage = args
            print(f"⚠️  POTENTIAL MEMORY LEAK: Memory usage increased by {increase:.1f}% (now at {current_usage:.1f}%)")
            print("\n🔍 Possible Causes:")
            print("   1. Variables not being properly deleted")
            print("   2. Circular references preventing garbage collection")
            print("   3. Caching too much data in memory")
            print("   4. PyTorch tensors not moved to CPU after use")
            print("   5. Matplotlib figures not being closed")
            print("\n💡 Recommended Solutions:")
            print("   • Add explicit del statements for large variables")
            print("   • Call torch.cuda.empty_cache() periodically")
            print("   • Use context managers for temporary objects")
            print("   • Monitor memory usage with memory_profiler")
            print("   • Restart training if memory continues increasing")
            
        # Learning rate anomalies
        elif warning_type == "invalid_lr":
            lr_value = args[0]
            print(f"⚠️  INVALID LEARNING RATE: Learning rate = {lr_value}")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate scheduler malfunction")
            print("   2. Numerical underflow in scheduler")
            print("   3. Incorrect scheduler configuration")
            print("   4. Manual learning rate modification error")
            print("\n💡 Recommended Solutions:")
            print("   • Reset learning rate to a valid value (e.g., 1e-4)")
            print("   • Check learning rate scheduler configuration")
            print("   • Add learning rate bounds checking")
            print("   • Log learning rate changes for debugging")
            
        elif warning_type == "high_lr":
            lr_value = args[0]
            print(f"⚠️  EXTREMELY HIGH LEARNING RATE: Learning rate = {lr_value}")
            print("\n🔍 Possible Causes:")
            print("   1. Incorrect initial learning rate setting")
            print("   2. Learning rate scheduler misconfiguration")
            print("   3. Learning rate warm-up gone wrong")
            print("\n💡 Recommended Solutions:")
            print("   • IMMEDIATELY reduce learning rate by 100x")
            print("   • Check for gradient explosion")
            print("   • Use gradient clipping")
            print("   • Restart with proper learning rate")
            
        elif warning_type == "low_lr":
            lr_value = args[0]
            print(f"⚠️  EXTREMELY LOW LEARNING RATE: Learning rate = {lr_value}")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate decay too aggressive")
            print("   2. Scheduler reducing LR too quickly")
            print("   3. Numerical precision issues")
            print("\n💡 Recommended Solutions:")
            print("   • Increase learning rate to reasonable value (e.g., 1e-4)")
            print("   • Adjust learning rate scheduler parameters")
            print("   • Use learning rate finder to determine optimal LR")
            
        # Training stability anomalies
        elif warning_type == "oscillating_loss":
            loss_std, loss_mean = args
            print(f"⚠️  OSCILLATING LOSS: High variance (std={loss_std:.4f}, mean={loss_mean:.4f})")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too high causing instability")
            print("   2. Batch size too small causing noisy gradients")
            print("   3. Poor data shuffling or imbalanced batches")
            print("   4. Gradient accumulation issues")
            print("   5. Model architecture instability")
            print("\n💡 Recommended Solutions:")
            print("   • Reduce learning rate by 2-5x")
            print("   • Increase batch size if memory allows")
            print("   • Improve data shuffling strategy")
            print("   • Add batch normalization or layer normalization")
            print("   • Use gradient clipping")
            print("   • Consider different optimizer (e.g., AdamW)")
            
        elif warning_type == "loss_spike":
            recent_avg, prev_avg = args
            print(f"⚠️  SUDDEN LOSS SPIKE: Loss jumped from {prev_avg:.4f} to {recent_avg:.4f}")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too high causing divergence")
            print("   2. Bad batch with corrupted data")
            print("   3. Numerical instability")
            print("   4. Gradient explosion")
            print("   5. Model weights became corrupted")
            print("\n💡 Recommended Solutions:")
            print("   • IMMEDIATELY reduce learning rate by 10x")
            print("   • Check data integrity")
            print("   • Add gradient clipping")
            print("   • Consider loading from previous checkpoint")
            print("   • Inspect batch that caused the spike")
            
        # System resource anomalies
        elif warning_type == "high_cpu":
            cpu_percent = args[0]
            print(f"⚠️  HIGH CPU USAGE: CPU usage at {cpu_percent:.1f}%")
            print("\n🔍 Possible Causes:")
            print("   1. Too many data loading workers")
            print("   2. CPU-intensive data preprocessing")
            print("   3. Background processes consuming CPU")
            print("   4. Inefficient data augmentation")
            print("\n💡 Recommended Solutions:")
            print("   • Reduce number of data loading workers")
            print("   • Optimize data preprocessing pipeline")
            print("   • Close unnecessary background applications")
            print("   • Move data preprocessing to GPU if possible")
            
        elif warning_type == "low_disk":
            free_gb = args[0]
            print(f"⚠️  LOW DISK SPACE: Only {free_gb:.1f}GB available")
            print("\n🔍 Possible Causes:")
            print("   1. Checkpoint files consuming space")
            print("   2. Log files growing too large")
            print("   3. Temporary files not being cleaned")
            print("   4. Data files taking up space")
            print("\n💡 Recommended Solutions:")
            print("   • Clean up old checkpoint files")
            print("   • Rotate or compress log files")
            print("   • Clear temporary directories")
            print("   • Move data to external storage")
            print("   • CRITICAL: Training may fail without space!")
            
        elif warning_type == "no_checkpoint":
            hours = args[0]
            print(f"⚠️  NO RECENT CHECKPOINT: Training running {hours:.1f} hours without checkpoint")
            print("\n🔍 Possible Causes:")
            print("   1. Checkpoint saving disabled or misconfigured")
            print("   2. Checkpoint directory not writable")
            print("   3. Disk space insufficient for checkpoints")
            print("   4. Checkpoint saving code has errors")
            print("\n💡 Recommended Solutions:")
            print("   • Verify checkpoint saving is enabled")
            print("   • Check checkpoint directory permissions")
            print("   • Ensure sufficient disk space")
            print("   • Force a manual checkpoint save")
            print("   • CRITICAL: Risk of losing training progress!")
            
        # Fall back to original loss warning method for loss-specific issues
        else:
            self._show_loss_warning(warning_type, *args)
            return
            
        print(f"{'='*80}")
        print("Note: Training will continue, but please consider applying these solutions.")
        print(f"{'='*80}\n")
    
    def _show_loss_warning(self, warning_type: str, *args):
        """Display specific loss warning with solutions (original method)."""
        # Update warning statistics for loss warnings too
        critical_loss_warnings = ['nan_loss', 'loss_explosion']
        is_critical = warning_type in critical_loss_warnings
        self._increment_warning_count(warning_type, is_critical)
        
        print(f"\n{'='*80}")
        if is_critical:
            print("🚨 CRITICAL TRAINING ANOMALY DETECTED")
        else:
            print("⚠️ TRAINING ANOMALY DETECTED")
        print(f"{'='*80}")
        
        if warning_type == "frequent_zero":
            zero_count, total_count = args
            print(f"⚠️  FREQUENT ZERO LOSSES: {zero_count}/{total_count} recent batches have zero loss")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too high causing gradient explosion/clipping")
            print("   2. Data preprocessing issues (all samples identical)")
            print("   3. Loss function implementation problems")
            print("   4. Gradient accumulation issues")
            print("   5. Mixed precision training problems")
            print("\n💡 Recommended Solutions:")
            print("   • Reduce learning rate by 10x (e.g., 0.001 → 0.0001)")
            print("   • Check data diversity: ensure different board positions")
            print("   • Disable mixed precision training temporarily")
            print("   • Verify gradient accumulation steps are correct")
            print("   • Check if loss function returns valid gradients")
            print("   • Add gradient clipping: torch.nn.utils.clip_grad_norm_()")
            
        elif warning_type == "nan_loss":
            loss_value = args[0]
            print(f"⚠️  NaN/Inf LOSS DETECTED: Loss = {loss_value}")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too high causing numerical instability")
            print("   2. Division by zero in loss calculation")
            print("   3. Log of zero or negative values")
            print("   4. Gradient explosion")
            print("   5. Invalid input data (NaN values)")
            print("\n💡 Recommended Solutions:")
            print("   • IMMEDIATELY reduce learning rate by 100x")
            print("   • Add numerical stability checks in loss function")
            print("   • Use gradient clipping with max_norm=1.0")
            print("   • Check input data for NaN/Inf values")
            print("   • Consider using more stable loss functions")
            print("   • Enable gradient debugging: check_grad=True")
            
        elif warning_type == "vanishing_gradients":
            small_count, total_count = args
            print(f"⚠️  VANISHING GRADIENTS: {small_count}/{total_count} losses are extremely small")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too small")
            print("   2. Network weights initialized poorly")
            print("   3. Activation functions causing gradient vanishing")
            print("   4. Network too deep without proper normalization")
            print("\n💡 Recommended Solutions:")
            print("   • Increase learning rate by 10x")
            print("   • Use better weight initialization (Xavier/He)")
            print("   • Add batch normalization or layer normalization")
            print("   • Check activation functions (avoid sigmoid in deep layers)")
            print("   • Use residual connections")
            print("   • Monitor gradient norms during training")
            
        elif warning_type == "loss_explosion":
            loss_value = args[0]
            print(f"⚠️  LOSS EXPLOSION: Loss = {loss_value:.6f} (very high)")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too high")
            print("   2. Gradient explosion")
            print("   3. Poor weight initialization")
            print("   4. Unstable training data")
            print("\n💡 Recommended Solutions:")
            print("   • IMMEDIATELY reduce learning rate by 10x")
            print("   • Add gradient clipping with max_norm=1.0")
            print("   • Use learning rate scheduling")
            print("   • Check data normalization")
            print("   • Consider warm-up learning rate schedule")
            
        elif warning_type == "loss_plateau":
            loss_std, loss_mean = args
            print(f"⚠️  LOSS PLATEAU: Loss stuck at {loss_mean:.6f} (std: {loss_std:.6f})")
            print("\n🔍 Possible Causes:")
            print("   1. Learning rate too small")
            print("   2. Model has converged (might be good!)")
            print("   3. Local minimum trap")
            print("   4. Insufficient model capacity")
            print("   5. Data not challenging enough")
            print("\n💡 Recommended Solutions:")
            print("   • Try learning rate scheduling (reduce on plateau)")
            print("   • Increase learning rate temporarily (learning rate cycling)")
            print("   • Add noise to gradients or weights")
            print("   • Check if loss is actually acceptable for your task")
            print("   • Consider early stopping if validation loss is good")
            print("   • Increase model complexity if underfitting")
        
        print(f"{'='*80}")
        print("Note: Training will continue, but please consider applying these solutions.")
        print(f"{'='*80}\n")
    
    def _report_epoch_loss_summary(self):
        """Report loss statistics summary for the current epoch."""
        if not self.loss_history:
            return
        
        # Calculate statistics
        total_losses = len(self.loss_history)
        zero_losses = sum(1 for loss in self.loss_history if abs(loss) < 1e-8)
        small_losses = sum(1 for loss in self.loss_history if 0 < loss < 1e-6)
        large_losses = sum(1 for loss in self.loss_history if loss > 10)
        
        # Only show summary if there are concerning patterns
        if zero_losses > 0 or small_losses > total_losses * 0.1 or large_losses > 0:
            print(f"   📊 Loss Health Check:")
            
            if zero_losses > 0:
                zero_pct = zero_losses / total_losses * 100
                status = "🚨" if zero_pct > 10 else "⚠️" if zero_pct > 5 else "ℹ️"
                print(f"      {status} Zero losses: {zero_losses}/{total_losses} ({zero_pct:.1f}%)")
            
            if small_losses > total_losses * 0.1:
                small_pct = small_losses / total_losses * 100
                print(f"      ⚠️ Very small losses: {small_losses}/{total_losses} ({small_pct:.1f}%)")
            
            if large_losses > 0:
                large_pct = large_losses / total_losses * 100
                print(f"      ⚠️ Large losses: {large_losses}/{total_losses} ({large_pct:.1f}%)")
            
            # Overall health indicator
            if zero_losses / total_losses > 0.2:
                print(f"      🚨 CRITICAL: >20% zero losses - check training setup!")
            elif zero_losses / total_losses > 0.1:
                print(f"      ⚠️ WARNING: >10% zero losses - training may be unstable")
            elif zero_losses == 0 and small_losses / total_losses < 0.05:
                print(f"      ✅ Loss distribution looks healthy")
    
    def _get_memory_status(self) -> Dict[str, float]:
        """Get current memory status."""
        try:
            memory_info = psutil.virtual_memory()
            return {
                'total_gb': memory_info.total / (1024**3),
                'available_gb': memory_info.available / (1024**3),
                'usage_percent': memory_info.percent
            }
        except Exception:
            return {'total_gb': 0, 'available_gb': 0, 'usage_percent': 0}
    
    def update_phase_statistics(self, phase: str, samples_count: int, loss_value: float, training_time: float):
        """Update statistics for a specific game phase."""
        if phase in self.phase_stats:
            stats = self.phase_stats[phase]
            stats['samples_trained'] += samples_count
            
            # Update moving average of loss
            if stats['samples_trained'] > 0:
                prev_total_loss = stats['avg_loss'] * (stats['samples_trained'] - samples_count)
                new_total_loss = prev_total_loss + (loss_value * samples_count)
                stats['avg_loss'] = new_total_loss / stats['samples_trained']
            
            stats['training_time'] += training_time
    
    def update_position_type_statistics(self, position_type: str, samples_count: int, loss_value: float):
        """Update statistics for specific position types."""
        if position_type in self.position_type_stats:
            stats = self.position_type_stats[position_type]
            stats['samples_trained'] += samples_count
            
            # Update moving average of loss
            if stats['samples_trained'] > 0:
                prev_total_loss = stats['avg_loss'] * (stats['samples_trained'] - samples_count)
                new_total_loss = prev_total_loss + (loss_value * samples_count)
                stats['avg_loss'] = new_total_loss / stats['samples_trained']
    
    def set_phase_totals(self, phase_totals: Dict[str, int]):
        """Set total sample counts for each phase from dataset analysis."""
        for phase, total in phase_totals.items():
            if phase in self.phase_stats:
                self.phase_stats[phase]['total_samples'] = total
    
    def display_training_progress_by_phase(self):
        """Display detailed training progress breakdown by game phase."""
        print(f"\n🎯 Training Progress by Game Phase:")
        print("-" * 80)
        
        total_trained = sum(stats['samples_trained'] for stats in self.phase_stats.values())
        total_available = sum(stats['total_samples'] for stats in self.phase_stats.values())
        
        for phase, stats in self.phase_stats.items():
            trained = stats['samples_trained']
            total = stats['total_samples']
            avg_loss = stats['avg_loss']
            training_time = stats['training_time']
            
            if total > 0:
                progress_percent = (trained / total) * 100
                progress_bar = self._create_progress_bar(progress_percent, 30)
                time_per_sample = training_time / trained if trained > 0 else 0
                
                print(f"  📍 {phase.capitalize():<10}: {trained:8,}/{total:8,} ({progress_percent:5.1f}%) {progress_bar}")
                print(f"     Loss: {avg_loss:.6f} | Time: {training_time:6.1f}s | Speed: {time_per_sample*1000:.2f}ms/sample")
            else:
                print(f"  📍 {phase.capitalize():<10}: No data available")
        
        if total_available > 0:
            overall_progress = (total_trained / total_available) * 100
            print(f"\n📊 Overall Progress: {total_trained:,}/{total_available:,} ({overall_progress:.1f}%)")
            
            # Identify phases that need more training
            phases_needing_training = []
            for phase, stats in self.phase_stats.items():
                if stats['total_samples'] > 0:
                    progress = (stats['samples_trained'] / stats['total_samples']) * 100
                    if progress < 80:  # Less than 80% complete
                        remaining = stats['total_samples'] - stats['samples_trained']
                        phases_needing_training.append((phase, progress, remaining))
            
            if phases_needing_training:
                print(f"\n🎯 Phases Requiring More Training:")
                phases_needing_training.sort(key=lambda x: x[1])  # Sort by progress percentage
                for phase, progress, remaining in phases_needing_training:
                    print(f"   • {phase.capitalize()}: {progress:.1f}% complete, {remaining:,} samples remaining")
            else:
                print(f"\n✅ All game phases have sufficient training coverage")
    
    def _display_chunk_composition(self, chunk_metadata: Dict[str, Any]):
        """Display the composition of game phases and position types in current chunk."""
        print(f"   📊 Chunk Composition Analysis:")
        
        # Display source files if available
        source_files = chunk_metadata.get('source_files', [])
        if source_files:
            print(f"      Source Files: {len(source_files)} files")
            # Show first few file names for debugging
            for i, filename in enumerate(source_files[:3]):
                print(f"        {i+1}. {filename}")
            if len(source_files) > 3:
                print(f"        ... and {len(source_files) - 3} more files")
        
        # Game phase distribution
        phase_counts = chunk_metadata.get('phase_distribution', {})
        if phase_counts:
            total_chunk_samples = sum(phase_counts.values())
            print(f"      Game Phases:")
            
            for phase, count in sorted(phase_counts.items()):
                percentage = (count / total_chunk_samples * 100) if total_chunk_samples > 0 else 0
                progress_bar = self._create_mini_progress_bar(percentage, 20)
                print(f"        {phase.capitalize():<10}: {count:6,} samples ({percentage:5.1f}%) {progress_bar}")
        
        # Position type distribution
        position_types = chunk_metadata.get('position_types', {})
        if position_types:
            print(f"      Position Types:")
            total_positions = sum(position_types.values())
            
            for pos_type, count in sorted(position_types.items()):
                percentage = (count / total_positions * 100) if total_positions > 0 else 0
                progress_bar = self._create_mini_progress_bar(percentage, 20)
                print(f"        {pos_type.replace('_', ' ').title():<15}: {count:6,} samples ({percentage:5.1f}%) {progress_bar}")
        
        # Difficulty distribution
        difficulty_dist = chunk_metadata.get('difficulty_distribution', {})
        if difficulty_dist:
            print(f"      Difficulty Levels:")
            total_difficulty = sum(difficulty_dist.values())
            
            for level, count in sorted(difficulty_dist.items()):
                percentage = (count / total_difficulty * 100) if total_difficulty > 0 else 0
                progress_bar = self._create_mini_progress_bar(percentage, 20)
                print(f"        {level.capitalize():<10}: {count:6,} samples ({percentage:5.1f}%) {progress_bar}")
    
    def _create_mini_progress_bar(self, percentage: float, width: int = 20) -> str:
        """Create a small progress bar for composition display."""
        filled_length = int(width * percentage / 100)
        bar = '█' * filled_length + '░' * (width - filled_length)
        return f"|{bar}|"


class MemoryMonitor:
    """Enhanced memory monitoring with safety mechanisms."""
    
    def __init__(self, 
                 memory_threshold_gb: float = 32.0,
                 swap_threshold_gb: float = 2.0,
                 critical_threshold_gb: float = 8.0):
        """
        Initialize memory monitor.
        
        Args:
            memory_threshold_gb: Safe memory threshold (GB)
            swap_threshold_gb: Maximum allowed swap increase (GB)
            critical_threshold_gb: Critical memory level (GB)
        """
        self.memory_threshold_gb = memory_threshold_gb
        self.swap_threshold_gb = swap_threshold_gb
        self.critical_threshold_gb = critical_threshold_gb
        
        # Baseline measurements
        self.baseline_memory_info = psutil.virtual_memory()
        self.baseline_swap_info = psutil.swap_memory()
        self.baseline_swap_mb = self.baseline_swap_info.used / (1024**2)
        
        logger.info(f"Memory Monitor initialized:")
        logger.info(f"  Total Memory: {self.baseline_memory_info.total / (1024**3):.1f} GB")
        logger.info(f"  Available Memory: {self.baseline_memory_info.available / (1024**3):.1f} GB")
        logger.info(f"  Baseline Swap: {self.baseline_swap_mb:.1f} MB")
        logger.info(f"  Memory Threshold: {memory_threshold_gb:.1f} GB")
        logger.info(f"  Swap Threshold: {swap_threshold_gb:.1f} GB")
    
    def get_memory_status(self) -> Dict[str, float]:
        """Get current memory status."""
        memory_info = psutil.virtual_memory()
        swap_info = psutil.swap_memory()
        
        current_swap_mb = swap_info.used / (1024**2)
        swap_increase_mb = current_swap_mb - self.baseline_swap_mb
        
        return {
            'total_gb': memory_info.total / (1024**3),
            'available_gb': memory_info.available / (1024**3),
            'used_gb': memory_info.used / (1024**3),
            'usage_percent': memory_info.percent,
            'swap_used_mb': current_swap_mb,
            'swap_increase_mb': swap_increase_mb,
            'is_safe': self._is_memory_safe(memory_info, swap_increase_mb)
        }
    
    def _is_memory_safe(self, memory_info, swap_increase_mb: float) -> bool:
        """Check if current memory usage is safe."""
        available_gb = memory_info.available / (1024**3)
        
        # Check available memory
        if available_gb < self.critical_threshold_gb:
            return False
        
        # Check swap increase
        if swap_increase_mb > self.swap_threshold_gb * 1024:
            return False
        
        return True
    
    def check_memory_safety(self, raise_on_critical: bool = True) -> bool:
        """
        Check memory safety and optionally raise exception on critical levels.
        
        Args:
            raise_on_critical: Whether to raise exception on critical memory levels
            
        Returns:
            True if memory is safe, False otherwise
            
        Raises:
            RuntimeError: If memory is critically low and raise_on_critical=True
        """
        status = self.get_memory_status()
        
        if not status['is_safe']:
            if status['available_gb'] < self.critical_threshold_gb:
                msg = f"Critical memory level: {status['available_gb']:.1f} GB available"
                logger.error(f"🚨 {msg}")
                if raise_on_critical:
                    raise RuntimeError(msg)
                return False
            
            if status['swap_increase_mb'] > self.swap_threshold_gb * 1024:
                msg = f"Excessive swap usage: {status['swap_increase_mb']:.1f} MB increase"
                logger.error(f"🚨 {msg}")
                if raise_on_critical:
                    raise RuntimeError(msg)
                return False
        
        return True
    
    def force_memory_cleanup(self):
        """Force aggressive memory cleanup."""
        logger.info("🧹 Forcing memory cleanup...")
        
        # Python garbage collection
        collected = gc.collect()
        logger.debug(f"Collected {collected} objects")
        
        # PyTorch cache cleanup
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            logger.debug("Cleared CUDA cache")
        
        # Force another GC pass
        gc.collect()
        
        # Wait a moment for system cleanup
        time.sleep(1.0)
        
        status = self.get_memory_status()
        logger.info(f"After cleanup: {status['available_gb']:.1f} GB available")
    


class ChunkedCheckpointManager:
    """Enhanced checkpoint manager for chunked training with anomaly tracking."""
    
    def __init__(self, checkpoint_dir: str, keep_n_checkpoints: int = 5):
        """
        Initialize checkpoint manager for chunked training.
        
        Args:
            checkpoint_dir: Directory to store checkpoints
            keep_n_checkpoints: Number of recent checkpoints to keep
        """
        self.checkpoint_dir = Path(checkpoint_dir)
        self.keep_n_checkpoints = keep_n_checkpoints
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)
        
        # Track checkpoint health
        self.checkpoint_health = {}  # epoch -> health_score
        self.last_healthy_checkpoint = None
        
        logger.info(f"ChunkedCheckpointManager initialized: {checkpoint_dir}")
    
    def save_checkpoint(self, neural_network, epoch: int, optimizer_state: Dict,
                       loss_history: List[float], config: Dict[str, Any],
                       warning_stats: Dict[str, int], training_metrics: Dict[str, Any]) -> str:
        """
        Save a training checkpoint with health information.
        
        Args:
            neural_network: Neural network to save
            epoch: Current epoch number
            optimizer_state: Optimizer state dict
            loss_history: Training loss history
            config: Training configuration
            warning_stats: Warning statistics from training
            training_metrics: Additional training metrics
            
        Returns:
            Path to saved checkpoint
        """
        checkpoint_path = self.checkpoint_dir / f"chunked_checkpoint_epoch_{epoch}.tar"
        
        # Calculate checkpoint health score
        health_score = self._calculate_health_score(loss_history, warning_stats, training_metrics)
        
        # Save the neural network
        neural_network.save(str(checkpoint_path))
        
        # Save comprehensive training state
        state_path = self.checkpoint_dir / f"chunked_training_state_epoch_{epoch}.json"
        training_state = {
            'epoch': epoch,
            'optimizer_state_dict': optimizer_state,
            'loss_history': loss_history,
            'config': config,
            'warning_stats': warning_stats,
            'training_metrics': training_metrics,
            'health_score': health_score,
            'save_timestamp': time.time(),
            'is_healthy': health_score > 0.7  # Threshold for healthy checkpoint
        }
        
        with open(state_path, 'w') as f:
            json.dump(training_state, f, indent=2, default=str)
        
        # Update health tracking
        self.checkpoint_health[epoch] = health_score
        if health_score > 0.7:  # Consider checkpoint healthy
            self.last_healthy_checkpoint = str(checkpoint_path)
        
        # Clean up old checkpoints
        self._cleanup_old_checkpoints()
        
        # Display checkpoint health
        health_status = "✅ Healthy" if health_score > 0.7 else "⚠️ Warning" if health_score > 0.4 else "🚨 Poor"
        print(f"💾 Checkpoint saved: Epoch {epoch}")
        print(f"   Health Score: {health_score:.2f} ({health_status})")
        print(f"   Warnings: {warning_stats.get('total_warnings', 0)} total")
        print(f"   Path: {checkpoint_path}")
        
        return str(checkpoint_path)
    
    def get_latest_checkpoint(self) -> Optional[str]:
        """Get the path to the latest checkpoint."""
        checkpoint_pattern = self.checkpoint_dir / "chunked_checkpoint_epoch_*.tar"
        checkpoints = glob.glob(str(checkpoint_pattern))
        
        if not checkpoints:
            return None
        
        # Sort by epoch number
        def extract_epoch(path):
            try:
                filename = Path(path).stem
                return int(filename.split('_')[-1])
            except (ValueError, IndexError):
                return 0
        
        latest = max(checkpoints, key=extract_epoch)
        return latest
    
    def get_healthiest_checkpoint(self) -> Optional[str]:
        """Get the path to the healthiest (most reliable) checkpoint."""
        checkpoints = self.list_available_checkpoints()
        
        if not checkpoints:
            return None
        
        # Find checkpoint with highest health score
        healthiest = max(checkpoints, key=lambda x: x['health_score'])
        return healthiest['path']
    
    def list_available_checkpoints(self) -> List[Dict[str, Any]]:
        """List all available checkpoints with their health information."""
        checkpoints = []
        
        checkpoint_pattern = self.checkpoint_dir / "chunked_checkpoint_epoch_*.tar"
        checkpoint_files = glob.glob(str(checkpoint_pattern))
        
        for checkpoint_path in checkpoint_files:
            epoch = self._extract_epoch_from_path(checkpoint_path)
            
            # Load training state if available
            state_path = self.checkpoint_dir / f"chunked_training_state_epoch_{epoch}.json"
            health_score = 0.5  # Default medium health
            warning_count = 0
            is_healthy = False
            
            if state_path.exists():
                try:
                    with open(state_path, 'r') as f:
                        state = json.load(f)
                    
                    health_score = state.get('health_score', health_score)
                    warning_count = state.get('warning_stats', {}).get('total_warnings', 0)
                    is_healthy = state.get('is_healthy', is_healthy)
                    
                except Exception:
                    pass
            
            checkpoints.append({
                'epoch': epoch,
                'path': checkpoint_path,
                'health_score': health_score,
                'warning_count': warning_count,
                'is_healthy': is_healthy,
                'file_size_mb': Path(checkpoint_path).stat().st_size / (1024**2)
            })
        
        # Sort by epoch
        checkpoints.sort(key=lambda x: x['epoch'])
        return checkpoints
    
    def load_checkpoint(self, neural_network, checkpoint_path: str) -> Dict[str, Any]:
        """Load a training checkpoint with health verification."""
        # Load the neural network
        success = neural_network.load(checkpoint_path)
        if not success:
            raise RuntimeError(f"Failed to load neural network from {checkpoint_path}")
        
        # Load training state
        epoch = self._extract_epoch_from_path(checkpoint_path)
        state_path = self.checkpoint_dir / f"chunked_training_state_epoch_{epoch}.json"
        
        if state_path.exists():
            with open(state_path, 'r') as f:
                training_state = json.load(f)
            
            # Verify checkpoint health
            health_score = training_state.get('health_score', 0.5)
            is_healthy = training_state.get('is_healthy', False)
            
            print(f"📂 Loaded checkpoint from epoch {epoch}")
            print(f"   Health Score: {health_score:.2f}")
            print(f"   Status: {'✅ Healthy' if is_healthy else '⚠️ Has Issues'}")
            
            if not is_healthy:
                print("⚠️ WARNING: This checkpoint was saved during problematic training")
                print("   Consider using a healthier checkpoint if available")
            
            return training_state
        else:
            # Fallback for checkpoints without detailed state
            return {
                'epoch': epoch,
                'optimizer_state_dict': {},
                'loss_history': [],
                'config': {},
                'warning_stats': {'total_warnings': 0},
                'health_score': 0.5,
                'is_healthy': False
            }
    
    def _calculate_health_score(self, loss_history: List[float], 
                              warning_stats: Dict[str, int],
                              training_metrics: Dict[str, Any]) -> float:
        """
        Calculate health score for a checkpoint (0.0 = poor, 1.0 = excellent).
        
        Args:
            loss_history: Recent loss history
            warning_stats: Warning statistics
            training_metrics: Training performance metrics
            
        Returns:
            Health score between 0.0 and 1.0
        """
        score = 1.0
        
        # Penalize based on warnings
        total_warnings = warning_stats.get('total_warnings', 0)
        critical_warnings = warning_stats.get('critical_warnings', 0)
        
        # Critical warnings heavily penalize health
        score -= critical_warnings * 0.3
        
        # Regular warnings mildly penalize health
        score -= min(total_warnings * 0.05, 0.4)
        
        # Check loss stability
        if loss_history and len(loss_history) >= 5:
            recent_losses = loss_history[-5:]
            
            # Penalize for zero losses
            zero_count = sum(1 for loss in recent_losses if abs(loss) < 1e-8)
            score -= zero_count * 0.1
            
            # Penalize for NaN losses
            nan_count = sum(1 for loss in recent_losses if not np.isfinite(loss))
            score -= nan_count * 0.2
            
            # Reward for decreasing loss trend
            if len(loss_history) >= 10:
                older_avg = np.mean(loss_history[-10:-5])
                recent_avg = np.mean(recent_losses)
                if recent_avg < older_avg:
                    score += 0.1  # Bonus for improving
        
        # Ensure score is in valid range
        return max(0.0, min(1.0, score))
    
    def _extract_epoch_from_path(self, checkpoint_path: str) -> int:
        """Extract epoch number from checkpoint path."""
        try:
            filename = Path(checkpoint_path).stem
            return int(filename.split('_')[-1])
        except (ValueError, IndexError):
            return 0
    
    def _cleanup_old_checkpoints(self):
        """Remove old checkpoints to save disk space, keeping the healthiest ones."""
        checkpoint_pattern = self.checkpoint_dir / "chunked_checkpoint_epoch_*.tar"
        
        checkpoints = glob.glob(str(checkpoint_pattern))
        
        if len(checkpoints) <= self.keep_n_checkpoints:
            return
        
        # Get checkpoint health scores
        checkpoint_health_list = []
        for checkpoint in checkpoints:
            epoch = self._extract_epoch_from_path(checkpoint)
            health_score = self.checkpoint_health.get(epoch, 0.5)
            checkpoint_health_list.append((checkpoint, epoch, health_score))
        
        # Sort by health score (descending) and then by epoch (descending)
        checkpoint_health_list.sort(key=lambda x: (x[2], x[1]), reverse=True)
        
        # Keep the best checkpoints
        to_keep = checkpoint_health_list[:self.keep_n_checkpoints]
        to_remove = checkpoint_health_list[self.keep_n_checkpoints:]
        
        # Remove old/unhealthy checkpoints
        for checkpoint_path, epoch, health_score in to_remove:
            try:
                os.remove(checkpoint_path)
                logger.info(f"Removed checkpoint: epoch {epoch} (health: {health_score:.2f})")
                
                # Remove corresponding state file
                state_path = self.checkpoint_dir / f"chunked_training_state_epoch_{epoch}.json"
                if state_path.exists():
                    os.remove(state_path)
                    
            except OSError as e:
                logger.warning(f"Failed to remove checkpoint {checkpoint_path}: {e}")


class DatasetScanner:
    """Scans NPZ data directory to calculate dataset statistics and training estimates."""
    
    def __init__(self, data_dir: str):
        """
        Initialize dataset scanner.
        
        Args:
            data_dir: Path to preprocessed NPZ data directory
        """
        self.data_dir = Path(data_dir)
        self.scan_results = {}
        self.total_size_bytes = 0
        self.total_files = 0
        self.total_samples_estimate = 0
        
    def scan_dataset(self) -> Dict[str, Any]:
        """
        Scan the entire dataset directory to get accurate statistics.
        
        Returns:
            Dictionary with dataset statistics and training estimates
        """
        logger.info(f"🔍 Scanning dataset directory: {self.data_dir}")
        start_time = time.time()
        
        # Find all NPZ files
        npz_files = list(self.data_dir.glob("*.npz"))
        self.total_files = len(npz_files)
        
        if not npz_files:
            logger.warning("No NPZ files found in dataset directory")
            return self._create_empty_results()
        
        # Scan files to get sizes and sample counts
        total_size = 0
        total_samples = 0
        file_stats = []
        
        # Phase distribution tracking
        phase_distribution = {'placement': 0, 'moving': 0, 'flying': 0, 'removal': 0}
        
        print(f"📊 Scanning {self.total_files} NPZ files for composition analysis...")
        
        for i, npz_file in enumerate(npz_files):
            file_size = npz_file.stat().st_size
            total_size += file_size
            
            # Try to get actual sample count from file
            try:
                with np.load(npz_file, allow_pickle=True) as data:
                    if 'board_tensors' in data:
                        samples_in_file = len(data['board_tensors'])
                        
                        # Analyze phase distribution if metadata is available
                        if 'metadata_list' in data:
                            metadata_list = data['metadata_list']
                            file_phase_dist = self._analyze_file_phase_distribution(metadata_list)
                            
                            # Add to global phase distribution
                            for phase, count in file_phase_dist.items():
                                if phase in phase_distribution:
                                    phase_distribution[phase] += count
                    else:
                        # Estimate based on file size
                        samples_in_file = max(1, file_size // 12000)  # Conservative estimate
                    
                    total_samples += samples_in_file
                    file_stats.append({
                        'filename': npz_file.name,
                        'size_bytes': file_size,
                        'samples': samples_in_file
                    })
                    
            except Exception as e:
                # If can't read file, estimate samples
                logger.debug(f"Could not read {npz_file.name}: {e}")
                estimated_samples = max(1, file_size // 12000)
                total_samples += estimated_samples
                file_stats.append({
                    'filename': npz_file.name,
                    'size_bytes': file_size,
                    'samples': estimated_samples
                })
            
            # Progress indicator
            if (i + 1) % 10 == 0 or i == len(npz_files) - 1:
                progress = (i + 1) / len(npz_files) * 100
                print(f"\r   Progress: {progress:5.1f}% ({i + 1}/{len(npz_files)} files)", end='', flush=True)
        
        print()  # New line after progress
        
        self.total_size_bytes = total_size
        self.total_samples_estimate = total_samples
        
        scan_time = time.time() - start_time
        
        # Calculate statistics
        avg_file_size = total_size / len(npz_files) if npz_files else 0
        avg_samples_per_file = total_samples / len(npz_files) if npz_files else 0
        
        # Create scan results
        self.scan_results = {
            'total_files': self.total_files,
            'total_size_bytes': total_size,
            'total_size_gb': total_size / (1024**3),
            'total_samples': total_samples,
            'avg_file_size_mb': avg_file_size / (1024**2),
            'avg_samples_per_file': avg_samples_per_file,
            'scan_time_seconds': scan_time,
            'file_stats': file_stats,
            'bytes_per_sample_actual': total_size / total_samples if total_samples > 0 else 12000,
            'phase_distribution': phase_distribution
        }
        
        logger.info(f"✅ Dataset scan completed in {scan_time:.1f}s:")
        logger.info(f"   Total files: {self.total_files:,}")
        logger.info(f"   Total size: {total_size / (1024**3):.2f} GB")
        logger.info(f"   Total samples: {total_samples:,}")
        logger.info(f"   Average file size: {avg_file_size / (1024**2):.1f} MB")
        logger.info(f"   Bytes per sample: {self.scan_results['bytes_per_sample_actual']:.0f}")
        
        # Display phase distribution from scan
        if any(count > 0 for count in phase_distribution.values()):
            print(f"\n📊 Dataset Phase Distribution:")
            for phase, count in sorted(phase_distribution.items()):
                percentage = (count / total_samples * 100) if total_samples > 0 else 0
                print(f"   {phase.capitalize():<10}: {count:8,} samples ({percentage:5.1f}%)")
        
        return self.scan_results
    
    def _analyze_file_phase_distribution(self, metadata_list) -> Dict[str, int]:
        """Analyze phase distribution in a single file."""
        phase_counts = {'placement': 0, 'moving': 0, 'flying': 0, 'removal': 0}
        
        for metadata in metadata_list:
            if isinstance(metadata, dict):
                # Determine game phase from metadata
                pieces_in_hand = metadata.get('white_pieces_in_hand', 0) + metadata.get('black_pieces_in_hand', 0)
                pieces_on_board = metadata.get('white_pieces_on_board', 0) + metadata.get('black_pieces_on_board', 0)
                is_removal = metadata.get('is_removal_phase', False)
                
                if is_removal:
                    phase_counts['removal'] += 1
                elif pieces_in_hand > 0:
                    phase_counts['placement'] += 1
                elif pieces_on_board <= 6:  # 3 pieces per side or less
                    phase_counts['flying'] += 1
                else:
                    phase_counts['moving'] += 1
        
        return phase_counts
    
    def _create_empty_results(self) -> Dict[str, Any]:
        """Create empty results when no files found."""
        return {
            'total_files': 0,
            'total_size_bytes': 0,
            'total_size_gb': 0,
            'total_samples': 0,
            'avg_file_size_mb': 0,
            'avg_samples_per_file': 0,
            'scan_time_seconds': 0,
            'file_stats': [],
            'bytes_per_sample_actual': 12000
        }
    
    def estimate_training_time(self, 
                              epochs: int, 
                              batch_size: int,
                              estimated_samples_per_second: float = 1000) -> Dict[str, float]:
        """
        Estimate total training time based on dataset size.
        
        Args:
            epochs: Number of training epochs
            batch_size: Training batch size
            estimated_samples_per_second: Estimated processing speed
            
        Returns:
            Dictionary with time estimates
        """
        if self.total_samples_estimate == 0:
            return {'total_hours': 0, 'total_minutes': 0, 'per_epoch_minutes': 0}
        
        total_batches = (self.total_samples_estimate + batch_size - 1) // batch_size
        total_batches_all_epochs = total_batches * epochs
        
        # Estimate time in seconds
        estimated_seconds = self.total_samples_estimate * epochs / estimated_samples_per_second
        
        # Add overhead for chunk switching, memory cleanup, etc. (20% overhead)
        estimated_seconds_with_overhead = estimated_seconds * 1.2
        
        return {
            'total_seconds': estimated_seconds_with_overhead,
            'total_minutes': estimated_seconds_with_overhead / 60,
            'total_hours': estimated_seconds_with_overhead / 3600,
            'per_epoch_seconds': estimated_seconds_with_overhead / epochs,
            'per_epoch_minutes': estimated_seconds_with_overhead / epochs / 60,
            'total_batches': total_batches_all_epochs,
            'batches_per_epoch': total_batches
        }


class ChunkedDataLoader:
    """Chunked data loader that splits large datasets into memory-safe chunks."""
    
    def __init__(self,
                 data_loader: FastDataLoader,
                 memory_monitor: MemoryMonitor,
                 target_chunk_memory_gb: float = 16.0,
                 min_chunk_size: int = 1000,
                 dataset_scanner: Optional[DatasetScanner] = None):
        """
        Initialize chunked data loader.
        
        Args:
            data_loader: Base data loader
            memory_monitor: Memory monitor instance
            target_chunk_memory_gb: Target memory usage per chunk (GB)
            min_chunk_size: Minimum samples per chunk
            dataset_scanner: Optional dataset scanner for accurate estimates
        """
        self.data_loader = data_loader
        self.memory_monitor = memory_monitor
        self.target_chunk_memory_gb = target_chunk_memory_gb
        self.min_chunk_size = min_chunk_size
        self.dataset_scanner = dataset_scanner
        
        # Use actual bytes per sample if scanner is available
        if dataset_scanner and dataset_scanner.scan_results:
            self.bytes_per_sample = int(dataset_scanner.scan_results.get('bytes_per_sample_actual', 12000))
        else:
            # Estimate bytes per sample (conservative)
            # Board: 19*7*7*4 = 3724 bytes
            # Policy: 1000*4 = 4000 bytes  
            # Value: 4 bytes
            # Metadata + overhead: ~4000 bytes
            self.bytes_per_sample = 12000  # Conservative estimate
        
        logger.info(f"ChunkedDataLoader initialized:")
        logger.info(f"  Target chunk memory: {target_chunk_memory_gb:.1f} GB")
        logger.info(f"  Bytes per sample: {self.bytes_per_sample}")
        logger.info(f"  Min chunk size: {min_chunk_size}")
    
    def calculate_safe_chunk_size(self, total_samples: int) -> int:
        """Calculate safe chunk size based on available memory."""
        status = self.memory_monitor.get_memory_status()
        available_gb = status['available_gb']
        
        # Use conservative memory allocation (50% of available or target, whichever is smaller)
        safe_memory_gb = min(
            available_gb * 0.5,
            self.target_chunk_memory_gb,
            available_gb - self.memory_monitor.critical_threshold_gb
        )
        
        if safe_memory_gb < 1.0:
            logger.warning(f"Very low memory available: {available_gb:.1f} GB")
            safe_memory_gb = 1.0
        
        # Calculate chunk size
        chunk_size = int(safe_memory_gb * 1024**3 / self.bytes_per_sample)
        chunk_size = max(chunk_size, self.min_chunk_size)
        chunk_size = min(chunk_size, total_samples)
        
        logger.info(f"Calculated chunk size: {chunk_size:,} samples ({safe_memory_gb:.1f} GB)")
        
        return chunk_size
    
    def create_chunks(self,
                     total_samples: int,
                     phase_filter: Optional[str] = None) -> List[ChunkInfo]:
        """Create chunk information for the dataset."""
        chunk_size = self.calculate_safe_chunk_size(total_samples)
        
        chunks = []
        for i in range(0, total_samples, chunk_size):
            end_pos = min(i + chunk_size, total_samples)
            num_samples = end_pos - i
            estimated_memory_mb = (num_samples * self.bytes_per_sample) / (1024**2)
            
            chunk = ChunkInfo(
                chunk_id=len(chunks),
                start_position=i,
                end_position=end_pos,
                estimated_memory_mb=estimated_memory_mb,
                num_samples=num_samples,
                phase_filter=phase_filter
            )
            chunks.append(chunk)
        
        logger.info(f"Created {len(chunks)} chunks:")
        for chunk in chunks:
            logger.info(f"  Chunk {chunk.chunk_id}: {chunk.num_samples:,} samples "
                       f"({chunk.estimated_memory_mb:.1f} MB)")
        
        return chunks
    
    def load_chunk_data(self, chunk: ChunkInfo) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, List[Dict], Dict[str, Any]]:
        """Load data for a specific chunk."""
        logger.info(f"Loading chunk {chunk.chunk_id}: samples {chunk.start_position}-{chunk.end_position}")
        
        # Check memory before loading
        self.memory_monitor.check_memory_safety()
        
        # Load data with position limits
        board_tensors, policy_targets, value_targets, metadata_list = \
            self.data_loader.load_training_data(
                phase_filter=chunk.phase_filter,
                max_positions=chunk.num_samples,
                shuffle=False,  # Don't shuffle individual chunks
                trap_ratio=0.0  # Apply trap ratio at global level, not per chunk
            )
        
        # Slice to exact chunk range if needed
        if len(board_tensors) > chunk.num_samples:
            board_tensors = board_tensors[:chunk.num_samples]
            policy_targets = policy_targets[:chunk.num_samples]
            value_targets = value_targets[:chunk.num_samples]
            metadata_list = metadata_list[:chunk.num_samples]
        
        # Convert to tensors
        board_tensors = torch.FloatTensor(board_tensors)
        policy_targets = torch.FloatTensor(policy_targets)
        value_targets = torch.FloatTensor(value_targets)
        
        # Collect source file information from metadata
        source_files = set()
        for metadata in metadata_list:
            if isinstance(metadata, dict):
                # Try different possible field names for source file
                source_file = metadata.get('source_file') or metadata.get('sector_filename') or metadata.get('filename')
                if source_file:
                    source_files.add(source_file)
        
        # Analyze chunk composition
        chunk_metadata = self._analyze_chunk_composition(metadata_list)
        
        # Add source file information to chunk metadata
        if source_files:
            chunk_metadata['source_files'] = sorted(list(source_files))
        
        # Verify memory status after loading
        status = self.memory_monitor.get_memory_status()
        logger.info(f"Chunk loaded: {len(board_tensors):,} samples, "
                   f"{status['available_gb']:.1f} GB available")
        
        return board_tensors, policy_targets, value_targets, metadata_list, chunk_metadata
    
    def _analyze_chunk_composition(self, metadata_list: List[Dict]) -> Dict[str, Any]:
        """Analyze the composition of a chunk by game phases and position types."""
        if not metadata_list:
            return {}
        
        # Initialize counters
        phase_counts = {'placement': 0, 'moving': 0, 'flying': 0, 'removal': 0}
        position_types = {'trap_positions': 0, 'critical_positions': 0, 'endgame_positions': 0, 'opening_positions': 0}
        difficulty_dist = {'easy': 0, 'medium': 0, 'hard': 0, 'expert': 0}
        
        # Analyze each sample's metadata
        for metadata in metadata_list:
            # Game phase analysis
            if isinstance(metadata, dict):
                # Use existing game_phase field if available, otherwise fall back to calculation
                game_phase = metadata.get('game_phase', '').lower()
                
                # Debug: Print some sample metadata to understand the issue
                total_classified = sum(phase_counts.values())
                if total_classified < 5:
                    print(f"🔍 Sample metadata #{total_classified}: game_phase='{game_phase}', sector_file='{metadata.get('sector_filename', 'N/A')}'")
                    print(f"    Full metadata keys: {list(metadata.keys())}")
                
                if game_phase in ['placement', 'moving', 'flying', 'removal']:
                    # Use the existing game_phase classification
                    phase_counts[game_phase] += 1
                else:
                    # Fallback to calculation if game_phase is not available or invalid
                    pieces_in_hand = metadata.get('white_pieces_in_hand', 0) + metadata.get('black_pieces_in_hand', 0)
                    pieces_on_board = metadata.get('white_pieces_on_board', 0) + metadata.get('black_pieces_on_board', 0)
                    is_removal = metadata.get('is_removal_phase', False)
                    
                    if is_removal:
                        phase_counts['removal'] += 1
                    elif pieces_in_hand > 0:
                        phase_counts['placement'] += 1
                    elif pieces_on_board <= 6:  # 3 pieces per side or less
                        phase_counts['flying'] += 1
                    else:
                        phase_counts['moving'] += 1
                
                # Position type analysis
                is_trap = metadata.get('is_trap', False)
                difficulty = metadata.get('difficulty', 0.0)
                steps_to_result = metadata.get('steps_to_result', -1)
                
                # Get pieces info for position type classification
                pieces_in_hand = metadata.get('white_pieces_in_hand', 0) + metadata.get('black_pieces_in_hand', 0)
                pieces_on_board = metadata.get('white_pieces_on_board', 0) + metadata.get('black_pieces_on_board', 0)
                
                if is_trap:
                    position_types['trap_positions'] += 1
                elif steps_to_result >= 0 and steps_to_result <= 5:
                    position_types['critical_positions'] += 1
                elif pieces_on_board <= 8:
                    position_types['endgame_positions'] += 1
                elif pieces_in_hand >= 6:
                    position_types['opening_positions'] += 1
                
                # Difficulty classification
                if difficulty == 0.0:
                    difficulty_dist['easy'] += 1
                elif difficulty < 1.0:
                    difficulty_dist['medium'] += 1
                elif difficulty < 2.0:
                    difficulty_dist['hard'] += 1
                else:
                    difficulty_dist['expert'] += 1
        
        return {
            'phase_distribution': phase_counts,
            'position_types': position_types,
            'difficulty_distribution': difficulty_dist,
            'total_samples': len(metadata_list)
        }


class ChunkedTrainer:
    """Chunked trainer that handles memory-safe training on large datasets."""
    
    def __init__(self,
                 neural_network: AlphaZeroNetworkWrapper,
                 data_loader: FastDataLoader,
                 memory_threshold_gb: float = 32.0,
                 target_chunk_memory_gb: float = 16.0):
        """
        Initialize chunked trainer.
        
        Args:
            neural_network: Neural network to train
            data_loader: Data loader instance
            memory_threshold_gb: Memory safety threshold
            target_chunk_memory_gb: Target memory per chunk
        """
        self.neural_network = neural_network
        self.data_loader = data_loader
        
        # Initialize memory monitor
        self.memory_monitor = MemoryMonitor(
            memory_threshold_gb=memory_threshold_gb,
            swap_threshold_gb=2.0,
            critical_threshold_gb=8.0
        )
        
        # Initialize dataset scanner
        self.dataset_scanner = DatasetScanner(data_loader.data_dir)
        
        # Initialize chunked loader with scanner
        self.chunked_loader = ChunkedDataLoader(
            data_loader=data_loader,
            memory_monitor=self.memory_monitor,
            target_chunk_memory_gb=target_chunk_memory_gb,
            dataset_scanner=self.dataset_scanner
        )
        
        # Initialize checkpoint manager (will be set during training)
        self.checkpoint_manager = None
        
        logger.info("ChunkedTrainer initialized")
    
    def train_chunked(self,
                     epochs: int = 10,
                     batch_size: int = 64,
                     learning_rate: float = 1e-3,
                     max_positions: Optional[int] = None,
                     phase_filter: Optional[str] = None,
                     gradient_accumulation_steps: int = 1,
                     save_checkpoint_every: int = 5,
                     checkpoint_dir: str = "checkpoints_chunked",
                     auto_resume: bool = True) -> Dict[str, Any]:
        """
        Train the neural network using chunked approach.
        
        Args:
            epochs: Number of training epochs
            batch_size: Batch size for training
            learning_rate: Learning rate
            max_positions: Maximum positions to use (None for all)
            phase_filter: Game phase filter
            gradient_accumulation_steps: Gradient accumulation steps
            save_checkpoint_every: Save checkpoint every N epochs
            checkpoint_dir: Directory to save checkpoints
            auto_resume: Automatically handle checkpoint resumption
            
        Returns:
            Training statistics
        """
        logger.info("🚀 Starting chunked training...")
        logger.info(f"  Epochs: {epochs}")
        logger.info(f"  Batch size: {batch_size}")
        logger.info(f"  Learning rate: {learning_rate}")
        logger.info(f"  Max positions: {max_positions or 'All'}")
        logger.info(f"  Gradient accumulation: {gradient_accumulation_steps}")
        
        # Scan dataset for accurate statistics and time estimation
        print("\n🔍 Scanning dataset for accurate training estimates...")
        scan_results = self.dataset_scanner.scan_dataset()
        
        # Display scan results
        print(f"\n📊 Dataset Analysis Results:")
        print(f"   Total NPZ files: {scan_results['total_files']:,}")
        print(f"   Total dataset size: {scan_results['total_size_gb']:.2f} GB")
        print(f"   Total training samples: {scan_results['total_samples']:,}")
        print(f"   Average file size: {scan_results['avg_file_size_mb']:.1f} MB")
        print(f"   Bytes per sample: {scan_results['bytes_per_sample_actual']:.0f}")
        
        # Get actual total sample count
        total_samples = scan_results['total_samples']
        if max_positions:
            total_samples = min(total_samples, max_positions)
            print(f"   Limited to: {total_samples:,} samples (due to max_positions)")
        
        # Estimate training time
        time_estimates = self.dataset_scanner.estimate_training_time(
            epochs=epochs,
            batch_size=batch_size,
            estimated_samples_per_second=1000  # Conservative estimate, will be updated during training
        )
        
        print(f"\n⏱️  Training Time Estimates (initial):")
        print(f"   Estimated total time: {time_estimates['total_hours']:.1f} hours ({time_estimates['total_minutes']:.0f} minutes)")
        print(f"   Estimated time per epoch: {time_estimates['per_epoch_minutes']:.1f} minutes")
        print(f"   Total batches: {time_estimates['total_batches']:,}")
        print(f"   Batches per epoch: {time_estimates['batches_per_epoch']:,}")
        print(f"   Note: These estimates will be refined during training based on actual performance")
        
        # Initialize optimizer
        optimizer = torch.optim.Adam(
            self.neural_network.net.parameters(),
            lr=learning_rate,
            weight_decay=1e-4
        )
        
        # Learning rate scheduler
        scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
            optimizer, T_0=5, T_mult=2, eta_min=1e-5
        )
        
        # Initialize checkpoint manager
        self.checkpoint_manager = ChunkedCheckpointManager(
            checkpoint_dir=checkpoint_dir,
            keep_n_checkpoints=5
        )
        
        # Handle checkpoint resumption
        start_epoch = 0
        loss_history = []
        
        if auto_resume:
            resume_checkpoint = self._handle_checkpoint_resumption()
            if resume_checkpoint:
                try:
                    training_state = self.checkpoint_manager.load_checkpoint(
                        self.neural_network, resume_checkpoint
                    )
                    
                    start_epoch = training_state.get('epoch', 0)
                    loss_history = training_state.get('loss_history', [])
                    
                    # Restore optimizer state if available
                    if training_state.get('optimizer_state_dict'):
                        optimizer.load_state_dict(training_state['optimizer_state_dict'])
                        print(f"✅ Optimizer state restored")
                    
                    print(f"🔄 Resuming training from epoch {start_epoch}")
                    
                except Exception as e:
                    print(f"❌ Failed to resume from checkpoint: {e}")
                    print("Starting fresh training...")
                    start_epoch = 0
                    loss_history = []
        
        # Create chunks
        chunks = self.chunked_loader.create_chunks(total_samples, phase_filter)
        
        # Initialize progress display
        progress_display = ChunkedTrainingProgressDisplay(
            total_epochs=epochs,
            total_chunks=len(chunks),
            total_samples=total_samples
        )
        
        # Set phase totals from dataset scan for progress tracking
        if scan_results.get('phase_distribution'):
            progress_display.set_phase_totals(scan_results['phase_distribution'])
        
        # Training statistics
        training_stats = {
            'total_loss': 0.0,
            'total_policy_loss': 0.0,
            'total_value_loss': 0.0,
            'samples_processed': 0,
            'chunks_processed': 0,
            'epochs_completed': 0,
            'training_time': 0.0
        }
        
        start_time = time.time()
        
        try:
            # Training loop
            for epoch in range(start_epoch, epochs):
                epoch_start = time.time()
                epoch_loss = 0.0
                epoch_samples = 0
                
                # Calculate total batches for this epoch
                total_batches_epoch = sum(
                    (chunk.num_samples + batch_size - 1) // batch_size 
                    for chunk in chunks
                )
                
                # Start epoch in progress display
                progress_display.start_epoch(epoch, total_batches_epoch)
                
                # Process each chunk
                for chunk in chunks:
                    chunk_start = time.time()
                    
                    # Check memory safety before processing chunk
                    if not self.memory_monitor.check_memory_safety(raise_on_critical=False):
                        logger.warning("Memory not safe, forcing cleanup...")
                        self.memory_monitor.force_memory_cleanup()
                        
                        # Recheck after cleanup
                        if not self.memory_monitor.check_memory_safety(raise_on_critical=False):
                            logger.error("Memory still not safe after cleanup, skipping chunk")
                            continue
                    
                    # Load chunk data
                    try:
                        board_tensors, policy_targets, value_targets, metadata_list, chunk_metadata = \
                            self.chunked_loader.load_chunk_data(chunk)
                    except Exception as e:
                        logger.error(f"Failed to load chunk {chunk.chunk_id}: {e}")
                        continue
                    
                    # Start chunk in progress display with metadata
                    progress_display.start_chunk(
                        chunk.chunk_id, chunk.num_samples, chunk.estimated_memory_mb, chunk_metadata
                    )
                    
                    # Update phase statistics based on chunk metadata
                    if chunk_metadata and 'phase_distribution' in chunk_metadata:
                        for phase, count in chunk_metadata['phase_distribution'].items():
                            progress_display.update_phase_statistics(phase, count, 0.0, 0.0)  # Will update loss later
                    
                    # Train on chunk with progress tracking
                    chunk_loss, chunk_samples = self._train_on_chunk(
                        board_tensors, policy_targets, value_targets,
                        optimizer, batch_size, gradient_accumulation_steps,
                        progress_display
                    )
                    
                    epoch_loss += chunk_loss
                    epoch_samples += chunk_samples
                    training_stats['chunks_processed'] += 1
                    
                    # Complete chunk in progress display
                    progress_display.complete_chunk(chunk_loss)
                    
                    # Cleanup after chunk
                    del board_tensors, policy_targets, value_targets, metadata_list
                    self.memory_monitor.force_memory_cleanup()
                
                # Epoch completion
                epoch_time = time.time() - epoch_start
                avg_epoch_loss = epoch_loss / len(chunks) if chunks else 0.0
                
                training_stats['total_loss'] += epoch_loss
                training_stats['samples_processed'] += epoch_samples
                training_stats['epochs_completed'] += 1
                
                # Complete epoch in progress display
                progress_display.complete_epoch(avg_epoch_loss)
                
                # Update learning rate
                scheduler.step()
                current_lr = scheduler.get_last_lr()[0]
                logger.info(f"Learning Rate updated to: {current_lr:.6f}")
                
                # Add to loss history
                loss_history.append(avg_epoch_loss)
                
                # Save checkpoint periodically with health tracking
                if (epoch + 1) % save_checkpoint_every == 0 or (epoch + 1) == epochs:
                    try:
                        # Prepare training metrics
                        training_metrics = {
                            'learning_rate': current_lr,
                            'epoch_time': epoch_time,
                            'samples_per_second': epoch_samples / epoch_time if epoch_time > 0 else 0,
                            'memory_usage_percent': self.memory_monitor.get_memory_status()['usage_percent']
                        }
                        
                        # Save checkpoint with health information
                        checkpoint_path = self.checkpoint_manager.save_checkpoint(
                            neural_network=self.neural_network,
                            epoch=epoch + 1,
                            optimizer_state=optimizer.state_dict(),
                            loss_history=loss_history,
                            config={'epochs': epochs, 'batch_size': batch_size, 'learning_rate': learning_rate},
                            warning_stats=progress_display.warning_stats,
                            training_metrics=training_metrics
                        )
                        
                        # Update checkpoint time for anomaly detection
                        progress_display.last_checkpoint_time = time.time()
                        
                    except Exception as e:
                        logger.error(f"❌ Failed to save checkpoint: {e}")
                        print(f"⚠️ Checkpoint saving failed, but training continues...")
        
        except Exception as e:
            logger.error(f"Training failed: {e}")
            raise
        finally:
            training_stats['training_time'] = time.time() - start_time
        
        # Final statistics
        avg_loss = training_stats['total_loss'] / training_stats['epochs_completed'] if training_stats['epochs_completed'] > 0 else 0.0
        
        # Complete training in progress display
        progress_display.complete_training(training_stats)
        
        return training_stats
    
    def _handle_checkpoint_resumption(self) -> Optional[str]:
        """
        Handle checkpoint resumption logic with user interaction.
        
        Returns:
            Selected checkpoint path or None for fresh training
        """
        if not self.checkpoint_manager:
            return None
        
        # Check for existing checkpoints
        checkpoints = self.checkpoint_manager.list_available_checkpoints()
        
        if not checkpoints:
            print("ℹ️ No existing checkpoints found. Starting fresh training.")
            return None
        
        print(f"\n{'='*80}")
        print("🔍 EXISTING CHECKPOINTS DETECTED")
        print(f"{'='*80}")
        print(f"Found {len(checkpoints)} existing checkpoints:")
        print(f"{'Epoch':<8} {'Health':<8} {'Status':<12} {'Warnings':<10} {'Size':<10}")
        print("-" * 60)
        
        for cp in checkpoints:
            health_str = f"{cp['health_score']:.2f}"
            status_str = "✅ Healthy" if cp['is_healthy'] else "⚠️ Issues"
            warnings_str = f"{cp['warning_count']}"
            size_str = f"{cp['file_size_mb']:.1f}MB"
            
            print(f"{cp['epoch']:<8} {health_str:<8} {status_str:<12} {warnings_str:<10} {size_str:<10}")
        
        # Get recommendations
        healthiest = max(checkpoints, key=lambda x: x['health_score'])
        latest = max(checkpoints, key=lambda x: x['epoch'])
        
        print(f"\n💡 Recommendations:")
        print(f"   Latest: Epoch {latest['epoch']} (health: {latest['health_score']:.2f})")
        print(f"   Healthiest: Epoch {healthiest['epoch']} (health: {healthiest['health_score']:.2f})")
        
        # Auto-select strategy
        if latest['health_score'] >= 0.7:
            # Latest checkpoint is healthy, use it
            print(f"✅ Auto-selecting latest healthy checkpoint: Epoch {latest['epoch']}")
            return latest['path']
        elif healthiest['health_score'] >= 0.7:
            # Latest is not healthy, but we have a healthy one
            print(f"⚠️ Latest checkpoint has issues (health: {latest['health_score']:.2f})")
            print(f"✅ Auto-selecting healthiest checkpoint: Epoch {healthiest['epoch']}")
            return healthiest['path']
        else:
            # No healthy checkpoints, ask user
            print(f"⚠️ All checkpoints have health issues!")
            return self._prompt_user_checkpoint_selection(checkpoints)
    
    def _prompt_user_checkpoint_selection(self, checkpoints: List[Dict]) -> Optional[str]:
        """Prompt user to select checkpoint when auto-selection is not safe."""
        latest = max(checkpoints, key=lambda x: x['epoch'])
        healthiest = max(checkpoints, key=lambda x: x['health_score'])
        
        print(f"\nOptions:")
        print(f"   1. Use latest checkpoint (Epoch {latest['epoch']}, health: {latest['health_score']:.2f})")
        print(f"   2. Use healthiest checkpoint (Epoch {healthiest['epoch']}, health: {healthiest['health_score']:.2f})")
        print(f"   3. Start fresh training (ignore checkpoints)")
        print(f"   4. Exit and manually inspect checkpoints")
        
        try:
            choice = input(f"\nSelect option (1-4) [default: 3]: ").strip()
            
            if choice == "1" or choice == "":
                return latest['path']
            elif choice == "2":
                return healthiest['path']
            elif choice == "3" or choice == "":
                print("Starting fresh training...")
                return None
            elif choice == "4":
                print("Exiting for manual inspection...")
                sys.exit(0)
            else:
                print("Invalid choice. Starting fresh training...")
                return None
                
        except (KeyboardInterrupt, EOFError):
            print("\nStarting fresh training...")
            return None
    
    def _train_on_chunk(self,
                       board_tensors: torch.Tensor,
                       policy_targets: torch.Tensor,
                       value_targets: torch.Tensor,
                       optimizer: torch.optim.Optimizer,
                       batch_size: int,
                       gradient_accumulation_steps: int,
                       progress_display: Optional[ChunkedTrainingProgressDisplay] = None) -> Tuple[float, int]:
        """Train on a single chunk of data."""
        self.neural_network.net.train()
        
        total_loss = 0.0
        num_batches = 0
        samples_processed = 0
        
        # Move tensors to device in smaller batches to avoid memory spikes
        device = self.neural_network.device
        total_batches = (len(board_tensors) + batch_size - 1) // batch_size
        
        # Process data in mini-batches
        for i in range(0, len(board_tensors), batch_size):
            end_idx = min(i + batch_size, len(board_tensors))
            
            # Move batch to device
            batch_boards = board_tensors[i:end_idx].to(device, non_blocking=True)
            batch_policies = policy_targets[i:end_idx].to(device, non_blocking=True)
            batch_values = value_targets[i:end_idx].to(device, non_blocking=True)
            
            # Forward pass
            pred_policies, pred_values = self.neural_network.net(batch_boards)
            
            # Adjust policy dimensions if needed
            if batch_policies.shape[1] != pred_policies.shape[1]:
                batch_size_actual = batch_policies.shape[0]
                num_actions = pred_policies.shape[1]
                expanded = torch.zeros(batch_size_actual, num_actions, device=device)
                to_copy = min(batch_policies.shape[1], num_actions)
                expanded[:, :to_copy] = batch_policies[:, :to_copy]
                sums = expanded.sum(dim=1, keepdim=True)
                fallback = torch.full_like(expanded, 1.0 / num_actions)
                batch_policies = torch.where(sums > 0, expanded / sums, fallback)
            
            # Calculate losses
            log_probs = torch.nn.functional.log_softmax(pred_policies, dim=1)
            policy_loss = torch.nn.functional.kl_div(log_probs, batch_policies, reduction='batchmean')
            value_loss = torch.nn.functional.mse_loss(pred_values.squeeze(), batch_values)
            
            total_loss_batch = policy_loss + value_loss
            
            # Scale for gradient accumulation
            total_loss_batch = total_loss_batch / gradient_accumulation_steps
            
            # Backward pass
            total_loss_batch.backward()
            
            # Update weights after accumulation steps
            if (num_batches + 1) % gradient_accumulation_steps == 0:
                # Gradient clipping
                torch.nn.utils.clip_grad_norm_(self.neural_network.net.parameters(), max_norm=1.0)
                
                optimizer.step()
                optimizer.zero_grad()
            
            # Statistics
            total_loss += total_loss_batch.item() * gradient_accumulation_steps
            num_batches += 1
            samples_processed += len(batch_boards)
            
            # Update progress display with additional metrics
            if progress_display:
                batch_idx = i // batch_size
                batch_time = time.time() - (getattr(self, '_batch_start_time', time.time()))
                current_lr = optimizer.param_groups[0]['lr'] if optimizer.param_groups else None
                
                progress_display.update_batch_progress(
                    batch_idx, total_batches, 
                    total_loss_batch.item() * gradient_accumulation_steps, 
                    len(batch_boards),
                    batch_time=batch_time,
                    learning_rate=current_lr
                )
                
                # Record batch start time for next iteration
                self._batch_start_time = time.time()
            
            # Cleanup batch tensors
            del batch_boards, batch_policies, batch_values, pred_policies, pred_values
            
            # Periodic memory check during training
            if num_batches % 50 == 0:
                if not self.memory_monitor.check_memory_safety(raise_on_critical=False):
                    logger.warning("Memory becoming unsafe during chunk training")
                    if torch.cuda.is_available():
                        torch.cuda.empty_cache()
        
        # Final gradient update if needed
        if num_batches % gradient_accumulation_steps != 0:
            torch.nn.utils.clip_grad_norm_(self.neural_network.net.parameters(), max_norm=1.0)
            optimizer.step()
            optimizer.zero_grad()
        
        avg_loss = total_loss / num_batches if num_batches > 0 else 0.0
        return avg_loss, samples_processed


def main():
    """Example usage of chunked training."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Chunked Training for Alpha Zero')
    parser.add_argument('--data-dir', required=True, help='Preprocessed data directory')
    parser.add_argument('--epochs', type=int, default=10, help='Number of epochs')
    parser.add_argument('--batch-size', type=int, default=64, help='Batch size')
    parser.add_argument('--learning-rate', type=float, default=1e-3, help='Learning rate')
    parser.add_argument('--max-positions', type=int, help='Maximum positions to use')
    parser.add_argument('--memory-threshold', type=float, default=32.0, help='Memory threshold (GB)')
    parser.add_argument('--chunk-memory', type=float, default=16.0, help='Target memory per chunk (GB)')
    parser.add_argument('--phase-filter', choices=['placement', 'moving', 'flying'], help='Game phase filter')
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(level=logging.INFO,
                       format='%(asctime)s - %(levelname)s - %(message)s')
    
    # Initialize components
    data_loader = FastDataLoader(args.data_dir)
    
    # Initialize neural network (simplified for example)
    model_args = {
        'input_channels': 19,
        'num_filters': 256,
        'num_residual_blocks': 10,
        'action_size': 1000,
        'dropout_rate': 0.2
    }
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    neural_network = AlphaZeroNetworkWrapper(model_args, device)
    
    # Initialize chunked trainer
    trainer = ChunkedTrainer(
        neural_network=neural_network,
        data_loader=data_loader,
        memory_threshold_gb=args.memory_threshold,
        target_chunk_memory_gb=args.chunk_memory
    )
    
    # Start training
    try:
        stats = trainer.train_chunked(
            epochs=args.epochs,
            batch_size=args.batch_size,
            learning_rate=args.learning_rate,
            max_positions=args.max_positions,
            phase_filter=args.phase_filter
        )
        
        print(f"\n🎉 Training completed successfully!")
        print(f"Final statistics: {stats}")
        
    except Exception as e:
        print(f"\n❌ Training failed: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
