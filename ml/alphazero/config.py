#!/usr/bin/env python3
"""
Configuration management for Alpha Zero training.

Provides default configurations and validation for different training scenarios.
"""

import os
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
import json
import yaml


@dataclass
class NetworkConfig:
    """Neural network configuration."""
    input_channels: int = 17
    num_filters: int = 256
    num_residual_blocks: int = 10
    dropout_rate: float = 0.3


@dataclass
class MCTSConfig:
    """MCTS configuration."""
    num_mcts_sims: int = 25
    c_puct: float = 1.0
    add_dirichlet_noise: bool = True
    dirichlet_alpha: float = 0.3
    dirichlet_epsilon: float = 0.25
    temperature_threshold: int = 10


@dataclass
class TrainingConfig:
    """Training configuration."""
    # Training loop
    iterations: int = 100
    games_per_iteration: int = 100
    max_examples: int = 200000

    # Neural network training
    train_batch_size: int = 64
    train_epochs: int = 5
    train_lr: float = 1e-3

    # Perfect Database pretraining
    use_pretraining: bool = True
    pretrain_positions: int = 50000
    pretrain_batch_size: int = 64
    pretrain_epochs: int = 10
    pretrain_lr: float = 1e-3

    # System
    cuda: bool = True
    self_play_workers: Optional[int] = None

    # Checkpointing
    checkpoint_dir: str = "checkpoints"
    checkpoint_interval: int = 10


@dataclass
class PerfectDBConfig:
    """Perfect Database configuration."""
    perfect_db_path: Optional[str] = None

    # Training method selection
    use_direct_perfect_db_training: bool = True  # True = direct extraction, False = MCTS simulation
    perfect_db_complete_enumeration: Optional[bool] = None  # None = auto-detect

    # Direct training parameters
    trap_ratio: float = 0.3  # Ratio of trap positions in sampling
    trap_weight: float = 2.0  # Weight multiplier for trap positions in training

    # Traditional loader parameters (for MCTS simulation mode)
    db_workers: int = 4
    db_cache_size: int = 10000
    db_batch_size: int = 1000

    # Phase weights for data generation
    phase_weights: Dict[str, float] = None

    def __post_init__(self):
        if self.phase_weights is None:
            self.phase_weights = {
                'placement': 0.45,
                'moving': 0.35,
                'flying': 0.20
            }


@dataclass
class PreprocessedTrainingConfig:
    """Configuration for training with preprocessed data."""
    # Data parameters
    data_dir: str = ""
    max_positions: Optional[int] = None
    trap_ratio: float = 0.3
    phase_filter: Optional[str] = None  # placement, moving, flying, or None for all

    # Training parameters
    epochs: int = 10
    batch_size: int = 64
    learning_rate: float = 1e-3
    policy_loss: str = "kld"  # kld or mse

    # Incremental training parameters
    resume_from_checkpoint: bool = False
    resume_checkpoint_path: Optional[str] = None
    save_checkpoint_every_n_epochs: int = 5
    keep_n_checkpoints: int = 3  # Keep only the last N checkpoints to save disk space

    # Data traversal parameters
    full_dataset_traversal: bool = False  # If True, traverse entire dataset without sampling
    shuffle_data: bool = True  # Shuffle data between epochs
    data_loading_workers: int = 4  # Separate from training workers
    prefetch_factor: int = 2  # Number of batches to prefetch per worker
    pin_memory: bool = True  # Pin memory for faster GPU transfer

    # Advanced training parameters
    gradient_accumulation_steps: int = 1  # Accumulate gradients over multiple batches
    mixed_precision: bool = True  # Use automatic mixed precision for faster training
    compile_model: bool = True  # Use torch.compile for optimization (PyTorch 2.0+)

    # System parameters
    cpu: bool = False
    num_workers: int = 2  # Kept for backward compatibility
    checkpoint_dir: str = "checkpoints_preprocessed"

    # Memory management
    memory_conservative: bool = False
    high_performance: bool = False
    force_small_dataset: bool = False
    no_swap: bool = False
    memory_threshold: float = 16.0
    chunked_training: bool = False
    chunk_memory: float = 16.0

    # Mode selection
    fast_mode: bool = False

    # Debug options
    verbose: bool = False
    metadata_debug: bool = False

    # Optional advanced scheduler and anomaly detection configuration
    scheduler: Optional[Dict[str, Any]] = None
    plateau_detection: Optional[Dict[str, Any]] = None


