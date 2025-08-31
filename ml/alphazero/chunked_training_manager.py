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


class ChunkedDataLoader:
    """Chunked data loader that splits large datasets into memory-safe chunks."""
    
    def __init__(self,
                 data_loader: FastDataLoader,
                 memory_monitor: MemoryMonitor,
                 target_chunk_memory_gb: float = 16.0,
                 min_chunk_size: int = 1000):
        """
        Initialize chunked data loader.
        
        Args:
            data_loader: Base data loader
            memory_monitor: Memory monitor instance
            target_chunk_memory_gb: Target memory usage per chunk (GB)
            min_chunk_size: Minimum samples per chunk
        """
        self.data_loader = data_loader
        self.memory_monitor = memory_monitor
        self.target_chunk_memory_gb = target_chunk_memory_gb
        self.min_chunk_size = min_chunk_size
        
        # Estimate bytes per sample (conservative)
        # Board: 19*7*7*4 = 3724 bytes
        # Policy: 1000*4 = 4000 bytes  
        # Value: 4 bytes
        # Metadata + overhead: ~4000 bytes
        self.bytes_per_sample = 12000  # Conservative estimate
        
        logger.info(f"ChunkedDataLoader initialized:")
        logger.info(f"  Target chunk memory: {target_chunk_memory_gb:.1f} GB")
        logger.info(f"  Estimated bytes per sample: {self.bytes_per_sample}")
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
        
        # Initialize memory monitor and chunked loader
        self.memory_monitor = MemoryMonitor(
            memory_threshold_gb=memory_threshold_gb,
            swap_threshold_gb=2.0,
            critical_threshold_gb=8.0
        )
        
        self.chunked_loader = ChunkedDataLoader(
            data_loader=data_loader,
            memory_monitor=self.memory_monitor,
            target_chunk_memory_gb=target_chunk_memory_gb
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
        
        # Get total sample count (estimate)
        stats = self.data_loader.get_statistics()
        total_samples = stats.get('total_positions', 100000)
        if max_positions:
            total_samples = min(total_samples, max_positions)
        
        # Create chunks
        chunks = self.chunked_loader.create_chunks(total_samples, phase_filter)
        
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
                
                logger.info(f"\n📈 Epoch {epoch + 1}/{epochs}")
                
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
                        board_tensors, policy_targets, value_targets, metadata_list = \
                            self.chunked_loader.load_chunk_data(chunk)
                    except Exception as e:
                        logger.error(f"Failed to load chunk {chunk.chunk_id}: {e}")
                        continue
                    
                    # Train on chunk
                    chunk_loss, chunk_samples = self._train_on_chunk(
                        board_tensors, policy_targets, value_targets,
                        optimizer, batch_size, gradient_accumulation_steps
                    )
                    
                    epoch_loss += chunk_loss
                    epoch_samples += chunk_samples
                    training_stats['chunks_processed'] += 1
                    
                    # Cleanup after chunk
                    del board_tensors, policy_targets, value_targets, metadata_list
                    self.memory_monitor.force_memory_cleanup()
                    
                    chunk_time = time.time() - chunk_start
                    logger.info(f"  Chunk {chunk.chunk_id} completed: "
                               f"Loss={chunk_loss:.6f}, Samples={chunk_samples:,}, "
                               f"Time={chunk_time:.1f}s")
                    
                    # Memory status update
                    status = self.memory_monitor.get_memory_status()
                    logger.info(f"  Memory: {status['available_gb']:.1f} GB available, "
                               f"{status['usage_percent']:.1f}% used")
                
                # Epoch completion
                epoch_time = time.time() - epoch_start
                avg_epoch_loss = epoch_loss / len(chunks) if chunks else 0.0
                
                training_stats['total_loss'] += epoch_loss
                training_stats['samples_processed'] += epoch_samples
                training_stats['epochs_completed'] += 1
                
                # Update learning rate
                scheduler.step()
                current_lr = scheduler.get_last_lr()[0]
                
                logger.info(f"✅ Epoch {epoch + 1} completed:")
                logger.info(f"  Average Loss: {avg_epoch_loss:.6f}")
                logger.info(f"  Samples Processed: {epoch_samples:,}")
                logger.info(f"  Time: {epoch_time:.1f}s")
                logger.info(f"  Learning Rate: {current_lr:.6f}")
                
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
        
        logger.info(f"\n🎉 Chunked training completed!")
        logger.info(f"  Total epochs: {training_stats['epochs_completed']}")
        logger.info(f"  Total chunks processed: {training_stats['chunks_processed']}")
        logger.info(f"  Total samples: {training_stats['samples_processed']:,}")
        logger.info(f"  Average loss: {avg_loss:.6f}")
        logger.info(f"  Training time: {training_stats['training_time']:.1f}s")
        
        return training_stats
    
    def _train_on_chunk(self,
                       board_tensors: torch.Tensor,
                       policy_targets: torch.Tensor,
                       value_targets: torch.Tensor,
                       optimizer: torch.optim.Optimizer,
                       batch_size: int,
                       gradient_accumulation_steps: int) -> Tuple[float, int]:
        """Train on a single chunk of data."""
        self.neural_network.net.train()
        
        total_loss = 0.0
        num_batches = 0
        samples_processed = 0
        
        # Move tensors to device in smaller batches to avoid memory spikes
        device = self.neural_network.device
        
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
