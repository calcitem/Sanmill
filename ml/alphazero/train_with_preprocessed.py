#!/usr/bin/env python3
"""
Alpha Zero Training with Preprocessed NPZ Data

This script is dedicated to fast training using preprocessed .npz files,
significantly improving training speed.
"""

import os
import sys
import argparse
import logging
import time
from pathlib import Path

# Add paths for imports
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)
sys.path.insert(0, os.path.join(os.path.dirname(current_dir), 'game'))

try:
    from fast_data_loader import FastDataLoader, create_fast_training_pipeline
    from trainer import AlphaZeroTrainer
    from config import get_default_config, get_fast_training_config
    from neural_network import AlphaZeroNetworkWrapper
    import torch
    import numpy as np
except ImportError as e:
    print(f"❌ Import Error: {e}")
    print("Please ensure you are running in the correct directory:")
    print("  cd D:\\Repo\\Sanmill\\ml\\alphazero")
    sys.exit(1)

logger = logging.getLogger(__name__)


def setup_logging(verbose: bool = False):
    """Set up logging."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler('preprocessed_training.log', encoding='utf-8')
        ]
    )


def validate_preprocessed_data(data_dir: str) -> bool:
    """Validate the integrity of the preprocessed data."""
    data_path = Path(data_dir)
    
    if not data_path.exists():
        print(f"❌ Data directory not found: {data_dir}")
        return False
    
    # Check for metadata.json
    metadata_file = data_path / "metadata.json"
    if not metadata_file.exists():
        print(f"❌ Missing metadata file: {metadata_file}")
        return False
    
    # Check for .npz files
    npz_files = list(data_path.glob("*.npz"))
    if not npz_files:
        print(f"❌ No .npz files found in: {data_dir}")
        return False
    
    print(f"✅ Found {len(npz_files)} preprocessed files")
    
    # Calculate total size
    total_size = sum(f.stat().st_size for f in npz_files + [metadata_file])
    total_size_mb = total_size / (1024 * 1024)
    print(f"📊 Total data size: {total_size_mb:.1f} MB")
    
    return True


def create_training_config(args):
    """Create the training configuration."""
    if args.fast_mode:
        config = get_fast_training_config()
        print("⚡ Using fast training configuration")
    else:
        config = get_default_config()
        print("📊 Using standard training configuration")
    
    # Override with command-line arguments
    if args.iterations:
        config.training.iterations = args.iterations
    if args.batch_size:
        config.training.train_batch_size = args.batch_size
    if args.learning_rate:
        config.training.train_lr = args.learning_rate
    if args.epochs:
        config.training.train_epochs = args.epochs
    
    # Disable traditional Perfect DB pre-training (we are using preprocessed data)
    config.training.use_pretraining = False
    
    # GPU settings
    if not args.cpu:
        config.training.cuda = torch.cuda.is_available()
        if config.training.cuda:
            print(f"🚀 Using GPU: {torch.cuda.get_device_name()}")
        else:
            print("⚠️  CUDA not available, using CPU")
    else:
        config.training.cuda = False
        print("💻 Forcing CPU usage")
    
    return config


def train_with_preprocessed_data(args):
    """Train using the preprocessed data."""
    print("🚀 Starting Alpha Zero training with preprocessed data")
    print("=" * 60)
    
    # 1. Validate data
    if not validate_preprocessed_data(args.data_dir):
        return False
    
    # 2. Create configuration
    config = create_training_config(args)
    
    # 3. Create data loader
    print(f"\n📦 Creating data loader...")
    print(f"  Data directory: {args.data_dir}")
    print(f"  Batch size: {args.batch_size}")
    print(f"  Trap ratio: {args.trap_ratio}")
    print(f"  Game phase filter: {args.phase_filter or 'All'}")
    
    try:
        loader = FastDataLoader(args.data_dir)
        
        # Get data statistics
        stats = loader.get_statistics()
        if stats:
            print(f"📊 Data Statistics:")
            print(f"  Processed sectors: {stats.get('total_sectors', 0):,}")
            print(f"  Total positions: {stats.get('total_positions', 0):,}")
            print(f"  Average processing speed: {stats.get('positions_per_second', 0):.0f} pos/s")
        
        # Create DataLoader (memory-safe mode)
        # When memory is low, limit the amount of data loaded at once
        import psutil
        available_memory_gb = psutil.virtual_memory().available / (1024**3)
        
        # Smart memory management strategy - optimized for high-end hardware
        if args.force_small_dataset:
            safe_max_positions = min(args.max_positions or 100000, 100000)
            logger.warning(f"🔒 Force small dataset mode: limiting to {safe_max_positions:,} positions")
        elif args.high_performance:
            # High-performance mode: designed for RTX4090 + 192GB+ memory configurations
            # Strictly avoid using virtual memory to prevent running out of disk space
            
            # Get system memory information
            import psutil
            memory_info = psutil.virtual_memory()
            total_memory_gb = memory_info.total / (1024**3)
            
            # More conservative calculation: considers system overhead, GPU VRAM, buffers, etc.
            # Actual memory requirement per position: 19*7*7*4 bytes ≈ 3.7KB, but considering Python object overhead ≈ 8KB
            bytes_per_position = 8192  # 8KB per position (conservative estimate)
            
            # Strict memory limit policy:
            # 1. Use no more than 60% of available memory (leaving 40% for the system and other processes)
            # 2. Reserve at least 32GB for the system (to prevent swapping)
            # 3. Account for temporary memory overhead during data conversion (2x factor)
            
            usable_memory_gb = min(
                available_memory_gb * 0.6,  # Use at most 60% of available memory
                available_memory_gb - 32,   # Reserve at least 32GB
                total_memory_gb * 0.5       # 50% of total memory as an upper limit
            )
            
            if usable_memory_gb < 16:
                logger.error(f"❌ High-performance mode requires at least 48GB of available memory (currently available: {available_memory_gb:.1f}GB)")
                usable_memory_gb = available_memory_gb * 0.3  # Fallback to a more conservative strategy
            
            # Calculate the safe maximum number of positions (considering 2x memory overhead for data conversion)
            safe_positions_by_memory = int(usable_memory_gb * 1024**3 / bytes_per_position / 2)
            
            safe_max_positions = min(
                args.max_positions or 50000000,  # User-specified or default 50 million
                safe_positions_by_memory         # Memory limit
            )
            
            # Estimate memory usage
            estimated_memory_gb = safe_max_positions * bytes_per_position * 2 / (1024**3)
            memory_utilization = estimated_memory_gb / available_memory_gb * 100
            
            logger.info(f"🚀🚀 HIGH-PERFORMANCE MODE (Physical Memory Priority):")
            logger.info(f"   Total Memory: {total_memory_gb:.1f} GB")
            logger.info(f"   Available Memory: {available_memory_gb:.1f} GB")
            logger.info(f"   Usable for Training: {usable_memory_gb:.1f} GB")
            logger.info(f"   Positions to Load: {safe_max_positions:,}")
            logger.info(f"   Estimated Memory Usage: {estimated_memory_gb:.1f} GB")
            logger.info(f"   Memory Utilization: {memory_utilization:.1f}%")
            
            # Virtual memory warning
            if memory_utilization > 50:
                logger.warning(f"⚠️  High memory utilization ({memory_utilization:.1f}%), monitor swap usage")
            
            # Disk space check (to prevent large swap files)
            import shutil
            disk_usage = shutil.disk_usage('/')
            available_disk_gb = disk_usage.free / (1024**3)
            
            # --no-swap option: strictly avoid virtual memory
            if args.no_swap:
                logger.info("🔒 Strict no-swap mode: further restricting memory usage")
                # Stricter limit: use only 50% of available memory, reserve more buffer
                stricter_memory_gb = min(usable_memory_gb * 0.5, available_memory_gb * 0.4)
                safe_positions_by_strict = int(stricter_memory_gb * 1024**3 / bytes_per_position / 2)
                safe_max_positions = min(safe_max_positions, safe_positions_by_strict)
                estimated_memory_gb = safe_max_positions * bytes_per_position * 2 / (1024**3)
                logger.info(f"   Strict Mode Positions: {safe_max_positions:,}")
                logger.info(f"   Strict Mode Memory: {estimated_memory_gb:.1f} GB")
            
            if available_disk_gb < estimated_memory_gb * 2:  # Need 2x space for a safe buffer
                logger.warning(f"⚠️  Disk space might be insufficient (Available: {available_disk_gb:.1f}GB, Possibly required: {estimated_memory_gb*2:.1f}GB)")
                if args.no_swap:
                    logger.info("✅ --no-swap is enabled, no need to worry about disk space")
                else:
                    logger.warning(f"   Consider adding the --no-swap option or reducing --max-positions")
        elif args.memory_conservative:
            # Conservative mode: suitable for low-memory environments
            conservative_positions = int(available_memory_gb * 1000)  # Approx. 1000 positions per GB
            safe_max_positions = min(args.max_positions or 200000, conservative_positions)
            logger.warning(f"🛡️  Conservative memory mode: limiting to {safe_max_positions:,} positions "
                           f"(available memory: {available_memory_gb:.1f} GB)")
        elif available_memory_gb >= 100:
            # High-end configuration: fully utilize large memory (e.g., RTX4090 + 192GB)
            # Each position actually needs ~4KB, but reserve 2x buffer for processing and conversion
            positions_per_gb = 2000  # Approx. 2000 positions per GB (conservative but fully utilizes)
            safe_max_positions = min(
                args.max_positions or 20000000,  # Default 20 million positions
                int(available_memory_gb * 0.6 * positions_per_gb)  # Use 60% of available memory
            )
            logger.info(f"🚀 High-performance mode (RTX4090+ config): loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB, will use ~{safe_max_positions*4/1024/1024:.1f} GB)")
        elif available_memory_gb >= 64:
            # Mid-to-high-end configuration: reasonable memory utilization
            positions_per_gb = 1500  # Approx. 1500 positions per GB
            safe_max_positions = min(
                args.max_positions or 10000000,  # Default 10 million positions
                int(available_memory_gb * 0.5 * positions_per_gb)  # Use 50% of available memory
            )
            logger.info(f"🔧 Mid-high-end mode: loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB)")
        elif available_memory_gb >= 32:
            # Mid-range configuration: cautious memory usage
            positions_per_gb = 1000  # Approx. 1000 positions per GB
            safe_max_positions = min(
                args.max_positions or 2000000,  # Default 2 million positions
                int(available_memory_gb * 0.4 * positions_per_gb)  # Use 40% of available memory
            )
            logger.info(f"🔧 Mid-range mode: loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB)")
        else:
            # Low-end configuration: strictly limit memory usage
            positions_per_gb = 500  # Approx. 500 positions per GB
            safe_max_positions = min(
                args.max_positions or 500000,  # Default 500,000 positions
                int(available_memory_gb * 0.3 * positions_per_gb)  # Use 30% of available memory
            )
            logger.warning(f"🛡️  Low-memory mode: limiting to {safe_max_positions:,} positions "
                           f"(available memory: {available_memory_gb:.1f} GB)")
        
        dataloader = loader.create_dataloader(
            phase_filter=args.phase_filter,
            max_positions=safe_max_positions,
            batch_size=args.batch_size,
            shuffle=True,
            trap_ratio=args.trap_ratio,
            num_workers=args.num_workers
        )
        
        print(f"✅ DataLoader created successfully:")
        print(f"  Dataset size: {len(dataloader.dataset):,}")
        print(f"  Number of batches: {len(dataloader):,}")
        
    except Exception as e:
        print(f"❌ Failed to create data loader: {e}")
        return False
    
    # 4. Create trainer
    print(f"\n🧠 Creating neural network and trainer...")
    
    try:
        # Create neural network
        model_args = {
            'input_channels': 19,  # Match the number of channels in the preprocessed data
            'num_filters': config.network.num_filters,
            'num_residual_blocks': config.network.num_residual_blocks,
            'action_size': 1000,  # From Game.getActionSize()
            'dropout_rate': config.network.dropout_rate
        }
        
        device = 'cuda' if config.training.cuda else 'cpu'
        neural_network = AlphaZeroNetworkWrapper(model_args, device)
        
        # Create trainer (simplified version, specialized for preprocessed data)
        trainer_args = {
            'cuda': config.training.cuda,
            'train_batch_size': config.training.train_batch_size,
            'train_epochs': config.training.train_epochs,
            'train_lr': config.training.train_lr,
            'checkpoint_dir': args.checkpoint_dir,
            'checkpoint_interval': 5
        }
        
        print(f"✅ Neural network created successfully ({device})")
        
    except Exception as e:
        print(f"❌ Failed to create neural network: {e}")
        return False
    
    # 5. Start training
    print(f"\n🎯 Starting training with preprocessed data...")
    print(f"  Epochs: {args.epochs}")
    print(f"  Learning rate: {args.learning_rate}")
    print(f"  Checkpoint directory: {args.checkpoint_dir}")
    
    start_time = time.time()
    
    try:
        # Training loop
        neural_network.net.train()
        
        # Set up optimizer
        if neural_network.optimizer is None:
            neural_network.optimizer = torch.optim.Adam(
                neural_network.net.parameters(), 
                lr=args.learning_rate
            )
        
        total_batches = len(dataloader)
        
        for epoch in range(args.epochs):
            epoch_start = time.time()
            epoch_loss = 0.0
            epoch_policy_loss = 0.0
            epoch_value_loss = 0.0
            
            # Check memory status at the start of training
            memory_info = psutil.virtual_memory()
            current_memory = memory_info.available / (1024**3)
            memory_usage_percent = memory_info.percent
            swap_info = psutil.swap_memory()
            swap_usage_mb = swap_info.used / (1024**2)
            
            print(f"\n📈 Epoch {epoch + 1}/{args.epochs}")
            print(f"   Available Memory: {current_memory:.1f} GB")
            print(f"   Memory Usage: {memory_usage_percent:.1f}%")
            print(f"   Swap Usage: {swap_usage_mb:.1f} MB")
            
            # More reasonable swap usage warning threshold
            if swap_usage_mb > 5120:  # Warn only if above 5GB
                logger.warning(f"⚠️  High swap usage: {swap_usage_mb:.1f} MB")
                logger.warning("   Recommend monitoring memory usage")
            
            # Strict memory monitoring
            if args.high_performance:
                if memory_usage_percent > 85:
                    logger.error(f"🚨 Memory usage too high ({memory_usage_percent:.1f}%), training may become unstable")
                    logger.error("   Recommend immediately reducing --max-positions or batch size")
                elif memory_usage_percent > 75:
                    logger.warning(f"⚠️  High memory usage ({memory_usage_percent:.1f}%), monitor closely")
                
                # Set different swap thresholds based on whether --no-swap is enabled
                # Get baseline swap usage (normal system usage before training starts)
                if not hasattr(args, '_baseline_swap_mb'):
                    args._baseline_swap_mb = swap_usage_mb
                    logger.info(f"📊 Baseline Swap Usage: {args._baseline_swap_mb:.1f} MB")
                
                # Calculate the increase relative to the baseline
                swap_increase_mb = swap_usage_mb - args._baseline_swap_mb
                
                if args.no_swap:
                    # NO-SWAP mode: allow baseline usage + 2GB increase
                    swap_threshold = args._baseline_swap_mb + 2048  
                    if swap_usage_mb > swap_threshold:
                        logger.error(f"🚨 NO-SWAP mode: Swap memory has increased too much")
                        logger.error(f"   Current: {swap_usage_mb:.1f} MB, Baseline: {args._baseline_swap_mb:.1f} MB")
                        logger.error(f"   Increase: {swap_increase_mb:.1f} MB (Threshold: 2048 MB)")
                        raise RuntimeError("NO-SWAP mode: Virtual memory increased too much during training")
                else:
                    # Normal mode: stop if swap usage exceeds 10GB
                    if swap_usage_mb > 10240:
                        logger.error(f"🚨 Excessive swap usage ({swap_usage_mb:.1f} MB), stopping training to prevent system instability")
                        raise RuntimeError("Virtual memory usage too high, stopping to prevent system instability")
            else:
                if current_memory < 8.0:
                    logger.warning(f"⚠️  Available memory is low ({current_memory:.1f} GB)")
                    logger.warning("Consider reducing batch size or enabling memory cleanup")
            
            for batch_idx, (boards, policies, values, metadata) in enumerate(dataloader):
                # Metadata and channel feature debugging (only output for the first batch to avoid polluting logs)
                if args.metadata_debug and batch_idx == 0:
                    try:
                        print("\n🔎 Feature Channel Check (first batch):")
                        print(f"  boards tensor shape: {tuple(boards.shape)}")
                        # Channel meaning reference: 7/8 pieces in hand, 9/10/11/12 phase, 13 move count, 15/16 pieces on board
                        with torch.no_grad():
                            if boards.shape[1] >= 13:
                                phase_sums = boards[:, 9:13].sum(dim=(0, 2, 3))
                                print(f"  Phase channel activations (placement/moving/flying/removal): {phase_sums.tolist()}")
                            if boards.shape[1] > 7:
                                cur_in_hand_avg = boards[:, 7].mean().item()
                                opp_in_hand_avg = boards[:, 8].mean().item() if boards.shape[1] > 8 else 0.0
                                print(f"  Pieces in hand (avg) current/opponent: {cur_in_hand_avg:.4f} / {opp_in_hand_avg:.4f}")
                            if boards.shape[1] > 13:
                                move_count_avg = boards[:, 13].mean().item()
                                print(f"  Move count channel (avg): {move_count_avg:.4f}")
                            if boards.shape[1] > 16:
                                cur_on_board_avg = boards[:, 15].mean().item()
                                opp_on_board_avg = boards[:, 16].mean().item()
                                print(f"  Pieces on board (avg) current/opponent: {cur_on_board_avg:.4f} / {opp_on_board_avg:.4f}")

                        sample_meta = metadata[0] if isinstance(metadata, (list, tuple)) and len(metadata) > 0 else metadata
                        if isinstance(sample_meta, dict):
                            keys_preview = list(sample_meta.keys())[:10]
                            print(f"  Metadata keys (example, first 10): {keys_preview}")
                    except Exception as _e:
                        logger.debug(f"metadata-debug output failed: {_e}")
                # Check memory every 100 batches
                if batch_idx % 100 == 0 and batch_idx > 0:
                    current_memory = psutil.virtual_memory().available / (1024**3)
                    if current_memory < 4.0:
                        logger.error(f"🚨 Critical memory low: {current_memory:.1f} GB")
                        logger.error("Training may fail due to insufficient memory")
                        # Force garbage collection
                        import gc
                        gc.collect()
                        if torch.cuda.is_available():
                            torch.cuda.empty_cache()
                # Move data to device
                boards = boards.to(device)
                values = values.to(device)
                
                # Handle policy target dimension mismatch issue
                policies = policies.to(device)
                
                # Forward pass
                pred_policies, pred_values = neural_network.net(boards)
                
                # Adjust policy target dimensions to match network output
                if policies.shape[1] != pred_policies.shape[1]:
                    # Preprocessed data is usually 24-dimensional (24 valid position distributions), network outputs to a larger action space
                    batch_size = policies.shape[0]
                    num_actions = pred_policies.shape[1]
                    expanded = torch.zeros(batch_size, num_actions, device=device)
                    to_copy = min(24, num_actions)
                    expanded[:, :to_copy] = policies[:, :to_copy]
                    # Normalize to a probability distribution; if all zeros, fallback to a uniform distribution
                    sums = expanded.sum(dim=1, keepdim=True)
                    fallback = torch.full_like(expanded, 1.0 / num_actions)
                    policies = torch.where(sums > 0, expanded / sums, fallback)
                
                # Calculate loss
                if args.policy_loss == 'kld':
                    log_probs = torch.nn.functional.log_softmax(pred_policies, dim=1)
                    policy_loss = torch.nn.functional.kl_div(log_probs, policies, reduction='batchmean')
                else:
                    probs = torch.nn.functional.softmax(pred_policies, dim=1)
                    policy_loss = torch.nn.functional.mse_loss(probs, policies)
                value_loss = torch.nn.functional.mse_loss(pred_values.squeeze(), values)
                total_loss = policy_loss + value_loss
                
                # Backpropagation
                neural_network.optimizer.zero_grad()
                total_loss.backward()
                neural_network.optimizer.step()
                
                # Statistics
                epoch_loss += total_loss.item()
                epoch_policy_loss += policy_loss.item()
                epoch_value_loss += value_loss.item()
                
                # Display progress
                if batch_idx % 100 == 0 or batch_idx == total_batches - 1:
                    progress = (batch_idx + 1) / total_batches * 100
                    print(f"  Batch {batch_idx + 1:,}/{total_batches:,} ({progress:.1f}%) - "
                          f"Loss: {total_loss.item():.4f}")
            
            # End of epoch statistics
            epoch_time = time.time() - epoch_start
            avg_loss = epoch_loss / total_batches
            avg_policy_loss = epoch_policy_loss / total_batches
            avg_value_loss = epoch_value_loss / total_batches
            
            print(f"✅ Epoch {epoch + 1} completed ({epoch_time:.1f}s)")
            print(f"  Average Loss: {avg_loss:.4f}")
            print(f"  Policy Loss: {avg_policy_loss:.4f}")
            print(f"  Value Loss: {avg_value_loss:.4f}")
            
            # Save checkpoint
            if (epoch + 1) % 5 == 0:
                checkpoint_path = Path(args.checkpoint_dir) / f"preprocessed_epoch_{epoch + 1}.tar"
                checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
                neural_network.save(str(checkpoint_path))
                print(f"💾 Checkpoint saved: {checkpoint_path}")
        
        # Training finished
        total_time = time.time() - start_time
        print(f"\n🎉 Training complete!")
        print(f"  Total time: {total_time:.1f}s ({total_time/60:.1f}min)")
        print(f"  Average time per epoch: {total_time/args.epochs:.1f}s")
        
        # Save final model
        final_model_path = Path(args.checkpoint_dir) / "final_preprocessed_model.tar"
        final_model_path.parent.mkdir(parents=True, exist_ok=True)
        neural_network.save(str(final_model_path))
        print(f"💾 Final model saved: {final_model_path}")
        
        return True
        
    except KeyboardInterrupt:
        print(f"\n⏹️  Training interrupted by user")
        return False
    except Exception as e:
        print(f"\n❌ Training failed: {e}")
        logger.exception("Training failed with exception")
        return False


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description='Alpha Zero Training with Preprocessed NPZ Data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example Usage:

  # Basic Training
  python train_with_preprocessed.py --data-dir "G:\\preprocessed_data"

  # Advanced Options
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --batch-size 128 \\
    --epochs 20 \\
    --learning-rate 0.001 \\
    --trap-ratio 0.4 \\
    --phase-filter "placement"

  # Fast Test Mode
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --fast-mode \\
    --max-positions 10000

  # High-Performance Mode (for RTX4090 + 192GB+ RAM)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --high-performance \\
    --batch-size 256 \\
    --epochs 10

  # Memory-Conservative Mode (for large datasets)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --memory-conservative \\
    --batch-size 32 \\
    --epochs 5
        """
    )
    
    # Required arguments
    parser.add_argument('--data-dir', required=True, 
                        help='Path to the preprocessed data directory (containing .npz files)')
    
    # Training parameters
    parser.add_argument('--epochs', type=int, default=10,
                        help='Number of training epochs (default: 10)')
    parser.add_argument('--batch-size', type=int, default=64,
                        help='Batch size (default: 64)')
    parser.add_argument('--learning-rate', type=float, default=1e-3,
                        help='Learning rate (default: 0.001)')
    parser.add_argument('--iterations', type=int,
                        help='Total training iterations (overrides epochs)')
    
    # Data filtering parameters
    parser.add_argument('--max-positions', type=int,
                        help='Maximum number of positions to train on (for testing)')
    parser.add_argument('--trap-ratio', type=float, default=0.3,
                        help='Ratio of trap positions (default: 0.3)')
    parser.add_argument('--phase-filter', choices=['placement', 'moving', 'flying'],
                        help='Only train on a specific game phase')
    
    # System parameters
    parser.add_argument('--cpu', action='store_true',
                        help='Force CPU usage (do not use GPU)')
    parser.add_argument('--num-workers', type=int, default=2,
                        help='Number of worker processes for data loading (default: 2)')
    parser.add_argument('--checkpoint-dir', default='checkpoints_preprocessed',
                        help='Directory to save checkpoints (default: checkpoints_preprocessed)')
    
    # Mode selection
    parser.add_argument('--fast-mode', action='store_true',
                        help='Fast training mode (smaller network and parameters)')
    
    # Memory management options
    parser.add_argument('--memory-safe', action='store_true',
                        help='Enable memory-safe mode (strictly controls physical memory usage)')
    parser.add_argument('--memory-threshold', type=float, default=16.0,
                        help='Physical memory safety threshold (in GB, default: 16.0)')
    parser.add_argument('--force-small-dataset', action='store_true',
                        help='Force using a small dataset mode (max 100,000 positions)')
    parser.add_argument('--memory-conservative', action='store_true',
                        help='Use the most conservative memory settings (suitable for large datasets)')
    parser.add_argument('--high-performance', action='store_true',
                        help='High-performance mode (for RTX4090 + 192GB+ RAM configurations)')
    parser.add_argument('--no-swap', action='store_true',
                        help='Limit swap memory growth (allows system baseline usage + 2GB increase)')
    
    # Other options
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Verbose output')

    # Metadata and loss function debugging/control
    parser.add_argument('--metadata-debug', action='store_true',
                        help='Print metadata and feature channel stats for the first batch for verification')
    parser.add_argument('--policy-loss', choices=['kld', 'mse'], default='kld',
                        help='Policy loss function type: kld or mse (default: kld)')
    
    args = parser.parse_args()
    
    # Check for option conflicts and resolve them automatically
    conflict_warnings = []
    
    # Check for memory mode conflicts
    memory_modes = [args.memory_conservative, args.high_performance, args.force_small_dataset]
    active_memory_modes = sum(memory_modes)
    
    if active_memory_modes > 1:
        if args.high_performance and args.memory_conservative:
            conflict_warnings.append("⚠️  Conflict detected: --high-performance and --memory-conservative specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing high-performance mode (ignoring conservative mode)")
            args.memory_conservative = False
        
        if args.high_performance and args.force_small_dataset:
            conflict_warnings.append("⚠️  Conflict detected: --high-performance and --force-small-dataset specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing high-performance mode (ignoring small dataset mode)")
            args.force_small_dataset = False
            
        if args.memory_conservative and args.force_small_dataset:
            conflict_warnings.append("⚠️  Conflict detected: --memory-conservative and --force-small-dataset specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing small dataset mode (stricter limit)")
            args.memory_conservative = False
    
    # Check compatibility of max-positions with memory modes
    if args.max_positions:
        if args.memory_conservative and args.max_positions > 500000:
            conflict_warnings.append(f"⚠️  Conflict detected: --max-positions ({args.max_positions:,}) is too large for --memory-conservative mode")
            conflict_warnings.append(f"   Suggestion: Conservative mode recommends not exceeding 500,000 positions")
            
        if args.force_small_dataset and args.max_positions > 100000:
            conflict_warnings.append(f"⚠️  Conflict detected: --max-positions ({args.max_positions:,}) is too large for --force-small-dataset mode")
            conflict_warnings.append(f"   Resolution: Limiting to 100,000 positions")
            args.max_positions = 100000
            
        if args.high_performance and args.max_positions < 1000000:
            conflict_warnings.append(f"⚠️  Notice: A small --max-positions ({args.max_positions:,}) was specified in --high-performance mode")
            conflict_warnings.append(f"   Suggestion: High-performance mode recommends at least 1,000,000 positions to fully utilize hardware")
    
    # Check compatibility of batch size with memory modes
    if args.batch_size:
        if args.memory_conservative and args.batch_size > 64:
            conflict_warnings.append(f"⚠️  Conflict detected: --batch-size ({args.batch_size}) is too large for --memory-conservative mode")
            conflict_warnings.append(f"   Suggestion: Conservative mode recommends a batch size no larger than 64")
            
        if args.high_performance and args.batch_size < 128:
            conflict_warnings.append(f"⚠️  Notice: A small --batch-size ({args.batch_size}) was specified in --high-performance mode")
            conflict_warnings.append(f"   Suggestion: High-performance mode recommends a batch size of at least 128 to fully utilize the GPU")
    
    # Set up logging
    setup_logging(args.verbose)
    
    print("🎯 Alpha Zero Preprocessed Data Training Tool")
    print("=" * 50)
    
    # Display conflict warnings
    if conflict_warnings:
        print("\n🚨 Option Conflict Detection:")
        for warning in conflict_warnings:
            print(warning)
        print("")
    
    # Validate arguments
    if not Path(args.data_dir).exists():
        print(f"❌ Data directory does not exist: {args.data_dir}")
        return 1
    
    # Display configuration
    print(f"📋 Training Configuration:")
    print(f"  Data Directory: {args.data_dir}")
    print(f"  Epochs: {args.epochs}")
    print(f"  Batch Size: {args.batch_size}")
    print(f"  Learning Rate: {args.learning_rate}")
    print(f"  Trap Ratio: {args.trap_ratio}")
    print(f"  Max Positions: {args.max_positions or 'Unlimited'}")
    print(f"  Game Phase: {args.phase_filter or 'All'}")
    print(f"  Device: {'CPU' if args.cpu else 'GPU (if available)'}")
    print(f"  Workers: {args.num_workers}")
    print(f"  Memory Safe Mode: {'Enabled' if args.memory_safe else 'Disabled'}")
    print(f"  Memory Threshold: {args.memory_threshold} GB")
    print(f"  Conservative Memory: {'Enabled' if args.memory_conservative else 'Disabled'}")
    print(f"  High Performance: {'Enabled' if args.high_performance else 'Disabled'}")
    print(f"  Disable Swap: {'Enabled' if args.no_swap else 'Disabled'}")
    print(f"  Force Small Dataset: {'Enabled' if args.force_small_dataset else 'Disabled'}")
    print(f"  Metadata Debug: {'Enabled' if args.metadata_debug else 'Disabled'}")
    print(f"  Policy Loss: {args.policy_loss.upper()}")
    
    # Display current memory status
    import psutil
    memory_info = psutil.virtual_memory()
    available_gb = memory_info.available / (1024**3)
    total_gb = memory_info.total / (1024**3)
    print(f"💾 Current Memory Status:")
    print(f"  Total Memory: {total_gb:.1f} GB")
    print(f"  Available Memory: {available_gb:.1f} GB")
    print(f"  Usage: {memory_info.percent:.1f}%")
    
    # Memory warning
    if available_gb < args.memory_threshold:
        print(f"⚠️  Warning: Available memory ({available_gb:.1f} GB) is below the threshold ({args.memory_threshold} GB)")
        print(f"   Consider enabling memory-safe mode: --memory-safe")
    
    # Start training
    success = train_with_preprocessed_data(args)
    
    if success:
        print("\n🎉 Training completed successfully!")
        return 0
    else:
        print("\n❌ Training failed!")
        return 1


if __name__ == '__main__':
    sys.exit(main())
