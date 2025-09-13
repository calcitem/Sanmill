#!/usr/bin/env python3
"""
Fast Training Data Loader

Directly loads preprocessed training data to avoid repeated parsing of .sec2 files.
Supports efficient batch training and data augmentation.
"""

import os
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
import logging
from typing import List, Dict, Optional, Tuple, Any
from pathlib import Path
import random

# Add paths for imports
import sys
import os
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from perfect_db_preprocessor import PerfectDBPreprocessor

logger = logging.getLogger(__name__)


class PreprocessedDataset(Dataset):
    """Preprocessed dataset for PyTorch DataLoader."""

    def __init__(self,
                 board_tensors: np.ndarray,
                 policy_targets: np.ndarray,
                 value_targets: np.ndarray,
                 metadata_list: List[Dict],
                 transform=None):
        """
        Initializes the dataset.

        Args:
            board_tensors: Board tensors (N, 19, 7, 7)
            policy_targets: Policy targets (N, action_size)
            value_targets: Value targets (N,)
            metadata_list: List of metadata
            transform: Data transformation function
        """
        self.board_tensors = torch.FloatTensor(board_tensors)
        self.policy_targets = torch.FloatTensor(policy_targets)
        self.value_targets = torch.FloatTensor(value_targets)
        self.metadata_list = metadata_list
        self.transform = transform

        assert len(self.board_tensors) == len(self.policy_targets) == len(self.value_targets) == len(self.metadata_list)

        logger.info(f"PreprocessedDataset created with {len(self)} samples")

    def __len__(self):
        return len(self.board_tensors)

    def __getitem__(self, idx):
        board = self.board_tensors[idx]
        policy = self.policy_targets[idx]
        value = self.value_targets[idx]
        metadata = self.metadata_list[idx]

        if self.transform:
            board, policy, value = self.transform(board, policy, value, metadata)

        return board, policy, value, metadata


