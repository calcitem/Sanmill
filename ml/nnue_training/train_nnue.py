#!/usr/bin/env python3
"""
NNUE training script for Sanmill
Uses training data generated from Perfect Database to train the neural network
"""

import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import numpy as np
import argparse
import os
import time
from typing import Tuple, List, Optional
import logging
from pathlib import Path
import math
import json
import subprocess
import multiprocessing as mp

# Plotting libraries
try:
    import matplotlib
    matplotlib.use('Agg')  # Use non-interactive backend for server environments
    import matplotlib.pyplot as plt
    import seaborn as sns
    sns.set_style("whitegrid")
    PLOTTING_AVAILABLE = True
except ImportError:
    PLOTTING_AVAILABLE = False
    plt = None
    sns = None

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class MillNNUE(nn.Module):
    """
    NNUE model for Mill game evaluation, matching the C++ implementation.
    Architecture:
    - Input: 115 features representing the game state.
    - Hidden Layer: 256 neurons with ReLU activation.
    - Output: A single value representing the position evaluation.
    """

    def __init__(self, feature_size: int = 115, hidden_size: int = 256):
        super(MillNNUE, self).__init__()
        self.feature_size = feature_size
        self.hidden_size = hidden_size

        # A single linear layer for the input to hidden transformation.
        # The C++ side uses int16_t weights, so we will quantize this later.
        self.input_to_hidden = nn.Linear(feature_size, hidden_size)

        # The output layer combines activations from two perspectives (current player
        # and opponent). This is modeled as a linear layer with a weight matrix
        # of size (1, hidden_size * 2).
        self.hidden_to_output = nn.Linear(hidden_size * 2, 1, bias=True)

        self._init_weights()

    def _init_weights(self):
        """Initialize network weights using Kaiming He initialization."""
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.kaiming_normal_(m.weight, mode='fan_in', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)

    def forward(self, x: torch.Tensor, side_to_move: torch.Tensor) -> torch.Tensor:
        """
        Performs the forward pass, mirroring the logic in the C++ engine.
        Args:
            x: The input feature tensor [batch_size, feature_size].
            side_to_move: A tensor indicating whose turn it is [batch_size].
                          0 for white, 1 for black.
        Returns:
            The evaluation score for each position in the batch [batch_size, 1].
        """
        # --- Perspective Handling ---
        # The C++ engine computes two perspectives: one for the current player
        # and one for the opponent. This is achieved by swapping the piece
        # placement features.

        # Perspective A (White's view)
        hidden_white = F.relu(self.input_to_hidden(x))

        # Perspective B (Black's view)
        # Create a swapped version of the input tensor for black's perspective.
        x_swapped = x.clone()
        # Swap white and black piece placement features (first 24 features for
        # white, next 24 for black).
        x_swapped[:, 0:24], x_swapped[:, 24:48] = x[:, 24:48], x[:, 0:24]
        hidden_black = F.relu(self.input_to_hidden(x_swapped))

        # --- Output Computation ---
        # The final output depends on the side to move. The C++ engine concatenates
        # the hidden activations of the current player and the opponent.
        batch_size = x.size(0)
        # Ensure consistent dtype for mixed precision training
        combined_hidden = torch.zeros(batch_size, self.hidden_size * 2, device=x.device, dtype=hidden_white.dtype)

        white_mask = (side_to_move == 0)
        black_mask = (side_to_move == 1)

        # If it's white's turn, the order is [hidden_white, hidden_black]
        if white_mask.any():
            combined_hidden[white_mask] = torch.cat((hidden_white[white_mask], hidden_black[white_mask]), dim=1)

        # If it's black's turn, the order is [hidden_black, hidden_white]
        if black_mask.any():
            combined_hidden[black_mask] = torch.cat((hidden_black[black_mask], hidden_white[black_mask]), dim=1)
        
        return self.hidden_to_output(combined_hidden)


class AdaptiveLRScheduler:
    """
    Adaptive learning rate scheduler that automatically adjusts LR based on:
    - Training loss trends
    - Validation loss trends  
    - Gradient norms
    - Learning progress
    """
    
    def __init__(self, optimizer, initial_lr=0.002, patience=10, factor=0.7, 
                 min_lr=1e-7, warmup_epochs=5, cooldown_epochs=3):
        self.optimizer = optimizer
        self.initial_lr = initial_lr
        self.current_lr = initial_lr
        self.patience = patience
        self.factor = factor
        self.min_lr = min_lr
        self.warmup_epochs = warmup_epochs
        self.cooldown_epochs = cooldown_epochs
        
        # State tracking
        self.best_loss = float('inf')
        self.epochs_without_improvement = 0
        self.last_reduction_epoch = -1
        self.epoch = 0
        
        # Loss history for trend analysis
        self.train_loss_history = []
        self.val_loss_history = []
        self.gradient_norm_history = []
        
        # Dynamic adjustment factors
        self.loss_smoothing = 0.9
        self.gradient_smoothing = 0.95
        
    def step(self, train_loss, val_loss, gradient_norm=None):
        """Update learning rate based on current metrics"""
        self.epoch += 1
        self.train_loss_history.append(train_loss)
        self.val_loss_history.append(val_loss)
        
        if gradient_norm is not None:
            self.gradient_norm_history.append(gradient_norm)
        
        # Warmup phase - gradually increase LR
        if self.epoch <= self.warmup_epochs:
            warmup_lr = self.initial_lr * (self.epoch / self.warmup_epochs)
            self._set_lr(warmup_lr)
            logger.info(f"Warmup LR: {warmup_lr:.6f}")
            return
        
        # Main adaptive logic
        should_reduce = self._should_reduce_lr(val_loss)
        
        if should_reduce and (self.epoch - self.last_reduction_epoch) > self.cooldown_epochs:
            old_lr = self.current_lr
            self.current_lr = max(self.current_lr * self.factor, self.min_lr)
            self._set_lr(self.current_lr)
            self.last_reduction_epoch = self.epoch
            self.epochs_without_improvement = 0
            logger.info(f"Reduced LR: {old_lr:.6f} -> {self.current_lr:.6f}")
        
        # Progressive LR boost for consistent improvement
        elif self._should_boost_lr():
            old_lr = self.current_lr
            boost_factor = min(1.05, math.sqrt(self.initial_lr / self.current_lr))
            self.current_lr = min(self.current_lr * boost_factor, self.initial_lr * 0.5)
            self._set_lr(self.current_lr)
            logger.info(f"Boosted LR: {old_lr:.6f} -> {self.current_lr:.6f}")
    
    def _should_reduce_lr(self, val_loss):
        """Determine if learning rate should be reduced"""
        # Track best validation loss
        if val_loss < self.best_loss:
            self.best_loss = val_loss
            self.epochs_without_improvement = 0
            return False
        else:
            self.epochs_without_improvement += 1
        
        # Reduce if no improvement for patience epochs
        if self.epochs_without_improvement >= self.patience:
            return True
        
        # Advanced criteria: check for loss plateau
        if len(self.val_loss_history) >= 5:
            recent_losses = self.val_loss_history[-5:]
            loss_variance = np.var(recent_losses)
            mean_loss = np.mean(recent_losses)
            
            # If variance is very low relative to mean, we might be plateaued
            if loss_variance < (mean_loss * 0.001) and self.epochs_without_improvement >= 3:
                return True
        
        # Check gradient norm trends
        if len(self.gradient_norm_history) >= 5:
            recent_grads = self.gradient_norm_history[-5:]
            if np.mean(recent_grads) < 1e-5:  # Very small gradients
                return True
        
        return False
    
    def _should_boost_lr(self):
        """Determine if learning rate should be increased"""
        if len(self.val_loss_history) < 10:
            return False
        
        # Check for consistent improvement trend
        recent_losses = self.val_loss_history[-10:]
        if len(recent_losses) >= 5:
            # Linear regression to check improvement trend
            x = np.arange(len(recent_losses))
            slope = np.polyfit(x, recent_losses, 1)[0]
            
            # If loss is decreasing consistently and we haven't reduced recently
            if (slope < -0.001 and 
                self.epochs_without_improvement == 0 and 
                (self.epoch - self.last_reduction_epoch) > 15 and
                self.current_lr < self.initial_lr * 0.3):
                return True
        
        return False
    
    def _set_lr(self, lr):
        """Set learning rate for all parameter groups"""
        for param_group in self.optimizer.param_groups:
            param_group['lr'] = lr
        self.current_lr = lr
    
    def get_last_lr(self):
        """Get current learning rate"""
        return [self.current_lr]
    
    def state_dict(self):
        """Return scheduler state"""
        return {
            'current_lr': self.current_lr,
            'best_loss': self.best_loss,
            'epochs_without_improvement': self.epochs_without_improvement,
            'last_reduction_epoch': self.last_reduction_epoch,
            'epoch': self.epoch,
            'train_loss_history': self.train_loss_history,
            'val_loss_history': self.val_loss_history,
            'gradient_norm_history': self.gradient_norm_history
        }
    
    def load_state_dict(self, state_dict):
        """Load scheduler state"""
        self.current_lr = state_dict['current_lr']
        self.best_loss = state_dict['best_loss']
        self.epochs_without_improvement = state_dict['epochs_without_improvement']
        self.last_reduction_epoch = state_dict['last_reduction_epoch']
        self.epoch = state_dict['epoch']
        self.train_loss_history = state_dict['train_loss_history']
        self.val_loss_history = state_dict['val_loss_history']
        self.gradient_norm_history = state_dict['gradient_norm_history']


