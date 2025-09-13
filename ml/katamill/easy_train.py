#!/usr/bin/env python3
"""
Easy Katamill Training Script - From Zero to Hero

This script provides a foolproof way to train a Katamill model from scratch.
It handles everything automatically:
1. Generate initial self-play data
2. Train the model iteratively
3. Evaluate model performance
4. Test the trained model

Usage:
    python -m ml.katamill.easy_train                    # Use default settings
    python -m ml.katamill.easy_train --config my.json  # Use custom config
    python -m ml.katamill.easy_train --quick            # Quick training for testing
"""

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Dict, Any, Optional
import torch
import numpy as np

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import modules with fallback for different execution contexts
try:
    from .config import NetConfig, default_net_config
    from .neural_network import KatamillNet, KatamillWrapper
    from .selfplay import run_selfplay, SelfPlayConfig
    from .train import train as train_model, TrainConfig
    from .data_loader import save_selfplay_data, load_selfplay_data, merge_data_files, split_data, filter_winner_samples
    from .pit import load_model as load_pit_model
    from .evaluate import self_play_analysis
except ImportError:
    # Fallback to absolute imports for standalone execution
    from config import NetConfig, default_net_config
    from neural_network import KatamillNet, KatamillWrapper
    from selfplay import run_selfplay, SelfPlayConfig
    from train import train as train_model, TrainConfig
    from data_loader import save_selfplay_data, load_selfplay_data, merge_data_files, split_data, filter_winner_samples
    from pit import load_model as load_pit_model
    from evaluate import self_play_analysis

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class EasyTrainConfig:
    """Complete configuration for easy training pipeline."""
    
    def __init__(self):
        # Directories
        self.data_dir = "data/katamill"
        self.checkpoint_dir = "checkpoints/katamill"
        self.output_dir = "output/katamill"
        
        # Training iterations - balanced for good convergence with early stopping
        self.num_iterations = 8  # Reasonable iterations for convergence
        self.games_per_iteration = [2000, 4000, 6000, 8000, 10000, 12000, 15000, 20000]  # Progressive increase
        self.epochs_per_iteration = 80  # Maximum epochs (early stopping will reduce if needed)
        
        # Self-play settings - optimized for decisive games
        self.initial_mcts_sims = 400    # Balanced quality and speed
        self.final_mcts_sims = 800      # Higher quality for later iterations
        self.temperature = 0.8          # Lower temperature for more decisive outcomes
        self.temp_decay_moves = 30      # Reasonable exploration phase
        self.max_moves = 250            # Reasonable buffer above theoretical max (~204 steps)
        self.workers = 8                # Parallel workers
        
        # Training settings - optimized for much stronger play
        self.batch_size = 128           # Large batch size for stability
        self.learning_rate = 5e-4       # Conservative learning rate for deep training
        self.use_validation = True
        self.validation_ratio = 0.2     # More validation data for better model selection
        
        # Model settings
        self.net_config = default_net_config()
        
        # Evaluation settings - more thorough evaluation
        self.eval_games = 100  # More games for accurate evaluation
        self.final_eval_games = 200  # Comprehensive final evaluation
        
        # Quick mode (for testing)
        self.quick_mode = False
        
        # UCT-CCNN paper inspired optimizations
        self.cpuct = 0.6  # Conservative exploration constant for Nine Men's Morris
        self.filter_winner_only = True  # Keep winner-side samples for better training signal
        
    def to_dict(self) -> Dict[str, Any]:
        """Convert config to dictionary."""
        return {
            'data_dir': self.data_dir,
            'checkpoint_dir': self.checkpoint_dir,
            'output_dir': self.output_dir,
            'num_iterations': self.num_iterations,
            'games_per_iteration': self.games_per_iteration,
            'epochs_per_iteration': self.epochs_per_iteration,
            'initial_mcts_sims': self.initial_mcts_sims,
            'final_mcts_sims': self.final_mcts_sims,
            'temperature': self.temperature,
            'temp_decay_moves': self.temp_decay_moves,
            'max_moves': self.max_moves,
            'workers': self.workers,
            'batch_size': self.batch_size,
            'learning_rate': self.learning_rate,
            'use_validation': self.use_validation,
            'validation_ratio': self.validation_ratio,
            'cpuct': self.cpuct,
            'filter_winner_only': self.filter_winner_only,
            'net_config': {
                'input_channels': self.net_config.input_channels,
                'num_filters': self.net_config.num_filters,
                'num_residual_blocks': self.net_config.num_residual_blocks,
                'policy_size': self.net_config.policy_size,
                'ownership_size': self.net_config.ownership_size,
                'dropout_rate': self.net_config.dropout_rate,
            },
            'eval_games': self.eval_games,
            'final_eval_games': self.final_eval_games,
            'quick_mode': self.quick_mode,
        }
    
    def from_dict(self, config_dict: Dict[str, Any]):
        """Load config from dictionary."""
        for key, value in config_dict.items():
            if key == 'net_config' and isinstance(value, dict):
                # Handle nested net config
                for net_key, net_value in value.items():
                    if hasattr(self.net_config, net_key):
                        setattr(self.net_config, net_key, net_value)
            elif hasattr(self, key):
                setattr(self, key, value)
    
    def setup_quick_mode(self):
        """Configure for very fast testing with minimal viable strength."""
        logger.info("Setting up quick mode for fast testing...")
        self.quick_mode = True
        self.num_iterations = 3  # Fewer iterations for speed
        self.games_per_iteration = [200, 400, 600]  # Much smaller games for speed
        self.epochs_per_iteration = 15  # Fewer epochs (early stopping will optimize)
        self.initial_mcts_sims = 100    # Much faster MCTS
        self.final_mcts_sims = 200      # Still reasonable but faster
        self.temperature = 0.8          # Lower temperature for decisive games
        self.max_moves = 200            # Shorter games for speed
        self.workers = 2                # Fewer workers to reduce overhead
        self.batch_size = 32            # Smaller batch for faster training
        self.eval_games = 10            # Minimal evaluation
        self.final_eval_games = 20      # Quick final evaluation
        # UCT-CCNN inspired optimizations for Nine Men's Morris
        self.cpuct = 0.6                # More conservative exploration (paper found 0.587 optimal)
        self.filter_winner_only = True  # Winner-side filtering for better training signal



