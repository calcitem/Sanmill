#!/usr/bin/env python3
"""
Self-play generator for Katamill.

Produces tuples (features, pi, z, aux) where
- features: CNN input from features.extract_features
- pi: action probabilities from MCTS
- z: game outcome from current player's perspective
- aux: dict of auxiliary targets (ownership, score, mill_potential)
"""

import argparse
import logging
import os
import sys
import time
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
import multiprocessing as mp
import numpy as np

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Import game module with fallback
try:
    from ml.game.Game import Game
except Exception:
    try:
        from game.Game import Game
    except Exception:
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game

# Import katamill modules with fallback
try:
    from .neural_network import KatamillNet, KatamillWrapper
    from .mcts import MCTS
    from .features import extract_features
    from .heuristics import build_auxiliary_targets
    from .data_loader import save_selfplay_data
    from .progress import SelfPlayProgressTracker
except ImportError:
    from neural_network import KatamillNet, KatamillWrapper
    from mcts import MCTS
    from features import extract_features
    from heuristics import build_auxiliary_targets
    from data_loader import save_selfplay_data
    from progress import SelfPlayProgressTracker

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class SelfPlayConfig:
    num_games: int = 10
    max_moves: int = 250  # Reasonable buffer above theoretical max of ~204 steps
    mcts_sims: int = 400
    temperature: float = 0.8  # Lower temperature for more decisive games
    temp_decay_moves: int = 30
    cpuct: float = 1.8
    # For parallel execution
    num_workers: int = 1
    games_per_worker: int = 10


