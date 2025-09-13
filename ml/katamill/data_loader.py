#!/usr/bin/env python3
"""
Data loading utilities for Katamill training.

Handles loading, preprocessing, and batching of selfplay data.
"""

import json
import logging
import os
import sys
from typing import Dict, List, Optional, Tuple
import numpy as np
import pickle
import gzip

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

logger = logging.getLogger(__name__)


def save_selfplay_data(samples: List[Dict[str, np.ndarray]], filepath: str, compress: bool = True):
    """Save selfplay samples to disk.
    
    Args:
        samples: List of training samples from selfplay
        filepath: Output file path (.npz or .pkl.gz)
        compress: Whether to compress the data
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    
    if filepath.endswith('.npz'):
        # NumPy format
        np.savez_compressed(filepath, samples=samples)
        logger.info(f"Saved {len(samples)} samples to {filepath}")
    else:
        # Pickle format (more flexible)
        if compress and not filepath.endswith('.gz'):
            filepath += '.gz'
        
        if filepath.endswith('.gz'):
            with gzip.open(filepath, 'wb') as f:
                pickle.dump(samples, f, protocol=pickle.HIGHEST_PROTOCOL)
        else:
            with open(filepath, 'wb') as f:
                pickle.dump(samples, f, protocol=pickle.HIGHEST_PROTOCOL)
        
        logger.info(f"Saved {len(samples)} samples to {filepath}")


def load_selfplay_data(filepath: str) -> List[Dict[str, np.ndarray]]:
    """Load selfplay samples from disk.
    
    Args:
        filepath: Input file path (.npz or .pkl.gz)
        
    Returns:
        List of training samples
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Data file not found: {filepath}")
    
    if filepath.endswith('.npz'):
        # NumPy format
        data = np.load(filepath, allow_pickle=True)
        samples = data['samples'].tolist()
        logger.info(f"Loaded {len(samples)} samples from {filepath}")
        return samples
    elif filepath.endswith('.gz'):
        # Compressed pickle
        with gzip.open(filepath, 'rb') as f:
            samples = pickle.load(f)
        logger.info(f"Loaded {len(samples)} samples from {filepath}")
        return samples
    else:
        # Regular pickle
        with open(filepath, 'rb') as f:
            samples = pickle.load(f)
        logger.info(f"Loaded {len(samples)} samples from {filepath}")
        return samples


def merge_data_files(filepaths: List[str], output_path: str, shuffle: bool = True):
    """Merge multiple data files into one.
    
    Args:
        filepaths: List of input file paths
        output_path: Output file path
        shuffle: Whether to shuffle the merged data
    """
    all_samples = []
    
    for filepath in filepaths:
        samples = load_selfplay_data(filepath)
        all_samples.extend(samples)
        logger.info(f"Added {len(samples)} samples from {filepath}")
    
    if shuffle:
        np.random.shuffle(all_samples)
        logger.info("Shuffled merged data")
    
    save_selfplay_data(all_samples, output_path)
    logger.info(f"Saved {len(all_samples)} total samples to {output_path}")


def split_data(samples: List[Dict[str, np.ndarray]], 
               train_ratio: float = 0.8,
               val_ratio: float = 0.1,
               test_ratio: float = 0.1) -> Tuple[List, List, List]:
    """Split data into train/val/test sets.
    
    Args:
        samples: List of all samples
        train_ratio: Fraction for training
        val_ratio: Fraction for validation
        test_ratio: Fraction for testing
        
    Returns:
        train_samples, val_samples, test_samples
    """
    assert abs(train_ratio + val_ratio + test_ratio - 1.0) < 1e-6
    
    n = len(samples)
    n_train = int(n * train_ratio)
    n_val = int(n * val_ratio)
    
    # Shuffle before splitting
    indices = np.random.permutation(n)
    
    train_idx = indices[:n_train]
    val_idx = indices[n_train:n_train + n_val]
    test_idx = indices[n_train + n_val:]
    
    train_samples = [samples[i] for i in train_idx]
    val_samples = [samples[i] for i in val_idx]
    test_samples = [samples[i] for i in test_idx]
    
    logger.info(f"Split data: train={len(train_samples)}, val={len(val_samples)}, test={len(test_samples)}")
    
    return train_samples, val_samples, test_samples