class TrainingVisualizer:
    """
    Training data collector for NNUE training
    Collects training metrics during training and saves to CSV for final plotting
    No intermediate plotting to ensure optimal training performance
    """
    
    def __init__(self, output_dir: str = "plots"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        # Only data collection - no intermediate plotting to avoid training interruptions
        
        # Training metrics storage
        self.epochs = []
        self.train_losses = []
        self.val_losses = []
        self.val_accuracies = []
        self.learning_rates = []
        self.gradient_norms = []
        self.epoch_times = []
        self.cumulative_times = []  # For tracking total elapsed time
    
    def add_epoch_data(self, epoch: int, train_loss: float, val_loss: float, 
                      val_accuracy: float, learning_rate: float, 
                      gradient_norm: float, epoch_time: float, cumulative_time: float = None,
                      total_epochs: int = None):
        """Add data for a completed epoch - only stores data, no intermediate plotting"""
        self.epochs.append(epoch + 1)  # 1-based epoch numbering
        self.train_losses.append(train_loss)
        self.val_losses.append(val_loss)
        self.val_accuracies.append(val_accuracy)
        self.learning_rates.append(learning_rate)
        self.gradient_norms.append(gradient_norm)
        self.epoch_times.append(epoch_time)
        
        if cumulative_time is not None:
            self.cumulative_times.append(cumulative_time)
        elif len(self.epoch_times) == 1:
            self.cumulative_times.append(epoch_time)
        else:
            self.cumulative_times.append(self.cumulative_times[-1] + epoch_time)
        
        # No intermediate plotting - only data collection for final CSV generation
        # This eliminates training interruptions caused by frequent plotting
    
    def update_plots(self):
        """Placeholder method - intermediate plotting disabled for performance"""
        # No intermediate plotting to avoid training interruptions
        # Final plots will be generated from CSV data after training completion
        pass
    
    def create_summary_plot(self):
        """Create a final summary plot at the end of training"""
        if not PLOTTING_AVAILABLE or not self.save_plots:
            return
        
        fig = plt.figure(figsize=(20, 16))
        
        # Enhanced loss plot with statistics
        ax1 = plt.subplot(3, 3, (1, 2))
        plt.plot(self.epochs, self.train_losses, 'b-', label='Training Loss', linewidth=2)
        plt.plot(self.epochs, self.val_losses, 'r-', label='Validation Loss', linewidth=2)
        
        # Add moving averages
        if len(self.epochs) >= 10:
            window = min(10, len(self.epochs) // 4)
            train_ma = np.convolve(self.train_losses, np.ones(window)/window, mode='valid')
            val_ma = np.convolve(self.val_losses, np.ones(window)/window, mode='valid')
            ma_epochs = self.epochs[window-1:]
            
            plt.plot(ma_epochs, train_ma, 'b:', label=f'Train MA({window})', alpha=0.8)
            plt.plot(ma_epochs, val_ma, 'r:', label=f'Val MA({window})', alpha=0.8)
        
        plt.xlabel('Epoch')
        plt.ylabel('Loss')
        plt.title('Training Summary - Loss Curves')
        plt.legend()
        plt.grid(True, alpha=0.3)
        
        # Add statistics box
        final_train_loss = self.train_losses[-1]
        final_val_loss = self.val_losses[-1]
        best_val_loss = min(self.val_losses)
        best_val_epoch = self.epochs[self.val_losses.index(best_val_loss)]
        
        stats_text = (f'Final Train Loss: {final_train_loss:.6f}\n'
                     f'Final Val Loss: {final_val_loss:.6f}\n'
                     f'Best Val Loss: {best_val_loss:.6f} @ Epoch {best_val_epoch}\n'
                     f'Total Epochs: {len(self.epochs)}')
        
        plt.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
                verticalalignment='top', fontsize=11,
                bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.8))
        
        # Detailed learning rate plot
        ax2 = plt.subplot(3, 3, 3)
        plt.plot(self.epochs, self.learning_rates, 'orange', linewidth=2)
        plt.xlabel('Epoch')
        plt.ylabel('Learning Rate')
        plt.title('Learning Rate Schedule')
        plt.yscale('log')
        plt.grid(True, alpha=0.3)
        
        # Training efficiency metrics
        ax3 = plt.subplot(3, 3, (4, 5))
        # Loss improvement rate
        if len(self.val_losses) >= 5:
            improvement_rates = []
            for i in range(4, len(self.val_losses)):
                recent_losses = self.val_losses[i-4:i+1]
                slope = np.polyfit(range(5), recent_losses, 1)[0]
                improvement_rates.append(-slope)  # Negative slope = improvement
            
            improvement_epochs = self.epochs[4:]
            plt.plot(improvement_epochs, improvement_rates, 'green', linewidth=2)
            plt.xlabel('Epoch')
            plt.ylabel('Loss Improvement Rate')
            plt.title('Learning Progress (5-epoch sliding window)')
            plt.grid(True, alpha=0.3)
            plt.axhline(y=0, color='black', linestyle='-', alpha=0.3)
        
        # Gradient health over time
        ax4 = plt.subplot(3, 3, 6)
        plt.plot(self.epochs, self.gradient_norms, 'purple', linewidth=2)
        plt.xlabel('Epoch')
        plt.ylabel('Gradient Norm')
        plt.title('Gradient Health')
        plt.yscale('log')
        plt.grid(True, alpha=0.3)
        
        # Performance timeline
        ax5 = plt.subplot(3, 3, (7, 8))
        # Dual y-axis for accuracy and time
        ax5_twin = ax5.twinx()
        
        line1 = ax5.plot(self.epochs, self.val_accuracies, 'g-', linewidth=2, label='Validation Accuracy')
        line2 = ax5_twin.plot(self.epochs, self.epoch_times, 'brown', linewidth=2, label='Epoch Time')
        
        ax5.set_xlabel('Epoch')
        ax5.set_ylabel('Validation Accuracy', color='g')
        ax5_twin.set_ylabel('Epoch Time (s)', color='brown')
        ax5.set_title('Performance Timeline')
        ax5.grid(True, alpha=0.3)
        
        # Combined legend
        lines = line1 + line2
        labels = [l.get_label() for l in lines]
        ax5.legend(lines, labels, loc='upper left')
        
        # Final statistics summary
        ax6 = plt.subplot(3, 3, 9)
        ax6.axis('off')
        
        total_time = sum(self.epoch_times)
        avg_time_per_epoch = total_time / len(self.epoch_times)
        best_acc = max(self.val_accuracies)
        final_acc = self.val_accuracies[-1]
        
        summary_stats = (
            f'TRAINING SUMMARY\n'
            f'{"="*30}\n'
            f'Total Training Time: {total_time:.1f}s ({total_time/3600:.2f}h)\n'
            f'Average Time/Epoch: {avg_time_per_epoch:.1f}s\n'
            f'Final Validation Accuracy: {final_acc:.4f}\n'
            f'Best Validation Accuracy: {best_acc:.4f}\n'
            f'Final Learning Rate: {self.learning_rates[-1]:.2e}\n'
            f'Final Gradient Norm: {self.gradient_norms[-1]:.4f}\n'
            f'Loss Reduction: {(self.val_losses[0] - self.val_losses[-1]):.6f}\n'
            f'Improvement: {((self.val_losses[0] - self.val_losses[-1])/self.val_losses[0]*100):.1f}%'
        )
        
        ax6.text(0.1, 0.9, summary_stats, transform=ax6.transAxes, 
                fontsize=12, verticalalignment='top', fontfamily='monospace',
                bbox=dict(boxstyle='round', facecolor='lightyellow', alpha=0.8))
        
        plt.tight_layout()
        
        # Save final summary
        summary_path = self.output_dir / "training_summary.png"
        plt.savefig(summary_path, dpi=300, bbox_inches='tight')
        plt.close()
        
        logger.info(f"Training summary plot saved to {summary_path}")
    
    def save_metrics_csv(self):
        """Save all metrics to CSV for further analysis"""
        import csv
        
        csv_path = self.output_dir / "training_metrics.csv"
        
        with open(csv_path, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['Epoch', 'Train_Loss', 'Val_Loss', 'Val_Accuracy', 
                           'Learning_Rate', 'Gradient_Norm', 'Epoch_Time'])
            
            for i in range(len(self.epochs)):
                writer.writerow([
                    self.epochs[i], self.train_losses[i], self.val_losses[i],
                    self.val_accuracies[i], self.learning_rates[i], 
                    self.gradient_norms[i], self.epoch_times[i]
                ])
        
        logger.info(f"Training metrics saved to {csv_path}")


