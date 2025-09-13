"""
Neural network architecture for Katamill, inspired by KataGo's multi-head design.

This module implements a sophisticated ResNet-based architecture specifically 
optimized for Nine Men's Morris, featuring:
- Improved weight initialization following KataGo's practices
- Multi-head outputs with auxiliary supervision
- Advanced training stability features
- Optimized for both training efficiency and inference speed

Key improvements over standard AlphaZero:
- Auxiliary targets (ownership, score) for richer learning signals
- Better normalization and activation strategies
- Adaptive loss weighting for stable multi-head training
- Support for various activation functions (ReLU, Mish, GELU)
"""

from typing import Tuple, Optional
import math
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import os
import sys

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

try:
    from .config import NetConfig, default_net_config
except ImportError:
    from config import NetConfig, default_net_config


def compute_gain(activation: str) -> float:
    """
    Compute initialization gain for different activation functions.
    
    Based on KataGo's improved initialization scheme that accounts for
    activation function characteristics and residual connections.
    
    Args:
        activation: Activation function name ('relu', 'mish', 'gelu', 'swish', 'identity')
        
    Returns:
        Gain factor for weight initialization
    """
    # Gains computed empirically for better training stability
    activation_gains = {
        "relu": math.sqrt(2.0),
        "mish": math.sqrt(2.210277),  # Empirically determined
        "gelu": math.sqrt(2.351718),  # Empirically determined  
        "swish": math.sqrt(2.181818), # Empirically determined
        "identity": 1.0,
        "linear": 1.0,
    }
    return activation_gains.get(activation.lower(), math.sqrt(2.0))


def init_weights(tensor: torch.Tensor, activation: str = "relu", scale: float = 1.0):
    """
    Initialize weights with KataGo-style advanced scaling for activation functions.
    
    Uses truncated normal distribution with careful variance control to prevent
    gradient vanishing/exploding, especially important for deep residual networks.
    
    Args:
        tensor: Weight tensor to initialize
        activation: Activation function that follows this layer
        scale: Additional scaling factor (useful for residual blocks)
    """
    if tensor.numel() == 0:
        return  # Skip empty tensors
    
    gain = compute_gain(activation)
    fan_in, fan_out = nn.init._calculate_fan_in_and_fan_out(tensor)
    
    # Ensure we have valid fan values
    if fan_in == 0 or fan_out == 0:
        tensor.fill_(0.0)
        return
    
    # KataGo uses a hybrid approach considering both fan_in and fan_out
    # for better gradient flow in deep networks
    effective_fan = math.sqrt(2.0 / (fan_in + fan_out)) * math.sqrt(fan_in)
    target_std = scale * gain / max(effective_fan, 1e-8)  # Prevent division by zero
    
    # Compensate for truncation in truncated normal distribution
    truncation_compensation = 0.87962566103423978
    std = target_std / truncation_compensation
    
    # Clamp std to reasonable bounds to prevent numerical issues
    std = max(min(std, 10.0), 1e-10)
    
    if std < 1e-10:
        tensor.fill_(0.0)
    else:
        # Use 2-sigma truncation for better tail behavior
        try:
            nn.init.trunc_normal_(tensor, mean=0.0, std=std, a=-2.0*std, b=2.0*std)
        except Exception:
            # Fallback to normal initialization if truncated normal fails
            nn.init.normal_(tensor, mean=0.0, std=std)