@dataclass
class AlphaZeroConfig:
    """Complete Alpha Zero configuration."""
    network: NetworkConfig
    mcts: MCTSConfig
    training: TrainingConfig
    perfect_db: PerfectDBConfig
    preprocessed_training: Optional[PreprocessedTrainingConfig] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        result = {
            'network': asdict(self.network),
            'mcts': asdict(self.mcts),
            'training': asdict(self.training),
            'perfect_db': asdict(self.perfect_db)
        }
        if self.preprocessed_training:
            result['preprocessed_training'] = asdict(self.preprocessed_training)
        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AlphaZeroConfig':
        """Create from dictionary."""
        preprocessed_training = None
        if 'preprocessed_training' in data:
            preprocessed_training = PreprocessedTrainingConfig(**data['preprocessed_training'])

        return cls(
            network=NetworkConfig(**data.get('network', {})),
            mcts=MCTSConfig(**data.get('mcts', {})),
            training=TrainingConfig(**data.get('training', {})),
            perfect_db=PerfectDBConfig(**data.get('perfect_db', {})),
            preprocessed_training=preprocessed_training
        )

    def save(self, filepath: str):
        """Save configuration to file."""
        config_dict = self.to_dict()

        if filepath.endswith('.json'):
            with open(filepath, 'w') as f:
                json.dump(config_dict, f, indent=2)
        elif filepath.endswith('.yaml') or filepath.endswith('.yml'):
            with open(filepath, 'w') as f:
                yaml.dump(config_dict, f, default_flow_style=False, indent=2)
        else:
            raise ValueError(f"Unsupported file format: {filepath}")

    @classmethod
    def load(cls, filepath: str) -> 'AlphaZeroConfig':
        """Load configuration from file."""
        if filepath.endswith('.json'):
            with open(filepath, 'r') as f:
                data = json.load(f)
        elif filepath.endswith('.yaml') or filepath.endswith('.yml'):
            with open(filepath, 'r') as f:
                data = yaml.safe_load(f)
        else:
            raise ValueError(f"Unsupported file format: {filepath}")

        return cls.from_dict(data)


def get_default_config() -> AlphaZeroConfig:
    """Get default Alpha Zero configuration."""
    return AlphaZeroConfig(
        network=NetworkConfig(),
        mcts=MCTSConfig(),
        training=TrainingConfig(),
        perfect_db=PerfectDBConfig()
    )


def get_fast_training_config() -> AlphaZeroConfig:
    """Get configuration for fast training (for testing)."""
    config = get_default_config()

    # Reduce neural network size
    config.network.num_filters = 128
    config.network.num_residual_blocks = 5

    # Reduce MCTS simulations
    config.mcts.num_mcts_sims = 10

    # Reduce training parameters
    config.training.iterations = 20
    config.training.games_per_iteration = 20
    config.training.train_epochs = 2
    config.training.pretrain_positions = 5000
    config.training.pretrain_epochs = 3

    return config


def get_production_config() -> AlphaZeroConfig:
    """Get configuration for production training."""
    config = get_default_config()

    # Larger neural network
    config.network.num_filters = 512
    config.network.num_residual_blocks = 20

    # More MCTS simulations
    config.mcts.num_mcts_sims = 100

    # Extended training
    config.training.iterations = 1000
    config.training.games_per_iteration = 500
    config.training.train_epochs = 10
    config.training.pretrain_positions = 200000
    config.training.pretrain_epochs = 20

    # Larger cache
    config.perfect_db.db_cache_size = 50000

    return config


def get_cpu_optimized_config() -> AlphaZeroConfig:
    """Get configuration optimized for CPU training."""
    config = get_default_config()

    # Smaller network for faster CPU training
    config.network.num_filters = 128
    config.network.num_residual_blocks = 8

    # Fewer MCTS simulations
    config.mcts.num_mcts_sims = 25

    # System settings
    config.training.cuda = False
    config.training.self_play_workers = None  # Use all CPU cores
    config.training.train_batch_size = 32  # Smaller batches for CPU

    return config


def get_gpu_optimized_config() -> AlphaZeroConfig:
    """Get configuration optimized for GPU training."""
    config = get_default_config()

    # Larger network to utilize GPU
    config.network.num_filters = 512
    config.network.num_residual_blocks = 15

    # More MCTS simulations
    config.mcts.num_mcts_sims = 50

    # System settings
    config.training.cuda = True
    config.training.self_play_workers = 2  # Fewer workers for GPU training
    config.training.train_batch_size = 128  # Larger batches for GPU

    return config