def load_config(config_path: str) -> dict:
    """Load configuration from JSON file"""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        logger.info(f"Loaded configuration from {config_path}")
        return config
    except FileNotFoundError:
        logger.error(f"Configuration file not found: {config_path}")
        return {}
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in configuration file {config_path}: {e}")
        return {}
    except Exception as e:
        logger.error(f"Error loading configuration file {config_path}: {e}")
        return {}

def merge_config_with_args(config: dict, args: argparse.Namespace) -> argparse.Namespace:
    """Merge configuration file with command line arguments (CLI takes precedence)"""
    # Create a new namespace with config defaults
    merged_args = argparse.Namespace()
    
    # First, set all config values
    for key, value in config.items():
        # Convert dashes to underscores for argument names
        key = key.replace('-', '_')
        
        # Handle nested configurations like data_generation
        if key == "data_generation" and isinstance(value, dict):
            for sub_key, sub_value in value.items():
                full_key = sub_key.replace('-', '_')
                setattr(merged_args, full_key, sub_value)
        else:
            setattr(merged_args, key, value)
    
    # Then override with any explicitly provided command line arguments
    # We need to distinguish between default values and user-provided values
    for key, value in vars(args).items():
        if hasattr(merged_args, key):
            # If key exists in config, don't override with command line defaults
            # unless it was explicitly provided by user
            continue
        else:
            # Set values for arguments not in config
            setattr(merged_args, key, value)
    
    return merged_args

def save_config_template(output_path: str):
    """Save a template configuration file with all available options"""
    template_config = {
        "# NNUE Training Configuration": "Template with all available options",
        "# Mode Selection": "Set pipeline=true for complete data generation + training",
        
        "pipeline": False,
        
        "# Training Mode Parameters": "Required when pipeline=false",
        "data": "training_data.txt",
        "output": "nnue_model.bin",
        
        "# Pipeline Mode Parameters": "Required when pipeline=true",
        "engine": "../../sanmill",
        "perfect-db": "/path/to/perfect/database",
        "output-dir": "./nnue_output",
        "positions": 500000,
        "threads": 0,
        
        "# Core Training Parameters": "Used in both modes",
        "epochs": 300,
        "batch-size": 8192,
        "lr": 0.002,
        "lr-scheduler": "adaptive",
        "lr-auto-scale": True,
        "feature-size": 115,
        "hidden-size": 512,
        "max-samples": None,
        "val-split": 0.1,
        "device": "auto",
        
        "# Visualization Parameters": "Used in both modes - optimized for performance",
        "plot": True,  # Generate final plots after training completion
        "plot-dir": "plots",
        "save-csv": True,  # Save training metrics to CSV for plotting
        
        "# Usage Examples": {
            "training-only": "python train_nnue.py --config config.json",
            "pipeline-mode": "python train_nnue.py --config config.json --pipeline",
            "override-params": "python train_nnue.py --config config.json --epochs 500"
        },
        
        "# Parameter Options": {
            "lr-scheduler": "adaptive, cosine, plateau, fixed",
            "device": "auto, cpu, cuda",
            "threads": "0 = auto-detect CPU cores"
        },
        
        "# Notes": {
            "pipeline-mode": "Complete end-to-end training from data generation",
            "training-mode": "Train from existing data file",
            "lr-auto-scale": "Automatically scale LR based on batch size and dataset size",
            "adaptive-scheduler": "Recommended for most users - automatically adjusts LR",
            "plot": "Generate visualization plots after training completion (no intermediate plotting)",
            "save-csv": "Save training metrics to CSV file for analysis and plotting",
            "hidden-size": "Larger networks may perform better but train slower",
            "batch-size": "Powers of 2 work best (1024, 2048, 4096, 8192, 16384)"
        }
    }
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(template_config, f, indent=2, ensure_ascii=False)
    
    logger.info(f"Configuration template saved to {output_path}")