def play_single_game(game: Game, wrapper: KatamillWrapper, cfg: SelfPlayConfig) -> List[Dict[str, Any]]:
    """
    Play a single self-play game with KataGo-inspired improvements.
    
    Features:
    - Proper handling of Nine Men's Morris consecutive moves
    - Advanced MCTS configuration based on game phase
    - Better sample quality through improved target calculation
    - Robust game termination handling
    """
    board = game.getInitBoard()
    # Randomize starting player to avoid systematic bias
    cur_player = np.random.choice([1, -1])
    episode = []
    consecutive_moves = 0  # Track consecutive moves for Nine Men's Morris
    last_player = None
    
    # Game phase tracking for adaptive parameters
    game_phase_history = []
    
    for move_idx in range(cfg.max_moves):
        # Store board state for auxiliary target calculation
        board_before_move = board
        current_phase = getattr(board, 'period', 0)
        game_phase_history.append(current_phase)
        
        # Track consecutive moves (important for Nine Men's Morris)
        if last_player == cur_player:
            consecutive_moves += 1
        else:
            consecutive_moves = 0
        last_player = cur_player
        
        # Extract features with enhanced context
        feats = extract_features(board, cur_player)
        
        # Create MCTS with balanced parameters for fair self-play
        mcts_config = {
            'cpuct': cfg.cpuct,  # Use base cpuct without multiplier for balance
            'num_simulations': cfg.mcts_sims,  # Use configured sims for speed
            'dirichlet_alpha': 0.3,  # Higher noise for more exploration and balance
            'dirichlet_epsilon': 0.25,  # Higher noise for diverse games
            'use_virtual_loss': True,
            'progressive_widening': True,
            'use_transpositions': True,  # Enable transposition table
            'max_transposition_size': 50000,
            'fpu_reduction': 0.1,  # Smaller FPU reduction for more balanced play
            'fpu_at_root': True,
            'consecutive_move_bonus': 0.01,  # Minimal bonus for neutral play
        }
        
        # Adjust MCTS parameters based on game phase with more balanced settings
        if current_phase == 0:  # Placing phase - strategic foundation
            mcts_config['dirichlet_alpha'] = 0.4  # High exploration for diverse openings
            mcts_config['dirichlet_epsilon'] = 0.3  # More noise for opening variety
        elif current_phase == 3:  # Removal phase - consecutive move after mill
            mcts_config['dirichlet_alpha'] = 0.2  # Moderate noise for tactical choices
            mcts_config['dirichlet_epsilon'] = 0.15  # Balanced noise
        elif current_phase == 2:  # Flying phase - complex endgame calculations
            mcts_config['dirichlet_alpha'] = 0.25  # Balanced noise for endgame
            mcts_config['dirichlet_epsilon'] = 0.2  # Moderate noise
        # Moving phase uses default balanced settings
        
        try:
            from .mcts import MCTS
        except ImportError:
            from mcts import MCTS
            
        mcts = MCTS(game, wrapper, mcts_config)
        
        # Balanced temperature scheduling for diverse and fair games
        # Keep temperature higher throughout the game for better exploration
        if move_idx < cfg.temp_decay_moves:
            # Slower decay to maintain exploration
            decay_factor = 1.0 - (move_idx / cfg.temp_decay_moves) * 0.3  # Only 30% decay
            base_temp = cfg.temperature * decay_factor
        else:
            base_temp = cfg.temperature * 0.7  # Keep substantial temperature
        
        # More conservative phase-specific adjustments for balanced games
        if current_phase == 0:  # Placing phase - diverse openings
            temp = base_temp * 1.2  # Moderate boost for opening diversity
        elif current_phase == 3:  # Removal phase - tactical choices
            temp = base_temp * 0.8  # Slight reduction but keep exploration
        elif current_phase == 2:  # Flying phase - endgame calculations
            temp = base_temp * 0.9  # Small reduction for calculation
        else:  # Moving phase - standard play
            temp = base_temp
        
        # Minimal adjustment for consecutive moves to maintain balance
        if consecutive_moves > 0:
            temp = temp * 0.95  # Very small reduction
        
        # Add root noise for exploration (more in early game)
        add_noise = move_idx < cfg.temp_decay_moves
        pi = mcts.get_action_probabilities(board, cur_player, temperature=temp, add_root_noise=add_noise)
        
        # Select action with improved sampling
        if temp > 0:
            # Use temperature-based sampling with safety checks
            valid_actions = game.getValidMoves(board, cur_player)
            masked_pi = pi * valid_actions
            if np.sum(masked_pi) > 0:
                masked_pi = masked_pi / np.sum(masked_pi)
                action = int(np.random.choice(len(pi), p=masked_pi))
            else:
                # Fallback to uniform sampling over valid moves
                valid_indices = np.where(valid_actions == 1)[0]
                action = int(np.random.choice(valid_indices))
        else:
            # Deterministic selection
            valid_actions = game.getValidMoves(board, cur_player)
            masked_pi = pi * valid_actions
            if np.sum(masked_pi) > 0:
                action = int(np.argmax(masked_pi))
            else:
                # Fallback
                valid_indices = np.where(valid_actions == 1)[0]
                action = int(valid_indices[0]) if len(valid_indices) > 0 else 0
        
        # Store experience with enhanced information
        episode.append({
            'features': feats,
            'pi': pi.astype(np.float32),
            'player': cur_player,
            'board_state': board_before_move,
            'move_idx': move_idx,
            'game_phase': current_phase,
            'consecutive_moves': consecutive_moves,
            'temperature': temp,
            'mcts_sims': mcts_config['num_simulations'],
        })
        
        # Execute move with comprehensive error handling
        max_recovery_attempts = 3
        recovery_attempt = 0
        
        while recovery_attempt <= max_recovery_attempts:
            try:
                prev_player = cur_player
                board, cur_player = game.getNextState(board, cur_player, action)
                
                # Log consecutive moves for debugging Nine Men's Morris
                if prev_player == cur_player and logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"Consecutive move detected: player {cur_player} continues "
                               f"(phase {current_phase}, move {move_idx})")
                
                break  # Success, exit retry loop
                
            except Exception as e:
                recovery_attempt += 1
                logger.warning(f"Invalid move in self-play (attempt {recovery_attempt}): "
                             f"action={action}, player={cur_player}, phase={current_phase}. Error: {e}")
                
                if recovery_attempt > max_recovery_attempts:
                    logger.error("Max recovery attempts exceeded. Terminating game.")
                    break
                
                # Try to recover by selecting a different valid move
                try:
                    valid_actions = game.getValidMoves(board, cur_player)
                    valid_indices = np.where(valid_actions == 1)[0]
                    
                    if len(valid_indices) == 0:
                        logger.error("No valid moves available! Terminating game.")
                        break
                    
                    # Remove the problematic action from consideration
                    valid_indices = valid_indices[valid_indices != action]
                    
                    if len(valid_indices) == 0:
                        logger.error("Only invalid move available! Terminating game.")
                        break
                    
                    # Select a new random valid action
                    action = int(np.random.choice(valid_indices))
                    logger.info(f"Recovery: trying action {action}")
                    
                except Exception as recovery_error:
                    logger.error(f"Recovery attempt failed: {recovery_error}")
                    break
        
        # If we exhausted recovery attempts, terminate the game
        if recovery_attempt > max_recovery_attempts:
            break
        
        # Check game end with enhanced timeout detection
        result = game.getGameEnded(board, cur_player)
        
        # Additional timeout detection for long games
        if result == 0 and move_idx >= cfg.max_moves * 0.8:  # 80% of max moves
            # Check if we're in a repetitive state that should be a draw
            if move_idx >= cfg.max_moves - 10:
                # Force draw for very long games to avoid infinite loops
                result = 1e-4  # Small positive value indicates draw
                logger.debug(f"Forced draw due to excessive length: {move_idx} moves")
        
        if result != 0:
            # Debug: Log game ending details to understand bias
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"Game ended: result={result:.4f}, cur_player={cur_player}, "
                           f"move_idx={move_idx}, phase={current_phase}")
            # Game ended - create training samples with proper value assignment
            samples = []
            for step_idx, step in enumerate(episode):
                # Determine game outcome from step player's perspective
                # Critical: Proper value assignment for Nine Men's Morris training
                if abs(result) < 0.01:  # Draw
                    z = 0.0
                else:
                    # CRITICAL: Handle Nine Men's Morris value assignment with consecutive moves
                    # result > 0 means the current player (at game end) wins
                    # result < 0 means the current player (at game end) loses
                    # IMPORTANT: cur_player at game end might have made consecutive moves
                    step_player = step['player']
                    
                    # Ensure result is properly bounded
                    result = max(-1.0, min(1.0, result))
                    
                    # Assign value from the perspective of the step player
                    # The result is from perspective of cur_player who was active at game end
                    # This correctly handles cases where game ends during consecutive moves
                    if result > 0:
                        # cur_player (at game end) wins
                        z = 1.0 if step_player == cur_player else -1.0
                    else:
                        # cur_player (at game end) loses  
                        z = -1.0 if step_player == cur_player else 1.0
                    
                    # Ensure z is properly bounded
                    z = max(-1.0, min(1.0, z))
                
                # Build auxiliary targets with enhanced context
                aux = build_auxiliary_targets(step['board_state'], step['player'])
                
                # Create training sample
                sample = {
                    'features': step['features'],
                    'pi': step['pi'],
                    'z': np.array([z], dtype=np.float32),
                    'aux': aux,
                }
                
                # Add metadata for analysis (not used in training)
                sample['metadata'] = {
                    'move_idx': step['move_idx'],
                    'game_phase': step['game_phase'],
                    'consecutive_moves': step['consecutive_moves'],
                    'game_length': len(episode),
                    'final_result': result,
                    # Record step player's color so later code can map z to white/black
                    'step_player': int(step['player']),
                }
                
                samples.append(sample)
            
            # Log game statistics
            game_length = len(episode)
            phase_distribution = {p: game_phase_history.count(p) for p in set(game_phase_history)}
            consecutive_count = sum(1 for step in episode if step['consecutive_moves'] > 0)
            
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"Game completed: length={game_length}, result={result:.2f}, "
                           f"consecutive_moves={consecutive_count}, phases={phase_distribution}")
            
            return samples
    
    # Game exceeded max moves - treat as draw with warning
    logger.warning(f"Game exceeded {cfg.max_moves} moves, treating as draw. "
                  f"Final phase: {game_phase_history[-1] if game_phase_history else 'unknown'}")
    
    samples = []
    for step_idx, step in enumerate(episode):
        aux = build_auxiliary_targets(step['board_state'], step['player'])
        sample = {
            'features': step['features'],
            'pi': step['pi'],
            'z': np.array([0.0], dtype=np.float32),  # Draw
            'aux': aux,
        }
        sample['metadata'] = {
            'move_idx': step['move_idx'],
            'game_phase': step['game_phase'],
            'consecutive_moves': step['consecutive_moves'],
            'game_length': len(episode),
            'final_result': 0.0,
            'timeout': True,
        }
        samples.append(sample)
    
    return samples


