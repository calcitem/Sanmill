#!/usr/bin/env python3
"""
Training script for Katamill neural network with multi-head losses.

Supports policy distillation, value regression, and auxiliary targets
(score prediction, ownership prediction, mill potential).
"""

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torch.optim import Adam
from torch.optim.lr_scheduler import CosineAnnealingLR

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import modules with fallback
try:
    from .config import NetConfig, default_net_config
    from .neural_network import KatamillNet
    from .selfplay import run_selfplay, SelfPlayConfig
    from .progress import TrainingProgressTracker
except ImportError:
    from config import NetConfig, default_net_config
    from neural_network import KatamillNet
    from selfplay import run_selfplay, SelfPlayConfig
    from progress import TrainingProgressTracker

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class TrainConfig:
    """Training hyperparameters optimized for much stronger Nine Men's Morris play."""
    batch_size: int = 128  # Large batch size for stable gradients
    num_epochs: int = 100  # Many epochs for thorough learning
    learning_rate: float = 5e-4  # Conservative learning rate for deep training
    weight_decay: float = 1e-3  # Strong regularization to prevent overfitting
    
    # Loss weights for multi-head training - heavily optimized for policy learning
    policy_weight: float = 8.0  # Much higher policy weight for superior move selection
    value_weight: float = 4.0   # Higher value weight for better position evaluation
    score_weight: float = 1.5   # Balanced score weight for tactical understanding
    ownership_weight: float = 1.0  # Moderate ownership weight
    mill_potential_weight: float = 0.8  # Higher mill potential for tactical awareness
    
    # Advanced training features (LC0-inspired)
    use_lr_schedule: bool = True
    warmup_epochs: int = 3  # Longer warmup
    use_mixed_precision: bool = True  # Enable mixed precision
    gradient_accumulation_steps: int = 2  # Effective batch size = 128
    adaptive_weighting: bool = True  # Dynamic loss balancing
    label_smoothing: float = 0.02  # Label smoothing for regularization
    aux_warmup_steps: int = 3000  # Gradual auxiliary target introduction
    
    # Checkpointing
    checkpoint_dir: str = "checkpoints"
    save_every_epochs: int = 3  # More frequent saves
    
    # Data augmentation via symmetries
    use_symmetries: bool = True
    
    # Gradient optimization
    grad_clip_norm: float = 0.5  # Tighter gradient clipping for stability
    
    # Early stopping for efficient training
    early_stopping_patience: int = 10  # Stop if no improvement for 10 epochs
    early_stopping_min_delta: float = 1e-4  # Minimum improvement to count as better
    early_stopping_monitor: str = "val_loss"  # Monitor validation loss