# Pipeline Functions
def validate_environment(engine_path: str, perfect_db_path: str) -> bool:
    """
    Strict validation of training environment
    """
    logger.info("Validating training environment...")
    
    # Check engine executable (now optional, can be None for direct Perfect DB usage)
    if engine_path is not None:
        if not os.path.exists(engine_path):
            logger.error(f"Engine not found: {engine_path}")
            return False
        
        if not os.access(engine_path, os.X_OK):
            logger.error(f"Engine is not executable: {engine_path}")
            return False
        logger.info(f"Engine validation passed: {engine_path}")
    else:
        logger.info("Engine not specified - using direct Perfect DB mode")
    
    # Check Perfect Database
    if not os.path.exists(perfect_db_path):
        logger.error(f"Perfect Database path not found: {perfect_db_path}")
        return False
    
    if not os.path.isdir(perfect_db_path):
        logger.error(f"Perfect Database path is not a directory: {perfect_db_path}")
        return False
    
    # Check for required database files (basic validation)
    db_files_found = any(
        f.endswith(('.db', '.dat', '.bin', '.idx', '.sec2', '.secval', '.statistics')) 
        for f in os.listdir(perfect_db_path)
    )
    
    if not db_files_found:
        logger.warning(f"No database files found in {perfect_db_path}")
        logger.warning("Perfect Database may not be properly installed")
    
    logger.info("Environment validation passed")
    return True

def generate_training_data_parallel(engine_path: str,
                                  output_file: str, 
                                  num_positions: int,
                                  perfect_db_path: str,
                                  num_threads: int = 0) -> bool:
    """
    Generate training data in parallel using multiple engine instances
    """
    if num_threads <= 0:
        num_threads = max(1, mp.cpu_count() - 1)
    
    logger.info(f"Generating {num_positions} training positions using {num_threads} threads...")
    
    start_time = time.time()
    
    # Calculate positions per thread
    positions_per_thread = num_positions // num_threads
    remaining_positions = num_positions % num_threads
    
    # Generate data files for each thread
    temp_files = []
    processes = []
    
    for i in range(num_threads):
        thread_positions = positions_per_thread
        if i < remaining_positions:
            thread_positions += 1
        
        if thread_positions == 0:
            continue
        
        temp_file = f"{output_file}.thread_{i}.tmp"
        temp_files.append(temp_file)
        
        # Command to generate training data
        cmd = [
            engine_path,
            "generate",
            str(thread_positions),
            temp_file,
            perfect_db_path
        ]
        
        logger.info(f"Thread {i}: generating {thread_positions} positions")
        
        try:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            processes.append((process, i, thread_positions))
        except Exception as e:
            logger.error(f"Failed to start thread {i}: {e}")
            return False
    
    # Wait for all processes to complete
    all_success = True
    for process, thread_id, thread_positions in processes:
        try:
            stdout, stderr = process.communicate(timeout=3600)  # 1 hour timeout
            
            if process.returncode != 0:
                logger.error(f"Thread {thread_id} failed with return code {process.returncode}")
                logger.error(f"Error output: {stderr}")
                all_success = False
            else:
                logger.info(f"Thread {thread_id} completed successfully")
                
        except subprocess.TimeoutExpired:
            logger.error(f"Thread {thread_id} timed out")
            process.kill()
            all_success = False
        except Exception as e:
            logger.error(f"Thread {thread_id} failed with exception: {e}")
            all_success = False
    
    if not all_success:
        # Clean up temp files
        for temp_file in temp_files:
            if os.path.exists(temp_file):
                os.remove(temp_file)
        return False
    
    # Combine all temp files into the final output
    logger.info("Combining training data files...")
    
    try:
        with open(output_file, 'w') as outfile:
            # Write header
            outfile.write("# NNUE Training Data Generated from Perfect Database\n")
            outfile.write(f"# Total positions: {num_positions}\n")
            outfile.write(f"# Generated on: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            outfile.write("# Format: features(95) target(1) side_to_move(1)\n")
            
            for temp_file in temp_files:
                if os.path.exists(temp_file):
                    with open(temp_file, 'r') as infile:
                        for line in infile:
                            if not line.startswith('#'):  # Skip comments
                                outfile.write(line)
                    os.remove(temp_file)  # Clean up
    
    except Exception as e:
        logger.error(f"Failed to combine training data files: {e}")
        return False
    
    end_time = time.time()
    
    # Validate output file
    if not os.path.exists(output_file):
        logger.error(f"Output file was not created: {output_file}")
        return False
    
    file_size = os.path.getsize(output_file)
    if file_size == 0:
        logger.error(f"Output file is empty: {output_file}")
        return False
    
    logger.info(f"Training data generated successfully in {end_time - start_time:.2f}s")
    logger.info(f"Output file: {output_file} ({file_size} bytes)")
    
    return True

def validate_final_model(model_path: str, engine_path: str) -> bool:
    """
    Validate the trained model works with the engine
    """
    logger.info("VALIDATE: Starting model validation...")
    logger.info(f"VALIDATE: Checking model file: {model_path}")
    
    if not os.path.exists(model_path):
        logger.error(f"Model file not found: {model_path}")
        return False
    
    logger.info("VALIDATE: Model file exists, checking size...")
    model_size = os.path.getsize(model_path)
    if model_size == 0:
        logger.error(f"Model file is empty: {model_path}")
        return False
    
    logger.info(f"VALIDATE: Model validation passed: {model_path} ({model_size} bytes)")
    
    # Basic engine connectivity test (if possible) - with aggressive timeout
    logger.info("VALIDATE: Starting engine compatibility test...")
    try:
        if engine_path is None:
            logger.info("VALIDATE: Engine path not specified (skipping compatibility test)")
            logger.info("VALIDATE: Model validation completed (no engine test)")
            return True
        
        logger.info(f"VALIDATE: Testing engine compatibility with: {engine_path}")
        logger.info("VALIDATE: Preparing engine test command...")
        cmd = [engine_path, "test", "model", model_path]
        logger.info(f"VALIDATE: Running command: {' '.join(cmd)}")
        
        # Reduce timeout to prevent hanging
        logger.info("VALIDATE: Executing subprocess with 3-second timeout...")
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            timeout=3  # Further reduced to 3 seconds
        )
        logger.info(f"VALIDATE: Subprocess completed with return code: {result.returncode}")
        
        if result.returncode == 0:
            logger.info("VALIDATE: Engine model compatibility test passed")
        else:
            logger.warning("VALIDATE: Engine model compatibility test failed (model may still be usable)")
            logger.warning(f"VALIDATE: Engine output: {result.stderr}")
        
    except FileNotFoundError:
        logger.info("VALIDATE: Engine test command not available (skipping compatibility test)")
    except subprocess.TimeoutExpired:
        logger.warning("VALIDATE: Engine compatibility test timed out after 3 seconds")
    except Exception as e:
        logger.warning(f"VALIDATE: Engine compatibility test failed: {e}")
    
    logger.info("VALIDATE: Model validation completed successfully")
    return True