class EasyTrainer:
    """Easy-to-use trainer that handles the complete pipeline."""
    
    def __init__(self, config: EasyTrainConfig):
        self.config = config
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
        # Create directories
        os.makedirs(self.config.data_dir, exist_ok=True)
        os.makedirs(self.config.checkpoint_dir, exist_ok=True)
        os.makedirs(self.config.output_dir, exist_ok=True)
        
        # Track training progress
        self.iteration_results = []
        self.best_model_path = None
        self.training_start_time = time.time()
    
    def run_complete_training(self):
        """Run the complete training pipeline optimized for stronger play."""
        logger.info("=" * 60)
        logger.info("KATAMILL ENHANCED TRAINING - LC0-INSPIRED PIPELINE")
        logger.info("=" * 60)
        logger.info(f"Device: {self.device}")
        logger.info(f"Iterations: {self.config.num_iterations}")
        logger.info(f"Quick mode: {self.config.quick_mode}")
        logger.info(f"Enhanced features: Stronger MCTS, Better NN, Improved Training")
        logger.info("")
        
        try:
            # Step 1: Generate initial data with random play
            self._bootstrap_initial_data()
            
            # Step 2: Iterative training
            for iteration in range(self.config.num_iterations):
                self._run_iteration(iteration)
            
            # Step 3: Final evaluation and testing
            self._final_evaluation()
            
            # Step 4: Generate summary report
            self._generate_report()
            
            logger.info("=" * 60)
            logger.info("TRAINING COMPLETED SUCCESSFULLY!")
            logger.info("=" * 60)
            
        except KeyboardInterrupt:
            logger.info("Training interrupted by user")
            self._save_partial_results()
        except Exception as e:
            logger.error(f"Training failed: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    def _bootstrap_initial_data(self):
        """Generate initial training data using random play."""
        logger.info("Step 1: Generating initial data with random play...")
        
        bootstrap_path = os.path.join(self.config.data_dir, "bootstrap.npz")
        if os.path.exists(bootstrap_path):
            logger.info(f"Bootstrap data already exists: {bootstrap_path}")
            return
        
        # Create random network for initial data generation
        net = KatamillNet(self.config.net_config)
        wrapper = KatamillWrapper(net, device=self.device)
        
        # Generate initial games with settings optimized for decisive outcomes
        selfplay_config = SelfPlayConfig(
            num_games=self.config.games_per_iteration[0],
            max_moves=self.config.max_moves,  # Use configured max_moves
            mcts_sims=self.config.initial_mcts_sims,
            temperature=self.config.temperature,  # Use configured temperature
            temp_decay_moves=self.config.temp_decay_moves,
            cpuct=self.config.cpuct,  # Use UCT-CCNN inspired conservative exploration
            num_workers=self.config.workers
        )
        
        logger.info(f"Generating {selfplay_config.num_games} bootstrap games...")
        data = run_selfplay(wrapper, selfplay_config)
        
        # Apply UCT-CCNN inspired winner-side filtering for better training signal
        if self.config.filter_winner_only:
            data = filter_winner_samples(data, keep_draws=True)
        
        save_selfplay_data(data, bootstrap_path)
        
        logger.info(f"Bootstrap data saved: {len(data)} samples")
    
    def _run_iteration(self, iteration: int):
        """Run a single training iteration."""
        logger.info(f"\n{'='*20} ITERATION {iteration + 1}/{self.config.num_iterations} {'='*20}")
        
        iteration_start = time.time()
        
        # Determine MCTS sims for this iteration (progressive increase)
        progress = iteration / max(1, self.config.num_iterations - 1)
        current_mcts_sims = int(
            self.config.initial_mcts_sims + 
            progress * (self.config.final_mcts_sims - self.config.initial_mcts_sims)
        )
        
        # Step 1: Generate self-play data (skip for iteration 0, use bootstrap)
        if iteration == 0:
            data_path = os.path.join(self.config.data_dir, "bootstrap.npz")
        else:
            data_path = self._generate_selfplay_data(iteration, current_mcts_sims)
        
        # Step 2: Train the model
        model_path = self._train_model(iteration, data_path)
        
        # Step 3: Evaluate the model
        eval_results = self._evaluate_model(iteration, model_path)
        
        # Record results with enhanced loss tracking
        iteration_time = time.time() - iteration_start
        
        # Extract loss information from the training checkpoint
        training_loss_info = {}
        try:
            checkpoint = torch.load(model_path, map_location='cpu')
            if 'losses' in checkpoint:
                training_loss_info = checkpoint['losses']
        except Exception:
            pass
        
        result = {
            'iteration': iteration + 1,
            'data_path': data_path,
            'model_path': model_path,
            'mcts_sims': current_mcts_sims,
            'eval_results': eval_results,
            'training_losses': training_loss_info,  # Add detailed loss breakdown
            'time_minutes': iteration_time / 60,
        }
        self.iteration_results.append(result)
        
        logger.info(f"Iteration {iteration + 1} completed in {iteration_time/60:.1f} minutes")
        logger.info(f"Model saved: {model_path}")
        
        # Display detailed loss information
        if training_loss_info:
            logger.info(f"Training Loss Breakdown:")
            logger.info(f"  Total: {training_loss_info.get('total', 'N/A'):.4f}")
            logger.info(f"  Policy: {training_loss_info.get('policy', 'N/A'):.4f}")
            logger.info(f"  Value: {training_loss_info.get('value', 'N/A'):.4f}")
            logger.info(f"  Score: {training_loss_info.get('score', 'N/A'):.4f}")
            logger.info(f"  Ownership: {training_loss_info.get('ownership', 'N/A'):.4f}")
        
        # Update best model
        if eval_results and (self.best_model_path is None or 
                           eval_results.get('win_rate', 0) > self._get_best_win_rate()):
            self.best_model_path = model_path
            logger.info(f"New best model: {eval_results.get('win_rate', 0):.1f}% win rate")
    
    def _generate_selfplay_data(self, iteration: int, mcts_sims: int) -> str:
        """Generate self-play data for current iteration."""
        logger.info(f"Generating self-play data (iteration {iteration + 1})...")
        
        # Load previous best model with adaptive loading
        if iteration > 0:
            prev_model_path = self.iteration_results[iteration - 1]['model_path']
            wrapper = load_pit_model(prev_model_path, str(self.device))
        else:
            # Use random model for first iteration
            net = KatamillNet(self.config.net_config)
            wrapper = KatamillWrapper(net, device=self.device)
        
        # Generate games with enhanced configuration for decisive outcomes
        num_games = self.config.games_per_iteration[min(iteration, len(self.config.games_per_iteration) - 1)]
        selfplay_config = SelfPlayConfig(
            num_games=num_games,
            max_moves=self.config.max_moves,  # Use configured max_moves
            mcts_sims=mcts_sims,
            temperature=self.config.temperature,
            temp_decay_moves=self.config.temp_decay_moves,
            cpuct=self.config.cpuct,  # Use UCT-CCNN inspired conservative exploration
            num_workers=self.config.workers
        )
        
        logger.info(f"Generating {num_games} games with {mcts_sims} MCTS sims...")
        data = run_selfplay(wrapper, selfplay_config)
        
        # Apply UCT-CCNN inspired winner-side filtering for better training signal
        if self.config.filter_winner_only:
            data = filter_winner_samples(data, keep_draws=True)
        
        # Save data
        data_path = os.path.join(self.config.data_dir, f"iteration_{iteration + 1}.npz")
        save_selfplay_data(data, data_path)
        
        logger.info(f"Generated {len(data)} training samples")
        return data_path
    
    def _train_model(self, iteration: int, data_path: str) -> str:
        """Train model for current iteration."""
        logger.info(f"Training model (iteration {iteration + 1})...")
        
        # Load training data
        train_data = load_selfplay_data(data_path)
        
        # Split data if validation is enabled
        val_data = None
        if self.config.use_validation:
            train_data, val_data, _ = split_data(
                train_data, 
                train_ratio=1 - self.config.validation_ratio,
                val_ratio=self.config.validation_ratio,
                test_ratio=0
            )
        
        # Create training config with LC0-inspired optimizations
        train_config = TrainConfig(
            batch_size=self.config.batch_size,
            num_epochs=self.config.epochs_per_iteration,
            learning_rate=self.config.learning_rate,
            checkpoint_dir=os.path.join(self.config.checkpoint_dir, f"iter_{iteration + 1}"),
            # Enable symmetries for better data efficiency
            use_symmetries=True,
            # LC0-style training improvements
            use_mixed_precision=True,
            gradient_accumulation_steps=2,
            adaptive_weighting=True,
            label_smoothing=0.02,
            aux_warmup_steps=2000,
            grad_clip_norm=0.5,
            # Adaptive warmup based on epoch count
            warmup_epochs=min(2, max(0, self.config.epochs_per_iteration - 1)),
            # Early stopping for efficient training
            early_stopping_patience=min(8, self.config.epochs_per_iteration),  # Adaptive patience
            early_stopping_min_delta=1e-4,
            # Enhanced loss weights for much stronger policy learning
            policy_weight=8.0,  # Much higher policy weight for better move selection
            value_weight=4.0,   # Higher value weight for position evaluation
            score_weight=1.5,   # Balanced score weight
            ownership_weight=1.0,  # Moderate ownership weight
            mill_potential_weight=0.8  # Higher mill potential for tactical awareness
        )
        
        # Determine weight initialization and resume mode
        resume_from = None
        init_weights_from = None
        if iteration > 0:
            # Use previous iteration's model weights to initialize, do not resume optimizer state
            init_weights_from = self.iteration_results[iteration - 1]['model_path']

        # Train the model (weights-only init across iterations, no epoch skip)
        train_model(
            train_config,
            self.config.net_config,
            train_data,
            val_data,
            resume_from,
            init_weights_from=init_weights_from,
        )
        
        # Return path to final model
        final_model_path = os.path.join(train_config.checkpoint_dir, "katamill_final.pth")
        return final_model_path
    
    def _evaluate_model(self, iteration: int, model_path: str) -> Dict[str, Any]:
        """Evaluate model performance."""
        logger.info(f"Evaluating model (iteration {iteration + 1})...")
        
        try:
            # Run self-play evaluation with adaptive model loading
            wrapper = load_pit_model(model_path, str(self.device))
            
            # Simple evaluation: count wins in self-play
            # Import with robust fallbacks to support both package and script modes
            try:
                from ml.game.Game import Game
            except Exception:
                try:
                    from game.Game import Game
                except Exception:
                    game_path = os.path.join(ml_dir, 'game')
                    sys.path.insert(0, game_path)
                    from Game import Game

            try:
                from .mcts import MCTS
            except ImportError:
                from mcts import MCTS
            
            game = Game()
            # Use stronger MCTS configuration for evaluation
            mcts = MCTS(game, wrapper, {
                'cpuct': 1.8,  # Balanced exploration for Nine Men's Morris 7x7 board
                'num_simulations': 400,  # Sufficient simulations for evaluation
                'dirichlet_alpha': 0.1,  # Lower noise for deterministic evaluation
                'dirichlet_epsilon': 0.05,  # Minimal noise
                'use_virtual_loss': True,
                'progressive_widening': True,
                'use_transpositions': True,
                'fpu_reduction': 0.25,  # LC0-style FPU
                'fpu_at_root': True
            })
            
            results = {'white_wins': 0, 'black_wins': 0, 'draws': 0}
            num_eval_games = self.config.eval_games
            
            logger.info(f"Running {num_eval_games} evaluation games...")
            for game_idx in range(num_eval_games):
                board = game.getInitBoard()
                current_player = 1
                moves = 0
                
                while moves < 200:  # Reasonable max moves for evaluation
                    # Add slight randomness to break symmetry and avoid repetitive draws
                    temp = 0.2 if moves < 30 else 0.1  # Higher temp in opening
                    probs = mcts.get_action_probabilities(board, current_player, temperature=temp)
                    action = int(np.argmax(probs))
                    board, current_player = game.getNextState(board, current_player, action)
                    moves += 1
                    
                    ended = game.getGameEnded(board, current_player)
                    if ended != 0:
                        if abs(ended) < 0.01:
                            results['draws'] += 1
                        elif (ended > 0 and current_player == 1) or (ended < 0 and current_player == -1):
                            results['white_wins'] += 1
                        else:
                            results['black_wins'] += 1
                        break
                else:
                    results['draws'] += 1
                
                if (game_idx + 1) % 10 == 0:
                    logger.info(f"Evaluated {game_idx + 1}/{num_eval_games} games")
            
            total_games = sum(results.values())
            win_rate = (results['white_wins'] / total_games) * 100 if total_games > 0 else 0
            
            eval_results = {
                'total_games': total_games,
                'white_wins': results['white_wins'],
                'black_wins': results['black_wins'],
                'draws': results['draws'],
                'win_rate': win_rate
            }
            
            logger.info(f"Evaluation results: {eval_results}")
            return eval_results
            
        except Exception as e:
            logger.warning(f"Evaluation failed: {e}")
            return {}
    
    def _final_evaluation(self):
        """Run comprehensive final evaluation."""
        logger.info("\nStep 3: Final Evaluation...")
        
        if not self.best_model_path:
            logger.warning("No best model found for final evaluation")
            return
        
        logger.info(f"Final evaluation with best model: {self.best_model_path}")
        
        # Run more comprehensive evaluation
        try:
            eval_results = self._evaluate_model(-1, self.best_model_path)  # Use more games
            self.final_eval_results = eval_results
            
            logger.info("Final evaluation completed:")
            logger.info(f"  Win rate: {eval_results.get('win_rate', 0):.1f}%")
            logger.info(f"  Games played: {eval_results.get('total_games', 0)}")
            
        except Exception as e:
            logger.error(f"Final evaluation failed: {e}")
    
    def _generate_report(self):
        """Generate training summary report."""
        logger.info("\nStep 4: Generating Summary Report...")
        
        total_time = time.time() - self.training_start_time
        
        report = {
            'training_config': self.config.to_dict(),
            'device': str(self.device),
            'total_time_hours': total_time / 3600,
            'iterations': self.iteration_results,
            'best_model': self.best_model_path,
            'final_evaluation': getattr(self, 'final_eval_results', {}),
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
        }
        
        # Save report
        report_path = os.path.join(self.config.output_dir, "training_report.json")
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        # Print summary with loss progression analysis
        logger.info(f"\nTRAINING SUMMARY:")
        logger.info(f"  Total time: {total_time/3600:.1f} hours")
        logger.info(f"  Iterations: {len(self.iteration_results)}")
        logger.info(f"  Best model: {self.best_model_path}")
        if hasattr(self, 'final_eval_results'):
            logger.info(f"  Final win rate: {self.final_eval_results.get('win_rate', 0):.1f}%")
        
        # Display loss progression across iterations
        logger.info(f"\nLOSS PROGRESSION:")
        for i, result in enumerate(self.iteration_results):
            losses = result.get('training_losses', {})
            total_loss = losses.get('total', 'N/A')
            policy_loss = losses.get('policy', 'N/A')
            value_loss = losses.get('value', 'N/A')
            
            if isinstance(total_loss, (int, float)):
                logger.info(f"  Iteration {i+1}: Total={total_loss:.4f}, Policy={policy_loss:.4f}, Value={value_loss:.4f}")
            else:
                logger.info(f"  Iteration {i+1}: Loss data unavailable")
        
        # Calculate loss trend
        if len(self.iteration_results) >= 2:
            try:
                first_loss = self.iteration_results[0].get('training_losses', {}).get('total')
                last_loss = self.iteration_results[-1].get('training_losses', {}).get('total')
                if first_loss is not None and last_loss is not None:
                    trend = ((last_loss - first_loss) / first_loss) * 100
                    trend_desc = "improving" if trend < 0 else "degrading"
                    logger.info(f"  Loss Trend: {trend:+.1f}% ({trend_desc})")
            except Exception:
                pass
        
        logger.info(f"  Report saved: {report_path}")
        
        # Create easy-to-use model symlink
        if self.best_model_path:
            best_link = os.path.join(self.config.output_dir, "best_model.pth")
            try:
                if os.path.exists(best_link):
                    os.remove(best_link)
                # Copy instead of symlink for Windows compatibility
                import shutil
                shutil.copy2(self.best_model_path, best_link)
                logger.info(f"  Best model copied to: {best_link}")
            except Exception as e:
                logger.warning(f"Could not create best model link: {e}")
    
    def _get_best_win_rate(self) -> float:
        """Get win rate of current best model."""
        if not self.iteration_results:
            return 0.0
        best_result = max(self.iteration_results, key=lambda x: x['eval_results'].get('win_rate', 0))
        return best_result['eval_results'].get('win_rate', 0)
    
    def _save_partial_results(self):
        """Save partial results when training is interrupted."""
        logger.info("Saving partial results...")
        try:
            self._generate_report()
        except Exception as e:
            logger.error(f"Could not save partial results: {e}")


def load_config(config_path: str) -> EasyTrainConfig:
    """Load configuration from JSON file."""
    config = EasyTrainConfig()
    
    if config_path and os.path.exists(config_path):
        logger.info(f"Loading configuration from: {config_path}")
        with open(config_path, 'r') as f:
            config_dict = json.load(f)
        config.from_dict(config_dict)
    else:
        logger.info("Using default configuration")
    
    return config


def create_sample_config(output_path: str):
    """Create a sample configuration file."""
    config = EasyTrainConfig()
    
    with open(output_path, 'w') as f:
        json.dump(config.to_dict(), f, indent=2)
    
    logger.info(f"Sample configuration created: {output_path}")


def main():
    """Main entry point for easy training."""
    parser = argparse.ArgumentParser(
        description='Katamill Easy Training - Complete Pipeline',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m ml.katamill.easy_train                    # Default training
  python -m ml.katamill.easy_train --quick            # Quick test run
  python -m ml.katamill.easy_train --config my.json  # Custom config
  python -m ml.katamill.easy_train --create-config   # Generate sample config
        """
    )
    
    parser.add_argument('--config', type=str, help='Configuration file (JSON)')
    parser.add_argument('--quick', action='store_true', help='Quick mode for testing')
    parser.add_argument('--create-config', type=str, help='Create sample config file')
    parser.add_argument('--data-dir', type=str, help='Override data directory')
    parser.add_argument('--checkpoint-dir', type=str, help='Override checkpoint directory')
    parser.add_argument('--workers', type=int, help='Override number of workers')
    parser.add_argument('--max-moves', type=int, help='Override max moves per game')
    parser.add_argument('--temperature', type=float, help='Override temperature for self-play')
    parser.add_argument('--fresh-start', action='store_true', help='Start training from scratch (ignore existing checkpoints)')
    
    args = parser.parse_args()
    
    # Create sample config if requested
    if args.create_config:
        create_sample_config(args.create_config)
        return
    
    # Load configuration
    config = load_config(args.config)
    
    # Apply command line overrides
    if args.quick:
        config.setup_quick_mode()
    if args.data_dir:
        config.data_dir = args.data_dir
    if args.checkpoint_dir:
        config.checkpoint_dir = args.checkpoint_dir
    if args.workers:
        config.workers = args.workers
    if args.max_moves:
        # Update max_moves for game completion
        config.max_moves = args.max_moves
        logger.info(f"Overriding max_moves to {args.max_moves}")
    if args.temperature:
        # Update temperature for more decisive games
        config.temperature = args.temperature
        logger.info(f"Overriding temperature to {args.temperature}")
    
    # Handle fresh start option
    if args.fresh_start:
        logger.info("Fresh start mode: will ignore existing checkpoints")
        # Clear existing data to force fresh training
        import shutil
        if os.path.exists(config.data_dir):
            shutil.rmtree(config.data_dir)
        if os.path.exists(config.checkpoint_dir):
            shutil.rmtree(config.checkpoint_dir)
    
    # Run training
    trainer = EasyTrainer(config)
    trainer.run_complete_training()


if __name__ == '__main__':
    main()