def get_preprocessed_training_config(mode: str = "default") -> AlphaZeroConfig:
    """Get configuration for training with preprocessed data."""
    config = get_default_config()

    if mode == "fast":
        preprocessed_config = PreprocessedTrainingConfig(
            epochs=5,
            batch_size=32,
            learning_rate=1e-3,
            fast_mode=True,
            max_positions=10000,
            checkpoint_dir="checkpoints_preprocessed_fast"
        )
        # Also adjust network for fast training
        config.network.num_filters = 128
        config.network.num_residual_blocks = 5
    elif mode == "high_performance":
        preprocessed_config = PreprocessedTrainingConfig(
            # Training parameters optimized for Ryzen 7950x + 192GB RAM + RTX4090
            epochs=30,
            batch_size=512,  # Large batch size to utilize RTX4090 fully
            learning_rate=2e-3,  # Slightly higher LR for large batches
            high_performance=True,

            # Data parameters for 207GB dataset
            max_positions=None,  # Use entire dataset (207GB)
            full_dataset_traversal=True,  # Complete traversal without sampling
            shuffle_data=True,

            # Incremental training support
            resume_from_checkpoint=True,
            save_checkpoint_every_n_epochs=2,  # More frequent saves for large training
            keep_n_checkpoints=5,

            # Advanced training optimizations
            gradient_accumulation_steps=1,  # No accumulation needed with large batch
            mixed_precision=True,  # Essential for RTX4090
            compile_model=True,  # PyTorch 2.0+ optimization

            # Data loading optimized for high-end hardware
            data_loading_workers=12,  # Utilize Ryzen 7950x (16 cores)
            prefetch_factor=4,  # Aggressive prefetching with 192GB RAM
            pin_memory=True,

            # System settings
            num_workers=2,  # Keep legacy compatibility
            no_swap=True,  # Strict memory management with 192GB
            memory_threshold=32.0,  # Higher threshold for high-end system
            checkpoint_dir="checkpoints_preprocessed_hp"
        )
        # Larger network for high performance - optimized for RTX4090
        config.network.num_filters = 768  # Increased from 512
        config.network.num_residual_blocks = 20  # Increased from 15
        config.network.dropout_rate = 0.2  # Reduced dropout for larger dataset
    elif mode == "conservative":
        preprocessed_config = PreprocessedTrainingConfig(
            epochs=10,
            batch_size=32,
            learning_rate=1e-3,
            memory_conservative=True,
            max_positions=200000,
            checkpoint_dir="checkpoints_preprocessed_conservative"
        )
        # Smaller network for conservative mode
        config.network.num_filters = 128
        config.network.num_residual_blocks = 8
    else:  # default
        preprocessed_config = PreprocessedTrainingConfig(
            epochs=10,
            batch_size=64,
            learning_rate=1e-3,
            checkpoint_dir="checkpoints_preprocessed"
        )

    config.preprocessed_training = preprocessed_config
    return config


def validate_config(config: AlphaZeroConfig) -> List[str]:
    """
    Validate configuration and return list of warnings/errors.

    Args:
        config: Configuration to validate

    Returns:
        List of validation messages
    """
    warnings = []

    # Network validation
    if config.network.num_filters < 32:
        warnings.append("Very small num_filters may hurt performance")
    if config.network.num_residual_blocks < 3:
        warnings.append("Very few residual blocks may hurt performance")
    if config.network.dropout_rate >= 0.5:
        warnings.append("High dropout rate may hurt training")

    # MCTS validation
    if config.mcts.num_mcts_sims < 10:
        warnings.append("Very few MCTS simulations may hurt play strength")
    if config.mcts.c_puct <= 0:
        warnings.append("c_puct must be positive")

    # Training validation
    if config.training.train_batch_size > config.training.max_examples:
        warnings.append("Batch size larger than max examples")
    if config.training.games_per_iteration < 10:
        warnings.append("Very few games per iteration may hurt training stability")

    # Perfect DB validation
    if config.perfect_db.perfect_db_path and not os.path.exists(config.perfect_db.perfect_db_path):
        warnings.append(f"Perfect DB path does not exist: {config.perfect_db.perfect_db_path}")

    # Phase weights validation
    phase_sum = sum(config.perfect_db.phase_weights.values())
    if abs(phase_sum - 1.0) > 0.01:
        warnings.append(f"Phase weights sum to {phase_sum:.3f}, should be 1.0")

    return warnings


def create_example_configs():
    """Create example configuration files."""
    configs = {
        'default': get_default_config(),
        'fast_training': get_fast_training_config(),
        'production': get_production_config(),
        'cpu_optimized': get_cpu_optimized_config(),
        'gpu_optimized': get_gpu_optimized_config(),
        'preprocessed_default': get_preprocessed_training_config("default"),
        'preprocessed_fast': get_preprocessed_training_config("fast"),
        'preprocessed_high_performance': get_preprocessed_training_config("high_performance"),
        'preprocessed_conservative': get_preprocessed_training_config("conservative")
    }

    for name, config in configs.items():
        # Save as YAML
        yaml_path = f"alphazero_config_{name}.yaml"
        config.save(yaml_path)
        print(f"Created {yaml_path}")

        # Save as JSON
        json_path = f"alphazero_config_{name}.json"
        config.save(json_path)
        print(f"Created {json_path}")


if __name__ == '__main__':
    # Create example configuration files
    create_example_configs()

    # Test configuration loading and validation
    config = get_default_config()
    warnings = validate_config(config)

    if warnings:
        print("Configuration warnings:")
        for warning in warnings:
            print(f"  - {warning}")
    else:
        print("Configuration is valid")
