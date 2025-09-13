from dataclasses import dataclass, field
from typing import Optional


@dataclass
class NetConfig:
    """
    Neural network hyperparameters and architecture configuration.
    
    Enhanced with LC0-inspired improvements for stronger Nine Men's Morris play.
    """
    # Core architecture - optimized for stronger play
    input_channels: int = 32
    num_filters: int = 192  # Increased from 128 for better pattern recognition
    num_residual_blocks: int = 10  # Increased from 6 for deeper understanding
    policy_size: int = 576  # 24*24 action space for Nine Men's Morris
    ownership_size: int = 24
    
    # Regularization and training stability
    dropout_rate: float = 0.1  # Reduced dropout for better learning
    activation: str = "mish"  # Better activation function for deeper networks
    use_se: bool = True  # Enable squeeze-and-excitation for attention
    se_ratio: float = 0.25  # SE reduction ratio
    
    # Advanced features (LC0-inspired)
    use_mixed_precision: bool = True  # Enable for faster training
    gradient_accumulation_steps: int = 2  # Larger effective batch size
    adaptive_weighting: bool = True
    label_smoothing: float = 0.02  # Slightly more smoothing
    aux_warmup_steps: int = 2000  # Longer warmup for auxiliary targets
    
    def __post_init__(self):
        """Validate configuration parameters to prevent common errors."""
        # Validate core architecture parameters
        assert self.input_channels > 0, "input_channels must be positive"
        assert self.num_filters > 0, "num_filters must be positive"
        assert self.num_residual_blocks >= 0, "num_residual_blocks must be non-negative"
        assert self.policy_size > 0, "policy_size must be positive"
        assert self.ownership_size > 0, "ownership_size must be positive"
        
        # Validate regularization parameters
        assert 0.0 <= self.dropout_rate <= 1.0, "dropout_rate must be in [0, 1]"
        assert 0.0 < self.se_ratio <= 1.0, "se_ratio must be in (0, 1]"
        
        # Validate training parameters
        assert self.gradient_accumulation_steps > 0, "gradient_accumulation_steps must be positive"
        assert 0.0 <= self.label_smoothing <= 1.0, "label_smoothing must be in [0, 1]"
        assert self.aux_warmup_steps >= 0, "aux_warmup_steps must be non-negative"
        
        # Validate activation function
        valid_activations = {"relu", "mish", "gelu", "swish", "identity"}
        assert self.activation.lower() in valid_activations, f"activation must be one of {valid_activations}"
    
    # Model size presets
    @classmethod
    def tiny(cls) -> 'NetConfig':
        """Tiny model for fast experimentation."""
        return cls(
            num_filters=64,
            num_residual_blocks=4,
            dropout_rate=0.1
        )
    
    @classmethod
    def small(cls) -> 'NetConfig':
        """Small model for resource-constrained training."""
        return cls(
            num_filters=96,
            num_residual_blocks=5,
            dropout_rate=0.12
        )
    
    @classmethod
    def large(cls) -> 'NetConfig':
        """Large model for maximum strength."""
        return cls(
            num_filters=256,
            num_residual_blocks=10,
            dropout_rate=0.2,
            use_se=True
        )
    
    @classmethod
    def huge(cls) -> 'NetConfig':
        """Huge model for research purposes."""
        return cls(
            num_filters=512,
            num_residual_blocks=20,
            dropout_rate=0.25,
            use_se=True,
            use_mixed_precision=True,
            gradient_accumulation_steps=2
        )