def run_selfplay(wrapper: KatamillWrapper, cfg: SelfPlayConfig) -> List[Dict[str, Any]]:
    """Run self-play games and collect training samples."""
    game = Game()
    all_samples = []
    
    # Initialize progress tracker
    progress_tracker = SelfPlayProgressTracker(cfg.num_games, cfg.mcts_sims)
    
    logger.info(f"Starting self-play: {cfg.num_games} games, {cfg.mcts_sims} MCTS sims per move")
    
    try:
        for game_idx in range(cfg.num_games):
            samples = play_single_game(game, wrapper, cfg)
            all_samples.extend(samples)
            
            # Determine game outcome for statistics using white/black perspective
            if samples:
                meta = samples[-1].get('metadata', {})
                final_result = float(meta.get('final_result', 0.0))
                # In Game.getGameEnded, result > 0 means current_player (at end) wins.
                # We need white/black outcome: infer winner color from final_result and current_player at end.
                # At the end of play_single_game, 'cur_player' is the player to move when game ended.
                # But we don't carry it out; instead deduce from step player's mapping on the final step.
                # Use z and step_player of the last step to derive winner color safely.
                last_step = samples[-1]
                z_last = float(last_step['z'][0])
                step_player = int(meta.get('step_player', last_step.get('player', 1)))
                # If z_last > 0, step_player won; map to white/black by step_player sign
                if abs(z_last) < 0.5:
                    outcome = 'draws'
                else:
                    winner_color = step_player if z_last > 0 else -step_player
                    outcome = 'white_wins' if winner_color == 1 else 'black_wins'
            else:
                outcome = 'draws'
            
            # Update progress
            progress_tracker.update_game(
                samples=len(samples),
                moves=len(samples),  # Approximate moves as samples
                outcome=outcome
            )
    
    finally:
        progress_tracker.close()
    
    return all_samples


