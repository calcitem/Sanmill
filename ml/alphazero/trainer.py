#!/usr/bin/env python3
"""
Alpha Zero Trainer for Nine Men's Morris

This module implements the complete Alpha Zero training pipeline with
optimized Perfect Database integration and efficient self-play generation.

Features:
- Two-phase training: Perfect DB supervised pretraining + self-play
- Concurrent self-play game generation
- Memory-efficient training data management
- Advanced checkpointing and resumption
- Performance monitoring and statistics
"""

import os
import sys
import time
import pickle
import logging
import threading
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor, as_completed
from queue import Queue, Empty
from typing import List, Dict, Tuple, Optional, Any
from collections import deque, defaultdict
from dataclasses import dataclass
import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset

# Add local imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'game'))

from game.Game import Game
from game.GameLogic import Board
from neural_network import AlphaZeroNetworkWrapper
from mcts import MCTS
from perfect_db_loader import EfficientPerfectDBLoader
from perfect_db_trainer import PerfectDBDirectTrainer

logger = logging.getLogger(__name__)


@dataclass
class TrainingExample:
    """Single training example for Alpha Zero."""
    board_tensor: np.ndarray
    policy_target: np.ndarray
    value_target: float
    current_player: int
    metadata: Dict[str, Any] = None


@dataclass
class GameResult:
    """Result of a single self-play game."""
    examples: List[TrainingExample]
    game_length: int
    final_result: float
    game_time: float
    metadata: Dict[str, Any] = None


class SelfPlayWorker:
    """
    Worker process for generating self-play games.
    
    Runs in separate process to enable concurrent game generation.
    """
    
    def __init__(self, 
                 worker_id: int,
                 model_args: Dict[str, Any],
                 mcts_args: Dict[str, Any],
                 game_args: Dict[str, Any]):
        """
        Initialize self-play worker.
        
        Args:
            worker_id: Worker process ID
            model_args: Neural network configuration
            mcts_args: MCTS configuration
            game_args: Game configuration
        """
        self.worker_id = worker_id
        self.model_args = model_args
        self.mcts_args = mcts_args
        self.game_args = game_args
        
        # Initialize game engine
        self.game = Game()
        
        # Initialize neural network (will be loaded from checkpoint)
        self.neural_network = AlphaZeroNetworkWrapper(model_args, device='cpu')  # Use CPU for workers
        
        # Initialize MCTS
        self.mcts = MCTS(self.game, self.neural_network, mcts_args)
        
        logger.debug(f"SelfPlayWorker {worker_id} initialized")
    
    def load_model(self, model_path: str) -> bool:
        """
        Load neural network weights.
        
        Args:
            model_path: Path to model checkpoint
            
        Returns:
            True if loaded successfully
        """
        return self.neural_network.load(model_path)
    
    def play_game(self, 
                  temperature_threshold: int = 10,
                  max_game_length: int = 200,
                  add_noise: bool = True) -> GameResult:
        """
        Play a single self-play game.
        
        Args:
            temperature_threshold: Moves before switching to deterministic play
            max_game_length: Maximum game length
            add_noise: Whether to add noise for exploration
            
        Returns:
            Game result with training examples
        """
        start_time = time.time()
        
        # Initialize game
        board = self.game.getInitBoard()
        current_player = 1
        move_count = 0
        
        # Store training examples
        training_examples = []
        
        while True:
            move_count += 1
            
            # Get canonical board
            canonical_board = self.game.getCanonicalForm(board, current_player)
            
            # Determine temperature
            temperature = 1.0 if move_count <= temperature_threshold else 0.0
            
            # Get action probabilities from MCTS
            action_probs = self.mcts.get_action_probabilities(
                canonical_board, 
                current_player, 
                temperature=temperature
            )
            
            # Store training example (will be labeled with game outcome later)
            board_tensor = self.neural_network.encoder.encode_board(canonical_board, current_player)
            
            example = TrainingExample(
                board_tensor=board_tensor.numpy(),
                policy_target=action_probs.copy(),
                value_target=0.0,  # Will be set after game ends
                current_player=current_player,
                metadata={'move_count': move_count}
            )
            training_examples.append(example)
            
            # Select action
            action = np.random.choice(len(action_probs), p=action_probs)
            
            # Make move
            board, current_player = self.game.getNextState(board, current_player, action)
            
            # Update MCTS tree
            self.mcts.update_root(action)
            
            # Check if game ended
            game_result = self.game.getGameEnded(board, current_player)
            
            if game_result != 0:
                # Game ended
                break
            
            # Check for maximum game length
            if move_count >= max_game_length:
                game_result = 1e-4  # Small positive value for draw
                logger.debug(f"Worker {self.worker_id}: Game reached max length {max_game_length}")
                break
        
        # Label training examples with game outcome
        final_examples = []
        for example in training_examples:
            # Value is from perspective of the player who made the move
            if example.current_player == current_player:
                value_target = game_result
            else:
                value_target = -game_result
            
            example.value_target = value_target
            final_examples.append(example)
        
        game_time = time.time() - start_time
        
        # Reset MCTS for next game
        self.mcts.reset_tree()
        
        return GameResult(
            examples=final_examples,
            game_length=move_count,
            final_result=game_result,
            game_time=game_time,
            metadata={
                'worker_id': self.worker_id,
                'temperature_threshold': temperature_threshold
            }
        )


