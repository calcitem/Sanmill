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
import glob
import json
from pathlib import Path
from typing import Optional, Dict, Any, List

# Add paths for imports
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)
sys.path.insert(0, os.path.join(os.path.dirname(current_dir), 'game'))

try:
    from fast_data_loader import FastDataLoader, create_fast_training_pipeline
    from trainer import AlphaZeroTrainer
    from config import (get_default_config, get_fast_training_config,
                       get_preprocessed_training_config, AlphaZeroConfig)
    from neural_network import AlphaZeroNetworkWrapper
    from chunked_training_manager import ChunkedTrainer, MemoryMonitor
    import torch
    import numpy as np
except ImportError as e:
    print(f"❌ Import Error: {e}")
    print("Please ensure you are running in the correct directory:")
    print("  cd ml\\alphazero")
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


def load_config_from_file(config_path: str) -> AlphaZeroConfig:
    """Load configuration from file."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    try:
        config = AlphaZeroConfig.load(config_path)
        print(f"✅ Configuration loaded from: {config_path}")
        return config
    except Exception as e:
        raise ValueError(f"Failed to load configuration from {config_path}: {e}")


class CheckpointManager:
    """Manages training checkpoints for incremental training."""

    def __init__(self, checkpoint_dir: str, keep_n_checkpoints: int = 3):
        self.checkpoint_dir = Path(checkpoint_dir)
        self.keep_n_checkpoints = keep_n_checkpoints
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def get_latest_checkpoint(self) -> Optional[str]:
        """Get the path to the latest checkpoint."""
        checkpoint_pattern = self.checkpoint_dir / "checkpoint_epoch_*.tar"
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

    def save_checkpoint(self, neural_network, epoch: int, optimizer_state: Dict,
                       loss_history: List[float], config: Dict[str, Any]) -> str:
        """Save a training checkpoint."""
        checkpoint_path = self.checkpoint_dir / f"checkpoint_epoch_{epoch}.tar"

        # Save the neural network
        neural_network.save(str(checkpoint_path))

        # Save additional training state
        state_path = self.checkpoint_dir / f"training_state_epoch_{epoch}.json"
        training_state = {
            'epoch': epoch,
            'optimizer_state_dict': optimizer_state,
            'loss_history': loss_history,
            'config': config
        }

        with open(state_path, 'w') as f:
            json.dump(training_state, f, indent=2, default=str)

        # Clean up old checkpoints
        self._cleanup_old_checkpoints()

        return str(checkpoint_path)

    def load_checkpoint(self, neural_network, checkpoint_path: str) -> Dict[str, Any]:
        """Load a training checkpoint."""
        # Load the neural network
        neural_network.load(checkpoint_path)

        # Load training state
        epoch = self._extract_epoch_from_path(checkpoint_path)
        state_path = self.checkpoint_dir / f"training_state_epoch_{epoch}.json"

        if state_path.exists():
            with open(state_path, 'r') as f:
                training_state = json.load(f)
            return training_state
        else:
            # Fallback for old checkpoints without training state
            return {
                'epoch': epoch,
                'optimizer_state_dict': {},
                'loss_history': [],
                'config': {}
            }

    def _extract_epoch_from_path(self, checkpoint_path: str) -> int:
        """Extract epoch number from checkpoint path."""
        try:
            filename = Path(checkpoint_path).stem
            return int(filename.split('_')[-1])
        except (ValueError, IndexError):
            return 0

    def _cleanup_old_checkpoints(self):
        """Remove old checkpoints to save disk space."""
        checkpoint_pattern = self.checkpoint_dir / "checkpoint_epoch_*.tar"
        state_pattern = self.checkpoint_dir / "training_state_epoch_*.json"

        checkpoints = glob.glob(str(checkpoint_pattern))
        states = glob.glob(str(state_pattern))

        if len(checkpoints) <= self.keep_n_checkpoints:
            return

        # Sort by epoch and keep only the latest N
        def extract_epoch(path):
            try:
                filename = Path(path).stem
                return int(filename.split('_')[-1])
            except (ValueError, IndexError):
                return 0

        checkpoints.sort(key=extract_epoch)
        states.sort(key=extract_epoch)

        # Remove old checkpoints
        for checkpoint in checkpoints[:-self.keep_n_checkpoints]:
            try:
                os.remove(checkpoint)
                logger.info(f"Removed old checkpoint: {checkpoint}")
            except OSError:
                pass

        # Remove corresponding state files
        for state in states[:-self.keep_n_checkpoints]:
            try:
                os.remove(state)
            except OSError:
                pass


def merge_config_with_args(config: AlphaZeroConfig, args) -> AlphaZeroConfig:
    """Merge configuration file settings with command line arguments."""
    # Command line arguments take precedence over config file
    if config.preprocessed_training is None:
        # If no preprocessed training config in file, create default
        config.preprocessed_training = get_preprocessed_training_config().preprocessed_training

    # Override with command-line arguments if provided
    preprocessed_config = config.preprocessed_training

    # Data parameters
    if args.data_dir:
        preprocessed_config.data_dir = args.data_dir
    if args.max_positions is not None:
        preprocessed_config.max_positions = args.max_positions
    if args.trap_ratio is not None:
        preprocessed_config.trap_ratio = args.trap_ratio
    if args.phase_filter:
        preprocessed_config.phase_filter = args.phase_filter

    # Training parameters
    if args.epochs is not None:
        preprocessed_config.epochs = args.epochs
    if args.batch_size is not None:
        preprocessed_config.batch_size = args.batch_size
    if args.learning_rate is not None:
        preprocessed_config.learning_rate = args.learning_rate
    if args.policy_loss:
        preprocessed_config.policy_loss = args.policy_loss

    # System parameters
    if args.cpu is not None:
        preprocessed_config.cpu = args.cpu
    if args.num_workers is not None:
        preprocessed_config.num_workers = args.num_workers
    if args.checkpoint_dir:
        preprocessed_config.checkpoint_dir = args.checkpoint_dir

    # Memory management
    # Only override config file settings if explicitly specified on command line
    if args.memory_conservative is not None:
        preprocessed_config.memory_conservative = args.memory_conservative
    if args.high_performance is not None:
        preprocessed_config.high_performance = args.high_performance
    if args.force_small_dataset is not None:
        preprocessed_config.force_small_dataset = args.force_small_dataset
    if args.no_swap is not None:
        preprocessed_config.no_swap = args.no_swap
    if args.memory_threshold is not None:
        preprocessed_config.memory_threshold = args.memory_threshold

    # Mode selection
    if args.fast_mode is not None:
        preprocessed_config.fast_mode = args.fast_mode

    # Debug options
    if args.verbose is not None:
        preprocessed_config.verbose = args.verbose
    if args.metadata_debug is not None:
        preprocessed_config.metadata_debug = args.metadata_debug

    # Incremental training options
    if hasattr(args, 'resume_training') and args.resume_training is not None:
        preprocessed_config.resume_from_checkpoint = args.resume_training
    if hasattr(args, 'resume_checkpoint') and args.resume_checkpoint:
        preprocessed_config.resume_checkpoint_path = args.resume_checkpoint
    if hasattr(args, 'save_every_n_epochs') and args.save_every_n_epochs is not None:
        preprocessed_config.save_checkpoint_every_n_epochs = args.save_every_n_epochs

    # Data traversal options
    if hasattr(args, 'full_traversal') and args.full_traversal is not None:
        preprocessed_config.full_dataset_traversal = args.full_traversal
    if hasattr(args, 'no_shuffle') and args.no_shuffle:
        preprocessed_config.shuffle_data = False
    if hasattr(args, 'data_workers') and args.data_workers is not None:
        preprocessed_config.data_loading_workers = args.data_workers

    # Advanced training options
    if hasattr(args, 'mixed_precision') and args.mixed_precision is not None:
        preprocessed_config.mixed_precision = args.mixed_precision
    if hasattr(args, 'compile_model') and args.compile_model is not None:
        preprocessed_config.compile_model = args.compile_model
    if hasattr(args, 'gradient_accumulation') and args.gradient_accumulation is not None:
        preprocessed_config.gradient_accumulation_steps = args.gradient_accumulation

    # Also update network config if fast mode is enabled
    if preprocessed_config.fast_mode:
        config.network.num_filters = 128
        config.network.num_residual_blocks = 5
    elif preprocessed_config.high_performance:
        config.network.num_filters = 768  # Updated for RTX4090
        config.network.num_residual_blocks = 20
        config.network.dropout_rate = 0.2
    elif preprocessed_config.memory_conservative:
        config.network.num_filters = 128
        config.network.num_residual_blocks = 8

    return config


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
    # Load configuration from file if provided
    if hasattr(args, 'config_file') and args.config_file:
        try:
            config = load_config_from_file(args.config_file)
            config = merge_config_with_args(config, args)
            print(f"📁 Using configuration from file: {args.config_file}")
        except (FileNotFoundError, ValueError) as e:
            print(f"❌ Configuration file error: {e}")
            print("📊 Falling back to default configuration")
            config = get_default_config()
    else:
        # Use preset configurations
        if args.fast_mode:
            config = get_fast_training_config()
            print("⚡ Using fast training configuration")
        else:
            config = get_default_config()
            print("📊 Using standard training configuration")

        # Override with command-line arguments for legacy compatibility
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

    # GPU settings - use preprocessed config if available, otherwise legacy logic
    if config.preprocessed_training:
        if not config.preprocessed_training.cpu:
            config.training.cuda = torch.cuda.is_available()
            if config.training.cuda:
                print(f"🚀 Using GPU: {torch.cuda.get_device_name()}")
            else:
                print("⚠️  CUDA not available, using CPU")
        else:
            config.training.cuda = False
            print("💻 Forcing CPU usage")
    else:
        # Legacy GPU settings
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


def train_with_chunked_approach(args, config):
    """Train using chunked approach to prevent memory overflow."""
    print("🧩 Using chunked training approach for memory safety")
    print("=" * 60)
    
    # Get configuration parameters
    if config.preprocessed_training:
        pc = config.preprocessed_training
        data_dir = pc.data_dir or args.data_dir
        batch_size = pc.batch_size
        epochs = pc.epochs
        learning_rate = pc.learning_rate
        checkpoint_dir = pc.checkpoint_dir
        max_positions = pc.max_positions
        phase_filter = pc.phase_filter
        memory_threshold = getattr(pc, 'memory_threshold', None) or getattr(args, 'memory_threshold', 32.0)
        chunk_memory = getattr(pc, 'chunk_memory', None) or getattr(args, 'chunk_memory', 16.0)
    else:
        # Fallback to args
        data_dir = args.data_dir
        batch_size = args.batch_size
        epochs = args.epochs
        learning_rate = args.learning_rate
        checkpoint_dir = args.checkpoint_dir
        max_positions = args.max_positions
        phase_filter = args.phase_filter
        memory_threshold = args.memory_threshold
        chunk_memory = args.chunk_memory
    
    print(f"📋 Chunked Training Configuration:")
    print(f"  Data Directory: {data_dir}")
    print(f"  Memory Threshold: {memory_threshold:.1f} GB")
    print(f"  Chunk Memory Target: {chunk_memory:.1f} GB")
    print(f"  Batch Size: {batch_size}")
    print(f"  Epochs: {epochs}")
    print(f"  Max Positions: {max_positions or 'All'}")
    
    # Validate data directory
    if not validate_preprocessed_data(data_dir):
        return False
    
    # Create data loader
    print(f"\n📦 Creating data loader...")
    try:
        loader = FastDataLoader(data_dir)
        stats = loader.get_statistics()
        if stats:
            print(f"📊 Data Statistics:")
            print(f"  Total positions: {stats.get('total_positions', 0):,}")
            print(f"  Processing speed: {stats.get('positions_per_second', 0):.0f} pos/s")
    except Exception as e:
        print(f"❌ Failed to create data loader: {e}")
        return False
    
    # Create neural network
    print(f"\n🧠 Creating neural network...")
    try:
        model_args = {
            'input_channels': 19,
            'num_filters': config.network.num_filters,
            'num_residual_blocks': config.network.num_residual_blocks,
            'action_size': 1000,
            'dropout_rate': config.network.dropout_rate
        }
        
        device = 'cuda' if config.training.cuda else 'cpu'
        neural_network = AlphaZeroNetworkWrapper(model_args, device)
        
        print(f"✅ Neural network created successfully ({device})")
        print(f"  Filters: {config.network.num_filters}")
        print(f"  Residual blocks: {config.network.num_residual_blocks}")
        
    except Exception as e:
        print(f"❌ Failed to create neural network: {e}")
        return False
    
    # Create chunked trainer
    print(f"\n🧩 Initializing chunked trainer...")
    try:
        chunked_trainer = ChunkedTrainer(
            neural_network=neural_network,
            data_loader=loader,
            memory_threshold_gb=memory_threshold,
            target_chunk_memory_gb=chunk_memory
        )
        print(f"✅ Chunked trainer initialized")
    except Exception as e:
        print(f"❌ Failed to create chunked trainer: {e}")
        return False
    
    # Start chunked training
    print(f"\n🚀 Starting chunked training...")
    try:
        # Build scheduler and plateau params from config (if present)
        scheduler_type = "cosine"
        scheduler_params = {}
        plateau_detection_params = None
        if config.preprocessed_training and config.preprocessed_training.high_performance:
            scheduler_type = "reduce_on_plateau"
            scheduler_params = {
                'mode': 'min',
                'factor': 0.5,
                'patience': 2,
                'threshold': 5e-4,
                'cooldown': 0,
                'min_lr': 1e-6
            }
            plateau_detection_params = {
                'window': 400,
                'min_history': 400,
                'rel_std_threshold': 0.004,
                'warmup_batches': 5000
            }

        # Prefer JSON-config overrides if provided
        try:
            if config.preprocessed_training:
                pc = config.preprocessed_training
                if hasattr(pc, 'scheduler') and isinstance(pc.scheduler, dict):
                    sch = pc.scheduler
                    scheduler_type = str(sch.get('type', scheduler_type))
                    if isinstance(sch.get('params'), dict):
                        scheduler_params.update(sch['params'])
                if hasattr(pc, 'plateau_detection') and isinstance(pc.plateau_detection, dict):
                    if plateau_detection_params is None:
                        plateau_detection_params = {}
                    plateau_detection_params.update(pc.plateau_detection)
                stability_detection_params = None
                if hasattr(pc, 'stability_detection') and isinstance(pc.stability_detection, dict):
                    stability_detection_params = dict(pc.stability_detection)
        except Exception:
            pass

        # Defensive defaults: ensure epochs, batch_size, learning_rate are valid
        epochs = epochs if (epochs is not None and epochs > 0) else (config.preprocessed_training.epochs if config.preprocessed_training else 10)
        batch_size = batch_size if (batch_size is not None and batch_size > 0) else (config.preprocessed_training.batch_size if config.preprocessed_training else 64)
        learning_rate = learning_rate if (learning_rate is not None and learning_rate > 0) else (config.preprocessed_training.learning_rate if config.preprocessed_training else 1e-3)

        training_stats = chunked_trainer.train_chunked(
            epochs=epochs,
            batch_size=batch_size,
            learning_rate=learning_rate,
            max_positions=max_positions,
            phase_filter=phase_filter,
            gradient_accumulation_steps=getattr(config.preprocessed_training, 'gradient_accumulation_steps', 1) if config.preprocessed_training else 1,
            save_checkpoint_every=getattr(config.preprocessed_training, 'save_checkpoint_every_n_epochs', 5) if config.preprocessed_training else 5,
            checkpoint_dir=checkpoint_dir,
            auto_resume=True,
            scheduler_type=scheduler_type,
            scheduler_params=scheduler_params,
            plateau_detection_params=plateau_detection_params
            ,stability_detection_params=stability_detection_params
        )
        
        print(f"\n🎉 Chunked training completed successfully!")
        print(f"📊 Final Statistics:")
        print(f"  Epochs completed: {training_stats['epochs_completed']}")
        print(f"  Chunks processed: {training_stats['chunks_processed']}")
        print(f"  Total samples: {training_stats['samples_processed']:,}")
        print(f"  Average loss: {training_stats['total_loss'] / max(training_stats['epochs_completed'], 1):.6f}")
        print(f"  Training time: {training_stats['training_time']:.1f}s")
        
        # Save final model
        final_model_path = Path(checkpoint_dir) / "final_chunked_model.tar"
        final_model_path.parent.mkdir(parents=True, exist_ok=True)
        neural_network.save(str(final_model_path))
        print(f"💾 Final model saved: {final_model_path}")
        
        return True
        
    except Exception as e:
        print(f"❌ Chunked training failed: {e}")
        logger.exception("Chunked training failed with exception")
        return False


def train_with_preprocessed_data(args, config=None):
    """Train using the preprocessed data."""
    print("🚀 Starting Alpha Zero training with preprocessed data")
    print("=" * 60)

    # 1. Create configuration if not provided
    if config is None:
        config = create_training_config(args)
    
    # 2. Check if chunked training should be used
    use_chunked_training = getattr(args, 'chunked_training', False) or getattr(args, 'force_chunked', False)
    
    # Also check config file for chunked training setting
    if not use_chunked_training and config.preprocessed_training:
        use_chunked_training = getattr(config.preprocessed_training, 'chunked_training', False)
    
    # Auto-enable chunked training for high-performance mode or large datasets
    if not use_chunked_training and hasattr(args, 'high_performance') and args.high_performance:
        # Check available memory and dataset size
        import psutil
        memory_info = psutil.virtual_memory()
        available_gb = memory_info.available / (1024**3)
        
        # Enable chunked training if memory is limited or dataset is large
        if available_gb < 64 or (hasattr(args, 'max_positions') and args.max_positions and args.max_positions > 10000000):
            use_chunked_training = True
            print("🔄 Auto-enabling chunked training for memory safety")
    
    if use_chunked_training:
        return train_with_chunked_approach(args, config)

    # Use config parameters if available, otherwise fall back to args
    if config.preprocessed_training:
        pc = config.preprocessed_training  # preprocessed config shorthand
        data_dir = pc.data_dir or args.data_dir
        batch_size = pc.batch_size
        trap_ratio = pc.trap_ratio
        phase_filter = pc.phase_filter
        epochs = pc.epochs
        learning_rate = pc.learning_rate
        checkpoint_dir = pc.checkpoint_dir
        max_positions = pc.max_positions
        num_workers = pc.num_workers
        policy_loss = pc.policy_loss
        metadata_debug = pc.metadata_debug
        memory_conservative = pc.memory_conservative
        high_performance = pc.high_performance
        force_small_dataset = pc.force_small_dataset
        no_swap = pc.no_swap
    else:
        # Fall back to args for backward compatibility
        data_dir = args.data_dir
        batch_size = args.batch_size
        trap_ratio = args.trap_ratio
        phase_filter = args.phase_filter
        epochs = args.epochs
        learning_rate = args.learning_rate
        checkpoint_dir = args.checkpoint_dir
        max_positions = args.max_positions
        num_workers = args.num_workers
        policy_loss = args.policy_loss
        metadata_debug = args.metadata_debug
        memory_conservative = args.memory_conservative or False
        high_performance = args.high_performance or False
        force_small_dataset = args.force_small_dataset or False
        no_swap = args.no_swap

    # 2. Validate data
    if not validate_preprocessed_data(data_dir):
        return False

    # 3. Create data loader
    print(f"\n📦 Creating data loader...")
    print(f"  Data directory: {data_dir}")
    print(f"  Batch size: {batch_size}")
    print(f"  Trap ratio: {trap_ratio}")
    print(f"  Game phase filter: {phase_filter or 'All'}")

    try:
        loader = FastDataLoader(data_dir)

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
        if force_small_dataset:
            safe_max_positions = min(max_positions or 100000, 100000)
            logger.warning(f"🔒 Force small dataset mode: limiting to {safe_max_positions:,} positions")
        elif high_performance:
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
                max_positions or 50000000,  # User-specified or default 50 million
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
            if no_swap:
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
                if no_swap:
                    logger.info("✅ --no-swap is enabled, no need to worry about disk space")
                else:
                    logger.warning(f"   Consider adding the --no-swap option or reducing --max-positions")
        elif memory_conservative:
            # Conservative mode: suitable for low-memory environments
            conservative_positions = int(available_memory_gb * 1000)  # Approx. 1000 positions per GB
            safe_max_positions = min(max_positions or 200000, conservative_positions)
            logger.warning(f"🛡️  Conservative memory mode: limiting to {safe_max_positions:,} positions "
                           f"(available memory: {available_memory_gb:.1f} GB)")
        elif available_memory_gb >= 100:
            # High-end configuration: fully utilize large memory (e.g., RTX4090 + 192GB)
            # Each position actually needs ~4KB, but reserve 2x buffer for processing and conversion
            positions_per_gb = 2000  # Approx. 2000 positions per GB (conservative but fully utilizes)
            safe_max_positions = min(
                max_positions or 20000000,  # Default 20 million positions
                int(available_memory_gb * 0.6 * positions_per_gb)  # Use 60% of available memory
            )
            logger.info(f"🚀 High-performance mode (RTX4090+ config): loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB, will use ~{safe_max_positions*4/1024/1024:.1f} GB)")
        elif available_memory_gb >= 64:
            # Mid-to-high-end configuration: reasonable memory utilization
            positions_per_gb = 1500  # Approx. 1500 positions per GB
            safe_max_positions = min(
                max_positions or 10000000,  # Default 10 million positions
                int(available_memory_gb * 0.5 * positions_per_gb)  # Use 50% of available memory
            )
            logger.info(f"🔧 Mid-high-end mode: loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB)")
        elif available_memory_gb >= 32:
            # Mid-range configuration: cautious memory usage
            positions_per_gb = 1000  # Approx. 1000 positions per GB
            safe_max_positions = min(
                max_positions or 2000000,  # Default 2 million positions
                int(available_memory_gb * 0.4 * positions_per_gb)  # Use 40% of available memory
            )
            logger.info(f"🔧 Mid-range mode: loading up to {safe_max_positions:,} positions "
                        f"(available memory: {available_memory_gb:.1f} GB)")
        else:
            # Low-end configuration: strictly limit memory usage
            positions_per_gb = 500  # Approx. 500 positions per GB
            safe_max_positions = min(
                max_positions or 500000,  # Default 500,000 positions
                int(available_memory_gb * 0.3 * positions_per_gb)  # Use 30% of available memory
            )
            logger.warning(f"🛡️  Low-memory mode: limiting to {safe_max_positions:,} positions "
                           f"(available memory: {available_memory_gb:.1f} GB)")

        # Configure data loading based on traversal mode
        if config.preprocessed_training and config.preprocessed_training.full_dataset_traversal:
            # Full dataset traversal mode - use all data without sampling
            actual_max_positions = None  # Use all available data
            shuffle_data = config.preprocessed_training.shuffle_data
            actual_trap_ratio = 0.0  # No trap sampling in full traversal mode
            actual_num_workers = config.preprocessed_training.data_loading_workers
            prefetch_factor = config.preprocessed_training.prefetch_factor
            pin_memory = config.preprocessed_training.pin_memory

            print(f"🔄 Full dataset traversal mode enabled")
            print(f"  Using entire dataset (~207GB)")
            print(f"  Data shuffle: {'Enabled' if shuffle_data else 'Disabled'}")
            print(f"  Data workers: {actual_num_workers}")
            print(f"  Prefetch factor: {prefetch_factor}")
        else:
            # Legacy sampling mode
            actual_max_positions = safe_max_positions
            shuffle_data = True
            actual_trap_ratio = trap_ratio
            actual_num_workers = num_workers
            prefetch_factor = 2
            pin_memory = False

            print(f"📊 Sampling mode (legacy)")
            print(f"  Max positions: {actual_max_positions:,}")
            print(f"  Trap ratio: {actual_trap_ratio}")

        dataloader = loader.create_dataloader(
            phase_filter=phase_filter,
            max_positions=actual_max_positions,
            batch_size=batch_size,
            shuffle=shuffle_data,
            trap_ratio=actual_trap_ratio,
            num_workers=actual_num_workers,
            pin_memory=pin_memory if hasattr(loader, 'pin_memory') else False,
            prefetch_factor=prefetch_factor if hasattr(loader, 'prefetch_factor') else 2
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

        # Apply advanced optimizations for high-performance training
        if config.preprocessed_training:
            pc = config.preprocessed_training

            # Enable model compilation for PyTorch 2.0+ (with Windows compatibility check)
            if pc.compile_model and hasattr(torch, 'compile'):
                try:
                    import platform
                    # Check if Triton is available (required for torch.compile)
                    try:
                        import triton
                        triton_available = True
                    except ImportError:
                        triton_available = False
                    
                    if not triton_available and platform.system() == 'Windows':
                        print("⚠️  Triton not available on Windows, skipping model compilation")
                        print("   Model will run without torch.compile optimization")
                    else:
                        neural_network.net = torch.compile(neural_network.net)
                        print("✅ Model compilation enabled (PyTorch 2.0+)")
                except Exception as e:
                    print(f"⚠️  Model compilation failed: {e}")
                    print("   Continuing without model compilation...")

            # Configure mixed precision training
            scaler = None
            if pc.mixed_precision and device == 'cuda':
                try:
                    from torch.amp import GradScaler
                    scaler = GradScaler('cuda')
                    print("✅ Mixed precision training enabled")
                except ImportError:
                    scaler = None
                    print("⚠️ Mixed precision not available, using standard training")
            else:
                scaler = None

        # Create trainer (simplified version, specialized for preprocessed data)
        trainer_args = {
            'cuda': config.training.cuda,
            'train_batch_size': config.training.train_batch_size,
            'train_epochs': config.training.train_epochs,
            'train_lr': config.training.train_lr,
            'checkpoint_dir': checkpoint_dir,
            'checkpoint_interval': 5
        }

        print(f"✅ Neural network created successfully ({device})")

    except Exception as e:
        print(f"❌ Failed to create neural network: {e}")
        return False

    # 5. Initialize checkpoint manager and resume training if needed
    checkpoint_manager = None
    start_epoch = 0
    loss_history = []

    if config.preprocessed_training:
        pc = config.preprocessed_training
        checkpoint_manager = CheckpointManager(
            checkpoint_dir,
            keep_n_checkpoints=pc.keep_n_checkpoints
        )

        # Handle checkpoint resumption
        if pc.resume_from_checkpoint:
            if pc.resume_checkpoint_path:
                resume_path = pc.resume_checkpoint_path
            else:
                resume_path = checkpoint_manager.get_latest_checkpoint()

            if resume_path:
                print(f"🔄 Resuming training from checkpoint: {resume_path}")
                try:
                    training_state = checkpoint_manager.load_checkpoint(neural_network, resume_path)
                    start_epoch = training_state.get('epoch', 0)
                    loss_history = training_state.get('loss_history', [])
                    print(f"✅ Resumed from epoch {start_epoch}")
                except Exception as e:
                    print(f"⚠️  Failed to resume from checkpoint: {e}")
                    print("Starting fresh training...")
            else:
                print("🔄 Resume requested but no checkpoint found, starting fresh training")

    # 6. Start training
    print(f"\n🎯 Starting training with preprocessed data...")
    print(f"  Total epochs: {epochs}")
    print(f"  Starting from epoch: {start_epoch + 1}")
    print(f"  Learning rate: {learning_rate}")
    print(f"  Batch size: {batch_size}")
    print(f"  Checkpoint directory: {checkpoint_dir}")
    if config.preprocessed_training:
        pc = config.preprocessed_training
        print(f"  Gradient accumulation steps: {pc.gradient_accumulation_steps}")
        print(f"  Mixed precision: {'Enabled' if pc.mixed_precision else 'Disabled'}")
        print(f"  Model compilation: {'Enabled' if pc.compile_model else 'Disabled'}")
        print(f"  Save checkpoint every: {pc.save_checkpoint_every_n_epochs} epochs")

    start_time = time.time()

    try:
        # Training loop
        neural_network.net.train()

        # Set up optimizer
        if neural_network.optimizer is None:
            neural_network.optimizer = torch.optim.Adam(
                neural_network.net.parameters(),
                lr=learning_rate,
                weight_decay=1e-4  # Add weight decay for better generalization
            )

        # Set up learning rate scheduler for long training
        if config.preprocessed_training and config.preprocessed_training.high_performance:
            scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
                neural_network.optimizer, T_0=5, T_mult=2, eta_min=1e-5
            )
        else:
            scheduler = None

        total_batches = len(dataloader)

        for epoch in range(start_epoch, epochs):
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

            print(f"\n📈 Epoch {epoch + 1}/{epochs}")
            print(f"   Available Memory: {current_memory:.1f} GB")
            print(f"   Memory Usage: {memory_usage_percent:.1f}%")
            print(f"   Swap Usage: {swap_usage_mb:.1f} MB")

            # More reasonable swap usage warning threshold
            if swap_usage_mb > 5120:  # Warn only if above 5GB
                logger.warning(f"⚠️  High swap usage: {swap_usage_mb:.1f} MB")
                logger.warning("   Recommend monitoring memory usage")

            # Strict memory monitoring
            if high_performance:
                if memory_usage_percent > 85:
                    logger.error(f"🚨 Memory usage too high ({memory_usage_percent:.1f}%), training may become unstable")
                    logger.error("   Recommend immediately reducing --max-positions or batch size")
                elif memory_usage_percent > 75:
                    logger.warning(f"⚠️  High memory usage ({memory_usage_percent:.1f}%), monitor closely")

                # Set different swap thresholds based on whether --no-swap is enabled
                # Get baseline swap usage (normal system usage before training starts)
                if not hasattr(config, '_baseline_swap_mb'):
                    config._baseline_swap_mb = swap_usage_mb
                    logger.info(f"📊 Baseline Swap Usage: {config._baseline_swap_mb:.1f} MB")

                # Calculate the increase relative to the baseline
                swap_increase_mb = swap_usage_mb - config._baseline_swap_mb

                if no_swap:
                    # NO-SWAP mode: allow baseline usage + 2GB increase
                    swap_threshold = config._baseline_swap_mb + 2048
                    if swap_usage_mb > swap_threshold:
                        logger.error(f"🚨 NO-SWAP mode: Swap memory has increased too much")
                        logger.error(f"   Current: {swap_usage_mb:.1f} MB, Baseline: {config._baseline_swap_mb:.1f} MB")
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

            # Configure gradient accumulation
            gradient_accumulation_steps = 1
            if config.preprocessed_training:
                gradient_accumulation_steps = config.preprocessed_training.gradient_accumulation_steps

            accumulated_loss = 0.0
            accumulated_policy_loss = 0.0
            accumulated_value_loss = 0.0

            for batch_idx, (boards, policies, values, metadata) in enumerate(dataloader):
                # Metadata and channel feature debugging (only output for the first batch to avoid polluting logs)
                if metadata_debug and batch_idx == 0:
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
                boards = boards.to(device, non_blocking=True)
                values = values.to(device, non_blocking=True)
                policies = policies.to(device, non_blocking=True)

                # Mixed precision forward pass
                if scaler is not None:
                    with torch.amp.autocast('cuda'):
                        # Forward pass
                        pred_policies, pred_values = neural_network.net(boards)

                        # Adjust policy target dimensions to match network output
                        if policies.shape[1] != pred_policies.shape[1]:
                            batch_size = policies.shape[0]
                            num_actions = pred_policies.shape[1]
                            expanded = torch.zeros(batch_size, num_actions, device=device)
                            to_copy = min(24, num_actions)
                            expanded[:, :to_copy] = policies[:, :to_copy]
                            sums = expanded.sum(dim=1, keepdim=True)
                            fallback = torch.full_like(expanded, 1.0 / num_actions)
                            policies = torch.where(sums > 0, expanded / sums, fallback)

                        # Calculate loss
                        if policy_loss == 'kld':
                            log_probs = torch.nn.functional.log_softmax(pred_policies, dim=1)
                            policy_loss_value = torch.nn.functional.kl_div(log_probs, policies, reduction='batchmean')
                        else:
                            probs = torch.nn.functional.softmax(pred_policies, dim=1)
                            policy_loss_value = torch.nn.functional.mse_loss(probs, policies)
                        value_loss_value = torch.nn.functional.mse_loss(pred_values.squeeze(), values)
                        total_loss = policy_loss_value + value_loss_value

                        # Scale loss for gradient accumulation
                        total_loss = total_loss / gradient_accumulation_steps
                else:
                    # Standard precision forward pass
                    pred_policies, pred_values = neural_network.net(boards)

                    # Adjust policy target dimensions to match network output
                    if policies.shape[1] != pred_policies.shape[1]:
                        batch_size = policies.shape[0]
                        num_actions = pred_policies.shape[1]
                        expanded = torch.zeros(batch_size, num_actions, device=device)
                        to_copy = min(24, num_actions)
                        expanded[:, :to_copy] = policies[:, :to_copy]
                        sums = expanded.sum(dim=1, keepdim=True)
                        fallback = torch.full_like(expanded, 1.0 / num_actions)
                        policies = torch.where(sums > 0, expanded / sums, fallback)

                    # Calculate loss
                    if policy_loss == 'kld':
                        log_probs = torch.nn.functional.log_softmax(pred_policies, dim=1)
                        policy_loss_value = torch.nn.functional.kl_div(log_probs, policies, reduction='batchmean')
                    else:
                        probs = torch.nn.functional.softmax(pred_policies, dim=1)
                        policy_loss_value = torch.nn.functional.mse_loss(probs, policies)
                    value_loss_value = torch.nn.functional.mse_loss(pred_values.squeeze(), values)
                    total_loss = policy_loss_value + value_loss_value

                    # Scale loss for gradient accumulation
                    total_loss = total_loss / gradient_accumulation_steps

                # Backward pass with gradient accumulation
                if scaler is not None:
                    # Mixed precision backward pass
                    scaler.scale(total_loss).backward()

                    if (batch_idx + 1) % gradient_accumulation_steps == 0:
                        # Gradient clipping for stability
                        scaler.unscale_(neural_network.optimizer)
                        torch.nn.utils.clip_grad_norm_(neural_network.net.parameters(), max_norm=1.0)

                        scaler.step(neural_network.optimizer)
                        scaler.update()
                        neural_network.optimizer.zero_grad()
                else:
                    # Standard backward pass
                    total_loss.backward()

                    if (batch_idx + 1) % gradient_accumulation_steps == 0:
                        # Gradient clipping for stability
                        torch.nn.utils.clip_grad_norm_(neural_network.net.parameters(), max_norm=1.0)

                        neural_network.optimizer.step()
                        neural_network.optimizer.zero_grad()

                # Statistics (scale back for logging)
                actual_loss = total_loss.item() * gradient_accumulation_steps
                actual_policy_loss = policy_loss_value.item() * gradient_accumulation_steps
                actual_value_loss = value_loss_value.item() * gradient_accumulation_steps

                accumulated_loss += actual_loss
                accumulated_policy_loss += actual_policy_loss
                accumulated_value_loss += actual_value_loss

                epoch_loss += actual_loss
                epoch_policy_loss += actual_policy_loss
                epoch_value_loss += actual_value_loss

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

            # Update learning rate scheduler
            if scheduler is not None:
                scheduler.step()
                current_lr = scheduler.get_last_lr()[0]
                print(f"  Learning rate: {current_lr:.6f}")

            # Add loss to history
            loss_history.append(avg_loss)

            # Save checkpoint using checkpoint manager
            if checkpoint_manager is not None:
                save_interval = config.preprocessed_training.save_checkpoint_every_n_epochs
                if (epoch + 1) % save_interval == 0 or (epoch + 1) == epochs:
                    try:
                        optimizer_state = neural_network.optimizer.state_dict()
                        config_dict = config.to_dict()

                        checkpoint_path = checkpoint_manager.save_checkpoint(
                            neural_network,
                            epoch + 1,
                            optimizer_state,
                            loss_history,
                            config_dict
                        )
                        print(f"💾 Checkpoint saved: {checkpoint_path}")
                    except Exception as e:
                        print(f"⚠️  Failed to save checkpoint: {e}")
            else:
                # Legacy checkpoint saving
                if (epoch + 1) % 5 == 0:
                    checkpoint_path = Path(checkpoint_dir) / f"preprocessed_epoch_{epoch + 1}.tar"
                    checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
                    neural_network.save(str(checkpoint_path))
                    print(f"💾 Checkpoint saved: {checkpoint_path}")

        # Training finished
        total_time = time.time() - start_time
        print(f"\n🎉 Training complete!")
        print(f"  Total time: {total_time:.1f}s ({total_time/60:.1f}min)")
        print(f"  Average time per epoch: {total_time/epochs:.1f}s")

        # Save final model
        final_model_path = Path(checkpoint_dir) / "final_preprocessed_model.tar"
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

  # Using Configuration Files (Recommended)
  python train_with_preprocessed.py --config train_with_preprocessed_config.json
  python train_with_preprocessed.py --config train_with_preprocessed_fast.json
  python train_with_preprocessed.py --config train_with_preprocessed_high_performance.json
  python train_with_preprocessed.py --config train_with_preprocessed_conservative.json

  # Override config file settings with command line
  python train_with_preprocessed.py \\
    --config train_with_preprocessed_config.json \\
    --data-dir "G:\\preprocessed_data" \\
    --epochs 15

  # Legacy Mode (without config file)
  python train_with_preprocessed.py --data-dir "G:\\preprocessed_data"

  # Advanced Options (Legacy)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --batch-size 128 \\
    --epochs 20 \\
    --learning-rate 0.001 \\
    --trap-ratio 0.4 \\
    --phase-filter "placement"

  # Fast Test Mode (Legacy)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --fast-mode \\
    --max-positions 10000

  # High-Performance Mode (Legacy)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --high-performance \\
    --batch-size 256 \\
    --epochs 10

  # Memory-Conservative Mode (Legacy)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --memory-conservative \\
    --batch-size 32 \\
    --epochs 5

  # Chunked Training Mode (Memory Safe)
  python train_with_preprocessed.py \\
    --config train_with_preprocessed_high_performance.json \\
    --data-dir "G:\\preprocessed_data" \\
    --chunked-training \\
    --chunk-memory 16.0 \\
    --memory-threshold 32.0

  # Force Chunked Training (Even for Small Datasets)
  python train_with_preprocessed.py \\
    --data-dir "G:\\preprocessed_data" \\
    --force-chunked \\
    --chunk-memory 8.0 \\
    --batch-size 64
        """
    )

    # Configuration file
    parser.add_argument('--config', '--config-file', dest='config_file',
                        help='Path to configuration file (JSON or YAML)')

    # Required arguments (optional if config file is provided)
    parser.add_argument('--data-dir',
                        help='Path to the preprocessed data directory (containing .npz files)')

    # Training parameters
    parser.add_argument('--epochs', type=int,
                        help='Number of training epochs (default: 10)')
    parser.add_argument('--batch-size', type=int,
                        help='Batch size (default: 64)')
    parser.add_argument('--learning-rate', type=float,
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
    parser.add_argument('--num-workers', type=int,
                        help='Number of worker processes for data loading (default: 2)')
    parser.add_argument('--checkpoint-dir',
                        help='Directory to save checkpoints (default: checkpoints_preprocessed)')

    # Mode selection
    parser.add_argument('--fast-mode', action='store_true',
                        help='Fast training mode (smaller network and parameters)')

    # Memory management options
    parser.add_argument('--memory-safe', action='store_true',
                        help='Enable memory-safe mode (strictly controls physical memory usage)')
    parser.add_argument('--memory-threshold', type=float,
                        help='Physical memory safety threshold (in GB, default: 16.0)')
    parser.add_argument('--force-small-dataset', action='store_true', default=None,
                        help='Force using a small dataset mode (max 100,000 positions)')
    parser.add_argument('--memory-conservative', action='store_true', default=None,
                        help='Use the most conservative memory settings (suitable for large datasets)')
    parser.add_argument('--high-performance', action='store_true', default=None,
                        help='High-performance mode (for RTX4090 + 192GB+ RAM configurations)')
    parser.add_argument('--no-swap', action='store_true',
                        help='Limit swap memory growth (allows system baseline usage + 2GB increase)')
    
    # Chunked training options
    parser.add_argument('--chunked-training', action='store_true',
                        help='Enable chunked training to prevent memory overflow')
    parser.add_argument('--chunk-memory', type=float,
                        help='Target memory usage per chunk (in GB, default: 16.0)')
    parser.add_argument('--force-chunked', action='store_true',
                        help='Force chunked training even for smaller datasets')

    # Other options
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Verbose output')

    # Metadata and loss function debugging/control
    parser.add_argument('--metadata-debug', action='store_true',
                        help='Print metadata and feature channel stats for the first batch for verification')
    parser.add_argument('--policy-loss', choices=['kld', 'mse'], default='kld',
                        help='Policy loss function type: kld or mse (default: kld)')

    # Incremental training options
    parser.add_argument('--resume-training', action='store_true',
                        help='Resume training from the latest checkpoint')
    parser.add_argument('--resume-checkpoint', type=str,
                        help='Specific checkpoint path to resume from')
    parser.add_argument('--save-every-n-epochs', type=int,
                        help='Save checkpoint every N epochs (overrides config)')

    # Data traversal options
    parser.add_argument('--full-traversal', action='store_true',
                        help='Use full dataset traversal without sampling')
    parser.add_argument('--no-shuffle', action='store_true',
                        help='Disable data shuffling between epochs')
    parser.add_argument('--data-workers', type=int,
                        help='Number of data loading workers (separate from training workers)')

    # Advanced training options
    parser.add_argument('--mixed-precision', action='store_true',
                        help='Enable automatic mixed precision training')
    parser.add_argument('--no-mixed-precision', dest='mixed_precision', action='store_false',
                        help='Disable mixed precision training')
    parser.add_argument('--compile-model', action='store_true',
                        help='Enable PyTorch 2.0+ model compilation')
    parser.add_argument('--no-compile-model', dest='compile_model', action='store_false',
                        help='Disable model compilation')
    parser.add_argument('--gradient-accumulation', type=int,
                        help='Number of gradient accumulation steps')

    # Set defaults for mixed precision and compilation
    parser.set_defaults(mixed_precision=None, compile_model=None)

    args = parser.parse_args()

    # Check for option conflicts and resolve them automatically
    conflict_warnings = []

    # Check for memory mode conflicts
    memory_modes = [args.memory_conservative or False, args.high_performance or False, args.force_small_dataset or False]
    active_memory_modes = sum(memory_modes)

    if active_memory_modes > 1:
        if (args.high_performance or False) and (args.memory_conservative or False):
            conflict_warnings.append("⚠️  Conflict detected: --high-performance and --memory-conservative specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing high-performance mode (ignoring conservative mode)")
            args.memory_conservative = False

        if (args.high_performance or False) and (args.force_small_dataset or False):
            conflict_warnings.append("⚠️  Conflict detected: --high-performance and --force-small-dataset specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing high-performance mode (ignoring small dataset mode)")
            args.force_small_dataset = False

        if (args.memory_conservative or False) and (args.force_small_dataset or False):
            conflict_warnings.append("⚠️  Conflict detected: --memory-conservative and --force-small-dataset specified simultaneously")
            conflict_warnings.append("   Resolution: Prioritizing small dataset mode (stricter limit)")
            args.memory_conservative = False

    # Check compatibility of max-positions with memory modes
    if args.max_positions:
        if (args.memory_conservative or False) and args.max_positions > 500000:
            conflict_warnings.append(f"⚠️  Conflict detected: --max-positions ({args.max_positions:,}) is too large for --memory-conservative mode")
            conflict_warnings.append(f"   Suggestion: Conservative mode recommends not exceeding 500,000 positions")

        if (args.force_small_dataset or False) and args.max_positions > 100000:
            conflict_warnings.append(f"⚠️  Conflict detected: --max-positions ({args.max_positions:,}) is too large for --force-small-dataset mode")
            conflict_warnings.append(f"   Resolution: Limiting to 100,000 positions")
            args.max_positions = 100000

        if (args.high_performance or False) and args.max_positions < 1000000:
            conflict_warnings.append(f"⚠️  Notice: A small --max-positions ({args.max_positions:,}) was specified in --high-performance mode")
            conflict_warnings.append(f"   Suggestion: High-performance mode recommends at least 1,000,000 positions to fully utilize hardware")

    # Check compatibility of batch size with memory modes
    if args.batch_size:
        if (args.memory_conservative or False) and args.batch_size > 64:
            conflict_warnings.append(f"⚠️  Conflict detected: --batch-size ({args.batch_size}) is too large for --memory-conservative mode")
            conflict_warnings.append(f"   Suggestion: Conservative mode recommends a batch size no larger than 64")

        if (args.high_performance or False) and args.batch_size < 128:
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
    if not args.config_file and not args.data_dir:
        print("❌ Either --config-file or --data-dir must be provided")
        return 1

    if args.data_dir and not Path(args.data_dir).exists():
        print(f"❌ Data directory does not exist: {args.data_dir}")
        return 1

    # Display configuration
    print(f"📋 Training Configuration:")
    if args.config_file:
        print(f"  Config File: {args.config_file}")
    print(f"  Data Directory: {args.data_dir or 'From config file'}")
    print(f"  Epochs: {args.epochs if args.epochs is not None else 'From config'}")
    print(f"  Batch Size: {args.batch_size if args.batch_size is not None else 'From config'}")
    print(f"  Learning Rate: {args.learning_rate if args.learning_rate is not None else 'From config'}")
    print(f"  Trap Ratio: {args.trap_ratio}")
    print(f"  Max Positions: {args.max_positions or 'Unlimited'}")
    print(f"  Game Phase: {args.phase_filter or 'All'}")
    print(f"  Device: {'CPU' if args.cpu else 'GPU (if available)'}")
    print(f"  Workers: {args.num_workers if args.num_workers is not None else 'From config'}")
    print(f"  Memory Safe Mode: {'Enabled' if hasattr(args, 'memory_safe') and args.memory_safe else 'Disabled'}")
    print(f"  Memory Threshold: {args.memory_threshold if args.memory_threshold is not None else 'From config'} GB")
    print(f"  Conservative Memory: {'Enabled' if (args.memory_conservative or False) else 'Disabled'}")
    print(f"  High Performance: {'Enabled' if (args.high_performance or False) else 'Disabled'}")
    print(f"  Disable Swap: {'Enabled' if args.no_swap else 'Disabled'}")
    print(f"  Force Small Dataset: {'Enabled' if (args.force_small_dataset or False) else 'Disabled'}")
    print(f"  Metadata Debug: {'Enabled' if args.metadata_debug else 'Disabled'}")
    print(f"  Policy Loss: {args.policy_loss.upper()}")
    print(f"  Chunked Training: {'Enabled' if getattr(args, 'chunked_training', False) or getattr(args, 'force_chunked', False) else 'Disabled'}")
    if getattr(args, 'chunked_training', False) or getattr(args, 'force_chunked', False):
        print(f"    Chunk Memory Target: {getattr(args, 'chunk_memory', 16.0):.1f} GB")

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