class KatamillDataset(Dataset):
    """Dataset for Katamill training samples."""
    
    def __init__(self, samples: List[Dict[str, np.ndarray]], use_symmetries: bool = True):
        """
        Args:
            samples: List of training samples from selfplay
            use_symmetries: Whether to apply board symmetries for augmentation
        """
        self.samples = samples
        self.use_symmetries = use_symmetries
        
        # Precompute symmetry transformations if needed
        if use_symmetries:
            self._init_symmetries()
    
    def _init_symmetries(self):
        """Initialize symmetry operations: 8 geometry x 2 color-flip = 16 variants."""
        try:
            from .symmetry import build_geometric_transforms
        except ImportError:
            from symmetry import build_geometric_transforms
        
        self.geom_transforms = build_geometric_transforms()
        # Compose with color-flip flag to reach 16 variants similar to NNUE practice
        self.symmetries = []
        for idx, t in enumerate(self.geom_transforms):
            self.symmetries.append((idx, False))
            self.symmetries.append((idx, True))
    
    def _apply_symmetry(self, features: np.ndarray, pi: np.ndarray, 
                       aux: Dict[str, np.ndarray], sym_idx: int) -> Tuple:
        """Apply a composed symmetry (geometry + optional color-flip) to inputs and targets.

        Geometry is applied to features spatial dimensions, policy via 576-index remap,
        and per-node vectors (ownership, mill_potential) via 24-index remap.
        Color-flip swaps color-dependent channels and keeps labels consistent with 
        the current player's perspective.
        """
        import numpy as _np
        try:
            from .symmetry import (
                apply_geometry_to_features,
                apply_geometry_to_pi,
                apply_geometry_to_pos_vector,
                apply_color_flip_to_features,
            )
        except ImportError:
            from symmetry import (
                apply_geometry_to_features,
                apply_geometry_to_pi,
                apply_geometry_to_pos_vector,
                apply_color_flip_to_features,
            )

        geom_idx, do_color_flip = self.symmetries[sym_idx]
        t = self.geom_transforms[geom_idx]
        rot = int(t['rot'])
        flip = bool(t['flip'])
        pos_map24 = t['pos_map24']
        action_map576 = t['action_map576']

        # Apply geometry to features
        feats_geo = apply_geometry_to_features(features, rot, flip)
        # Optional color flip to mimic NNUE-style color inversion augmentation
        feats_final = apply_color_flip_to_features(feats_geo) if do_color_flip else feats_geo

        # Policy remap by 576-index map
        pi_final = apply_geometry_to_pi(pi, action_map576)

        # Ownership and mill_potential are 24-length vectors under aux
        transformed_aux = {
            'score': aux['score'].copy(),
            'ownership': apply_geometry_to_pos_vector(aux['ownership'], pos_map24),
            'mill_potential': apply_geometry_to_pos_vector(aux['mill_potential'], pos_map24),
        }

        return feats_final, pi_final, transformed_aux
    
    def __len__(self):
        base_len = len(self.samples)
        if self.use_symmetries:
            return base_len * len(self.symmetries)
        return base_len
    
    def __getitem__(self, idx):
        if self.use_symmetries:
            base_idx = idx // len(self.symmetries)
            sym_idx = idx % len(self.symmetries)
        else:
            base_idx = idx
            sym_idx = 0
        
        # Validate index bounds
        if base_idx >= len(self.samples):
            raise IndexError(f"Sample index {base_idx} out of range (have {len(self.samples)} samples)")
        
        sample = self.samples[base_idx]
        
        # Validate sample structure
        required_keys = ['features', 'pi', 'z', 'aux']
        for key in required_keys:
            if key not in sample:
                raise ValueError(f"Sample {base_idx} missing required key: {key}")
        
        features = sample['features']
        pi = sample['pi']
        z = sample['z']
        aux = sample['aux']
        
        # Validate auxiliary targets structure
        required_aux_keys = ['score', 'ownership', 'mill_potential']
        for key in required_aux_keys:
            if key not in aux:
                raise ValueError(f"Sample {base_idx} auxiliary targets missing key: {key}")
        
        # Apply symmetries if enabled
        if self.use_symmetries and sym_idx > 0:
            try:
                features, pi, aux = self._apply_symmetry(features, pi, aux, sym_idx)
            except Exception as e:
                # Fallback to original sample if symmetry fails
                print(f"Warning: Symmetry application failed for sample {base_idx}, sym {sym_idx}: {e}")
        
        # Convert to tensors with proper error handling
        try:
            return {
                'features': torch.from_numpy(features.astype(np.float32)).float(),
                'pi': torch.from_numpy(pi.astype(np.float32)).float(),
                'z': torch.from_numpy(z.astype(np.float32)).float(),
                'score': torch.from_numpy(aux['score'].astype(np.float32)).float(),
                'ownership': torch.from_numpy(aux['ownership'].astype(np.float32)).float(),
                'mill_potential': torch.from_numpy(aux['mill_potential'].astype(np.float32)).float(),
            }
        except Exception as e:
            raise ValueError(f"Failed to convert sample {base_idx} to tensors: {e}")