def worker_play_games(worker_id: int,
                      num_games: int,
                      model_path: str,
                      model_args: Dict[str, Any],
                      mcts_args: Dict[str, Any],
                      game_args: Dict[str, Any]) -> List[GameResult]:
    """
    Worker function for playing multiple games.
    
    Args:
        worker_id: Worker process ID
        num_games: Number of games to play
        model_path: Path to current model
        model_args: Model configuration
        mcts_args: MCTS configuration
        game_args: Game configuration
        
    Returns:
        List of game results
    """
    try:
        # Initialize worker
        worker = SelfPlayWorker(worker_id, model_args, mcts_args, game_args)
        
        # Load current model
        if not worker.load_model(model_path):
            logger.error(f"Worker {worker_id}: Failed to load model from {model_path}")
            return []
        
        # Play games
        results = []
        for game_idx in range(num_games):
            try:
                result = worker.play_game()
                results.append(result)
                
                if (game_idx + 1) % 5 == 0:
                    logger.debug(f"Worker {worker_id}: Completed {game_idx + 1}/{num_games} games")
                    
            except Exception as e:
                logger.error(f"Worker {worker_id}: Game {game_idx} failed: {e}")
                continue
        
        logger.info(f"Worker {worker_id}: Completed {len(results)}/{num_games} games")
        return results
        
    except Exception as e:
        logger.error(f"Worker {worker_id} failed: {e}")
        return []