class FastDataLoader:
    """Fast data loader that uses preprocessed data for training."""

    def __init__(self, preprocessed_data_dir: str):
        """
        Initializes the fast data loader.

        Args:
            preprocessed_data_dir: Directory of preprocessed data
        """
        self.data_dir = Path(preprocessed_data_dir)

        if not self.data_dir.exists():
            raise FileNotFoundError(f"Preprocessed data directory not found: {self.data_dir}")

        # Load the preprocessor to access metadata
        self.preprocessor = PerfectDBPreprocessor(
            perfect_db_path="",  # Original data path not needed
            output_dir=str(self.data_dir)
        )

        logger.info(f"FastDataLoader initialized with {self.data_dir}")

    def load_training_data(self,
                           phase_filter: Optional[str] = None,
                           max_positions: Optional[int] = None,
                           shuffle: bool = True,
                           trap_ratio: float = 0.0) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List[Dict]]:
        """
        Loads training data.

        Args:
            phase_filter: Game phase filter
            max_positions: Maximum number of positions
            shuffle: Whether to shuffle the data
            trap_ratio: Ratio of trap positions (0-1)

        Returns:
            (board_tensors, policy_targets, value_targets, metadata_list)
        """
        logger.info("Loading preprocessed training data...")

        # Load all data
        board_tensors, policy_targets, value_targets, metadata_list = \
            self.preprocessor.load_preprocessed_data(phase_filter, max_positions)

        if len(board_tensors) == 0:
            logger.warning("No data loaded")
            return board_tensors, policy_targets, value_targets, metadata_list

        # Apply trap filtering
        if trap_ratio > 0 and trap_ratio < 1:
            indices = self._apply_trap_sampling(metadata_list, trap_ratio)
            board_tensors = board_tensors[indices]
            policy_targets = policy_targets[indices]
            value_targets = value_targets[indices]
            metadata_list = [metadata_list[i] for i in indices]

        # Shuffle data
        if shuffle:
            indices = np.random.permutation(len(board_tensors))
            board_tensors = board_tensors[indices]
            policy_targets = policy_targets[indices]
            value_targets = value_targets[indices]
            metadata_list = [metadata_list[i] for i in indices]

        logger.info(f"Loaded {len(board_tensors)} training positions")

        return board_tensors, policy_targets, value_targets, metadata_list

    def _apply_trap_sampling(self, metadata_list: List[Dict], trap_ratio: float) -> np.ndarray:
        """Applies trap position sampling."""
        trap_indices = []
        normal_indices = []

        for i, metadata in enumerate(metadata_list):
            if metadata.get('is_trap', False):
                trap_indices.append(i)
            else:
                normal_indices.append(i)

        # Calculate sample counts
        total_positions = len(metadata_list)
        target_trap_count = int(total_positions * trap_ratio)
        target_normal_count = total_positions - target_trap_count

        # Sample trap positions
        if len(trap_indices) >= target_trap_count:
            selected_trap = np.random.choice(trap_indices, target_trap_count, replace=False)
        else:
            selected_trap = np.array(trap_indices, dtype=int)
            target_normal_count = total_positions - len(selected_trap)

        # Sample normal positions
        if len(normal_indices) >= target_normal_count:
            selected_normal = np.random.choice(normal_indices, target_normal_count, replace=False)
        else:
            selected_normal = np.array(normal_indices, dtype=int)

        # Merge and shuffle
        selected_indices = np.concatenate([selected_trap, selected_normal])
        np.random.shuffle(selected_indices)

        logger.info(f"Applied trap sampling: {len(selected_trap)} trap, {len(selected_normal)} normal")

        return selected_indices

    def create_dataloader(self,
                          phase_filter: Optional[str] = None,
                          max_positions: Optional[int] = None,
                          batch_size: int = 64,
                          shuffle: bool = True,
                          trap_ratio: float = 0.0,
                          num_workers: int = 0,
                          pin_memory: bool = None,
                          prefetch_factor: int = 2) -> DataLoader:
        """
        Creates a PyTorch DataLoader.

        Args:
            phase_filter: Game phase filter
            max_positions: Maximum number of positions
            batch_size: Batch size
            shuffle: Whether to shuffle the data
            trap_ratio: Ratio of trap positions
            num_workers: Number of worker processes for data loading

        Returns:
            A PyTorch DataLoader
        """
        # Load data
        board_tensors, policy_targets, value_targets, metadata_list = \
            self.load_training_data(phase_filter, max_positions, shuffle, trap_ratio)

        if len(board_tensors) == 0:
            raise ValueError("No data available for DataLoader")

        # Create dataset
        dataset = PreprocessedDataset(
            board_tensors, policy_targets, value_targets, metadata_list
        )

        # Create DataLoader
        dataloader = DataLoader(
            dataset,
            batch_size=batch_size,
            shuffle=shuffle,
            num_workers=num_workers,
            pin_memory=torch.cuda.is_available()
        )

        logger.info(f"Created DataLoader with {len(dataset)} samples, batch_size={batch_size}")

        return dataloader

    def get_statistics(self) -> Dict[str, Any]:
        """Gets data statistics."""
        return self.preprocessor.get_statistics()

    def benchmark_loading(self, num_trials: int = 5) -> Dict[str, float]:
        """
        Benchmarks the data loading speed.

        Args:
            num_trials: Number of trials to run

        Returns:
            Performance statistics
        """
        import time

        logger.info(f"Benchmarking data loading ({num_trials} trials)...")

        loading_times = []

        for trial in range(num_trials):
            start_time = time.time()

            board_tensors, policy_targets, value_targets, metadata_list = \
                self.load_training_data(max_positions=10000)

            loading_time = time.time() - start_time
            loading_times.append(loading_time)

            positions_per_second = len(board_tensors) / loading_time if loading_time > 0 else 0

            logger.info(f"  Trial {trial + 1}: {loading_time:.2f}s, "
                        f"{positions_per_second:.0f} positions/s")

        avg_time = np.mean(loading_times)
        std_time = np.std(loading_times)

        stats = {
            'avg_loading_time': avg_time,
            'std_loading_time': std_time,
            'min_loading_time': np.min(loading_times),
            'max_loading_time': np.max(loading_times),
            'avg_positions_per_second': 10000 / avg_time if avg_time > 0 else 0
        }

        logger.info(f"Benchmark results: {stats['avg_loading_time']:.2f}±{stats['std_loading_time']:.2f}s, "
                    f"{stats['avg_positions_per_second']:.0f} positions/s")

        return stats