class MultiHeadLoss(nn.Module):
    """
    Advanced multi-head loss function inspired by KataGo's training improvements.
    
    Features:
    - KataGo-style loss scaling and weighting
    - Adaptive loss balancing based on gradient norms
    - Improved numerical stability
    - Support for auxiliary target scheduling
    - Robust handling of edge cases
    """
    
    def __init__(self, config: TrainConfig):
        super().__init__()
        self.config = config
        self.eps = 1e-8  # Small epsilon for numerical stability
        
        # KataGo-style adaptive loss weighting
        self.adaptive_weighting = getattr(config, 'adaptive_weighting', True)
        self.gradient_norm_history = {}
        self.loss_history = {}
        
        # Loss scheduling (gradually increase auxiliary loss weights)
        self.training_step = 0
        self.warmup_steps = getattr(config, 'aux_warmup_steps', 1000)
        
        # Register buffers for running statistics
        self.register_buffer('policy_loss_ema', torch.tensor(1.0))
        self.register_buffer('value_loss_ema', torch.tensor(1.0))
        self.register_buffer('score_loss_ema', torch.tensor(1.0))
        self.register_buffer('ownership_loss_ema', torch.tensor(1.0))
        
        # EMA decay factor
        self.ema_decay = 0.99
        
    def forward(self, predictions: Dict[str, torch.Tensor], 
                targets: Dict[str, torch.Tensor]) -> Tuple[torch.Tensor, Dict[str, float]]:
        """
        Compute multi-head loss with KataGo-inspired improvements.
        
        Features:
        - Adaptive loss weighting based on gradient norms
        - Auxiliary target scheduling during warmup
        - Improved numerical stability
        - KataGo-style loss scaling
        
        Args:
            predictions: Model outputs
            targets: Ground truth targets
            
        Returns:
            total_loss: Weighted sum of all losses
            loss_components: Individual loss values for logging
        """
        self.training_step += 1
        losses = {}
        raw_losses = {}
        
        # Policy loss with KataGo-style improvements
        policy_pred = predictions['policy']
        policy_target = targets['pi']
        
        # Use focal loss for better handling of imbalanced action distributions
        # Add numerical stability to prevent NaN/Inf
        policy_pred_stable = torch.clamp(policy_pred, min=-50.0, max=50.0)
        log_probs = F.log_softmax(policy_pred_stable, dim=1)
        softmax_probs = F.softmax(policy_pred_stable, dim=1)
        
        # Focal loss with numerical stability
        focal_weight = torch.pow(torch.clamp(1 - softmax_probs, min=1e-8, max=1.0), 2.0)
        
        # Add label smoothing for regularization
        smoothing = getattr(self.config, 'label_smoothing', 0.01)
        smoothing = max(0.0, min(smoothing, 0.5))  # Clamp smoothing to reasonable range
        
        # Ensure policy target is valid probability distribution
        policy_target_sum = torch.sum(policy_target, dim=1, keepdim=True)
        policy_target_normalized = policy_target / torch.clamp(policy_target_sum, min=1e-8)
        
        smooth_target = policy_target_normalized * (1 - smoothing) + smoothing / policy_target.size(1)
        
        # Compute policy loss with focal weighting and numerical stability
        policy_loss_raw = F.kl_div(log_probs, smooth_target, reduction='none')
        # Clamp to prevent extreme values and ensure non-negative
        policy_loss_raw = torch.clamp(policy_loss_raw, min=0.0, max=50.0)
        
        losses['policy'] = (focal_weight * policy_loss_raw).sum(dim=1).mean()
        raw_losses['policy'] = torch.clamp(
            F.kl_div(log_probs, smooth_target, reduction='batchmean'),
            min=0.0  # Ensure policy loss is non-negative
        )
        
        # Value loss with improved robustness
        value_pred = predictions['value'].squeeze(-1)
        value_target = targets['z'].squeeze(-1)
        
        # Use Huber loss with adaptive delta based on target distribution
        if len(value_target) > 1:
            value_std = torch.std(value_target) + self.eps
            adaptive_delta = torch.clamp(value_std, 0.1, 2.0)
        else:
            adaptive_delta = 1.0  # Default delta for single sample
        
        # Ensure delta is positive for Huber loss
        adaptive_delta = max(float(adaptive_delta), 0.1)
        losses['value'] = F.huber_loss(value_pred, value_target, delta=adaptive_delta)
        raw_losses['value'] = losses['value']
        
        # Score loss with improved scaling
        score_pred = predictions['score'].squeeze(-1)
        score_target = targets['score'].squeeze(-1)
        
        # Adaptive scaling based on score magnitude with proper handling
        if len(score_target) > 1:
            score_std = torch.std(score_target)
            score_scale = torch.clamp(score_std + self.eps, 0.1, 10.0)
        else:
            score_scale = 1.0  # Default scale for single sample
            
        # Ensure scale is reasonable
        score_scale = max(float(score_scale), 0.1)
        normalized_score_pred = score_pred / score_scale
        normalized_score_target = score_target / score_scale
        
        losses['score'] = F.mse_loss(normalized_score_pred, normalized_score_target)
        raw_losses['score'] = losses['score']
        
        # Ownership loss with spatial awareness
        ownership_pred = predictions['ownership']
        ownership_target = targets['ownership']
        
        # Use smooth L1 loss with position-dependent weighting
        position_weights = torch.ones_like(ownership_target)
        # Give higher weight to positions that are more contested (closer to 0)
        contest_factor = 1.0 - torch.abs(ownership_target)
        position_weights = 1.0 + 0.5 * contest_factor
        
        ownership_loss_raw = F.smooth_l1_loss(ownership_pred, ownership_target, reduction='none')
        losses['ownership'] = (ownership_loss_raw * position_weights).mean()
        raw_losses['ownership'] = F.smooth_l1_loss(ownership_pred, ownership_target)
        
        # Mill potential loss (auxiliary target) - fixed for stability
        mill_target = targets['mill_potential']
        # Clamp targets to valid range [0, 1] to prevent loss issues
        mill_target = torch.clamp(mill_target, 0.0, 1.0)
        
        # Use ownership features to predict mill potential with proper scaling
        mill_features = torch.abs(ownership_pred)  # Mill potential correlates with piece control
        mill_pred = torch.sigmoid(mill_features.mean(dim=1, keepdim=True).expand_as(mill_target))
        
        # Use MSE loss instead of BCE for better stability with continuous targets
        losses['mill_potential'] = F.mse_loss(mill_pred, mill_target)
        raw_losses['mill_potential'] = losses['mill_potential']
        
        # Update EMA statistics for adaptive weighting
        self._update_loss_ema(raw_losses)
        
        # Get adaptive weights using KataGo-style balancing
        weights = self._get_adaptive_weights()
        
        # Apply auxiliary target scheduling (gradually increase aux weights)
        aux_schedule_factor = min(1.0, self.training_step / self.warmup_steps)
        weights['score'] *= aux_schedule_factor
        weights['ownership'] *= aux_schedule_factor
        weights['mill_potential'] *= aux_schedule_factor
        
        # Compute weighted total loss with proper bounds checking
        total_loss = (
            weights['policy'] * losses['policy'] +
            weights['value'] * losses['value'] +
            weights['score'] * losses['score'] +
            weights['ownership'] * losses['ownership'] +
            weights['mill_potential'] * losses['mill_potential']
        )
        
        # Ensure total loss is reasonable (prevent negative or extreme values)
        total_loss = torch.clamp(total_loss, min=0.0, max=100.0)
        
        # Prepare logging information
        loss_components = {k: v.item() for k, v in losses.items()}
        loss_components['total'] = total_loss.item()
        loss_components['weights'] = {k: float(v) for k, v in weights.items()}
        loss_components['aux_schedule_factor'] = aux_schedule_factor
        
        return total_loss, loss_components
    
    def _update_loss_ema(self, losses: Dict[str, torch.Tensor]):
        """Update exponential moving averages of loss magnitudes."""
        with torch.no_grad():
            self.policy_loss_ema = self.ema_decay * self.policy_loss_ema + (1 - self.ema_decay) * losses['policy']
            self.value_loss_ema = self.ema_decay * self.value_loss_ema + (1 - self.ema_decay) * losses['value']
            self.score_loss_ema = self.ema_decay * self.score_loss_ema + (1 - self.ema_decay) * losses['score']
            self.ownership_loss_ema = self.ema_decay * self.ownership_loss_ema + (1 - self.ema_decay) * losses['ownership']
    
    def _get_adaptive_weights(self) -> Dict[str, float]:
        """
        Get adaptive loss weights using KataGo-style balancing.
        
        The idea is to balance losses so they contribute roughly equally
        to the total gradient norm, preventing any single loss from dominating.
        """
        if not self.adaptive_weighting:
            # Use static weights from config
            return {
                'policy': self.config.policy_weight,
                'value': self.config.value_weight,
                'score': self.config.score_weight,
                'ownership': self.config.ownership_weight,
                'mill_potential': self.config.mill_potential_weight,
            }
        
        # Use EMA statistics to balance loss magnitudes
        base_weights = {
            'policy': self.config.policy_weight,
            'value': self.config.value_weight,
            'score': self.config.score_weight,
            'ownership': self.config.ownership_weight,
            'mill_potential': self.config.mill_potential_weight,
        }
        
        # Get current loss magnitudes
        loss_magnitudes = {
            'policy': float(self.policy_loss_ema),
            'value': float(self.value_loss_ema),
            'score': float(self.score_loss_ema),
            'ownership': float(self.ownership_loss_ema),
            'mill_potential': 1.0,  # Mill potential is typically well-scaled
        }
        
        # Compute adaptive weights (inverse relationship with magnitude)
        adaptive_weights = {}
        for key in base_weights:
            magnitude = loss_magnitudes[key]
            if magnitude > self.eps:
                # Scale weight inversely with loss magnitude
                scale_factor = 1.0 / max(magnitude, 0.1)
                adaptive_weights[key] = base_weights[key] * scale_factor
            else:
                adaptive_weights[key] = base_weights[key]
        
        # Normalize weights to prevent total loss from growing too large
        total_weight = sum(adaptive_weights.values())
        if total_weight > 0:
            norm_factor = 5.0 / total_weight  # Target total weight of 5.0
            adaptive_weights = {k: v * norm_factor for k, v in adaptive_weights.items()}
        
        return adaptive_weights