def analyze_data(samples: List[Dict[str, np.ndarray]]) -> Dict[str, any]:
    """Analyze dataset statistics.
    
    Args:
        samples: List of training samples
        
    Returns:
        Dictionary of statistics
    """
    stats = {
        'num_samples': len(samples),
        'features_shape': None,
        'policy_shape': None,
        'value_distribution': {},
        'score_distribution': {},
        'ownership_stats': {},
        'mill_potential_stats': {},
    }
    
    if len(samples) == 0:
        return stats
    
    # Get shapes from first sample
    first = samples[0]
    stats['features_shape'] = first['features'].shape
    stats['policy_shape'] = first['pi'].shape
    
    # Collect values for analysis
    values = np.array([s['z'][0] for s in samples])
    scores = np.array([s['aux']['score'][0] for s in samples])
    ownerships = np.vstack([s['aux']['ownership'] for s in samples])
    mill_potentials = np.vstack([s['aux']['mill_potential'] for s in samples])
    
    # Value distribution
    stats['value_distribution'] = {
        'mean': float(np.mean(values)),
        'std': float(np.std(values)),
        'min': float(np.min(values)),
        'max': float(np.max(values)),
        'wins': int(np.sum(values > 0.5)),
        'draws': int(np.sum(np.abs(values) < 0.5)),
        'losses': int(np.sum(values < -0.5)),
    }
    
    # Score distribution
    stats['score_distribution'] = {
        'mean': float(np.mean(scores)),
        'std': float(np.std(scores)),
        'min': float(np.min(scores)),
        'max': float(np.max(scores)),
    }
    
    # Ownership statistics
    stats['ownership_stats'] = {
        'mean_per_position': ownerships.mean(axis=0).tolist(),
        'overall_mean': float(np.mean(ownerships)),
        'overall_std': float(np.std(ownerships)),
    }
    
    # Mill potential statistics
    stats['mill_potential_stats'] = {
        'mean_per_position': mill_potentials.mean(axis=0).tolist(),
        'overall_mean': float(np.mean(mill_potentials)),
        'positions_with_potential': int(np.sum(mill_potentials > 0.5)),
    }
    
    return stats


def create_balanced_dataset(samples: List[Dict[str, np.ndarray]], 
                          balance_by: str = 'value') -> List[Dict[str, np.ndarray]]:
    """Create a balanced dataset by outcome.
    
    Args:
        samples: Original samples
        balance_by: What to balance ('value' for win/draw/loss)
        
    Returns:
        Balanced dataset
    """
    if balance_by == 'value':
        # Separate by outcome
        wins = [s for s in samples if s['z'][0] > 0.5]
        draws = [s for s in samples if abs(s['z'][0]) < 0.5]
        losses = [s for s in samples if s['z'][0] < -0.5]
        
        # Find minimum class size
        min_size = min(len(wins), len(draws), len(losses))
        
        if min_size == 0:
            logger.warning("One outcome class is empty, returning original dataset")
            return samples
        
        # Sample equally from each class
        balanced = []
        if len(wins) > 0:
            balanced.extend(np.random.choice(wins, min_size, replace=False))
        if len(draws) > 0:
            balanced.extend(np.random.choice(draws, min_size, replace=False))
        if len(losses) > 0:
            balanced.extend(np.random.choice(losses, min_size, replace=False))
        
        # Shuffle
        np.random.shuffle(balanced)
        
        logger.info(f"Balanced dataset: {len(balanced)} samples "
                   f"(was {len(samples)}, min_class={min_size})")
        
        return balanced
    else:
        logger.warning(f"Unknown balance_by option: {balance_by}")
        return samples