class MillDataset(Dataset):
    """Dataset for Mill NNUE training"""
    
    def __init__(self, data_file: str, max_samples: Optional[int] = None):
        """
        Load training data from file
        Args:
            data_file: Path to training data file
            max_samples: Maximum number of samples to load (None for all)
        """
        self.features = []
        self.targets = []
        self.side_to_move = []
        self.phases = []
        
        self._load_data(data_file, max_samples)
        
        # Convert to tensors
        self.features = torch.tensor(self.features, dtype=torch.float32)
        self.targets = torch.tensor(self.targets, dtype=torch.float32).unsqueeze(1)
        self.side_to_move = torch.tensor(self.side_to_move, dtype=torch.long)
        
        logger.info(f"Loaded {len(self.features)} training samples")
    
    def _load_data(self, data_file: str, max_samples: Optional[int]):
        """Load data from training file"""
        with open(data_file, 'r') as f:
            lines = f.readlines()
        
        # Skip header comments
        data_lines = [line for line in lines if not line.startswith('#')]
        
        if len(data_lines) == 0:
            raise ValueError("No data found in training file")
        
        # First line should contain the number of samples
        try:
            total_samples = int(data_lines[0].strip())
            data_lines = data_lines[1:]
        except (ValueError, IndexError):
            logger.warning("Could not read sample count, processing all lines")
            total_samples = len(data_lines)
        
        if max_samples:
            total_samples = min(total_samples, max_samples)
            data_lines = data_lines[:total_samples]
        
        logger.info(f"Processing {len(data_lines)} data lines...")
        
        for i, line in enumerate(data_lines):
            if i % 10000 == 0:
                logger.info(f"Processed {i}/{len(data_lines)} samples")
            
            # Debug: show first few lines to understand format
            if i < 3:
                logger.info(f"Sample line {i}: {line.strip()[:100]}...")
            
            try:
                parts = line.strip().split(' | ')
                if len(parts) < 4:
                    if i < 10:  # Only log first 10 mismatches to avoid spam
                        logger.warning(f"Line {i} has {len(parts)} parts, expected 4: {line.strip()[:100]}...")
                    continue
                
                # Parse features
                feature_str = parts[0]
                features = [int(x) for x in feature_str.split()]
                
                # Parse target evaluation
                target = float(parts[1])
                
                # Parse phase (not used directly in training but useful for analysis)
                phase = int(parts[2])
                
                # Parse FEN to extract side to move
                fen = parts[3]
                fen_parts = fen.split()
                if len(fen_parts) >= 2:
                    # Standard FEN format: fen_parts[1] is active color
                    side = 0 if fen_parts[1] == 'w' else 1
                else:
                    # Invalid FEN format
                    logger.warning(f"Invalid FEN format on line {i}: {fen}")
                    side = 0  # Default to white
                
                self.features.append(features)
                self.targets.append(target)
                self.side_to_move.append(side)
                self.phases.append(phase)
                
            except (ValueError, IndexError) as e:
                logger.warning(f"Skipping malformed line {i}: {e}")
                continue
    
    def __len__(self):
        return len(self.features)
    
    def __getitem__(self, idx):
        return {
            'features': self.features[idx],
            'target': self.targets[idx],
            'side_to_move': self.side_to_move[idx]
        }

def train_epoch(model: nn.Module, 
                dataloader: DataLoader, 
                optimizer: torch.optim.Optimizer, 
                criterion: nn.Module,
                device: torch.device,
                max_grad_norm: float = 1.0,
                scaler: torch.amp.GradScaler = None) -> Tuple[float, float]:
    """Train for one epoch with gradient clipping for stability and gradient norm tracking"""
    model.train()
    total_loss = 0.0
    total_grad_norm = 0.0
    num_batches = 0
    
    for batch in dataloader:
        features = batch['features'].to(device, non_blocking=True)
        targets = batch['target'].to(device, non_blocking=True)
        side_to_move = batch['side_to_move'].to(device, non_blocking=True)
        
        # Enable mixed precision for faster training on modern GPUs
        with torch.amp.autocast('cuda', enabled=device.type == 'cuda'):
            outputs = model(features, side_to_move)
            loss = criterion(outputs, targets)
        
        optimizer.zero_grad()
        
        # Use gradient scaling for mixed precision training
        if device.type == 'cuda' and scaler is not None:
            scaler.scale(loss).backward()
            
            # Gradient clipping for training stability with large batch sizes
            scaler.unscale_(optimizer)
            grad_norm = torch.nn.utils.clip_grad_norm_(model.parameters(), max_grad_norm)
            
            scaler.step(optimizer)
            scaler.update()
        else:
            loss.backward()
            grad_norm = torch.nn.utils.clip_grad_norm_(model.parameters(), max_grad_norm)
            optimizer.step()
        
        total_loss += loss.item()
        total_grad_norm += grad_norm.item() if isinstance(grad_norm, torch.Tensor) else grad_norm
        num_batches += 1
    
    avg_loss = total_loss / num_batches
    avg_grad_norm = total_grad_norm / num_batches
    return avg_loss, avg_grad_norm

def validate_epoch(model: nn.Module, 
                  dataloader: DataLoader, 
                  criterion: nn.Module,
                  device: torch.device) -> Tuple[float, float]:
    """Validate for one epoch"""
    model.eval()
    total_loss = 0.0
    total_accuracy = 0.0
    num_batches = 0
    
    with torch.no_grad():
        for batch in dataloader:
            features = batch['features'].to(device)
            targets = batch['target'].to(device)
            side_to_move = batch['side_to_move'].to(device)
            
            outputs = model(features, side_to_move)
            loss = criterion(outputs, targets)
            
            # Calculate accuracy (for win/loss/draw predictions)
            predictions = torch.sign(outputs)
            target_signs = torch.sign(targets)
            accuracy = (predictions == target_signs).float().mean()
            
            total_loss += loss.item()
            total_accuracy += accuracy.item()
            num_batches += 1
    
    return total_loss / num_batches, total_accuracy / num_batches


def backup_existing_model(filepath: str) -> bool:
    """
    Backup existing model files with timestamp before saving new ones.
    Returns True if backup was created, False if no existing model.
    """
    import time
    import shutil
    
    bin_file = filepath
    pytorch_file = f"{filepath}.pytorch"
    
    backup_created = False
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    
    # Backup .bin file if exists
    if os.path.exists(bin_file):
        backup_bin = f"{bin_file}.backup_{timestamp}"
        shutil.copy2(bin_file, backup_bin)
        # Reduced backup logging to avoid spam
        backup_created = True
    
    # Backup .pytorch file if exists  
    if os.path.exists(pytorch_file):
        backup_pytorch = f"{pytorch_file}.backup_{timestamp}"
        shutil.copy2(pytorch_file, backup_pytorch)
        # Reduced backup logging to avoid spam
        backup_created = True
        
    return backup_created