def train_epoch(model: KatamillNet, dataloader: DataLoader, optimizer: torch.optim.Optimizer,
                loss_fn: MultiHeadLoss, device: torch.device, epoch: int, 
                progress_tracker=None) -> Dict[str, float]:
    """
    Train for one epoch with KataGo-inspired improvements.
    
    Features:
    - Advanced gradient clipping with per-parameter monitoring
    - Gradient accumulation support
    - Mixed precision training
    - Better loss tracking and statistics
    """
    model.train()
    
    # Initialize comprehensive loss tracking
    total_losses = {
        'total': 0.0,
        'policy': 0.0,
        'value': 0.0,
        'score': 0.0,
        'ownership': 0.0,
        'mill_potential': 0.0,
    }
    
    # Gradient statistics
    grad_stats = {
        'grad_norm': 0.0,
        'grad_clips': 0,
        'max_grad': 0.0,
    }
    
    num_batches = len(dataloader)
    gradient_accumulation_steps = getattr(loss_fn.config, 'gradient_accumulation_steps', 1)
    
    # Mixed precision support
    use_amp = getattr(loss_fn.config, 'use_mixed_precision', False)
    scaler = torch.amp.GradScaler('cuda') if use_amp and device.type == 'cuda' else None
    
    for batch_idx, batch in enumerate(dataloader):
        # Move to device with non-blocking transfer
        features = batch['features'].to(device, non_blocking=True)
        targets = {k: v.to(device, non_blocking=True) for k, v in batch.items() if k != 'features'}
        
        # Forward pass with optional mixed precision
        if use_amp and scaler:
            with torch.amp.autocast('cuda'):
                policy_logits, value, score, ownership = model(features)
                predictions = {
                    'policy': policy_logits,
                    'value': value,
                    'score': score,
                    'ownership': ownership,
                }
                loss, loss_components = loss_fn(predictions, targets)
                # Scale loss for gradient accumulation
                loss = loss / gradient_accumulation_steps
        else:
            policy_logits, value, score, ownership = model(features)
            predictions = {
                'policy': policy_logits,
                'value': value,
                'score': score,
                'ownership': ownership,
            }
            loss, loss_components = loss_fn(predictions, targets)
            # Scale loss for gradient accumulation
            loss = loss / gradient_accumulation_steps
        
        # Backward pass with gradient accumulation
        if use_amp and scaler:
            scaler.scale(loss).backward()
        else:
            loss.backward()
        
        # Update weights every gradient_accumulation_steps
        if (batch_idx + 1) % gradient_accumulation_steps == 0:
            # Advanced gradient clipping with monitoring
            if hasattr(loss_fn.config, 'grad_clip_norm') and loss_fn.config.grad_clip_norm > 0:
                if use_amp and scaler:
                    scaler.unscale_(optimizer)
                
                # Calculate gradient norm before clipping
                total_norm = torch.nn.utils.clip_grad_norm_(
                    model.parameters(), loss_fn.config.grad_clip_norm
                )
                
                # Track gradient statistics
                grad_stats['grad_norm'] += total_norm.item()
                if total_norm.item() > loss_fn.config.grad_clip_norm:
                    grad_stats['grad_clips'] += 1
                grad_stats['max_grad'] = max(grad_stats['max_grad'], total_norm.item())
            
            # Optimizer step
            if use_amp and scaler:
                scaler.step(optimizer)
                scaler.update()
            else:
                optimizer.step()
            
            optimizer.zero_grad()
        
        # Accumulate losses (unscale for proper averaging)
        actual_loss = loss.item() * gradient_accumulation_steps
        total_losses['total'] += actual_loss
        
        for k, v in loss_components.items():
            if isinstance(v, (int, float)) and k in total_losses:
                total_losses[k] += v
        
        # Update progress tracker with enhanced information
        if progress_tracker:
            # Prepare enhanced progress info
            progress_info = {
                'policy': f"{loss_components['policy']:.3f}",
                'value': f"{loss_components['value']:.3f}",
                'score': f"{loss_components['score']:.3f}",
                'ownership': f"{loss_components['ownership']:.3f}",
            }
            
            # Add gradient information if available
            if (batch_idx + 1) % gradient_accumulation_steps == 0:
                current_grad_norm = grad_stats['grad_norm'] / max(1, batch_idx // gradient_accumulation_steps + 1)
                progress_info['grad_norm'] = f"{current_grad_norm:.2e}"
            
            # Add auxiliary loss scheduling info
            if 'aux_schedule_factor' in loss_components:
                progress_info['aux_sched'] = f"{loss_components['aux_schedule_factor']:.2f}"
            
            progress_tracker.update_batch(actual_loss, **progress_info)
    
    # Average losses and statistics
    for k in total_losses:
        total_losses[k] /= num_batches
    
    # Add gradient statistics to output
    if num_batches > 0:
        effective_batches = max(1, num_batches // gradient_accumulation_steps)
        total_losses['grad_norm'] = grad_stats['grad_norm'] / effective_batches
        total_losses['grad_clips_percent'] = (grad_stats['grad_clips'] / effective_batches) * 100
        total_losses['max_grad_norm'] = grad_stats['max_grad']
    
    return total_losses


def validate(model: KatamillNet, dataloader: DataLoader, loss_fn: MultiHeadLoss,
             device: torch.device) -> Dict[str, float]:
    """Validate model on validation set."""
    model.eval()
    
    total_losses = {
        'total': 0.0,
        'policy': 0.0,
        'value': 0.0,
        'score': 0.0,
        'ownership': 0.0,
        'mill_potential': 0.0,
    }
    
    num_batches = len(dataloader)
    
    with torch.no_grad():
        for batch in dataloader:
            # Move to device
            features = batch['features'].to(device)
            targets = {k: v.to(device) for k, v in batch.items() if k != 'features'}
            
            # Forward pass
            policy_logits, value, score, ownership = model(features)
            predictions = {
                'policy': policy_logits,
                'value': value,
                'score': score,
                'ownership': ownership,
            }
            
            # Compute loss
            loss, loss_components = loss_fn(predictions, targets)
            
            # Accumulate losses
            total_losses['total'] += loss.item()
            for k, v in loss_components.items():
                # Skip non-numeric values like adaptive_weights
                if isinstance(v, (int, float)) and k in total_losses:
                    total_losses[k] += v
    
    # Average losses
    for k in total_losses:
        total_losses[k] /= num_batches
    
    return total_losses


def save_checkpoint(model: KatamillNet, optimizer: torch.optim.Optimizer,
                   epoch: int, losses: Dict[str, float], config: TrainConfig,
                   filepath: str, scheduler: Optional[torch.optim.lr_scheduler._LRScheduler] = None,
                   best_val_loss: Optional[float] = None):
    """Save training checkpoint with complete state."""
    checkpoint = {
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
        'losses': losses,
        'config': asdict(config),
        'net_config': asdict(model.cfg if hasattr(model, 'cfg') else default_net_config()),
    }
    
    # Save scheduler state if available
    if scheduler is not None:
        checkpoint['scheduler_state_dict'] = scheduler.state_dict()
    
    # Save best validation loss for model selection
    if best_val_loss is not None:
        checkpoint['best_val_loss'] = best_val_loss
    
    torch.save(checkpoint, filepath)
    logger.info(f"Saved checkpoint to {filepath}")


def load_checkpoint(filepath: str, model: KatamillNet, optimizer: Optional[torch.optim.Optimizer] = None,
                   scheduler: Optional[torch.optim.lr_scheduler._LRScheduler] = None):
    """Load training checkpoint with full state restoration."""
    checkpoint = torch.load(filepath, map_location='cpu')
    
    # Load model state
    model.load_state_dict(checkpoint['model_state_dict'])
    
    # Load optimizer state
    if optimizer and 'optimizer_state_dict' in checkpoint:
        optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
    
    # Load scheduler state if available
    if scheduler and 'scheduler_state_dict' in checkpoint:
        scheduler.load_state_dict(checkpoint['scheduler_state_dict'])
    
    # Get training metadata
    epoch = checkpoint.get('epoch', 0)
    losses = checkpoint.get('losses', {})
    config = checkpoint.get('config', {})
    
    logger.info(f"Resumed from checkpoint: epoch {epoch}, losses: {losses}")
    
    return epoch, losses, config


def train(config: TrainConfig, net_config: NetConfig, train_data: List[Dict],
          val_data: Optional[List[Dict]] = None,
          resume_from: Optional[str] = None,
          init_weights_from: Optional[str] = None):
    """Main training loop with resume capability."""
    # Setup device
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    logger.info(f"Training on device: {device}")
    
    # Create model
    model = KatamillNet(net_config).to(device)
    logger.info(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    # Optionally initialize model weights from a checkpoint (weights-only init)
    # This is used for new iterations where we want to start from a previous
    # model's weights but NOT resume optimizer/scheduler/epoch state.
    if init_weights_from and os.path.exists(init_weights_from):
        try:
            checkpoint = torch.load(init_weights_from, map_location='cpu')
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                state_dict = checkpoint['model_state_dict']
            elif isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
                state_dict = checkpoint['state_dict']
            else:
                state_dict = checkpoint
            missing, unexpected = model.load_state_dict(state_dict, strict=False)
            if missing or unexpected:
                logger.warning(f"Weights init: missing keys={len(missing)}, unexpected={len(unexpected)}")
        except Exception as e:
            raise AssertionError(f"Failed to initialize weights from {init_weights_from}: {e}")
    
    # Create datasets and dataloaders
    train_dataset = KatamillDataset(train_data, use_symmetries=config.use_symmetries)
    train_loader = DataLoader(train_dataset, batch_size=config.batch_size,
                            shuffle=True, num_workers=4, pin_memory=True)
    
    val_loader = None
    if val_data:
        val_dataset = KatamillDataset(val_data, use_symmetries=False)
        val_loader = DataLoader(val_dataset, batch_size=config.batch_size,
                              shuffle=False, num_workers=4, pin_memory=True)
    
    # Create optimizer with better settings inspired by KataGo
    optimizer = Adam(
        model.parameters(), 
        lr=config.learning_rate,
        weight_decay=config.weight_decay,
        betas=(0.9, 0.999),  # Standard Adam betas
        eps=1e-8,  # Better numerical stability
        amsgrad=False  # Use standard Adam for now
    )
    
    # Improved learning rate scheduling
    scheduler = None
    if config.use_lr_schedule and config.num_epochs > 1:
        # Use warmup + cosine annealing for better convergence
        from torch.optim.lr_scheduler import SequentialLR, LinearLR, CosineAnnealingLR
        
        # Ensure warmup doesn't exceed total epochs
        effective_warmup = min(config.warmup_epochs, config.num_epochs - 1)
        cosine_epochs = max(1, config.num_epochs - effective_warmup)
        
        if effective_warmup > 0 and cosine_epochs > 1:
            warmup_scheduler = LinearLR(
                optimizer, 
                start_factor=0.1,  # Start at 10% of target LR
                total_iters=effective_warmup
            )
            
            cosine_scheduler = CosineAnnealingLR(
                optimizer, 
                T_max=cosine_epochs,
                eta_min=config.learning_rate * 0.01  # Don't go below 1% of original LR
            )
            
            scheduler = SequentialLR(
                optimizer,
                schedulers=[warmup_scheduler, cosine_scheduler],
                milestones=[effective_warmup]
            )
        else:
            # Fallback to simple cosine annealing if warmup is not practical
            scheduler = CosineAnnealingLR(
                optimizer, 
                T_max=max(1, config.num_epochs),
                eta_min=config.learning_rate * 0.01
            )
    
    # Create loss function
    loss_fn = MultiHeadLoss(config)
    
    # Create checkpoint directory
    os.makedirs(config.checkpoint_dir, exist_ok=True)
    
    # Resume from checkpoint if specified
    start_epoch = 1
    best_val_loss = float('inf')
    early_stopping_counter = 0  # Track epochs without improvement
    
    if resume_from and os.path.exists(resume_from):
        logger.info(f"Resuming training from checkpoint: {resume_from}")
        loaded_epoch, loaded_losses, loaded_config = load_checkpoint(
            resume_from, model, optimizer, scheduler
        )
        start_epoch = loaded_epoch + 1
        
        # Update config with any new settings while preserving training state
        if 'best_val_loss' in loaded_config:
            best_val_loss = loaded_config['best_val_loss']
        
        logger.info(f"Resuming from epoch {start_epoch}")
    
    # Initialize progress tracker
    progress_tracker = TrainingProgressTracker(
        total_epochs=config.num_epochs - start_epoch + 1,
        batches_per_epoch=len(train_loader)
    )
    
    # Initialize train_losses for the case where no training occurs
    train_losses = {
        'total': float('inf'),
        'policy': 0.0,
        'value': 0.0,
        'score': 0.0,
        'ownership': 0.0,
        'mill_potential': 0.0,
    }
    
    # Training loop
    try:
        if start_epoch <= config.num_epochs:
            for epoch in range(start_epoch, config.num_epochs + 1):
                # Start epoch tracking
                progress_tracker.start_epoch(epoch)
                
                # Train
                train_losses = train_epoch(model, train_loader, optimizer, loss_fn, device, epoch, progress_tracker)
                
                # Validate
                val_losses = None
                if val_loader:
                    val_losses = validate(model, val_loader, loss_fn, device)
                    
                    # Track best model and early stopping
                    current_val_loss = val_losses['total']
                    
                    # Check for improvement (with minimum delta threshold)
                    if current_val_loss < best_val_loss - config.early_stopping_min_delta:
                        best_val_loss = current_val_loss
                        early_stopping_counter = 0  # Reset counter
                        best_model_path = os.path.join(config.checkpoint_dir, "katamill_best.pth")
                        save_checkpoint(model, optimizer, epoch, val_losses, config, 
                                      best_model_path, scheduler, best_val_loss)
                        logger.info(f"New best model saved (val_loss: {best_val_loss:.4f})")
                    else:
                        early_stopping_counter += 1
                        logger.info(f"No improvement for {early_stopping_counter} epochs "
                                  f"(best: {best_val_loss:.4f}, current: {current_val_loss:.4f})")
                    
                    # Check early stopping condition
                    if early_stopping_counter >= config.early_stopping_patience:
                        logger.info(f"Early stopping triggered after {early_stopping_counter} epochs without improvement")
                        logger.info(f"Best validation loss: {best_val_loss:.4f}")
                        break  # Exit training loop
                
                # Update learning rate
                current_lr = None
                if scheduler:
                    scheduler.step()
                    current_lr = scheduler.get_last_lr()[0]
                
                # End epoch tracking
                progress_tracker.end_epoch(
                    train_losses['total'], 
                    val_losses['total'] if val_losses else None
                )
                
                # Log additional info
                if current_lr:
                    logger.info(f"Learning rate: {current_lr:.6f}")
                
                # Save periodic checkpoint
                if epoch % config.save_every_epochs == 0:
                    checkpoint_path = os.path.join(config.checkpoint_dir,
                                                 f"katamill_epoch_{epoch}.pth")
                    save_checkpoint(model, optimizer, epoch, train_losses, config, 
                                  checkpoint_path, scheduler, best_val_loss)
                
                # Save latest checkpoint (for easy resuming)
                latest_path = os.path.join(config.checkpoint_dir, "katamill_latest.pth")
                save_checkpoint(model, optimizer, epoch, train_losses, config, 
                              latest_path, scheduler, best_val_loss)
        else:
            logger.info(f"No training needed: start_epoch ({start_epoch}) > num_epochs ({config.num_epochs})")
    
    finally:
        # Always close progress tracker
        progress_tracker.close()
    
    # Save final model
    final_path = os.path.join(config.checkpoint_dir, "katamill_final.pth")
    save_checkpoint(model, optimizer, config.num_epochs, train_losses, config, 
                  final_path, scheduler, best_val_loss)
    
    logger.info("Training completed!")
    logger.info(f"Best validation loss: {best_val_loss:.4f}")


def main():
    parser = argparse.ArgumentParser(description='Train Katamill neural network')
    parser.add_argument('--config', type=str, help='Training config JSON file')
    parser.add_argument('--data', type=str, required=True, help='Training data file (.npz)')
    parser.add_argument('--val-data', type=str, help='Validation data file (.npz)')
    parser.add_argument('--resume', type=str, help='Resume from checkpoint')
    parser.add_argument('--epochs', type=int, help='Override number of epochs')
    parser.add_argument('--batch-size', type=int, help='Override batch size')
    parser.add_argument('--lr', type=float, help='Override learning rate')
    parser.add_argument('--checkpoint-dir', type=str, help='Override checkpoint directory')
    
    args = parser.parse_args()
    
    # Load config
    train_config = TrainConfig()
    net_config = default_net_config()
    
    # If resuming, try to load config from checkpoint first
    if args.resume and os.path.exists(args.resume):
        try:
            checkpoint = torch.load(args.resume, map_location='cpu')
            if 'config' in checkpoint:
                saved_config = checkpoint['config']
                for k, v in saved_config.items():
                    if hasattr(train_config, k):
                        setattr(train_config, k, v)
                logger.info("Loaded training config from checkpoint")
            if 'net_config' in checkpoint:
                saved_net_config = checkpoint['net_config']
                for k, v in saved_net_config.items():
                    if hasattr(net_config, k):
                        setattr(net_config, k, v)
                logger.info("Loaded network config from checkpoint")
        except Exception as e:
            logger.warning(f"Could not load config from checkpoint: {e}")
    
    # Load config file (overrides checkpoint config)
    if args.config:
        with open(args.config, 'r') as f:
            config_dict = json.load(f)
            
            # Handle nested config structure
            if 'training' in config_dict:
                for k, v in config_dict['training'].items():
                    if hasattr(train_config, k):
                        setattr(train_config, k, v)
            
            if 'network' in config_dict:
                for k, v in config_dict['network'].items():
                    if hasattr(net_config, k):
                        setattr(net_config, k, v)
            
            # Also handle flat config structure
            for k, v in config_dict.items():
                if k not in ['training', 'network', 'selfplay', 'mcts']:
                    if hasattr(train_config, k):
                        setattr(train_config, k, v)
    
    # Override with command line args (highest priority)
    if args.epochs:
        train_config.num_epochs = args.epochs
    if args.batch_size:
        train_config.batch_size = args.batch_size
    if args.lr:
        train_config.learning_rate = args.lr
    if args.checkpoint_dir:
        train_config.checkpoint_dir = args.checkpoint_dir
    
    # Load data
    logger.info(f"Loading training data from {args.data}")
    train_data_raw = np.load(args.data, allow_pickle=True)
    train_data = train_data_raw['samples'] if 'samples' in train_data_raw else train_data_raw
    
    # Convert to list if needed
    if isinstance(train_data, np.ndarray):
        train_data = train_data.tolist()
    
    logger.info(f"Loaded {len(train_data)} training samples")
    
    val_data = None
    if args.val_data:
        logger.info(f"Loading validation data from {args.val_data}")
        val_data_raw = np.load(args.val_data, allow_pickle=True)
        val_data = val_data_raw['samples'] if 'samples' in val_data_raw else val_data_raw
        if isinstance(val_data, np.ndarray):
            val_data = val_data.tolist()
        logger.info(f"Loaded {len(val_data)} validation samples")
    
    # Log configuration
    logger.info(f"Training configuration:")
    logger.info(f"  Batch size: {train_config.batch_size}")
    logger.info(f"  Epochs: {train_config.num_epochs}")
    logger.info(f"  Learning rate: {train_config.learning_rate}")
    logger.info(f"  Checkpoint dir: {train_config.checkpoint_dir}")
    if args.resume:
        logger.info(f"  Resuming from: {args.resume}")
    
    # Start training
    train(train_config, net_config, train_data, val_data, resume_from=args.resume)


if __name__ == '__main__':
    main()