class ResidualBlock(nn.Module):
    """
    Advanced residual block inspired by KataGo's architecture improvements.
    
    Features:
    - Improved weight initialization for deep networks
    - Support for multiple activation functions
    - Optional squeeze-and-excitation attention
    - Adaptive dropout for regularization
    - Better gradient flow through careful scaling
    """

    def __init__(self, num_filters: int, dropout: float, activation: str = "relu", 
                 use_se: bool = False, se_ratio: float = 0.25):
        super().__init__()
        self.activation = activation
        self.use_se = use_se
        
        # Main convolution path
        self.conv1 = nn.Conv2d(num_filters, num_filters, kernel_size=3, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(num_filters, eps=1e-4, momentum=0.001)
        self.conv2 = nn.Conv2d(num_filters, num_filters, kernel_size=3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(num_filters, eps=1e-4, momentum=0.001)
        
        # Squeeze-and-Excitation block (optional)
        if use_se:
            se_channels = max(1, int(num_filters * se_ratio))
            self.se_pool = nn.AdaptiveAvgPool2d(1)
            self.se_fc1 = nn.Linear(num_filters, se_channels, bias=False)
            self.se_fc2 = nn.Linear(se_channels, num_filters, bias=False)
        
        # Dropout with adaptive rate
        self.dropout = nn.Dropout2d(dropout) if dropout > 0 else nn.Identity()
        
        # Initialize weights properly
        self._initialize_weights()

    def _initialize_weights(self):
        """Initialize weights using KataGo-style initialization."""
        # First conv layer - moderate scaling for better gradient flow
        init_weights(self.conv1.weight, self.activation, scale=0.8)
        # Second conv layer - smaller scale as it feeds into residual connection
        init_weights(self.conv2.weight, "identity", scale=0.3)
        
        # Initialize batch norm with small initial variance
        nn.init.constant_(self.bn1.weight, 1.0)
        nn.init.constant_(self.bn1.bias, 0.0)
        nn.init.constant_(self.bn2.weight, 0.1)  # Small initial weight for stability
        nn.init.constant_(self.bn2.bias, 0.0)
        
        # Initialize SE block if present
        if self.use_se:
            init_weights(self.se_fc1.weight, "relu", scale=1.0)
            init_weights(self.se_fc2.weight, "identity", scale=1.0)

    def _get_activation(self, x: torch.Tensor) -> torch.Tensor:
        """Apply activation function with proper handling."""
        activation_map = {
            "relu": lambda t: F.relu(t, inplace=True),
            "mish": F.mish,
            "gelu": F.gelu,
            "swish": F.silu,  # SiLU is the same as Swish
            "identity": lambda t: t,
        }
        
        activation_fn = activation_map.get(self.activation.lower(), 
                                         lambda t: F.relu(t, inplace=True))
        return activation_fn(x)

    def _apply_se_block(self, x: torch.Tensor) -> torch.Tensor:
        """Apply Squeeze-and-Excitation attention mechanism."""
        batch_size, channels, height, width = x.size()
        
        # Squeeze: Global average pooling
        squeeze = self.se_pool(x).view(batch_size, channels)
        
        # Excitation: Two FC layers with ReLU and Sigmoid
        excitation = self.se_fc1(squeeze)
        excitation = F.relu(excitation, inplace=True)
        excitation = self.se_fc2(excitation)
        excitation = torch.sigmoid(excitation).view(batch_size, channels, 1, 1)
        
        # Scale the input
        return x * excitation

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = x
        
        # First convolution block
        out = self.conv1(x)
        out = self.bn1(out)
        out = self._get_activation(out)
        out = self.dropout(out)
        
        # Second convolution block
        out = self.conv2(out)
        out = self.bn2(out)
        
        # Apply SE block if enabled
        if self.use_se:
            out = self._apply_se_block(out)
        
        # Residual connection with careful scaling
        out = out + residual
        out = self._get_activation(out)
        
        return out


class KatamillNet(nn.Module):
    """
    Advanced multi-head CNN for Nine Men's Morris inspired by KataGo.
    
    Key improvements over standard AlphaZero architecture:
    - KataGo-style weight initialization for deep networks
    - Multi-head auxiliary supervision (policy, value, score, ownership)
    - Advanced normalization and regularization techniques
    - Support for modern activation functions
    - Squeeze-and-excitation attention (optional)
    - Adaptive head scaling for different output types

    Architecture:
    - Input: 32-channel 7x7 feature planes
    - Trunk: Configurable ResNet with 6-20 residual blocks
    - Heads: Policy (576), Value (1), Score (1), Ownership (24)
    """

    def __init__(self, cfg: Optional[NetConfig] = None):
        super().__init__()
        self.cfg = cfg or default_net_config()

        # Network dimensions
        C = self.cfg.input_channels
        Fm = self.cfg.num_filters
        B = self.cfg.num_residual_blocks
        activation = getattr(self.cfg, 'activation', 'relu')
        use_se = getattr(self.cfg, 'use_se', False)  # Squeeze-and-excitation
        
        # Input processing with advanced normalization
        self.input_conv = nn.Conv2d(C, Fm, kernel_size=3, padding=1, bias=False)
        self.input_bn = nn.BatchNorm2d(Fm, eps=1e-4, momentum=0.001)
        
        # Advanced residual tower with optional SE blocks
        self.resblocks = nn.ModuleList([
            ResidualBlock(Fm, self.cfg.dropout_rate, activation, 
                         use_se=use_se and i % 2 == 1)  # SE every other block
            for i in range(B)
        ])

        # Enhanced multi-scale policy head with better pattern recognition
        self.policy_conv1 = nn.Conv2d(Fm, Fm // 2, kernel_size=1, bias=False)
        self.policy_bn1 = nn.BatchNorm2d(Fm // 2, eps=1e-4, momentum=0.001)
        # Add 3x3 conv for local pattern recognition
        self.policy_conv2 = nn.Conv2d(Fm // 2, Fm // 4, kernel_size=3, padding=1, bias=False)
        self.policy_bn2 = nn.BatchNorm2d(Fm // 4, eps=1e-4, momentum=0.001)
        # Add 5x5 conv for larger pattern recognition (important for Nine Men's Morris mills)
        self.policy_conv3 = nn.Conv2d(Fm // 4, Fm // 8, kernel_size=5, padding=2, bias=False)
        self.policy_bn3 = nn.BatchNorm2d(Fm // 8, eps=1e-4, momentum=0.001)
        # Intermediate FC layer for better feature processing
        self.policy_fc1 = nn.Linear((Fm // 8) * 7 * 7, Fm // 2)
        self.policy_fc2 = nn.Linear(Fm // 2, self.cfg.policy_size)
        self.policy_dropout = nn.Dropout(0.1)  # Light regularization

        # Deep value head with residual connections
        self.value_conv = nn.Conv2d(Fm, Fm // 2, kernel_size=1, bias=False)
        self.value_bn = nn.BatchNorm2d(Fm // 2, eps=1e-4, momentum=0.001)
        self.value_fc1 = nn.Linear((Fm // 2) * 7 * 7, Fm)
        self.value_fc2 = nn.Linear(Fm, Fm // 2)
        self.value_fc3 = nn.Linear(Fm // 2, 1)
        self.value_dropout = nn.Dropout(0.1)  # Light regularization

        # Score head with global context
        self.score_conv = nn.Conv2d(Fm, Fm // 4, kernel_size=1, bias=False)
        self.score_bn = nn.BatchNorm2d(Fm // 4, eps=1e-4, momentum=0.001)
        self.score_global_pool = nn.AdaptiveAvgPool2d(1)
        self.score_fc1 = nn.Linear(Fm // 4, Fm // 8)
        self.score_fc2 = nn.Linear(Fm // 8, 1)

        # Ownership head with spatial preservation
        self.own_conv1 = nn.Conv2d(Fm, Fm // 2, kernel_size=1, bias=False)
        self.own_bn1 = nn.BatchNorm2d(Fm // 2, eps=1e-4, momentum=0.001)
        self.own_conv2 = nn.Conv2d(Fm // 2, Fm // 4, kernel_size=3, padding=1, bias=False)
        self.own_bn2 = nn.BatchNorm2d(Fm // 4, eps=1e-4, momentum=0.001)
        self.own_fc = nn.Linear((Fm // 4) * 7 * 7, self.cfg.ownership_size)
        
        # Store activation type and configuration
        self.activation = activation
        
        # Initialize all weights with KataGo-style initialization
        self._initialize_weights()

    def _initialize_weights(self):
        """Initialize all weights using advanced KataGo-style initialization."""
        # Input processing
        init_weights(self.input_conv.weight, self.activation, scale=1.0)
        nn.init.constant_(self.input_bn.weight, 1.0)
        nn.init.constant_(self.input_bn.bias, 0.0)
        
        # Enhanced policy head - multi-scale initialization
        init_weights(self.policy_conv1.weight, self.activation, scale=1.0)
        nn.init.constant_(self.policy_bn1.weight, 1.0)
        nn.init.constant_(self.policy_bn1.bias, 0.0)
        init_weights(self.policy_conv2.weight, self.activation, scale=0.8)
        nn.init.constant_(self.policy_bn2.weight, 1.0)
        nn.init.constant_(self.policy_bn2.bias, 0.0)
        init_weights(self.policy_conv3.weight, self.activation, scale=0.7)
        nn.init.constant_(self.policy_bn3.weight, 1.0)
        nn.init.constant_(self.policy_bn3.bias, 0.0)
        init_weights(self.policy_fc1.weight, self.activation, scale=0.8)
        nn.init.constant_(self.policy_fc1.bias, 0.0)
        init_weights(self.policy_fc2.weight, "identity", scale=0.01)  # Very small for neutral policy
        nn.init.constant_(self.policy_fc2.bias, 0.0)
        
        # Value head - deep network initialization
        init_weights(self.value_conv.weight, self.activation, scale=1.0)
        nn.init.constant_(self.value_bn.weight, 1.0)
        nn.init.constant_(self.value_bn.bias, 0.0)
        init_weights(self.value_fc1.weight, self.activation, scale=0.9)
        nn.init.constant_(self.value_fc1.bias, 0.0)
        init_weights(self.value_fc2.weight, self.activation, scale=0.8)
        nn.init.constant_(self.value_fc2.bias, 0.0)
        init_weights(self.value_fc3.weight, "identity", scale=0.01)  # Much smaller for neutral start
        nn.init.constant_(self.value_fc3.bias, 0.0)
        
        # Score head - global context initialization
        init_weights(self.score_conv.weight, self.activation, scale=1.0)
        nn.init.constant_(self.score_bn.weight, 1.0)
        nn.init.constant_(self.score_bn.bias, 0.0)
        init_weights(self.score_fc1.weight, self.activation, scale=0.7)
        nn.init.constant_(self.score_fc1.bias, 0.0)
        init_weights(self.score_fc2.weight, "identity", scale=0.01)  # Small for neutral score
        nn.init.constant_(self.score_fc2.bias, 0.0)
        
        # Ownership head - spatial preservation initialization
        init_weights(self.own_conv1.weight, self.activation, scale=1.0)
        nn.init.constant_(self.own_bn1.weight, 1.0)
        nn.init.constant_(self.own_bn1.bias, 0.0)
        init_weights(self.own_conv2.weight, self.activation, scale=0.8)
        nn.init.constant_(self.own_bn2.weight, 1.0)
        nn.init.constant_(self.own_bn2.bias, 0.0)
        init_weights(self.own_fc.weight, "identity", scale=0.1)
        nn.init.constant_(self.own_fc.bias, 0.0)

    def _get_activation(self, x: torch.Tensor) -> torch.Tensor:
        """Apply activation function with optimized implementation."""
        activation_map = {
            "relu": lambda t: F.relu(t, inplace=True),
            "mish": F.mish,
            "gelu": F.gelu,
            "swish": F.silu,  # SiLU is the same as Swish
            "identity": lambda t: t,
        }
        
        activation_fn = activation_map.get(self.activation.lower(), 
                                         lambda t: F.relu(t, inplace=True))
        return activation_fn(x)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        Forward pass with KataGo-style multi-head architecture.
        
        Args:
            x: Input feature tensor (batch_size, 32, 7, 7)
            
        Returns:
            policy_logits: Raw policy logits (batch_size, 576)
            value: Game outcome prediction (batch_size, 1) 
            score: Heuristic score prediction (batch_size, 1)
            ownership: Position ownership prediction (batch_size, 24)
        """
        # Trunk processing with residual blocks
        trunk = self.input_conv(x)
        trunk = self.input_bn(trunk)
        trunk = self._get_activation(trunk)
        
        # Process through residual tower
        for block in self.resblocks:
            trunk = block(trunk)

        # Enhanced multi-scale policy head for better action understanding
        p = self.policy_conv1(trunk)
        p = self.policy_bn1(p)
        p = self._get_activation(p)
        p = self.policy_conv2(p)
        p = self.policy_bn2(p)
        p = self._get_activation(p)
        p = self.policy_conv3(p)
        p = self.policy_bn3(p)
        p = self._get_activation(p)
        p = p.reshape(p.size(0), -1)
        # Two-stage fully connected processing for better pattern recognition
        p = self._get_activation(self.policy_fc1(p))
        p = self.policy_dropout(p)  # Apply dropout for regularization
        policy_logits = self.policy_fc2(p)

        # Deep value head with regularization
        v = self.value_conv(trunk)
        v = self.value_bn(v)
        v = self._get_activation(v)
        v = v.reshape(v.size(0), -1)
        v = self._get_activation(self.value_fc1(v))
        v = self.value_dropout(v)  # Apply dropout for regularization
        v = self._get_activation(self.value_fc2(v))
        value = torch.tanh(self.value_fc3(v))  # Bounded to [-1, 1]

        # Score head with global context understanding
        s = self.score_conv(trunk)
        s = self.score_bn(s)
        s = self._get_activation(s)
        s = self.score_global_pool(s)  # Global average pooling
        s = s.reshape(s.size(0), -1)
        s = self._get_activation(self.score_fc1(s))
        score = self.score_fc2(s)  # Unbounded score

        # Ownership head with spatial information preservation
        o = self.own_conv1(trunk)
        o = self.own_bn1(o)
        o = self._get_activation(o)
        o = self.own_conv2(o)
        o = self.own_bn2(o)
        o = self._get_activation(o)
        o = o.reshape(o.size(0), -1)
        ownership = torch.tanh(self.own_fc(o))  # Bounded to [-1, 1]

        return policy_logits, value, score, ownership


class KatamillWrapper:
    """
    Advanced adapter for KatamillNet with KataGo-style optimizations.

    This wrapper provides a clean interface for MCTS while supporting
    advanced features like batch prediction, caching, and auxiliary outputs.
    
    Features:
    - Automatic device management
    - Efficient batch processing
    - Feature caching for repeated positions
    - Access to auxiliary predictions (score, ownership)
    - Memory-efficient inference
    """

    def __init__(self, net: KatamillNet, device: str = "auto", enable_cache: bool = True):
        self.net = net
        
        # Device setup with automatic selection
        if device == "auto":
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        else:
            self.device = torch.device(device)
        
        self.net.to(self.device)
        self.net.eval()
        
        # Feature caching for repeated positions (KataGo-style optimization)
        self.enable_cache = enable_cache
        self.feature_cache = {} if enable_cache else None
        self.cache_hits = 0
        self.cache_misses = 0
        
        # Batch processing support
        self.batch_size = 1
        self.pending_positions = []

    def clear_cache(self):
        """Clear the feature cache to free memory."""
        if self.feature_cache is not None:
            self.feature_cache.clear()
            self.cache_hits = 0
            self.cache_misses = 0

    def get_cache_stats(self) -> dict:
        """Get cache performance statistics."""
        total = self.cache_hits + self.cache_misses
        hit_rate = self.cache_hits / total if total > 0 else 0.0
        return {
            "cache_hits": self.cache_hits,
            "cache_misses": self.cache_misses,
            "hit_rate": hit_rate
        }

    @torch.no_grad()
    def _encode(self, board, current_player: int) -> torch.Tensor:
        """
        Encode board position to feature tensor with caching support.
        
        Args:
            board: Game board state
            current_player: Current player (1 or -1)
            
        Returns:
            Feature tensor ready for neural network input
        """
        # Generate cache key if caching is enabled
        cache_key = None
        if self.enable_cache:
            try:
                # Create a hashable representation of the position
                board_str = str(board.pieces.tolist()) + str(current_player)
                cache_key = hash(board_str)
                
                if cache_key in self.feature_cache:
                    self.cache_hits += 1
                    return self.feature_cache[cache_key]
            except:
                # Fallback if hashing fails
                pass
        
        # Extract features using the feature extraction module
        try:
            from .features import extract_features
        except ImportError:
            from features import extract_features
            
        feats = extract_features(board, current_player)
        tensor = torch.from_numpy(feats).unsqueeze(0).to(self.device)
        
        # Cache the result if caching is enabled
        if self.enable_cache and cache_key is not None:
            # Check cache size before adding to prevent unbounded growth
            max_cache_size = 10000
            if len(self.feature_cache) >= max_cache_size:
                # Remove oldest 20% of entries (more efficient than removing one by one)
                keys_to_remove = list(self.feature_cache.keys())[:max_cache_size // 5]
                for key in keys_to_remove:
                    del self.feature_cache[key]
            
            # Add to cache
            self.feature_cache[cache_key] = tensor
            self.cache_misses += 1
        
        return tensor

    @torch.no_grad()
    def predict(self, board, current_player: int) -> Tuple[np.ndarray, float]:
        """
        Predict policy and value for a single position.
        
        Compatible with MCTS interface while providing optimized inference.
        
        Args:
            board: Game board state
            current_player: Current player (1 or -1)
            
        Returns:
            policy: Action probability distribution (576,)
            value: Position value from current player's perspective
        """
        x = self._encode(board, current_player)
        policy_logits, value, _, _ = self.net(x)
        
        # Convert to probabilities and extract scalar value
        policy = torch.softmax(policy_logits, dim=1).squeeze(0).cpu().numpy()
        value_scalar = float(value.squeeze(0).cpu().item())
        
        return policy, value_scalar

    @torch.no_grad()
    def predict_full(self, board, current_player: int) -> dict:
        """
        Predict all outputs (policy, value, score, ownership) for analysis.
        
        Args:
            board: Game board state
            current_player: Current player (1 or -1)
            
        Returns:
            Dictionary containing all model predictions
        """
        x = self._encode(board, current_player)
        policy_logits, value, score, ownership = self.net(x)
        
        return {
            "policy": torch.softmax(policy_logits, dim=1).squeeze(0).cpu().numpy(),
            "value": float(value.squeeze(0).cpu().item()),
            "score": float(score.squeeze(0).cpu().item()),
            "ownership": ownership.squeeze(0).cpu().numpy()
        }

    @torch.no_grad()
    def predict_batch(self, positions: list) -> list:
        """
        Predict for multiple positions efficiently (KataGo-style batching).
        
        Args:
            positions: List of (board, current_player) tuples
            
        Returns:
            List of (policy, value) tuples
        """
        if not positions:
            return []
        
        # Encode all positions
        batch_tensors = []
        for board, current_player in positions:
            tensor = self._encode(board, current_player)
            batch_tensors.append(tensor)
        
        # Batch process
        batch_input = torch.cat(batch_tensors, dim=0)
        policy_logits, values, _, _ = self.net(batch_input)
        
        # Convert results
        policies = torch.softmax(policy_logits, dim=1).cpu().numpy()
        values = values.squeeze(-1).cpu().numpy()
        
        return [(policies[i], float(values[i])) for i in range(len(positions))]