def augment_with_symmetries(samples: List[Dict[str, np.ndarray]], 
                           max_augment: Optional[int] = None) -> List[Dict[str, np.ndarray]]:
    """Augment dataset with board symmetries.
    
    Args:
        samples: Original samples
        max_augment: Maximum number of augmented samples per original
        
    Returns:
        Augmented dataset
    """
    # For Nine Men's Morris, we have 8 symmetries (4 rotations * 2 reflections)
    # This is handled in the Dataset class during training
    # Here we could pre-generate if needed for offline augmentation
    
    logger.info("Symmetry augmentation is handled online during training")
    return samples


def filter_winner_samples(samples: List[Dict[str, np.ndarray]], 
                         keep_draws: bool = True) -> List[Dict[str, np.ndarray]]:
    """
    Filter samples to keep winner-side data, inspired by UCT-CCNN paper.
    
    The UCT-CCNN methodology showed that keeping only samples from the winning
    side improves training signal quality, as winner moves are more likely to
    represent good decisions leading to optimal play.
    
    Args:
        samples: Raw training samples collected from self-play
        keep_draws: Whether to keep samples from draw games
        
    Returns:
        Filtered samples emphasizing winner-side moves for better training targets
    """
    if not samples:
        return samples
        
    filtered = []
    
    for sample in samples:
        # Extract game outcome information from sample
        meta = sample.get('metadata', {})
        final_result = float(meta.get('final_result', 0.0))
        
        # Get step player's perspective value
        z_array = sample.get('z', np.array([0.0], dtype=np.float32))
        try:
            z_value = float(z_array[0]) if hasattr(z_array, '__len__') else float(z_array)
        except (IndexError, TypeError, ValueError):
            z_value = 0.0
        
        # Filter based on game outcome
        if abs(final_result) < 0.01:  # Draw game
            if keep_draws:
                filtered.append(sample)
        else:
            # Keep samples where the step player won (z_value > 0)
            # This follows UCT-CCNN's strategy of keeping winner-side examples
            if z_value > 0.0:
                filtered.append(sample)
    
    logger.info(f"Winner-side filtering: kept {len(filtered)}/{len(samples)} samples "
               f"({len(filtered)/len(samples)*100:.1f}%)")
    
    return filtered


def main():
    """Command-line interface for data operations."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Katamill data utilities')
    parser.add_argument('command', choices=['analyze', 'merge', 'split', 'balance'],
                       help='Operation to perform')
    parser.add_argument('--input', '-i', nargs='+', required=True,
                       help='Input data file(s)')
    parser.add_argument('--output', '-o', help='Output file path')
    parser.add_argument('--train-ratio', type=float, default=0.8,
                       help='Training set ratio for split')
    parser.add_argument('--val-ratio', type=float, default=0.1,
                       help='Validation set ratio for split')
    
    args = parser.parse_args()
    
    if args.command == 'analyze':
        for filepath in args.input:
            samples = load_selfplay_data(filepath)
            stats = analyze_data(samples)
            print(f"\nAnalysis of {filepath}:")
            print(json.dumps(stats, indent=2))
    
    elif args.command == 'merge':
        if not args.output:
            parser.error("--output required for merge")
        merge_data_files(args.input, args.output)
    
    elif args.command == 'split':
        if not args.output:
            parser.error("--output required for split")
        
        samples = load_selfplay_data(args.input[0])
        train, val, test = split_data(samples, args.train_ratio, args.val_ratio)
        
        base = os.path.splitext(args.output)[0]
        save_selfplay_data(train, f"{base}_train.npz")
        save_selfplay_data(val, f"{base}_val.npz")
        save_selfplay_data(test, f"{base}_test.npz")
    
    elif args.command == 'balance':
        if not args.output:
            parser.error("--output required for balance")
        
        samples = load_selfplay_data(args.input[0])
        balanced = create_balanced_dataset(samples)
        save_selfplay_data(balanced, args.output)


if __name__ == '__main__':
    main()
