#!/usr/bin/env python3
"""
Configuration file loader for AlphaZero training.
Supports YAML and JSON formats.
"""

import os
import json
import logging
from typing import Dict, Any, Optional

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

from utils import dotdict

log = logging.getLogger(__name__)


def load_config(config_path: str) -> dotdict:
    """
    Load configuration from YAML or JSON file.
    
    Args:
        config_path: Path to configuration file (.yaml, .yml, or .json)
        
    Returns:
        dotdict: Configuration dictionary
        
    Raises:
        FileNotFoundError: If config file doesn't exist
        ValueError: If file format is unsupported or parsing fails
    """
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")
    
    ext = os.path.splitext(config_path)[1].lower()
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            if ext in ['.yaml', '.yml']:
                if not HAS_YAML:
                    raise ValueError("PyYAML is required for YAML config files. Install with: pip install PyYAML")
                config_dict = yaml.safe_load(f)
            elif ext == '.json':
                config_dict = json.load(f)
            else:
                raise ValueError(f"Unsupported config file format: {ext}. Use .yaml, .yml, or .json")
        
        if config_dict is None:
            config_dict = {}
            
        return dotdict(config_dict)
        
    except Exception as e:
        raise ValueError(f"Failed to parse config file {config_path}: {e}")


def get_supported_formats():
    """Get list of supported configuration file formats."""
    formats = ['.json']
    if HAS_YAML:
        formats.extend(['.yaml', '.yml'])
    return formats


def merge_config_with_args(base_args: dotdict, config_path: Optional[str] = None) -> dotdict:
    """
    Merge configuration file with base arguments.
    Config file values override base values.
    
    Args:
        base_args: Base arguments (from main.py)
        config_path: Optional path to config file
        
    Returns:
        dotdict: Merged configuration
    """
    if config_path is None:
        return base_args
    
    try:
        config = load_config(config_path)
        log.info(f"Loaded configuration from {config_path}")
        
        # Merge: config overrides base_args
        merged = dotdict(base_args)
        merged.update(config)
        
        return merged
        
    except Exception as e:
        log.warning(f"Failed to load config file {config_path}: {e}")
        log.warning("Using default arguments instead")
        return base_args