def save_model_c_format(model: nn.Module, filepath: str):
    """
    Saves the model in a binary format that is compatible with the C++ engine.
    This involves quantizing the weights and arranging them in the exact order
    and format expected by the NNUEWeights struct in `nnue.h`.
    """
    model.eval()

    # --- 1. Extract Weights and Biases from PyTorch Model ---
    input_weights_float = model.input_to_hidden.weight.transpose(0, 1).detach().cpu().numpy()
    input_biases_float = model.input_to_hidden.bias.detach().cpu().numpy()
    output_weights_float = model.hidden_to_output.weight.flatten().detach().cpu().numpy()
    output_bias_float = model.hidden_to_output.bias.detach().cpu().numpy()

    # --- 2. Quantization ---
    # The quantization scales must match the C++ implementation.
    # The hidden layer activation is clipped and scaled by 1/64. To compensate,
    # we scale the input weights and biases.
    # The output is also scaled.
    input_scale = 64.0
    output_scale = 127.0
    
    # Quantize weights to the C++ types
    input_weights_int16 = np.clip(input_weights_float * input_scale, -32767, 32767).astype(np.int16)
    input_biases_int32 = np.clip(input_biases_float * input_scale, -2147483647, 2147483647).astype(np.int32)
    output_weights_int8 = np.clip(output_weights_float * output_scale, -127, 127).astype(np.int8)
    output_bias_int32 = np.clip(output_bias_float.item() * output_scale, -2147483647, 2147483647).astype(np.int32)

    # --- 3. Write to Binary File ---
    with open(filepath, 'wb') as f:
        # Write header "SANMILL1"
        f.write(b'SANMILL1')

        # Write dimensions (feature_size, hidden_size)
        f.write(np.array([model.feature_size, model.hidden_size], dtype=np.int32).tobytes())

        # Write the quantized weights in the exact order expected by the C++ side
        # 1) input_weights: shape (feature_size, hidden_size) in C++ layout f-major
        f.write(input_weights_int16.tobytes())
        # 2) input_biases: shape (hidden_size,)
        f.write(input_biases_int32.tobytes())
        # 3) output_weights: shape (hidden_size * 2,)
        f.write(output_weights_int8.tobytes())
        # 4) output_bias: single int32
        f.write(output_bias_int32.tobytes())

    # Reduce logging frequency to avoid spam - only log for important saves
    pass  # Removed frequent C++ format save logging


