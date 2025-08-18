#!/usr/bin/env python3
"""
Configuration file loader for NNUE training and inference.
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

logger = logging.getLogger(__name__)


class dotdict(dict):
    """Dictionary with dot notation access"""
    __getattr__ = dict.get
    __setattr__ = dict.__setitem__
    __delattr__ = dict.__delitem__

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for key, value in self.items():
            if isinstance(value, dict):
                self[key] = dotdict(value)


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
        logger.info(f"Loaded configuration from {config_path}")
        
        # Merge: config overrides base_args
        merged = dotdict(base_args)
        merged.update(config)
        
        return merged
        
    except Exception as e:
        logger.warning(f"Failed to load config file {config_path}: {e}")
        logger.warning("Using default arguments instead")
        return base_args


def save_config_template(output_path: str, format: str = 'json') -> None:
    """
    Save a template configuration file for NNUE pit.
    
    Args:
        output_path: Where to save the template
        format: 'yaml' or 'json'
    """
    # Template configuration for NNUE pit
    template = {
        # Model settings
        'model_path': 'nnue_model.bin',
        'feature_size': 115,
        'hidden_size': 256,
        
        # Game settings
        'search_depth': 3,
        'human_first': True,
        'gui': True,
        'games': 1,
        
        # Display settings
        'log_level': 'INFO',
        'show_evaluation': True,
        'show_thinking_time': True,
        
        # AI settings
        'time_per_move': 3.0,  # seconds
        'use_time_management': False,
        
        # Advanced settings
        'device': 'auto',  # 'auto', 'cpu', 'cuda'
        'batch_size': 1,
        'temperature': 1.0,
    }
    
    if format.lower() == 'yaml' and HAS_YAML:
        with open(output_path, 'w', encoding='utf-8') as f:
            # Add comments for YAML
            f.write("# NNUE Pit Configuration\n")
            f.write("# Configuration for human vs NNUE AI games\n\n")
            f.write("# === Model Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'model_path', 'feature_size', 'hidden_size'
            ]}, f, default_flow_style=False)
            f.write("\n# === Game Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'search_depth', 'human_first', 'gui', 'games'
            ]}, f, default_flow_style=False)
            f.write("\n# === Display Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'log_level', 'show_evaluation', 'show_thinking_time'
            ]}, f, default_flow_style=False)
            f.write("\n# === AI Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'time_per_move', 'use_time_management'
            ]}, f, default_flow_style=False)
            f.write("\n# === Advanced Settings ===\n")
            yaml.dump({k: v for k, v in template.items() if k in [
                'device', 'batch_size', 'temperature'
            ]}, f, default_flow_style=False)
    else:
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(template, f, indent=2, ensure_ascii=False)
    
    logger.info(f"Configuration template saved to {output_path}")


if __name__ == '__main__':
    # Create template config files
    import sys
    output_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    
    if HAS_YAML:
        save_config_template(os.path.join(output_dir, 'nnue_pit_config.yaml'), 'yaml')
    save_config_template(os.path.join(output_dir, 'nnue_pit_config.json'), 'json')
    
    print(f"Template configuration files created in {output_dir}")