class AlphaZeroTrainer:
    """
    Main Alpha Zero trainer with Perfect Database integration.
    
    Implements the complete training pipeline with optimizations for 
    Nine Men's Morris and large-scale Perfect Database processing.
    """
    
    def __init__(self, args: Dict[str, Any]):
        """
        Initialize Alpha Zero trainer.
        
        Args:
            args: Training configuration
        """
        self.args = args
        self.device = torch.device('cuda' if args.get('cuda', True) and torch.cuda.is_available() else 'cpu')
        
        # Initialize game engine
        self.game = Game()
        
        # Initialize neural network
        model_args = {
            'input_channels': args.get('input_channels', 17),
            'num_filters': args.get('num_filters', 256),
            'num_residual_blocks': args.get('num_residual_blocks', 10),
            'action_size': self.game.getActionSize(),
            'dropout_rate': args.get('dropout_rate', 0.3)
        }
        self.neural_network = AlphaZeroNetworkWrapper(model_args, device=self.device)
        
        # Initialize Perfect Database components
        self.perfect_db_loader = None
        self.perfect_db_direct_trainer = None
        
        if args.get('perfect_db_path'):
            # Choose training method based on configuration
            use_direct_training = args.get('use_direct_perfect_db_training', True)
            
            if use_direct_training:
                try:
                    # Direct Perfect Database training (no MCTS simulation)
                    self.perfect_db_direct_trainer = PerfectDBDirectTrainer(
                        perfect_db_path=args['perfect_db_path'],
                        neural_network=self.neural_network,
                        use_complete_enumeration=args.get('perfect_db_complete_enumeration', None)
                    )
                    logger.info(f"Perfect Database direct trainer initialized: {args['perfect_db_path']}")
                except Exception as e:
                    logger.error(f"CRITICAL: Failed to initialize Perfect Database direct trainer: {e}")
                    logger.error("Fallback is strictly forbidden - Perfect Database initialization must succeed")
                    raise RuntimeError(f"Perfect Database initialization failed: {e}")
            else:
                try:
                    # Traditional Perfect Database loader (with MCTS simulation)
                    self.perfect_db_loader = EfficientPerfectDBLoader(
                        perfect_db_path=args['perfect_db_path'],
                        max_workers=args.get('db_workers', 4),
                        cache_size=args.get('db_cache_size', 10000),
                        batch_size=args.get('db_batch_size', 1000)
                    )
                    logger.info(f"Perfect Database loader initialized: {args['perfect_db_path']}")
                except Exception as e:
                    logger.error(f"CRITICAL: Failed to initialize Perfect Database loader: {e}")
                    logger.error("Fallback is strictly forbidden - Perfect Database initialization must succeed")
                    raise RuntimeError(f"Perfect Database initialization failed: {e}")
        else:
            if args.get('use_pretraining', False):
                logger.error("CRITICAL: use_pretraining=True but no perfect_db_path provided")
                logger.error("Fallback is strictly forbidden - A Perfect Database path must be provided")
                raise ValueError("Perfect Database path required when pretraining is enabled")
        
        # Training data storage
        self.training_examples = deque(maxlen=args.get('max_examples', 200000))
        self.training_history = []
        
        # Training state
        self.iteration = 0
        self.total_games_played = 0
        
        # Statistics
        self.stats = {
            'training_time': 0.0,
            'self_play_time': 0.0,
            'pretraining_time': 0.0,
            'games_played': 0,
            'positions_generated': 0,
            'neural_net_updates': 0
        }
        
        # Checkpointing
        self.checkpoint_dir = args.get('checkpoint_dir', 'checkpoints')
        os.makedirs(self.checkpoint_dir, exist_ok=True)
        
        logger.info(f"AlphaZeroTrainer initialized on device: {self.device}")
        logger.info(f"Action size: {self.game.getActionSize()}")
    
    def pretrain_with_perfect_db(self, 
                                 num_positions: int = 50000,
                                 batch_size: int = 64,
                                 epochs: int = 10,
                                 learning_rate: float = 1e-3,
                                 trap_ratio: float = 0.3,
                                 use_complete_enumeration: bool = None) -> bool:
        """
        Pretrain neural network using Perfect Database.
        
        Args:
            num_positions: Number of positions for pretraining
            batch_size: Training batch size
            epochs: Number of training epochs
            learning_rate: Learning rate
            trap_ratio: Ratio of trap positions to include (for sampling mode)
            use_complete_enumeration: Force enumeration mode (None = auto-detect)
            
        Returns:
            True if pretraining successful
        """
        # Check which Perfect Database interface is available
        use_direct_trainer = self.perfect_db_direct_trainer is not None
        use_loader = self.perfect_db_loader is not None
        
        if not (use_direct_trainer or use_loader):
            logger.error("CRITICAL: No Perfect Database interface available")
            logger.error("Fallback is strictly forbidden - The Perfect Database interface must be available")
            raise RuntimeError("No Perfect Database interface available and fallback is disabled")
        
        training_method = "Direct Perfect DB Training" if use_direct_trainer else "Perfect DB with MCTS"
        logger.info(f"Starting {training_method} pretraining with {num_positions} positions...")
        start_time = time.time()
        
        try:
            if use_direct_trainer:
                # Direct Perfect Database training (NO MCTS simulation)
                logger.info("Extracting positions directly from Perfect Database...")
                
                # Determine whether to use complete enumeration or sampling
                if num_positions is None:
                    # None means complete enumeration mode
                    logger.info("Using complete enumeration mode (num_positions=None)")
                    # Get intra-sector enumeration mode from configuration
                    complete_sector_enum = self.args.get('complete_sector_enumeration', False)
                    positions = self.perfect_db_direct_trainer.extract_all_positions(
                        max_positions=None,  # No limit - extract all
                        complete_sector_enumeration=complete_sector_enum  # Determine intra-sector enumeration mode based on configuration
                    )
                else:
                    # Determine sampling strategy based on database feasibility
                    if use_complete_enumeration is None:
                        # Auto-detect based on database analysis
                        enumeration_feasible = self.perfect_db_direct_trainer.use_complete_enumeration
                    else:
                        enumeration_feasible = use_complete_enumeration
                    
                    if enumeration_feasible and num_positions is not None:
                        # Complete enumeration approach with position limit
                        logger.info("Using complete enumeration of Perfect Database with limit")
                        positions = self.perfect_db_direct_trainer.extract_all_positions(
                            max_positions=num_positions
                        )
                    else:
                        # Strategic sampling approach (focusing on traps)
                        logger.info(f"Using strategic sampling (trap_ratio={trap_ratio:.1%})")
                        positions = self.perfect_db_direct_trainer.sample_strategic_positions(
                            num_positions=num_positions,
                            trap_ratio=trap_ratio
                        )
                
                if not positions:
                    logger.error("CRITICAL: No training positions extracted from Perfect Database")
                    logger.error("Fallback is strictly forbidden - The Perfect Database must provide training data")
                    raise RuntimeError("Failed to extract positions from Perfect Database")
                
                logger.info(f"Extracted {len(positions)} positions from Perfect Database")
                
                # Train neural network directly on Perfect Database positions
                train_stats = self.perfect_db_direct_trainer.train_neural_network(
                    positions=positions,
                    batch_size=batch_size,
                    epochs=epochs,
                    learning_rate=learning_rate,
                    trap_weight=2.0  # Give extra weight to trap positions
                )
                
                # Update statistics
                pretraining_time = time.time() - start_time
                self.stats['pretraining_time'] = pretraining_time
                self.stats['neural_net_updates'] += epochs * (len(positions) // batch_size)
                
                # Log results
                trap_count = train_stats.get('trap_positions', 0)
                logger.info(f"Direct Perfect DB pretraining completed:")
                logger.info(f"  Training loss: {train_stats['loss']:.6f}")
                logger.info(f"  Policy loss: {train_stats['policy_loss']:.6f}")
                logger.info(f"  Value loss: {train_stats['value_loss']:.6f}")
                logger.info(f"  Trap positions: {trap_count} ({train_stats.get('trap_ratio', 0):.1%})")
                logger.info(f"  Pretraining time: {pretraining_time:.2f}s")
                
                return True
                
            else:
                # Traditional approach with MCTS simulation
                logger.info("Generating training data from Perfect Database (with MCTS)...")
                positions = self.perfect_db_loader.generate_training_batch(
                    batch_size=num_positions,
                    use_cache=False  # Don't use cache for pretraining
                )
            
            if not positions:
                logger.error("CRITICAL: No training positions generated from Perfect Database")
                logger.error("Fallback is strictly forbidden - The Perfect Database must provide training data")
                raise RuntimeError("Failed to generate positions from Perfect Database")
            
            logger.info(f"Generated {len(positions)} training positions")
            
            # Convert to training examples
            training_examples = []
            for pos_data in positions:
                try:
                    board = pos_data['board']
                    current_player = pos_data['current_player']
                    
                    # Encode board
                    board_tensor = self.neural_network.encoder.encode_board(board, current_player)
                    
                    # Create uniform policy target (simplified for pretraining)
                    valid_moves = self.game.getValidMoves(board, current_player)
                    policy_target = valid_moves / np.sum(valid_moves)
                    
                    # Use small random value as target (will be improved during self-play)
                    value_target = np.random.uniform(-0.1, 0.1)
                    
                    example = TrainingExample(
                        board_tensor=board_tensor.numpy(),
                        policy_target=policy_target,
                        value_target=value_target,
                        current_player=current_player
                    )
                    training_examples.append(example)
                    
                except Exception as e:
                    logger.debug(f"Error processing position: {e}")
                    continue
            
            if not training_examples:
                logger.error("CRITICAL: No valid training examples created")
                logger.error("Fallback is strictly forbidden - Valid training examples must be generated")
                raise RuntimeError("Failed to create valid training examples")
            
            logger.info(f"Created {len(training_examples)} training examples")
            
            # Train neural network
            logger.info(f"Training neural network for {epochs} epochs...")
            
            # Prepare data loaders
            board_tensors = torch.stack([torch.FloatTensor(ex.board_tensor) for ex in training_examples])
            policy_targets = torch.stack([torch.FloatTensor(ex.policy_target) for ex in training_examples])
            value_targets = torch.FloatTensor([ex.value_target for ex in training_examples])
            
            dataset = TensorDataset(board_tensors, policy_targets, value_targets)
            dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
            
            # Training loop
            self.neural_network.net.train()
            optimizer = torch.optim.Adam(self.neural_network.net.parameters(), lr=learning_rate)
            
            for epoch in range(epochs):
                epoch_loss = 0.0
                epoch_policy_loss = 0.0
                epoch_value_loss = 0.0
                num_batches = 0
                
                for batch_boards, batch_policies, batch_values in dataloader:
                    batch_boards = batch_boards.to(self.device)
                    batch_policies = batch_policies.to(self.device)
                    batch_values = batch_values.to(self.device)
                    
                    # Forward pass
                    pred_policies, pred_values = self.neural_network.net(batch_boards)
                    
                    # Calculate losses
                    policy_loss = F.cross_entropy(pred_policies, batch_policies)
                    value_loss = F.mse_loss(pred_values.squeeze(), batch_values)
                    total_loss = policy_loss + value_loss
                    
                    # Backward pass
                    optimizer.zero_grad()
                    total_loss.backward()
                    optimizer.step()
                    
                    # Accumulate losses
                    epoch_loss += total_loss.item()
                    epoch_policy_loss += policy_loss.item()
                    epoch_value_loss += value_loss.item()
                    num_batches += 1
                
                # Log epoch statistics
                if num_batches > 0:
                    avg_loss = epoch_loss / num_batches
                    avg_policy_loss = epoch_policy_loss / num_batches
                    avg_value_loss = epoch_value_loss / num_batches
                    
                    logger.info(f"Epoch {epoch + 1}/{epochs}: "
                                f"Loss={avg_loss:.6f}, "
                                f"Policy={avg_policy_loss:.6f}, "
                                f"Value={avg_value_loss:.6f}")
            
            # Save pretrained model
            pretrain_path = os.path.join(self.checkpoint_dir, 'pretrained_model.pth')
            self.neural_network.save(pretrain_path)
            
            pretraining_time = time.time() - start_time
            self.stats['pretraining_time'] = pretraining_time
            self.stats['neural_net_updates'] += epochs * len(dataloader)
            
            logger.info(f"Pretraining completed in {pretraining_time:.2f}s")
            return True
            
        except Exception as e:
            logger.error(f"CRITICAL: Pretraining failed: {e}")
            logger.error("Fallback is strictly forbidden - Pretraining failure must terminate the process")
            raise RuntimeError(f"Perfect Database pretraining failed: {e}")
    
    def generate_self_play_data(self, num_games: int, num_workers: int = None) -> List[TrainingExample]:
        """
        Generate self-play training data using multiple workers.
        
        Args:
            num_games: Number of games to play
            num_workers: Number of worker processes
            
        Returns:
            List of training examples
        """
        if num_workers is None:
            num_workers = min(num_games, self.args.get('self_play_workers', mp.cpu_count()))
        
        logger.info(f"Generating {num_games} self-play games using {num_workers} workers...")
        start_time = time.time()
        
        # Save current model for workers
        temp_model_path = os.path.join(self.checkpoint_dir, 'temp_model_for_workers.pth')
        self.neural_network.save(temp_model_path)
        
        # Prepare worker arguments
        model_args = {
            'input_channels': self.args.get('input_channels', 17),
            'num_filters': self.args.get('num_filters', 256),
            'num_residual_blocks': self.args.get('num_residual_blocks', 10),
            'action_size': self.game.getActionSize(),
            'dropout_rate': self.args.get('dropout_rate', 0.3)
        }
        
        mcts_args = {
            'c_puct': self.args.get('c_puct', 1.0),
            'num_mcts_sims': self.args.get('num_mcts_sims', 25),
            'add_dirichlet_noise': self.args.get('add_dirichlet_noise', True),
            'dirichlet_alpha': self.args.get('dirichlet_alpha', 0.3),
            'dirichlet_epsilon': self.args.get('dirichlet_epsilon', 0.25)
        }
        
        game_args = {}
        
        # Distribute games among workers
        games_per_worker = num_games // num_workers
        remaining_games = num_games % num_workers
        
        all_examples = []
        
        if num_workers > 1:
            # Use multiprocessing
            with ProcessPoolExecutor(max_workers=num_workers) as executor:
                futures = []
                
                for worker_id in range(num_workers):
                    worker_games = games_per_worker + (1 if worker_id < remaining_games else 0)
                    
                    future = executor.submit(
                        worker_play_games,
                        worker_id,
                        worker_games,
                        temp_model_path,
                        model_args,
                        mcts_args,
                        game_args
                    )
                    futures.append(future)
                
                # Collect results
                total_games_completed = 0
                for worker_id, future in enumerate(futures):
                    try:
                        game_results = future.result()
                        
                        # Extract training examples
                        for result in game_results:
                            all_examples.extend(result.examples)
                            total_games_completed += 1
                        
                        logger.info(f"Worker {worker_id}: collected {len(game_results)} games, "
                                    f"{sum(len(r.examples) for r in game_results)} examples")
                        
                    except Exception as e:
                        logger.error(f"Worker {worker_id} failed: {e}")
        else:
            # Single process
            worker = SelfPlayWorker(0, model_args, mcts_args, game_args)
            if worker.load_model(temp_model_path):
                for game_idx in range(num_games):
                    try:
                        result = worker.play_game()
                        all_examples.extend(result.examples)
                        
                        if (game_idx + 1) % 10 == 0:
                            logger.info(f"Completed {game_idx + 1}/{num_games} games")
                            
                    except Exception as e:
                        logger.error(f"Game {game_idx} failed: {e}")
        
        # Clean up temporary model file
        if os.path.exists(temp_model_path):
            os.remove(temp_model_path)
        
        self_play_time = time.time() - start_time
        self.stats['self_play_time'] += self_play_time
        self.stats['games_played'] += num_games
        
        logger.info(f"Self-play completed in {self_play_time:.2f}s: "
                    f"{len(all_examples)} examples from {num_games} games "
                    f"({len(all_examples) / self_play_time:.1f} examples/s)")
        
        return all_examples
    
    def train_neural_network(self, 
                             training_examples: List[TrainingExample],
                             batch_size: int = 64,
                             epochs: int = 5,
                             learning_rate: float = 1e-3) -> Dict[str, float]:
        """
        Train neural network on training examples.
        
        Args:
            training_examples: List of training examples
            batch_size: Training batch size
            epochs: Number of epochs
            learning_rate: Learning rate
            
        Returns:
            Training statistics
        """
        if not training_examples:
            return {'loss': 0.0, 'policy_loss': 0.0, 'value_loss': 0.0}
        
        logger.info(f"Training neural network on {len(training_examples)} examples "
                    f"for {epochs} epochs...")
        
        start_time = time.time()
        
        # Prepare data
        board_tensors = torch.stack([torch.FloatTensor(ex.board_tensor) for ex in training_examples])
        policy_targets = torch.stack([torch.FloatTensor(ex.policy_target) for ex in training_examples])
        value_targets = torch.FloatTensor([ex.value_target for ex in training_examples])
        
        dataset = TensorDataset(board_tensors, policy_targets, value_targets)
        dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
        
        # Training
        self.neural_network.net.train()
        optimizer = torch.optim.Adam(self.neural_network.net.parameters(), lr=learning_rate)
        
        total_loss = 0.0
        total_policy_loss = 0.0
        total_value_loss = 0.0
        total_batches = 0
        
        print(f"\n🧠 Starting neural network training...")
        print(f"📊 Training parameters: {epochs} epochs, {len(training_examples)} samples, batch size {batch_size}")
        print(f"🎯 Device: {self.device}")
        print()
        
        # Create progress display
        from progress_display import CompactProgressDisplay
        
        for epoch in range(epochs):
            epoch_start_time = time.time()
            epoch_loss = 0.0
            batch_count = 0
            total_batches_in_epoch = len(dataloader)
            
            print(f"Epoch {epoch + 1}/{epochs}:")
            
            # Create progress display for each epoch
            progress_display = CompactProgressDisplay()
            
            for batch_boards, batch_policies, batch_values in dataloader:
                batch_boards = batch_boards.to(self.device)
                batch_policies = batch_policies.to(self.device)
                batch_values = batch_values.to(self.device)
                
                # Forward pass
                pred_policies, pred_values = self.neural_network.net(batch_boards)
                
                # Calculate losses
                policy_loss = F.cross_entropy(pred_policies, batch_policies)
                value_loss = F.mse_loss(pred_values.squeeze(), batch_values)
                loss = policy_loss + value_loss
                
                # Backward pass
                optimizer.zero_grad()
                loss.backward()
                optimizer.step()
                
                # Accumulate statistics
                total_loss += loss.item()
                total_policy_loss += policy_loss.item()
                total_value_loss += value_loss.item()
                total_batches += 1
                epoch_loss += loss.item()
                batch_count += 1
                
                # Update progress display - update every 10 batches to reduce overhead
                if batch_count % 10 == 0 or batch_count == total_batches_in_epoch:
                    current_loss = epoch_loss / batch_count
                    extra_info = f"Loss: {current_loss:.6f}"
                    progress_display.update(
                        current=batch_count,
                        total=total_batches_in_epoch,
                        current_file=f"Epoch {epoch + 1}/{epochs}",
                        extra_info=extra_info
                    )
            
            # Finish epoch progress display
            epoch_time = time.time() - epoch_start_time
            avg_epoch_loss = epoch_loss / total_batches_in_epoch
            progress_display.finish(f"Epoch {epoch + 1} completed!")
            print(f"  ✅ Epoch {epoch + 1}/{epochs} completed: Loss = {avg_epoch_loss:.6f}, Time = {epoch_time:.1f}s")
            print()
        
        training_time = time.time() - start_time
        self.stats['training_time'] += training_time
        self.stats['neural_net_updates'] += total_batches
        
        # Calculate averages
        avg_loss = total_loss / total_batches if total_batches > 0 else 0.0
        avg_policy_loss = total_policy_loss / total_batches if total_batches > 0 else 0.0
        avg_value_loss = total_value_loss / total_batches if total_batches > 0 else 0.0
        
        logger.info(f"Training completed in {training_time:.2f}s: "
                    f"Loss={avg_loss:.6f}, Policy={avg_policy_loss:.6f}, Value={avg_value_loss:.6f}")
        
        return {
            'loss': avg_loss,
            'policy_loss': avg_policy_loss,
            'value_loss': avg_value_loss,
            'training_time': training_time
        }
    
    def save_checkpoint(self, iteration: int):
        """Save training checkpoint."""
        # Save neural network
        model_path = os.path.join(self.checkpoint_dir, f'model_iter_{iteration}.pth')
        self.neural_network.save(model_path)
        
        # Save training state
        state = {
            'iteration': iteration,
            'total_games_played': self.total_games_played,
            'training_history': self.training_history,
            'stats': self.stats,
            'args': self.args
        }
        
        state_path = os.path.join(self.checkpoint_dir, f'training_state_iter_{iteration}.pkl')
        with open(state_path, 'wb') as f:
            pickle.dump(state, f)
        
        logger.info(f"Checkpoint saved for iteration {iteration}")
    
    def load_checkpoint(self, iteration: int) -> bool:
        """Load training checkpoint."""
        # Load neural network
        model_path = os.path.join(self.checkpoint_dir, f'model_iter_{iteration}.pth')
        if not self.neural_network.load(model_path):
            return False
        
        # Load training state
        state_path = os.path.join(self.checkpoint_dir, f'training_state_iter_{iteration}.pkl')
        if os.path.exists(state_path):
            with open(state_path, 'rb') as f:
                state = pickle.load(f)
                
            self.iteration = state['iteration']
            self.total_games_played = state['total_games_played']
            self.training_history = state['training_history']
            self.stats = state['stats']
            
            logger.info(f"Training state loaded for iteration {iteration}")
        
        return True
    
    def train(self, num_iterations: int = 100, start_iteration: int = 0):
        """
        Main training loop.
        
        Args:
            num_iterations: Number of training iterations
            start_iteration: Starting iteration (for resuming)
        """
        logger.info("="*80)
        logger.info("ALPHA ZERO TRAINING FOR NINE MEN'S MORRIS")
        logger.info("="*80)
        
        # Load checkpoint if resuming
        if start_iteration > 0:
            if self.load_checkpoint(start_iteration):
                logger.info(f"Resumed training from iteration {start_iteration}")
            else:
                logger.warning(f"Could not load checkpoint for iteration {start_iteration}")
                start_iteration = 0
        
        # Perfect Database pretraining (only on first run)
        if start_iteration == 0 and self.args.get('use_pretraining', True):
            # Handle None values for pretrain_positions (None means complete enumeration)
            pretrain_positions = self.args.get('pretrain_positions', 50000)
            if pretrain_positions is None:
                pretrain_positions = None  # Keep None for complete enumeration
            
            pretrain_success = self.pretrain_with_perfect_db(
                num_positions=pretrain_positions,
                batch_size=self.args.get('pretrain_batch_size', 64),
                epochs=self.args.get('pretrain_epochs', 10),
                learning_rate=self.args.get('pretrain_lr', 1e-3)
            )
            
            if pretrain_success:
                logger.info("Perfect Database pretraining completed successfully")
            else:
                logger.error("Perfect Database pretraining FAILED - TRAINING ABORTED")
                logger.error("Fallback to self-play mode is strictly forbidden")
                raise RuntimeError("Perfect Database pretraining failed and fallback is disabled")
        
        # Main training loop
        for iteration in range(start_iteration, start_iteration + num_iterations):
            iteration_start = time.time()
            
            logger.info(f"\n{'='*60}")
            logger.info(f"TRAINING ITERATION {iteration + 1}/{start_iteration + num_iterations}")
            logger.info(f"{'='*60}")
            
            # Generate self-play data
            num_games = self.args.get('games_per_iteration', 100)
            new_examples = self.generate_self_play_data(
                num_games=num_games,
                num_workers=self.args.get('self_play_workers', None)
            )
            
            # Add to training data
            self.training_examples.extend(new_examples)
            self.total_games_played += num_games
            
            logger.info(f"Training data size: {len(self.training_examples)} examples")
            
            # Train neural network
            if len(self.training_examples) > 0:
                train_stats = self.train_neural_network(
                    training_examples=list(self.training_examples),
                    batch_size=self.args.get('train_batch_size', 64),
                    epochs=self.args.get('train_epochs', 5),
                    learning_rate=self.args.get('train_lr', 1e-3)
                )
                
                # Record history
                iteration_stats = {
                    'iteration': iteration + 1,
                    'games_played': num_games,
                    'total_examples': len(self.training_examples),
                    'new_examples': len(new_examples),
                    **train_stats
                }
                self.training_history.append(iteration_stats)
            
            # Save checkpoint
            if (iteration + 1) % self.args.get('checkpoint_interval', 10) == 0:
                self.save_checkpoint(iteration + 1)
            
            # Print iteration summary
            iteration_time = time.time() - iteration_start
            logger.info(f"\nIteration {iteration + 1} completed in {iteration_time:.2f}s")
            logger.info(f"Total games played: {self.total_games_played}")
            logger.info(f"Training examples: {len(self.training_examples)}")
            
        # Final checkpoint
        self.save_checkpoint(start_iteration + num_iterations)
        
        # Print final statistics
        logger.info("\n" + "="*80)
        logger.info("TRAINING COMPLETED")
        logger.info("="*80)
        logger.info(f"Total iterations: {num_iterations}")
        logger.info(f"Total games played: {self.total_games_played}")
        logger.info(f"Total training time: {self.stats['training_time']:.2f}s")
        logger.info(f"Total self-play time: {self.stats['self_play_time']:.2f}s")
        logger.info(f"Neural network updates: {self.stats['neural_net_updates']}")
        
        if self.perfect_db_loader:
            perf_stats = self.perfect_db_loader.get_performance_statistics()
            logger.info(f"Perfect DB positions generated: {perf_stats.get('positions_generated', 0)}")
            logger.info(f"Perfect DB cache hit rate: {perf_stats.get('cache_hit_rate', 0):.2%}")


def main():
    """Main function for command-line training."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Alpha Zero Training for Nine Men\'s Morris',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    # Training parameters
    parser.add_argument('--iterations', type=int, default=100,
                        help='Number of training iterations (default: 100)')
    parser.add_argument('--start-iteration', type=int, default=0,
                        help='Starting iteration for resuming training (default: 0)')
    parser.add_argument('--games-per-iteration', type=int, default=100,
                        help='Number of self-play games per iteration (default: 100)')
    
    # Perfect Database
    parser.add_argument('--perfect-db', default=None,
                        help='Path to Perfect Database for pretraining')
    parser.add_argument('--pretrain-positions', type=int, default=50000,
                        help='Number of positions for pretraining (default: 50000)')
    parser.add_argument('--skip-pretraining', action='store_true',
                        help='Skip Perfect Database pretraining')
    
    # Neural network
    parser.add_argument('--input-channels', type=int, default=17,
                        help='Number of input channels (default: 17)')
    parser.add_argument('--num-filters', type=int, default=256,
                        help='Number of convolutional filters (default: 256)')
    parser.add_argument('--num-residual-blocks', type=int, default=10,
                        help='Number of residual blocks (default: 10)')
    parser.add_argument('--dropout-rate', type=float, default=0.3,
                        help='Dropout rate (default: 0.3)')
    
    # MCTS
    parser.add_argument('--mcts-sims', type=int, default=25,
                        help='Number of MCTS simulations (default: 25)')
    parser.add_argument('--c-puct', type=float, default=1.0,
                        help='MCTS exploration constant (default: 1.0)')
    
    # Training
    parser.add_argument('--train-batch-size', type=int, default=64,
                        help='Training batch size (default: 64)')
    parser.add_argument('--train-epochs', type=int, default=5,
                        help='Training epochs per iteration (default: 5)')
    parser.add_argument('--train-lr', type=float, default=1e-3,
                        help='Training learning rate (default: 1e-3)')
    
    # System
    parser.add_argument('--cuda', action='store_true',
                        help='Use CUDA if available')
    parser.add_argument('--self-play-workers', type=int, default=None,
                        help='Number of self-play workers (default: CPU count)')
    parser.add_argument('--checkpoint-dir', default='checkpoints',
                        help='Directory for checkpoints (default: checkpoints)')
    parser.add_argument('--checkpoint-interval', type=int, default=10,
                        help='Checkpoint interval (default: 10)')
    
    # Logging
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Set up logging
    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Convert to configuration dictionary
    config = {
        # Training
        'games_per_iteration': args.games_per_iteration,
        'checkpoint_dir': args.checkpoint_dir,
        'checkpoint_interval': args.checkpoint_interval,
        
        # Perfect Database
        'perfect_db_path': args.perfect_db,
        'use_pretraining': not args.skip_pretraining and args.perfect_db is not None,
        'pretrain_positions': args.pretrain_positions,
        
        # Neural Network
        'input_channels': args.input_channels,
        'num_filters': args.num_filters,
        'num_residual_blocks': args.num_residual_blocks,
        'dropout_rate': args.dropout_rate,
        
        # MCTS
        'num_mcts_sims': args.mcts_sims,
        'c_puct': args.c_puct,
        
        # Training
        'train_batch_size': args.train_batch_size,
        'train_epochs': args.train_epochs,
        'train_lr': args.train_lr,
        
        # System
        'cuda': args.cuda,
        'self_play_workers': args.self_play_workers,
    }
    
    # Log configuration
    logger.info("Alpha Zero Training Configuration:")
    for key, value in config.items():
        logger.info(f"  {key}: {value}")
    
    # Create trainer and start training
    trainer = AlphaZeroTrainer(config)
    
    try:
        trainer.train(
            num_iterations=args.iterations,
            start_iteration=args.start_iteration
        )
        return 0
    except KeyboardInterrupt:
        logger.info("Training interrupted by user")
        return 1
    except Exception as e:
        logger.error(f"Training failed: {e}")
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