@dataclass
class MCTSConfig:
    """
    Advanced MCTS hyperparameters with LC0-inspired improvements for stronger play.
    
    Optimized for Nine Men's Morris with enhanced search strength.
    """
    # Core MCTS parameters - optimized for Nine Men's Morris tactical play
    cpuct: float = 1.8  # Balanced exploration (2.5 too high for 7x7 board)
    num_simulations: int = 800  # More simulations for stronger play
    dirichlet_alpha: float = 0.2  # Moderate noise suitable for Nine Men's Morris
    dirichlet_epsilon: float = 0.15  # Balanced noise for exploration
    temperature: float = 1.0
    
    # LC0-style search improvements
    use_virtual_loss: bool = True
    virtual_loss_count: int = 3
    progressive_widening: bool = True
    min_visits_for_expansion: int = 1
    use_transpositions: bool = True  # Enable for better efficiency
    max_transposition_size: int = 100000  # Large transposition table
    
    # First Play Urgency (LC0 innovation)
    fpu_reduction: float = 0.25  # Reduction for unvisited nodes
    fpu_at_root: bool = True  # Apply FPU at root
    
    # Nine Men's Morris specific parameters - tuned for game characteristics
    consecutive_move_bonus: float = 0.03  # Conservative bonus (removal moves are forced)
    removal_phase_exploration: float = 0.8  # Less exploration (tactical precision needed)
    placing_phase_exploration: float = 1.3  # More exploration (strategic foundation)
    flying_phase_simulations_multiplier: float = 2.0  # Much more search (complex endgame)
    
    # Performance tuning
    batch_size: int = 1  # For batch MCTS (future)
    cache_size: int = 50000  # Larger feature cache for better performance
    
    def __post_init__(self):
        """Validate MCTS configuration parameters to prevent common errors."""
        # Validate core MCTS parameters
        assert self.cpuct > 0.0, "cpuct must be positive"
        assert self.num_simulations > 0, "num_simulations must be positive"
        assert self.dirichlet_alpha > 0.0, "dirichlet_alpha must be positive"
        assert 0.0 <= self.dirichlet_epsilon <= 1.0, "dirichlet_epsilon must be in [0, 1]"
        assert self.temperature >= 0.0, "temperature must be non-negative"
        
        # Validate advanced search parameters
        assert self.virtual_loss_count > 0, "virtual_loss_count must be positive"
        assert self.min_visits_for_expansion >= 0, "min_visits_for_expansion must be non-negative"
        
        # Validate Nine Men's Morris specific parameters
        assert self.consecutive_move_bonus >= 0.0, "consecutive_move_bonus must be non-negative"
        assert self.removal_phase_exploration > 0.0, "removal_phase_exploration must be positive"
        assert self.placing_phase_exploration > 0.0, "placing_phase_exploration must be positive"
        assert self.flying_phase_simulations_multiplier > 0.0, "flying_phase_simulations_multiplier must be positive"
        
        # Validate performance parameters
        assert self.batch_size > 0, "batch_size must be positive"
        assert self.cache_size >= 0, "cache_size must be non-negative"
    
    @classmethod
    def fast(cls) -> 'MCTSConfig':
        """Fast MCTS for quick games."""
        return cls(
            num_simulations=100,
            use_virtual_loss=False,
            progressive_widening=False
        )
    
    @classmethod
    def strong(cls) -> 'MCTSConfig':
        """Strong MCTS for tournament play with LC0-inspired optimizations."""
        return cls(
            cpuct=2.0,  # Moderate exploration suitable for Nine Men's Morris
            num_simulations=1200,  # More simulations for tournament strength
            dirichlet_alpha=0.15,  # Balanced noise for strong play
            dirichlet_epsilon=0.08,  # Low but not minimal noise
            use_virtual_loss=True,
            progressive_widening=True,
            use_transpositions=True,
            max_transposition_size=200000,  # Large transposition table
            fpu_reduction=0.2,  # Stronger FPU reduction
            consecutive_move_bonus=0.03,  # Conservative bonus
            removal_phase_exploration=1.4,
            placing_phase_exploration=1.3,
            flying_phase_simulations_multiplier=1.8
        )
    
    @classmethod
    def analysis(cls) -> 'MCTSConfig':
        """MCTS for deep position analysis."""
        return cls(
            num_simulations=1600,
            dirichlet_epsilon=0.0,  # No noise for analysis
            use_virtual_loss=True,
            progressive_widening=True,
            use_transpositions=True
        )


@dataclass
class PitConfig:
    """Configuration for pit matches and model/device selection."""
    model_path: Optional[str] = None
    device: str = "auto"  # "cpu", "cuda", or "auto"
    mcts: MCTSConfig = field(default_factory=MCTSConfig)


def default_net_config() -> NetConfig:
    return NetConfig()


def default_mcts_config() -> MCTSConfig:
    return MCTSConfig()


def default_pit_config() -> PitConfig:
    return PitConfig()