def worker_selfplay(worker_id: int, model_path: str, cfg: SelfPlayConfig, 
                   output_queue: mp.Queue, device: str = "cpu"):
    """
    Enhanced worker process for parallel self-play with KataGo-style optimizations.
    
    Features:
    - Optimized model loading and caching
    - Better error handling and recovery
    - Enhanced statistics collection
    - Memory management for long-running processes
    """
    import torch
    import gc
    import time
    
    start_time = time.time()
    logger.info(f"Worker {worker_id} starting on device {device}")
    
    try:
        # Load model in worker process with proper device handling
        try:
            from .config import default_net_config
        except ImportError:
            from config import default_net_config
            
        net = KatamillNet(default_net_config())
        
        if model_path and os.path.exists(model_path):
            # Load checkpoint with proper device mapping
            map_location = device if device != 'auto' else 'cpu'
            checkpoint = torch.load(model_path, map_location=map_location)
            
            if 'model_state_dict' in checkpoint:
                net.load_state_dict(checkpoint['model_state_dict'])
                logger.debug(f"Worker {worker_id}: Loaded model state dict")
            else:
                net.load_state_dict(checkpoint)
                logger.debug(f"Worker {worker_id}: Loaded direct checkpoint")
        else:
            logger.warning(f"Worker {worker_id}: No model path provided, using random weights")
        
        # Create wrapper with caching enabled for efficiency
        wrapper = KatamillWrapper(net, device=device, enable_cache=True)
        game = Game()
        
        # Statistics tracking
        worker_stats = {
            'games_completed': 0,
            'samples_generated': 0,
            'total_moves': 0,
            'consecutive_moves': 0,
            'phase_distribution': {0: 0, 1: 0, 2: 0, 3: 0},
            'game_lengths': [],
            'outcomes': {'wins': 0, 'losses': 0, 'draws': 0},
            'errors': 0,
        }
        
        # Play assigned games with enhanced error handling
        worker_samples = []
        games_per_checkpoint = max(1, cfg.games_per_worker // 10)
        
        for i in range(cfg.games_per_worker):
            try:
                samples = play_single_game(game, wrapper, cfg)
                worker_samples.extend(samples)
                
                # Update statistics
                worker_stats['games_completed'] += 1
                worker_stats['samples_generated'] += len(samples)
                
                if samples:
                    # Extract game statistics from metadata
                    last_sample = samples[-1]
                    if 'metadata' in last_sample:
                        meta = last_sample['metadata']
                        worker_stats['total_moves'] += meta.get('game_length', 0)
                        worker_stats['game_lengths'].append(meta.get('game_length', 0))
                        
                        # Count consecutive moves
                        consecutive_count = sum(1 for s in samples if s.get('metadata', {}).get('consecutive_moves', 0) > 0)
                        worker_stats['consecutive_moves'] += consecutive_count
                        
                        # Track phase distribution
                        for sample in samples:
                            if 'metadata' in sample:
                                phase = sample['metadata'].get('game_phase', 0)
                                worker_stats['phase_distribution'][phase] += 1
                        
                        # Track outcomes
                        final_result = meta.get('final_result', 0.0)
                        if abs(final_result) < 0.01:
                            worker_stats['outcomes']['draws'] += 1
                        elif final_result > 0:
                            worker_stats['outcomes']['wins'] += 1
                        else:
                            worker_stats['outcomes']['losses'] += 1
                
                # Periodic logging and memory management
                if (i + 1) % games_per_checkpoint == 0:
                    elapsed = time.time() - start_time
                    games_per_hour = (i + 1) / elapsed * 3600 if elapsed > 0 else 0
                    
                    logger.info(f"Worker {worker_id}: {i + 1}/{cfg.games_per_worker} games "
                              f"({games_per_hour:.1f} games/hour, {len(worker_samples)} samples)")
                    
                    # Memory cleanup
                    if wrapper.feature_cache:
                        cache_stats = wrapper.get_cache_stats()
                        if len(wrapper.feature_cache) > 5000:  # Clear large caches
                            wrapper.clear_cache()
                            logger.debug(f"Worker {worker_id}: Cleared cache "
                                       f"(hit rate: {cache_stats['hit_rate']:.2f})")
                    
                    # Force garbage collection
                    gc.collect()
                
            except Exception as e:
                logger.error(f"Worker {worker_id}: Game {i + 1} failed: {e}")
                worker_stats['errors'] += 1
                
                # Continue with next game unless too many errors
                if worker_stats['errors'] > cfg.games_per_worker * 0.1:  # >10% error rate
                    logger.error(f"Worker {worker_id}: Too many errors, stopping")
                    break
        
        # Final statistics
        total_time = time.time() - start_time
        final_cache_stats = wrapper.get_cache_stats() if hasattr(wrapper, 'get_cache_stats') else {}
        
        # Prepare results with enhanced statistics
        result_data = {
            'worker_id': worker_id,
            'samples': worker_samples,
            'statistics': {
                **worker_stats,
                'total_time_seconds': total_time,
                'games_per_hour': worker_stats['games_completed'] / total_time * 3600 if total_time > 0 else 0,
                'samples_per_game': worker_stats['samples_generated'] / max(1, worker_stats['games_completed']),
                'avg_game_length': np.mean(worker_stats['game_lengths']) if worker_stats['game_lengths'] else 0,
                'cache_stats': final_cache_stats,
            }
        }
        
        # Send results back
        output_queue.put(result_data)
        
        logger.info(f"Worker {worker_id} completed: {worker_stats['games_completed']} games, "
                   f"{len(worker_samples)} samples in {total_time:.1f}s")
        
    except Exception as e:
        logger.error(f"Worker {worker_id} failed with error: {e}")
        import traceback
        traceback.print_exc()
        
        # Send error result
        output_queue.put({
            'worker_id': worker_id,
            'samples': [],
            'statistics': {'error': str(e)},
            'failed': True
        })


def run_parallel_selfplay(model_path: Optional[str], cfg: SelfPlayConfig) -> List[Dict[str, Any]]:
    """
    Run self-play in parallel with KataGo-style optimizations and monitoring.
    
    Features:
    - Intelligent device allocation across GPUs
    - Enhanced worker monitoring and statistics
    - Robust error handling and recovery
    - Comprehensive performance metrics
    """
    import torch
    import time
    
    start_time = time.time()
    num_workers = cfg.num_workers
    games_per_worker = cfg.num_games // num_workers
    remainder = cfg.num_games % num_workers
    
    logger.info(f"Starting parallel self-play: {cfg.num_games} games across {num_workers} workers")
    
    # Intelligent device allocation optimized for MCTS efficiency
    if torch.cuda.is_available():
        num_gpus = torch.cuda.device_count()
        # For MCTS self-play, CPU is often more efficient due to tree traversal nature
        # Use mixed CPU/GPU allocation: more CPU workers, fewer GPU workers for NN inference
        devices = []
        gpu_workers = min(num_gpus, max(1, num_workers // 4))  # 25% GPU workers
        cpu_workers = num_workers - gpu_workers
        
        for i in range(num_workers):
            if i < gpu_workers:
                devices.append(f"cuda:{i % num_gpus}")
            else:
                devices.append("cpu")
        
        logger.info(f"Optimized device allocation: {num_gpus} GPUs available")
        logger.info(f"  CPU workers: {cpu_workers} (better for MCTS tree search)")
        logger.info(f"  GPU workers: {gpu_workers} (for neural network inference)")
    else:
        devices = ["cpu"] * num_workers
        logger.info(f"Using CPU-only execution with {num_workers} workers")
    
    # Create output queue with proper size
    output_queue = mp.Queue(maxsize=num_workers * 2)
    
    # Start worker processes with enhanced configuration
    processes = []
    for worker_id in range(num_workers):
        # Distribute remainder games evenly
        worker_games = games_per_worker + (1 if worker_id < remainder else 0)
        
        # Create worker-specific config
        worker_cfg = SelfPlayConfig(
            num_games=worker_games,
            games_per_worker=worker_games,
            max_moves=cfg.max_moves,
            mcts_sims=cfg.mcts_sims,
            temperature=cfg.temperature,
            temp_decay_moves=cfg.temp_decay_moves,
            cpuct=cfg.cpuct,
        )
        
        # Start worker process
        p = mp.Process(
            target=worker_selfplay, 
            args=(worker_id, model_path, worker_cfg, output_queue, devices[worker_id]),
            name=f"SelfPlayWorker-{worker_id}"
        )
        p.start()
        processes.append(p)
        
        logger.debug(f"Started worker {worker_id} on {devices[worker_id]} "
                    f"({worker_games} games)")
    
    # Collect results with enhanced monitoring
    all_samples = []
    worker_statistics = []
    completed_workers = 0
    
    while completed_workers < num_workers:
        try:
            # Get result with timeout
            result_data = output_queue.get(timeout=300)  # 5 minute timeout
            
            worker_id = result_data['worker_id']
            samples = result_data['samples']
            stats = result_data['statistics']
            
            if result_data.get('failed', False):
                logger.error(f"Worker {worker_id} failed: {stats.get('error', 'Unknown error')}")
            else:
                all_samples.extend(samples)
                worker_statistics.append(stats)
                
                # Log worker completion with statistics
                games_completed = stats.get('games_completed', 0)
                samples_generated = len(samples)
                games_per_hour = stats.get('games_per_hour', 0)
                avg_game_length = stats.get('avg_game_length', 0)
                
                logger.info(f"Worker {worker_id} completed: {games_completed} games, "
                           f"{samples_generated} samples ({games_per_hour:.1f} games/hour, "
                           f"avg length: {avg_game_length:.1f})")
                
                # Log Nine Men's Morris specific statistics
                consecutive_moves = stats.get('consecutive_moves', 0)
                phase_dist = stats.get('phase_distribution', {})
                if consecutive_moves > 0:
                    logger.info(f"  Consecutive moves detected: {consecutive_moves} "
                               f"(phase distribution: {phase_dist})")
            
            completed_workers += 1
            
        except mp.TimeoutError:
            logger.warning("Timeout waiting for worker results, checking process status...")
            # Check if any processes are still alive
            alive_processes = [p for p in processes if p.is_alive()]
            if not alive_processes:
                logger.warning("All processes finished but queue empty, continuing...")
                break
        except Exception as e:
            logger.error(f"Error collecting worker results: {e}")
            break
    
    # Wait for all processes to complete with timeout
    for i, p in enumerate(processes):
        try:
            p.join(timeout=60)  # 1 minute timeout per process
            if p.is_alive():
                logger.warning(f"Worker process {i} still alive after timeout, terminating...")
                p.terminate()
                p.join(timeout=10)
                if p.is_alive():
                    logger.error(f"Worker process {i} could not be terminated, killing...")
                    p.kill()
        except Exception as e:
            logger.error(f"Error joining worker process {i}: {e}")
    
    # Aggregate and log final statistics
    total_time = time.time() - start_time
    
    if worker_statistics:
        aggregate_stats = {
            'total_games': sum(s.get('games_completed', 0) for s in worker_statistics),
            'total_samples': len(all_samples),
            'total_time_hours': total_time / 3600,
            'games_per_hour': sum(s.get('games_per_hour', 0) for s in worker_statistics),
            'avg_game_length': np.mean([s.get('avg_game_length', 0) for s in worker_statistics if s.get('avg_game_length', 0) > 0]),
            'total_consecutive_moves': sum(s.get('consecutive_moves', 0) for s in worker_statistics),
            'total_errors': sum(s.get('errors', 0) for s in worker_statistics),
            'phase_distribution': {},
            'outcome_distribution': {'wins': 0, 'losses': 0, 'draws': 0},
        }
        
        # Aggregate phase distribution
        for stats in worker_statistics:
            phase_dist = stats.get('phase_distribution', {})
            for phase, count in phase_dist.items():
                aggregate_stats['phase_distribution'][phase] = aggregate_stats['phase_distribution'].get(phase, 0) + count
        
        # Aggregate outcomes
        for stats in worker_statistics:
            outcomes = stats.get('outcomes', {})
            for outcome, count in outcomes.items():
                aggregate_stats['outcome_distribution'][outcome] += count
        
        logger.info("Parallel self-play completed:")
        logger.info(f"  Total games: {aggregate_stats['total_games']}")
        logger.info(f"  Total samples: {aggregate_stats['total_samples']}")
        logger.info(f"  Time: {aggregate_stats['total_time_hours']:.2f} hours")
        logger.info(f"  Performance: {aggregate_stats['games_per_hour']:.1f} games/hour")
        logger.info(f"  Avg game length: {aggregate_stats['avg_game_length']:.1f} moves")
        logger.info(f"  Consecutive moves: {aggregate_stats['total_consecutive_moves']}")
        logger.info(f"  Errors: {aggregate_stats['total_errors']}")
        
        # Log Nine Men's Morris specific statistics
        if aggregate_stats['phase_distribution']:
            logger.info(f"  Phase distribution: {aggregate_stats['phase_distribution']}")
        if any(aggregate_stats['outcome_distribution'].values()):
            outcomes = aggregate_stats['outcome_distribution']
            total_outcomes = sum(outcomes.values())
            if total_outcomes > 0:
                logger.info(f"  Outcomes: W={outcomes['wins']}/{total_outcomes} "
                           f"({outcomes['wins']/total_outcomes*100:.1f}%), "
                           f"L={outcomes['losses']}/{total_outcomes} "
                           f"({outcomes['losses']/total_outcomes*100:.1f}%), "
                           f"D={outcomes['draws']}/{total_outcomes} "
                           f"({outcomes['draws']/total_outcomes*100:.1f}%)")
    
    else:
        logger.warning("No worker statistics available")
    
    logger.info(f"Parallel self-play complete: {len(all_samples)} total samples")
    return all_samples


def main():
    parser = argparse.ArgumentParser(description='Generate Katamill self-play data')
    parser.add_argument('--model', type=str, help='Model checkpoint path (optional for random play)')
    parser.add_argument('--output', type=str, required=True, help='Output data file path')
    parser.add_argument('--games', type=int, default=100, help='Number of games to play')
    parser.add_argument('--mcts-sims', type=int, default=400, help='MCTS simulations per move')
    parser.add_argument('--max-moves', type=int, default=200, help='Maximum moves per game')
    parser.add_argument('--temperature', type=float, default=1.0, help='Temperature for move selection')
    parser.add_argument('--temp-moves', type=int, default=20, help='Moves to apply temperature')
    parser.add_argument('--cpuct', type=float, default=1.0, help='MCTS exploration constant')
    parser.add_argument('--workers', type=int, default=1, help='Number of parallel workers')
    parser.add_argument('--device', type=str, default='auto', help='Device (cpu/cuda/auto)')
    
    args = parser.parse_args()
    
    # Configure
    cfg = SelfPlayConfig(
        num_games=args.games,
        max_moves=args.max_moves,
        mcts_sims=args.mcts_sims,
        temperature=args.temperature,
        temp_decay_moves=args.temp_moves,
        cpuct=args.cpuct,
        num_workers=args.workers,
    )
    
    # Run self-play
    if args.workers > 1:
        # Parallel execution
        samples = run_parallel_selfplay(args.model, cfg)
    else:
        # Single process execution
        import torch
        try:
            from .config import default_net_config
        except ImportError:
            from config import default_net_config
        
        # Load model
        net = KatamillNet(default_net_config())
        if args.model and os.path.exists(args.model):
            checkpoint = torch.load(args.model, map_location='cpu')
            if 'model_state_dict' in checkpoint:
                net.load_state_dict(checkpoint['model_state_dict'])
            else:
                net.load_state_dict(checkpoint)
            logger.info(f"Loaded model from {args.model}")
        else:
            logger.info("Using random initialization")
        
        device = args.device
        if device == 'auto':
            device = 'cuda' if torch.cuda.is_available() else 'cpu'
        
        wrapper = KatamillWrapper(net, device=device)
        samples = run_selfplay(wrapper, cfg)
    
    # Save data
    save_selfplay_data(samples, args.output)
    
    # Print statistics
    values = [s['z'][0] for s in samples]
    print(f"\nDataset statistics:")
    print(f"Total samples: {len(samples)}")
    print(f"White wins: {sum(1 for v in values if v > 0.5)} ({sum(1 for v in values if v > 0.5)/len(values)*100:.1f}%)")
    print(f"Black wins: {sum(1 for v in values if v < -0.5)} ({sum(1 for v in values if v < -0.5)/len(values)*100:.1f}%)")
    print(f"Draws: {sum(1 for v in values if abs(v) < 0.5)} ({sum(1 for v in values if abs(v) < 0.5)/len(values)*100:.1f}%)")


if __name__ == '__main__':
    main()