def save_config_template(output_path: str, format: str = 'yaml') -> None:
    """
    Save a template configuration file with all available options.
    
    Args:
        output_path: Where to save the template
        format: 'yaml' or 'json'
    """
    # Default configuration with comments
    template = {
        # Training parameters
        'numIters': 100,
        'numEps': 100, 
        'tempThreshold': 80,
        'updateThreshold': 0.55,
        'maxlenOfQueue': 200000,
        'numMCTSSims': 40,
        'arenaCompare': 20,
        'cpuct': 1.5,
        
        # File paths
        'checkpoint': './temp/',
        'load_model': False,
        'load_folder_file': ['temp/', 'best.pth.tar'],
        'numItersForTrainExamplesHistory': 5,
        
        # System settings
        'num_processes': 5,
        'cuda': True,  # Will be auto-detected if not specified
        
        # Neural network hyperparameters
        'lr': 0.002,
        'dropout': 0.3,
        'epochs': 10,
        'batch_size': 1024,
        'num_channels': 256,
        
        # Perfect DB teacher settings
        'usePerfectTeacher': False,
        'teacherExamplesPerIter': 1000,
        'teacherBatch': 256,
        'teacherDBPath': '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted',
        'teacherAnalyzeTimeout': 120,
        'teacherThreads': 1,
        'pitAgainstPerfect': True,
        
        # Debugging options
        'verbose_games': 1,
        'log_detailed_moves': True,
        # Curriculum learning (phase-wise)
        # modes: 'off' | 'auto' | 'stage1' | 'stage2' | 'stage3'
        'curriculum_mode': 'off',
        # When mode=='auto', number of iterations for stage-1 and stage-2 before unlocking stage-3
        'curriculum_s1_iters': 0,
        'curriculum_s2_iters': 0,
        # Mix ratio of earlier-stage samples during later stages (0.0-0.9)
        'curriculum_mix_prev_ratio': 0.3,
        # Stage-1 early-stop heuristic weight (value shaping magnitude)
        'curriculum_stage1_weight': 0.03,
        # Stage-specific MCTS sims scaling during sampling
        'curriculum_mcts_scale_s1': 1.25,
        'curriculum_mcts_scale_s2': 1.10,
        'curriculum_mcts_scale_s3': 1.00,
        # Arena-driven curriculum advancement
        'curriculum_advance_by_arena': False,
        'curriculum_promote_s1': 0.70,
        'curriculum_promote_s2': 0.65,
        'curriculum_promote_patience': 2,
        'curriculum_min_iters_per_stage': 1,
        'curriculum_draw_weight': 0.0,
        # Curriculum timebox (avoid long stagnation)
        'curriculum_timebox_iters': 4,
        'curriculum_timebox_action': 'increase_mcts',  # increase_mcts | lower_threshold | both | none
        'curriculum_timebox_mcts_scale': 1.20,
        'curriculum_timebox_threshold_relax': 0.03,
        'curriculum_timebox_max_relax': 0.10,
        # Dataset logging/splitting
        'curriculum_split_examples': False,
        'curriculum_log_stats': True,
    }
    
    if format.lower() == 'yaml' and HAS_YAML:
        with open(output_path, 'w', encoding='utf-8') as f:
            # Add comments for YAML
            f.write("# AlphaZero Training Configuration\n")
            f.write("# Copy this file and modify as needed\n\n")
            f.write("# === Training Parameters ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'numIters', 'numEps', 'tempThreshold', 'updateThreshold', 
                'maxlenOfQueue', 'numMCTSSims', 'arenaCompare', 'cpuct'
            ]}, f, default_flow_style=False)
            f.write("\n# === File Paths ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'checkpoint', 'load_model', 'load_folder_file', 'numItersForTrainExamplesHistory'
            ]}, f, default_flow_style=False)
            f.write("\n# === System Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'num_processes', 'cuda'
            ]}, f, default_flow_style=False)
            f.write("\n# === Neural Network ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'lr', 'dropout', 'epochs', 'batch_size', 'num_channels'
            ]}, f, default_flow_style=False)
            f.write("\n# === Perfect Database Teacher ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'usePerfectTeacher', 'teacherExamplesPerIter', 'teacherBatch',
                'teacherDBPath', 'teacherAnalyzeTimeout', 'teacherThreads', 'pitAgainstPerfect'
            ]}, f, default_flow_style=False)
            f.write("\n# === Debugging ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'verbose_games', 'log_detailed_moves'
            ]}, f, default_flow_style=False)
            f.write("\n# === Curriculum Learning (Phase-wise) ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'curriculum_mode', 'curriculum_s1_iters', 'curriculum_s2_iters',
                'curriculum_mix_prev_ratio', 'curriculum_stage1_weight',
                'curriculum_mcts_scale_s1', 'curriculum_mcts_scale_s2', 'curriculum_mcts_scale_s3',
                'curriculum_advance_by_arena', 'curriculum_promote_s1', 'curriculum_promote_s2',
                'curriculum_promote_patience', 'curriculum_min_iters_per_stage', 'curriculum_draw_weight',
                'curriculum_timebox_iters', 'curriculum_timebox_action', 'curriculum_timebox_mcts_scale',
                'curriculum_timebox_threshold_relax', 'curriculum_timebox_max_relax',
                'curriculum_split_examples', 'curriculum_log_stats'
            ]}, f, default_flow_style=False)
    else:
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(template, f, indent=2, ensure_ascii=False)
    
    log.info(f"Configuration template saved to {output_path}")


if __name__ == '__main__':
    # Create template config files
    import sys
    output_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    
    if HAS_YAML:
        save_config_template(os.path.join(output_dir, 'config_template.yaml'), 'yaml')
    save_config_template(os.path.join(output_dir, 'config_template.json'), 'json')
    
    print(f"Template configuration files created in {output_dir}")