class DataAugmentation:
    """Data augmentation class to add variations to training data."""

    @staticmethod
    def board_rotation(board_tensor: torch.Tensor, k: int = 1) -> torch.Tensor:
        """
        Rotates the board tensor.

        Args:
            board_tensor: Board tensor (19, 7, 7)
            k: Number of 90-degree rotations

        Returns:
            The rotated board tensor
        """
        # Apply the same rotation to all feature planes
        return torch.rot90(board_tensor, k, dims=[1, 2])

    @staticmethod
    def board_flip(board_tensor: torch.Tensor, horizontal: bool = True) -> torch.Tensor:
        """
        Flips the board tensor.

        Args:
            board_tensor: Board tensor (19, 7, 7)
            horizontal: Whether to flip horizontally

        Returns:
            The flipped board tensor
        """
        if horizontal:
            return torch.flip(board_tensor, [2])  # Flip horizontally
        else:
            return torch.flip(board_tensor, [1])  # Flip vertically

    @staticmethod
    def random_augmentation(board_tensor: torch.Tensor,
                            policy_target: torch.Tensor,
                            value_target: torch.Tensor,
                            metadata: Dict) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        Randomly applies data augmentation.

        Args:
            board_tensor: Board tensor
            policy_target: Policy target
            value_target: Value target
            metadata: Metadata

        Returns:
            Augmented data
        """
        # Randomly choose an augmentation method
        augmentation_type = random.choice(['none', 'rotation', 'flip'])

        if augmentation_type == 'rotation':
            k = random.randint(1, 3)
            board_tensor = DataAugmentation.board_rotation(board_tensor, k)
            # Note: The policy target also needs to be adjusted accordingly, simplified here

        elif augmentation_type == 'flip':
            horizontal = random.choice([True, False])
            board_tensor = DataAugmentation.board_flip(board_tensor, horizontal)
            # Note: The policy target also needs to be adjusted accordingly, simplified here

        return board_tensor, policy_target, value_target


def create_fast_training_pipeline(preprocessed_data_dir: str,
                                  batch_size: int = 64,
                                  phase_filter: Optional[str] = None,
                                  trap_ratio: float = 0.3) -> DataLoader:
    """
    Creates a fast training pipeline.

    Args:
        preprocessed_data_dir: Directory of preprocessed data
        batch_size: Batch size
        phase_filter: Game phase filter
        trap_ratio: Ratio of trap positions

    Returns:
        A configured DataLoader
    """
    loader = FastDataLoader(preprocessed_data_dir)

    dataloader = loader.create_dataloader(
        phase_filter=phase_filter,
        batch_size=batch_size,
        shuffle=True,
        trap_ratio=trap_ratio,
        num_workers=2  # Parallel data loading
    )

    return dataloader


def main():
    """Example usage."""
    import argparse

    parser = argparse.ArgumentParser(description='Fast Data Loader Test')
    parser.add_argument('--data-dir', required=True, help='Directory for preprocessed data')
    parser.add_argument('--benchmark', action='store_true', help='Run benchmark tests')
    parser.add_argument('--stats', action='store_true', help='Display statistics')

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    loader = FastDataLoader(args.data_dir)

    if args.stats:
        stats = loader.get_statistics()
        print("\n📊 Data Statistics:")
        print(f"  Total Sectors: {stats.get('total_sectors', 0)}")
        print(f"  Total Positions: {stats.get('total_positions', 0):,}")
        print(f"  Error Rate: {stats.get('error_rate', 0):.2%}")

        phase_stats = stats.get('phase_statistics', {})
        if phase_stats:
            print("\n📈 Game Phase Distribution:")
            for phase, data in phase_stats.items():
                print(f"  {phase}: {data['positions']:,} positions")

    if args.benchmark:
        loader.benchmark_loading()

    if not args.stats and not args.benchmark:
        # Example loading
        dataloader = create_fast_training_pipeline(
            args.data_dir,
            batch_size=32,
            trap_ratio=0.3
        )

        print(f"\n🚀 Created DataLoader with {len(dataloader.dataset)} samples")
        print(f"   Batch Size: {dataloader.batch_size}")
        print(f"   Number of Batches: {len(dataloader)}")

        # Test the first batch
        for batch_idx, (boards, policies, values, metadata) in enumerate(dataloader):
            print(f"\n📦 Batch {batch_idx + 1}:")
            print(f"   Board Tensors: {boards.shape}")
            print(f"   Policy Targets: {policies.shape}")
            print(f"   Value Targets: {values.shape}")
            break


if __name__ == '__main__':
    main()