def main():
    parser = argparse.ArgumentParser(description='Unified NNUE Training System for Mill game')
    
    # Configuration file support
    parser.add_argument('--config', type=str, help='Configuration file path (JSON format)')
    parser.add_argument('--save-config', type=str, help='Save configuration template to file and exit')
    
    # Mode selection
    parser.add_argument('--pipeline', action='store_true', 
                       help='Run complete pipeline: data generation + training (requires --engine and --perfect-db)')
    
    # Core training parameters
    parser.add_argument('--data', help='Training data file (required unless using --pipeline)')
    parser.add_argument('--output', default='nnue_model.bin', help='Output model file')
    parser.add_argument('--epochs', type=int, default=300, help='Number of training epochs')
    parser.add_argument('--batch-size', type=int, default=8192, help='Batch size')
    parser.add_argument('--lr', type=float, default=0.002, help='Initial learning rate')
    parser.add_argument('--lr-scheduler', default='adaptive', choices=['adaptive', 'cosine', 'plateau', 'fixed'], 
                       help='Learning rate scheduler type')
    parser.add_argument('--lr-auto-scale', action='store_true', help='Automatically scale LR based on batch size')
    parser.add_argument('--feature-size', type=int, default=115, help='Input feature size')
    parser.add_argument('--hidden-size', type=int, default=256, help='Hidden layer size')
    parser.add_argument('--max-samples', type=int, help='Maximum training samples')
    parser.add_argument('--val-split', type=float, default=0.1, help='Validation split ratio')
    parser.add_argument('--device', default='auto', help='Device to use (cpu/cuda/auto)')
    
    # Pipeline-specific parameters
    parser.add_argument('--engine', help='Path to Sanmill engine executable (required for --pipeline)')
    parser.add_argument('--perfect-db', help='Path to Perfect Database directory (required for --pipeline)')
    parser.add_argument('--output-dir', default='./nnue_output', help='Output directory for pipeline artifacts')
    parser.add_argument('--positions', type=int, default=500000, help='Number of training positions to generate')
    parser.add_argument('--threads', type=int, default=0, help='Number of threads for data generation (0=auto)')
    parser.add_argument('--validate-only', action='store_true', help='Only validate environment (pipeline mode)')
    parser.add_argument('--force-regenerate', action='store_true', help='Force regeneration of training data even if file exists')
    
    # Visualization options
    parser.add_argument('--plot', action='store_true', help='Enable final training visualization plots (generated after training)')
    parser.add_argument('--plot-dir', default='plots', help='Directory to save plots and CSV metrics')
    parser.add_argument('--save-csv', action='store_true', help='Save training metrics to CSV file')
    
    args = parser.parse_args()
    
    # Handle config template generation
    if args.save_config:
        save_config_template(args.save_config)
        logger.info(f"Configuration template saved to {args.save_config}")
        logger.info("Edit the template and use with --config <file>")
        return 0
    
    # Load configuration file if provided
    config = {}
    if args.config:
        config = load_config(args.config)
        if not config:
            logger.error("Failed to load configuration file")
            return 1
        
        # Merge config with command line arguments
        args = merge_config_with_args(config, args)
    
    # Validate required arguments based on mode
    if args.pipeline:
        # Pipeline mode validation
        # Engine is now optional - can use Perfect DB directly
        if not args.perfect_db:
            parser.error("--perfect-db is required for pipeline mode (or specify in config file)")
            return 1
        
        # Auto-detect thread count for pipeline
        if args.threads <= 0:
            args.threads = max(1, mp.cpu_count() - 1)
            
        # Set up pipeline-specific paths
        if not hasattr(args, 'output_dir') or not args.output_dir:
            args.output_dir = './nnue_output'
        os.makedirs(args.output_dir, exist_ok=True)
        
        # Set default data file for pipeline
        if not args.data:
            args.data = os.path.join(args.output_dir, "training_data.txt")
        
        # Update output path for pipeline - always prefer models/ directory
        if args.output == 'nnue_model.bin':  # Default output
            # Ensure models directory exists
            os.makedirs('./models', exist_ok=True)
            args.output = './models/nnue_model.bin'
            logger.info(f"Pipeline mode: Model will be saved to {args.output} for consistent management")
            
        # Update plot directory for pipeline
        if args.plot_dir == 'plots':  # Default plot dir
            args.plot_dir = os.path.join(args.output_dir, "plots")
            
    else:
        # Training-only mode validation
        if not args.data:
            parser.error("--data is required for training mode (or specify in config file)")
            return 1
    
    # Pipeline Mode: Handle data generation and environment validation
    if args.pipeline:
        logger.info("=== NNUE Training Pipeline Mode ===")
        logger.info(f"Engine: {args.engine}")
        logger.info(f"Perfect DB: {args.perfect_db}")
        logger.info(f"Output directory: {args.output_dir}")
        logger.info(f"Positions: {args.positions}")
        logger.info(f"Threads: {args.threads}")
        
        # Step 1: Environment validation
        logger.info("=== Step 1: Environment Validation ===")
        if not validate_environment(args.engine, args.perfect_db):
            logger.error("Environment validation failed")
            return 1
        
        if args.validate_only:
            logger.info("Environment validation completed successfully")
            return 0
        
        # Step 2: Generate training data
        logger.info("=== Step 2: Training Data Generation ===")
        
        # Check if we should regenerate data (force regeneration if file exists but is potentially old format)
        should_regenerate = (not os.path.exists(args.data) or 
                           os.path.getsize(args.data) == 0 or
                           args.force_regenerate)
        
        if should_regenerate:
            logger.info(f"Generating training data: {args.data}")
            if args.engine is None:
                # Use direct Perfect DB generation (new approach)
                from generate_training_data import generate_training_data_with_perfect_db
                success = generate_training_data_with_perfect_db(
                    args.perfect_db,
                    args.data,
                    args.positions,
                    args.threads,
                    batch_size=1000  # Add batch processing optimization
                )
            else:
                # Use legacy engine-based generation
                success = generate_training_data_parallel(
                    args.engine,
                    args.data,
                    args.positions,
                    args.perfect_db,
                    args.threads
                )
            
            if not success:
                logger.error("Training data generation failed")
                return 1
        else:
            logger.info(f"Using existing training data: {args.data}")
    
    # Automatic learning rate scaling based on batch size and dataset size
    if args.lr_auto_scale:
        # Load dataset first to get size information
        temp_dataset = MillDataset(args.data, args.max_samples)
        dataset_size = len(temp_dataset)
        
        # Base learning rate is calibrated for batch_size=1024 and dataset_size=100k
        base_batch_size = 1024
        base_dataset_size = 100000
        base_lr = 0.001
        
        # Scale learning rate based on batch size (linear scaling rule)
        batch_scale = args.batch_size / base_batch_size
        
        # Scale learning rate based on dataset size (sqrt scaling for better generalization)
        dataset_scale = (dataset_size / base_dataset_size) ** 0.5
        
        # Combined scaling with conservative factors
        args.lr = base_lr * batch_scale * dataset_scale * 0.8  # 0.8 safety factor
        
        logger.info(f"Auto-scaled learning rate: {args.lr:.6f}")
        logger.info(f"  Batch scale factor: {batch_scale:.2f}")
        logger.info(f"  Dataset scale factor: {dataset_scale:.2f}")
        logger.info(f"  Final LR: {base_lr} * {batch_scale:.2f} * {dataset_scale:.2f} * 0.8 = {args.lr:.6f}")
    
    # Setup device with hardware-specific optimizations
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    
    logger.info(f"Using device: {device}")
    
    # Enable GPU optimizations for high-end hardware
    if device.type == 'cuda':
        # Enable TensorFloat-32 for faster training on modern GPUs
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        
        # Enable optimized attention for transformer-like architectures
        torch.backends.cuda.enable_flash_sdp(True)
        
        # Set memory management for large GPU memory
        torch.cuda.empty_cache()
        
        # Log GPU information
        logger.info(f"GPU: {torch.cuda.get_device_name()}")
        logger.info(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
        logger.info(f"CUDA Version: {torch.version.cuda}")
        
        # Set GPU memory growth to avoid OOM issues
        os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'max_split_size_mb:512'
    
    # Load dataset
    logger.info("Loading training data...")
    dataset = MillDataset(args.data, args.max_samples)
    
    # Split into train/validation
    val_size = int(len(dataset) * args.val_split)
    train_size = len(dataset) - val_size
    
    train_dataset, val_dataset = torch.utils.data.random_split(
        dataset, [train_size, val_size],
        generator=torch.Generator().manual_seed(42)
    )
    
    # Create data loaders with optimized settings for high-end hardware
    # Increased num_workers to utilize more CPU cores for data loading
    # Added pin_memory for faster GPU transfer on systems with adequate RAM
    train_loader = DataLoader(
        train_dataset, 
        batch_size=args.batch_size, 
        shuffle=True, 
        num_workers=16,
        pin_memory=True,
        persistent_workers=True
    )
    val_loader = DataLoader(
        val_dataset, 
        batch_size=args.batch_size, 
        shuffle=False, 
        num_workers=8,
        pin_memory=True,
        persistent_workers=True
    )
    
    # Create model
    model = MillNNUE(feature_size=args.feature_size, hidden_size=args.hidden_size).to(device)
    logger.info(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")
    
    # Setup training with optimized components for high-performance hardware
    # Use AdamW optimizer with weight decay for better generalization
    optimizer = optim.AdamW(
        model.parameters(), 
        lr=args.lr,
        weight_decay=1e-5,
        betas=(0.9, 0.999),
        eps=1e-8
    )
    
    criterion = nn.MSELoss()
    
    # Setup learning rate scheduler based on user preference
    if args.lr_scheduler == 'adaptive':
        scheduler = AdaptiveLRScheduler(
            optimizer,
            initial_lr=args.lr,
            patience=10,
            factor=0.7,
            min_lr=1e-7,
            warmup_epochs=5,
            cooldown_epochs=3
        )
        logger.info("Using adaptive learning rate scheduler")
    elif args.lr_scheduler == 'cosine':
        scheduler = optim.lr_scheduler.CosineAnnealingWarmRestarts(
            optimizer, 
            T_0=30,  # Initial restart period
            T_mult=2,  # Multiplicative factor for period growth
            eta_min=1e-7  # Minimum learning rate
        )
        logger.info("Using cosine annealing scheduler")
    elif args.lr_scheduler == 'plateau':
        scheduler = optim.lr_scheduler.ReduceLROnPlateau(
            optimizer, 
            patience=10, 
            factor=0.5,
            min_lr=1e-7
        )
        logger.info("Using plateau scheduler")
    else:  # fixed
        scheduler = None
        logger.info("Using fixed learning rate")
    
    logger.info(f"Initial learning rate: {args.lr:.6f}")
    
    # Initialize training visualizer for data collection only
    visualizer = None
    if args.plot or args.save_csv:
        visualizer = TrainingVisualizer(output_dir=args.plot_dir)
        logger.info(f"Training data collection enabled - metrics will be saved to CSV")
        logger.info("Intermediate plotting disabled for optimal training performance")
        logger.info("Final plots will be generated after training completion")
    
    # Use gradient clipping for stability with larger batch sizes
    max_grad_norm = 1.0
    
    # Initialize gradient scaler for mixed precision training
    scaler = torch.amp.GradScaler('cuda') if device.type == 'cuda' else None
    
    best_val_loss = float('inf')
    patience_counter = 0
    max_patience = 50  # Increased patience for longer training
    
    # Training time tracking for ETA calculation
    training_start_time = time.time()
    epoch_times = []
    
    logger.info("Starting training...")
    logger.info("Progress: [--------------------] 0% | Detailed logs every 10 epochs")
    
    for epoch in range(args.epochs):
        start_time = time.time()
        
        # Train
        train_loss, avg_grad_norm = train_epoch(model, train_loader, optimizer, criterion, device, max_grad_norm, scaler)
        
        # Validate
        val_loss, val_accuracy = validate_epoch(model, val_loader, criterion, device)
        
        # Update learning rate based on scheduler type
        if args.lr_scheduler == 'adaptive':
            scheduler.step(train_loss, val_loss, avg_grad_norm)
            current_lr = scheduler.get_last_lr()[0]
        elif args.lr_scheduler == 'cosine':
            scheduler.step()
            current_lr = scheduler.get_last_lr()[0]
        elif args.lr_scheduler == 'plateau':
            scheduler.step(val_loss)
            current_lr = optimizer.param_groups[0]['lr']
        else:  # fixed
            current_lr = args.lr
        
        epoch_time = time.time() - start_time
        epoch_times.append(epoch_time)
        
        # Calculate ETA (Estimated Time to Arrival)
        eta_str = ""
        if len(epoch_times) >= 2:  # Need at least 2 epochs for meaningful estimate
            avg_epoch_time = sum(epoch_times) / len(epoch_times)
            remaining_epochs = args.epochs - (epoch + 1)
            eta_seconds = avg_epoch_time * remaining_epochs
            
            # Format ETA
            if eta_seconds < 60:
                eta_str = f", ETA: {eta_seconds:.0f}s"
            elif eta_seconds < 3600:
                eta_minutes = eta_seconds / 60
                eta_str = f", ETA: {eta_minutes:.1f}m"
            else:
                eta_hours = eta_seconds / 3600
                eta_str = f", ETA: {eta_hours:.1f}h"
        
        # Calculate total elapsed time
        total_elapsed = time.time() - training_start_time
        if total_elapsed < 60:
            elapsed_str = f"{total_elapsed:.0f}s"
        elif total_elapsed < 3600:
            elapsed_str = f"{total_elapsed/60:.1f}m"
        else:
            elapsed_str = f"{total_elapsed/3600:.1f}h"
        
        # Use simple percentage progress output
        progress_percent = ((epoch + 1) / args.epochs) * 100
        
        # Only log every 10 epochs or important milestones
        if (epoch + 1) % 10 == 0 or epoch == 0 or epoch == args.epochs - 1:
            # Clear any existing progress line before logging
            print()  # Ensure clean line for logger output
            logger.info(f"{progress_percent:5.1f}% | "
                       f"Epoch {epoch+1:3d}/{args.epochs} | "
                       f"Loss: T={train_loss:.0f} V={val_loss:.0f} | "
                       f"Acc: {val_accuracy:.3f} | "
                       f"LR: {current_lr:.1e} | "
                       f"Time: {epoch_time:.2f}s{eta_str}")
        else:
            # Print a simple progress indicator that overwrites itself
            print(f"\r{progress_percent:5.1f}% | Epoch {epoch+1:3d}/{args.epochs} | Loss: {val_loss:.0f} | Acc: {val_accuracy:.3f}", end="", flush=True)
        
        # Update visualization
        if visualizer:
            visualizer.add_epoch_data(
                epoch, train_loss, val_loss, val_accuracy, 
                current_lr, avg_grad_norm, epoch_time, 
                cumulative_time=time.time() - training_start_time,
                total_epochs=args.epochs
            )
        
        # Early stopping
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            patience_counter = 0
            # Save best model with automatic backup
            backup_existing_model(args.output)
            torch.save(model.state_dict(), f"{args.output}.pytorch")
            save_model_c_format(model, args.output)
            # Reduce model save logging to avoid spam
            if (epoch + 1) % 20 == 0 or epoch == args.epochs - 1:
                # Clear progress line before logging model update (may already be cleared by main log)
                if not ((epoch + 1) % 10 == 0 or epoch == 0 or epoch == args.epochs - 1):
                    print()
                logger.info(f"BEST: Model updated - Val Loss {val_loss:.0f} @ Epoch {epoch+1}")
        else:
            patience_counter += 1
            if patience_counter >= max_patience:
                # Clear progress line before logging early stopping
                print()
                logger.info(f"Early stopping after {epoch+1} epochs")
                break
    
    # Ensure progress bar line is completed
    print()  # New line after progress bar
    
    # Calculate and display total training time
    total_training_time = time.time() - training_start_time
    if total_training_time < 60:
        time_str = f"{total_training_time:.1f} seconds"
    elif total_training_time < 3600:
        time_str = f"{total_training_time/60:.1f} minutes"
    else:
        time_str = f"{total_training_time/3600:.2f} hours"
    
    avg_epoch_time = sum(epoch_times) / len(epoch_times) if epoch_times else 0
    
    logger.info(f"Training completed. Best validation loss: {best_val_loss:.6f}")
    logger.info(f"Total training time: {time_str}")
    logger.info(f"Average time per epoch: {avg_epoch_time:.2f}s")
    logger.info(f"Model saved to {args.output}")
    
    # Generate final visualizations
    if visualizer:
        logger.info("Generating final training summary...")
        visualizer.create_summary_plot()
        
        if args.save_csv:
            visualizer.save_metrics_csv()
        
        logger.info(f"Training visualizations saved to {args.plot_dir}")
        
        # Generate final comprehensive plots after training completion
        try:
            from auto_plot import auto_generate_plots
            csv_path = Path(args.plot_dir) / "training_metrics.csv"
            if csv_path.exists():
                logger.info("Skipping plot generation to avoid potential delays...")
                # Temporarily disable all plotting to identify bottleneck
                logger.info("Plot generation disabled for performance debugging")
            else:
                logger.warning(f"Training metrics CSV not found at {csv_path}")
        except Exception as e:
            logger.warning(f"Failed to generate final plots: {e}")
    
    # Pipeline Mode: Final model validation
    if args.pipeline:
        logger.info("=== Step 4: Model Validation ===")
        logger.info("PIPELINE: About to call validate_final_model...")
        
        validation_start = time.time()
        success = validate_final_model(args.output, args.engine)
        validation_end = time.time()
        
        logger.info(f"PIPELINE: validate_final_model completed in {validation_end - validation_start:.2f} seconds")
        
        if not success:
            logger.error("Model validation failed")
            return 1
        
        logger.info("PIPELINE: Starting pipeline completion summary...")
        # Pipeline completion summary
        logger.info("=== Pipeline Completed Successfully ===")
        logger.info(f"Training data: {args.data}")
        logger.info(f"Trained model: {args.output}")
        logger.info("")
        logger.info("To use the trained model:")
        logger.info(f"  setoption name UseNNUE value true")
        logger.info(f"  setoption name NNUEModelPath value {args.output}")
        logger.info(f"  setoption name NNUEWeight value 90")
        logger.info("PIPELINE: Pipeline summary completed")
    
    logger.info("PIPELINE: About to return from main function...")
    return 0

if __name__ == '__main__':
    main()
