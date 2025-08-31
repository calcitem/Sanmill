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
        
    def start_chunk(self, chunk_id: int, chunk_samples: int, estimated_memory_mb: float):
        """Start processing a new chunk."""
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
        
    def update_batch_progress(self, batch_idx: int, total_batches: int, 
                            current_loss: float, samples_in_batch: int):
        """Update progress for current batch."""
        now = time.time()
        
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
              f"Total Remaining: {self._format_time(estimated_remaining)}")
        
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
        
        # Learning progress indicator
        if len(self.epoch_losses) > 1:
            loss_change = epoch_loss - self.epoch_losses[-2]
            trend = "↓" if loss_change < 0 else "↑" if loss_change > 0 else "→"
            print(f"   Loss Trend: {trend} {abs(loss_change):+.6f}")
        
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
        
        print(f"📊 Scanning {self.total_files} NPZ files...")
        
        for i, npz_file in enumerate(npz_files):
            file_size = npz_file.stat().st_size
            total_size += file_size
            
            # Try to get actual sample count from file
            try:
                with np.load(npz_file, allow_pickle=True) as data:
                    if 'board_tensors' in data:
                        samples_in_file = len(data['board_tensors'])
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
            'bytes_per_sample_actual': total_size / total_samples if total_samples > 0 else 12000
        }
        
        logger.info(f"✅ Dataset scan completed in {scan_time:.1f}s:")
        logger.info(f"   Total files: {self.total_files:,}")
        logger.info(f"   Total size: {total_size / (1024**3):.2f} GB")
        logger.info(f"   Total samples: {total_samples:,}")
        logger.info(f"   Average file size: {avg_file_size / (1024**2):.1f} MB")
        logger.info(f"   Bytes per sample: {self.scan_results['bytes_per_sample_actual']:.0f}")
        
        return self.scan_results
    
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
    
    def load_chunk_data(self, chunk: ChunkInfo) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, List[Dict]]:
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
        
        # Verify memory status after loading
        status = self.memory_monitor.get_memory_status()
        logger.info(f"Chunk loaded: {len(board_tensors):,} samples, "
                   f"{status['available_gb']:.1f} GB available")
        
        return board_tensors, policy_targets, value_targets, metadata_list


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
        
        logger.info("ChunkedTrainer initialized")
    
    def train_chunked(self,
                     epochs: int = 10,
                     batch_size: int = 64,
                     learning_rate: float = 1e-3,
                     max_positions: Optional[int] = None,
                     phase_filter: Optional[str] = None,
                     gradient_accumulation_steps: int = 1,
                     save_checkpoint_every: int = 5) -> Dict[str, Any]:
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
        
        # Create chunks
        chunks = self.chunked_loader.create_chunks(total_samples, phase_filter)
        
        # Initialize progress display
        progress_display = ChunkedTrainingProgressDisplay(
            total_epochs=epochs,
            total_chunks=len(chunks),
            total_samples=total_samples
        )
        
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
            for epoch in range(epochs):
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
                    
                    # Start chunk in progress display
                    progress_display.start_chunk(
                        chunk.chunk_id, chunk.num_samples, chunk.estimated_memory_mb
                    )
                    
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
                        board_tensors, policy_targets, value_targets, metadata_list = \
                            self.chunked_loader.load_chunk_data(chunk)
                    except Exception as e:
                        logger.error(f"Failed to load chunk {chunk.chunk_id}: {e}")
                        continue
                    
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
                
                # Save checkpoint periodically
                if (epoch + 1) % save_checkpoint_every == 0:
                    checkpoint_path = f"chunked_checkpoint_epoch_{epoch + 1}.tar"
                    self.neural_network.save(checkpoint_path)
                    logger.info(f"💾 Checkpoint saved: {checkpoint_path}")
        
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
            
            # Update progress display
            if progress_display:
                batch_idx = i // batch_size
                progress_display.update_batch_progress(
                    batch_idx, total_batches, 
                    total_loss_batch.item() * gradient_accumulation_steps, 
                    len(batch_boards)
                )
            
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
