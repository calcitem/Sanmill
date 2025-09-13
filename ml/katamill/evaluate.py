#!/usr/bin/env python3
"""
Evaluation utilities for analyzing Katamill model predictions.

Provides tools to visualize and understand model behavior.
"""

import argparse
import logging
import os
import sys
import time
from typing import Dict, List, Optional, Tuple
import numpy as np
import torch

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

try:
    import matplotlib.pyplot as plt
    import seaborn as sns
    HAS_PLOTTING = True
except ImportError:
    HAS_PLOTTING = False

# Import modules with fallback
try:
    from .config import default_net_config
    from .neural_network import KatamillNet, KatamillWrapper
    from .features import extract_features
    from .heuristics import build_auxiliary_targets
except ImportError:
    from config import default_net_config
    from neural_network import KatamillNet, KatamillWrapper
    from features import extract_features
    from heuristics import build_auxiliary_targets

try:
    from ml.game.Game import Game
    from ml.game.engine_adapter import move_to_engine_token
    from ml.game.standard_rules import xy_to_coord
except:
    try:
        from game.Game import Game
        from game.engine_adapter import move_to_engine_token
        from game.standard_rules import xy_to_coord
    except:
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game
        from engine_adapter import move_to_engine_token
        from standard_rules import xy_to_coord

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def visualize_policy(board, policy_probs: np.ndarray, top_k: int = 10):
    """Visualize policy predictions on the board.
    
    Args:
        board: Current board state
        policy_probs: Policy probabilities from model
        top_k: Number of top moves to show
    """
    game = Game()
    valids = game.getValidMoves(board, 1)  # Assuming canonical form
    
    # Get top moves
    valid_probs = policy_probs * valids
    top_actions = np.argsort(valid_probs)[-top_k:][::-1]
    
    print("\nTop predicted moves:")
    for i, action in enumerate(top_actions):
        if valid_probs[action] > 0:
            try:
                move = board.get_move_from_action(action)
                if board.period == 3:
                    notation = 'x' + move_to_engine_token(move[:2])
                else:
                    notation = move_to_engine_token(move)
                print(f"{i+1}. {notation}: {valid_probs[action]:.3f}")
            except:
                print(f"{i+1}. Action {action}: {valid_probs[action]:.3f}")


def visualize_ownership(ownership: np.ndarray, board):
    """Visualize ownership predictions.
    
    Args:
        ownership: Ownership values for 24 valid positions
        board: Current board state
    """
    if not HAS_PLOTTING:
        logger.warning("Matplotlib/seaborn not available for visualization")
        return
    
    # Create 7x7 visualization
    ownership_map = np.zeros((7, 7))
    
    # Map ownership to valid positions
    valid_positions = [(x, y) for x in range(7) for y in range(7) if board.allowed_places[x][y]]
    for i, (x, y) in enumerate(valid_positions):
        if i < len(ownership):
            ownership_map[y, x] = ownership[i]  # Note: y,x for visualization
    
    # Plot heatmap
    plt.figure(figsize=(8, 8))
    mask = ~board.allowed_places.T  # Transpose for visualization
    sns.heatmap(ownership_map, cmap='RdBu_r', center=0, vmin=-1, vmax=1,
                mask=mask, square=True, cbar_kws={'label': 'Ownership'})
    
    # Add coordinate labels
    coords = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
    plt.xticks(np.arange(7) + 0.5, coords)
    plt.yticks(np.arange(7) + 0.5, reversed(range(1, 8)))
    plt.title('Ownership Prediction (Red=White, Blue=Black)')
    plt.tight_layout()
    plt.show()


def analyze_position(model_path: str, board=None, current_player: int = 1):
    """
    Comprehensive position analysis with KataGo-inspired insights.
    
    Features:
    - Multi-head prediction analysis
    - MCTS search tree visualization
    - Nine Men's Morris specific tactical analysis
    - Confidence estimation and uncertainty quantification
    
    Args:
        model_path: Path to model checkpoint
        board: Board position to analyze (None for initial position)
        current_player: Current player (1 or -1)
    """
    # Load model
    wrapper = load_model(model_path)
    model = wrapper.net
    model.eval()
    
    # Get board
    game = Game()
    if board is None:
        board = game.getInitBoard()
    
    # Get comprehensive predictions
    predictions = wrapper.predict_full(board, current_player)
    
    # Display board with enhanced information
    print("\n" + "="*60)
    print("POSITION ANALYSIS")
    print("="*60)
    Game.display(board)
    
    # Game state information
    phase_names = {0: "Placing", 1: "Moving", 2: "Flying", 3: "Removal"}
    phase = getattr(board, 'period', 0)
    print(f"\nGame Phase: {phase_names.get(phase, 'Unknown')} (period {phase})")
    print(f"Current Player: {'White' if current_player == 1 else 'Black'}")
    print(f"Move Counter: {getattr(board, 'move_counter', 0)}")
    
    # Piece count analysis
    white_on = board.count(1)
    black_on = board.count(-1)
    print(f"Pieces on Board: White={white_on}, Black={black_on}")
    
    if phase == 0:  # Placing phase
        white_in_hand = 9 - (board.put_pieces // 2)
        black_in_hand = 9 - ((board.put_pieces + 1) // 2)
        print(f"Pieces in Hand: White={white_in_hand}, Black={black_in_hand}")
    
    # Model predictions with confidence analysis
    print(f"\n{'='*30} MODEL PREDICTIONS {'='*30}")
    print(f"Value: {predictions['value']:+.3f} (from current player's perspective)")
    print(f"Score: {predictions['score']:+.3f} (heuristic evaluation)")
    
    # Confidence estimation using multiple forward passes with dropout
    confidence_analysis = _estimate_prediction_confidence(wrapper, board, current_player)
    print(f"Prediction Confidence: {confidence_analysis['confidence']:.2f}")
    print(f"Value Uncertainty: ±{confidence_analysis['value_std']:.3f}")
    
    # Policy analysis with move categorization
    print(f"\n{'='*30} POLICY ANALYSIS {'='*30}")
    _analyze_policy_distribution(board, predictions['policy'], current_player)
    
    # Ownership analysis (if pieces are on board)
    if board.put_pieces > 0:
        print(f"\n{'='*30} OWNERSHIP ANALYSIS {'='*30}")
        _analyze_ownership_predictions(board, predictions['ownership'])
    
    # Tactical analysis specific to Nine Men's Morris
    print(f"\n{'='*30} TACTICAL ANALYSIS {'='*30}")
    _analyze_tactical_features(board, current_player)
    
    # MCTS search analysis for deeper insights
    print(f"\n{'='*30} SEARCH ANALYSIS {'='*30}")
    _analyze_mcts_search(wrapper, board, current_player)


def _estimate_prediction_confidence(wrapper: KatamillWrapper, board, current_player: int, 
                                   num_samples: int = 10) -> dict:
    """
    Estimate prediction confidence using Monte Carlo dropout.
    
    This technique, inspired by KataGo's uncertainty estimation,
    provides insights into model confidence for different positions.
    """
    if not hasattr(wrapper.net, 'training'):
        return {'confidence': 1.0, 'value_std': 0.0}
    
    # Enable dropout for uncertainty estimation
    wrapper.net.train()
    
    values = []
    policies = []
    
    with torch.no_grad():
        for _ in range(num_samples):
            # Get prediction with dropout enabled
            pred = wrapper.predict_full(board, current_player)
            values.append(pred['value'])
            policies.append(pred['policy'])
    
    # Restore evaluation mode
    wrapper.net.eval()
    
    # Calculate statistics
    value_mean = np.mean(values)
    value_std = np.std(values)
    
    # Policy consistency (average KL divergence from mean policy)
    mean_policy = np.mean(policies, axis=0)
    policy_divergences = []
    for policy in policies:
        # Add small epsilon to prevent log(0)
        epsilon = 1e-8
        kl_div = np.sum(policy * np.log((policy + epsilon) / (mean_policy + epsilon)))
        policy_divergences.append(kl_div)
    
    policy_consistency = 1.0 / (1.0 + np.mean(policy_divergences))
    
    # Overall confidence combining value and policy consistency
    confidence = policy_consistency * (1.0 - min(value_std, 1.0))
    
    return {
        'confidence': confidence,
        'value_mean': value_mean,
        'value_std': value_std,
        'policy_consistency': policy_consistency
    }


def _analyze_policy_distribution(board, policy: np.ndarray, current_player: int):
    """
    Analyze policy distribution with Nine Men's Morris specific insights.
    """
    try:
        from ml.game.Game import Game
        from ml.game.engine_adapter import move_to_engine_token
        
        game = Game()
        valid_moves = game.getValidMoves(board, current_player)
        
        # Get valid actions and their probabilities
        valid_actions = [(i, policy[i]) for i in range(len(policy)) if valid_moves[i] == 1]
        valid_actions.sort(key=lambda x: x[1], reverse=True)
        
        # Categorize moves by type
        move_categories = {'place': [], 'move': [], 'remove': []}
        
        for action, prob in valid_actions[:10]:  # Top 10 moves
            try:
                move = board.get_move_from_action(action)
                
                if board.period == 3:  # Removal phase
                    notation = 'x' + move_to_engine_token(move[:2])
                    move_categories['remove'].append((notation, prob))
                elif len(move) == 2 or (len(move) == 4 and move[0] == move[2] and move[1] == move[3]):
                    # Placing
                    notation = move_to_engine_token(move[:2])
                    move_categories['place'].append((notation, prob))
                else:
                    # Moving
                    notation = move_to_engine_token(move)
                    move_categories['move'].append((notation, prob))
                    
            except Exception:
                move_categories['move'].append((f"action_{action}", prob))
        
        # Display categorized moves
        for category, moves in move_categories.items():
            if moves:
                print(f"\nTop {category.upper()} moves:")
                for i, (notation, prob) in enumerate(moves[:5]):
                    print(f"  {i+1}. {notation}: {prob:.3f}")
        
        # Policy entropy analysis
        valid_probs = policy[valid_moves == 1]
        entropy = -np.sum(valid_probs * np.log(valid_probs + 1e-8))
        max_entropy = np.log(len(valid_probs))
        normalized_entropy = entropy / max_entropy if max_entropy > 0 else 0
        
        print(f"\nPolicy Statistics:")
        print(f"  Entropy: {entropy:.3f} (normalized: {normalized_entropy:.3f})")
        print(f"  Top move probability: {np.max(valid_probs):.3f}")
        print(f"  Valid moves: {len(valid_probs)}")
        
    except Exception as e:
        logger.warning(f"Policy analysis failed: {e}")
        # Fallback to simple display
        valid_indices = np.where(policy > 0.01)[0]  # Show moves with >1% probability
        print(f"Top moves: {valid_indices[:10].tolist()}")


def _analyze_ownership_predictions(board, ownership: np.ndarray):
    """
    Analyze ownership predictions with Nine Men's Morris context.
    """
    try:
        from ml.game.standard_rules import xy_to_coord
        
        valid_positions = [(x, y) for x in range(7) for y in range(7) if board.allowed_places[x][y]]
        
        # Categorize ownership predictions
        strong_white = []
        strong_black = []
        contested = []
        
        for i, (x, y) in enumerate(valid_positions):
            if i < len(ownership):
                coord = xy_to_coord.get((x, y), f"({x},{y})")
                own_value = ownership[i]
                
                if own_value > 0.5:
                    strong_white.append((coord, own_value))
                elif own_value < -0.5:
                    strong_black.append((coord, own_value))
                elif abs(own_value) > 0.1:
                    contested.append((coord, own_value))
        
        # Display ownership categories
        if strong_white:
            print(f"Strong White Control: {', '.join([f'{c}({v:+.2f})' for c, v in strong_white])}")
        if strong_black:
            print(f"Strong Black Control: {', '.join([f'{c}({v:+.2f})' for c, v in strong_black])}")
        if contested:
            print(f"Contested Positions: {', '.join([f'{c}({v:+.2f})' for c, v in contested])}")
        
        # Overall ownership statistics
        white_controlled = sum(1 for x in ownership if x > 0.3)
        black_controlled = sum(1 for x in ownership if x < -0.3)
        neutral = len(ownership) - white_controlled - black_controlled
        
        print(f"\nOwnership Summary:")
        print(f"  White controlled: {white_controlled}/24 ({white_controlled/24*100:.1f}%)")
        print(f"  Black controlled: {black_controlled}/24 ({black_controlled/24*100:.1f}%)")
        print(f"  Neutral/Contested: {neutral}/24 ({neutral/24*100:.1f}%)")
        
    except Exception as e:
        logger.warning(f"Ownership analysis failed: {e}")


def _analyze_tactical_features(board, current_player: int):
    """
    Analyze tactical features specific to Nine Men's Morris.
    """
    try:
        from ml.game.standard_rules import mills, coord_to_xy
        
        pieces = np.array(board.pieces, dtype=np.int8)
        
        # Mill analysis
        formed_mills = {'white': 0, 'black': 0}
        potential_mills = {'white': 0, 'black': 0}
        blocked_mills = {'white': 0, 'black': 0}
        
        for a, b, c in mills:
            ax, ay = coord_to_xy[a]
            bx, by = coord_to_xy[b]
            cx, cy = coord_to_xy[c]
            line = [pieces[ax, ay], pieces[bx, by], pieces[cx, cy]]
            
            if line.count(1) == 3:
                formed_mills['white'] += 1
            elif line.count(-1) == 3:
                formed_mills['black'] += 1
            elif line.count(1) == 2 and line.count(0) == 1:
                potential_mills['white'] += 1
            elif line.count(-1) == 2 and line.count(0) == 1:
                potential_mills['black'] += 1
            elif line.count(1) == 2 and line.count(-1) == 1:
                blocked_mills['white'] += 1
            elif line.count(-1) == 2 and line.count(1) == 1:
                blocked_mills['black'] += 1
        
        print(f"Mills Analysis:")
        print(f"  Formed - White: {formed_mills['white']}, Black: {formed_mills['black']}")
        print(f"  Potential - White: {potential_mills['white']}, Black: {potential_mills['black']}")
        print(f"  Blocked - White: {blocked_mills['white']}, Black: {blocked_mills['black']}")
        
        # Mobility analysis
        white_pieces = np.sum(pieces == 1)
        black_pieces = np.sum(pieces == -1)
        
        # Flying phase detection
        white_flying = white_pieces == 3
        black_flying = black_pieces == 3
        
        if white_flying or black_flying:
            print(f"Flying Phase: White={'Yes' if white_flying else 'No'}, "
                  f"Black={'Yes' if black_flying else 'No'}")
        
        # Game phase specific analysis
        phase = getattr(board, 'period', 0)
        if phase == 0:
            remaining_placements = 18 - board.put_pieces
            print(f"Remaining pieces to place: {remaining_placements}")
        elif phase == 3:
            print("Removal phase - mill was formed, piece must be removed")
        
        # Strategic assessment
        material_balance = white_pieces - black_pieces
        print(f"\nStrategic Assessment:")
        print(f"  Material balance: {material_balance:+d} (positive favors White)")
        
        if abs(material_balance) >= 2:
            leader = "White" if material_balance > 0 else "Black"
            print(f"  Material advantage: {leader} (+{abs(material_balance)} pieces)")
        
    except Exception as e:
        logger.warning(f"Tactical analysis failed: {e}")


def _analyze_mcts_search(wrapper: KatamillWrapper, board, current_player: int, 
                        search_depth: int = 200):
    """
    Analyze MCTS search tree to understand model's decision-making process.
    
    This provides insights similar to KataGo's analysis mode, showing:
    - Principal variation
    - Alternative lines
    - Value estimates at different depths
    - Search statistics
    """
    try:
        from .mcts import MCTS
        
        game = Game()
        
        # Create MCTS optimized for Nine Men's Morris analysis with consecutive move awareness
        mcts = MCTS(game, wrapper, {
            'cpuct': 1.9,  # Balanced exploration for Nine Men's Morris analysis
            'num_simulations': max(search_depth, 800),  # Ensure sufficient depth
            'dirichlet_alpha': 0.15,
            'dirichlet_epsilon': 0.0,  # No noise for pure analysis
            'use_virtual_loss': True,  # Better search efficiency
            'progressive_widening': True,
            'use_transpositions': True,  # Reuse computation
            'max_transposition_size': 200000,  # Large table for analysis
            'fpu_reduction': 0.2,  # Strong FPU for accurate evaluation
            'fpu_at_root': True,
            'consecutive_move_bonus': 0.01,  # Minimal bonus (analysis should be objective)
            'max_search_depth': 200,
            # Phase-specific analysis parameters
            'removal_phase_exploration': 0.7,  # Focus on best captures in analysis
            'flying_phase_simulations_multiplier': 2.5  # Deep analysis in flying phase
        })
        
        # Run search
        print(f"Running MCTS analysis ({search_depth} simulations)...")
        start_time = time.time()
        probs = mcts.get_action_probabilities(board, current_player, temperature=0.0)
        search_time = time.time() - start_time
        
        # Get search statistics
        search_stats = mcts.get_search_statistics()
        
        print(f"Search completed in {search_time:.2f}s")
        print(f"Search Statistics:")
        print(f"  Simulations: {search_stats['total_simulations']}")
        print(f"  Terminal nodes: {search_stats['terminal_nodes_reached']}")
        print(f"  Consecutive moves: {search_stats['consecutive_moves_found']}")
        
        # Show principal variation (most visited path)
        valid_moves = game.getValidMoves(board, current_player)
        valid_actions = [(i, probs[i]) for i in range(len(probs)) if valid_moves[i] == 1]
        valid_actions.sort(key=lambda x: x[1], reverse=True)
        
        print(f"\nPrincipal Variation (top moves):")
        for i, (action, prob) in enumerate(valid_actions[:5]):
            try:
                move = board.get_move_from_action(action)
                notation = _format_move_notation(move, board.period)
                print(f"  {i+1}. {notation}: {prob:.3f}")
                
                # Show what happens after this move
                if i == 0:  # Only for best move
                    try:
                        next_board, next_player = game.getNextState(board, current_player, action)
                        next_pred = wrapper.predict_full(next_board, next_player)
                        print(f"     After this move: value={next_pred['value']:+.3f}")
                    except Exception:
                        pass
                        
            except Exception:
                print(f"  {i+1}. Action {action}: {prob:.3f}")
        
    except Exception as e:
        logger.warning(f"MCTS search analysis failed: {e}")


def _format_move_notation(move, phase: int) -> str:
    """Format move for display based on game phase."""
    try:
        from ml.game.engine_adapter import move_to_engine_token
        
        if phase == 3:  # Removal phase
            return 'x' + move_to_engine_token(move[:2])
        elif len(move) == 2:  # Placing
            return move_to_engine_token(move)
        else:  # Moving
            return move_to_engine_token(move)
    except Exception:
        return str(move)


def compare_with_heuristics(model_path: str, board=None, current_player: int = 1):
    """Compare model predictions with heuristic targets.
    
    Args:
        model_path: Path to model checkpoint
        board: Board position
        current_player: Current player
    """
    # Get model predictions
    wrapper = load_model(model_path)
    model = wrapper.net
    model.eval()
    
    game = Game()
    if board is None:
        board = game.getInitBoard()
    
    # Model predictions
    features = extract_features(board, current_player)
    features_tensor = torch.from_numpy(features).unsqueeze(0).to(wrapper.device)
    
    with torch.no_grad():
        _, value_pred, score_pred, ownership_pred = model(features_tensor)
        value_pred = value_pred.squeeze().cpu().item()
        score_pred = score_pred.squeeze().cpu().item()
        ownership_pred = ownership_pred.squeeze(0).cpu().numpy()
    
    # Heuristic targets
    targets = build_auxiliary_targets(board, current_player)
    
    print("\nComparison of predictions vs heuristics:")
    print(f"Score - Model: {score_pred:+.3f}, Heuristic: {targets['score'][0]:+.3f}")
    
    # Ownership comparison
    ownership_diff = ownership_pred - targets['ownership']
    ownership_mae = np.mean(np.abs(ownership_diff))
    print(f"Ownership MAE: {ownership_mae:.3f}")
    
    # Find positions with largest differences
    valid_positions = [(x, y) for x in range(7) for y in range(7) if board.allowed_places[x][y]]
    diffs = [(i, abs(ownership_diff[i])) for i in range(len(ownership_diff))]
    diffs.sort(key=lambda x: x[1], reverse=True)
    
    print("\nLargest ownership prediction differences:")
    for i, diff in diffs[:5]:
        if i < len(valid_positions):
            x, y = valid_positions[i]
            coord = xy_to_coord.get((x, y), f"({x},{y})")
            print(f"  {coord}: Model={ownership_pred[i]:+.3f}, "
                  f"Heuristic={targets['ownership'][i]:+.3f}, Diff={ownership_diff[i]:+.3f}")


def load_model(model_path: str) -> KatamillWrapper:
    """
    Load model from checkpoint with robust error handling and auto-detection.
    
    Args:
        model_path: Path to model checkpoint file
        
    Returns:
        KatamillWrapper: Loaded model wrapper ready for inference
        
    Raises:
        FileNotFoundError: If model file doesn't exist
        ValueError: If model checkpoint is corrupted or incompatible
    """
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model checkpoint not found: {model_path}")
    
    try:
        # Load checkpoint with proper error handling
        checkpoint = torch.load(model_path, map_location='cpu')
        
        # Auto-detect network configuration from checkpoint
        net_config = default_net_config()
        if 'net_config' in checkpoint:
            # Load saved network config if available
            saved_config = checkpoint['net_config']
            for key, value in saved_config.items():
                if hasattr(net_config, key):
                    setattr(net_config, key, value)
            logger.info(f"Auto-detected network config: {net_config.num_filters} filters, {net_config.num_residual_blocks} blocks")
        
        # Create network with detected config
        net = KatamillNet(net_config)
        
        # Load model state with adaptive compatibility
        if 'model_state_dict' in checkpoint:
            state_dict = checkpoint['model_state_dict']
        elif 'state_dict' in checkpoint:
            state_dict = checkpoint['state_dict']
        else:
            state_dict = checkpoint
        
        # Load with strict=True for exact matching (after auto-detection)
        try:
            net.load_state_dict(state_dict, strict=True)
            logger.info(f"Successfully loaded model with exact architecture match")
        except RuntimeError as e:
            # If strict loading fails, it means config detection failed
            logger.error(f"Architecture mismatch even after auto-detection: {str(e)[:200]}...")
            logger.error("This indicates the checkpoint may be corrupted or from incompatible version")
            raise ValueError(f"Cannot load model due to architecture mismatch: {model_path}")
        
        # Setup device
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        wrapper = KatamillWrapper(net, device=device)
        
        logger.info(f"Successfully loaded model from {model_path} on {device} (exact matching)")
        
        # Log model information if available
        if 'epoch' in checkpoint:
            logger.info(f"  Checkpoint from epoch: {checkpoint['epoch']}")
        if 'losses' in checkpoint:
            losses = checkpoint['losses']
            if isinstance(losses, dict) and 'total' in losses:
                logger.info(f"  Training loss: {losses['total']:.4f}")
        
        return wrapper
        
    except Exception as e:
        raise ValueError(f"Failed to load model from {model_path}: {str(e)}")


def self_play_analysis(model_path: str, num_games: int = 10):
    """Analyze model performance in self-play.
    
    Args:
        model_path: Path to model checkpoint
        num_games: Number of games to play
    """
    try:
        from .mcts import MCTS
    except ImportError:
        from mcts import MCTS
    
    wrapper = load_model(model_path)
    game = Game()
    
    results = {'white_wins': 0, 'black_wins': 0, 'draws': 0}
    game_lengths = []
    
    for game_idx in range(num_games):
        board = game.getInitBoard()
        current_player = 1
        moves = 0
        
        # Create fresh MCTS for each game optimized for Nine Men's Morris
        mcts = MCTS(game, wrapper, {
            'cpuct': 1.8,  # Balanced exploration for Nine Men's Morris
            'num_simulations': 800,  # More simulations for quality play
            'dirichlet_alpha': 0.15,  # Moderate noise for self-play
            'dirichlet_epsilon': 0.08,  # Low noise for quality games
            'use_virtual_loss': True,
            'progressive_widening': True,
            'use_transpositions': True,
            'fpu_reduction': 0.25,
            'fpu_at_root': True,
            'consecutive_move_bonus': 0.02,  # Small bonus for consecutive moves
            # Phase-specific parameters
            'removal_phase_exploration': 0.8,  # Less exploration in removal (often forced)
            'flying_phase_simulations_multiplier': 2.0  # More search in flying phase
        })
        
        while moves < 200:
            # Get move
            probs = mcts.get_action_probabilities(board, current_player, temperature=0.0)
            action = int(np.argmax(probs))
            
            # Apply move
            board, current_player = game.getNextState(board, current_player, action)
            moves += 1
            
            # Check game end
            ended = game.getGameEnded(board, current_player)
            if ended != 0:
                game_lengths.append(moves)
                if abs(ended) < 0.01:
                    results['draws'] += 1
                elif (ended > 0 and current_player == 1) or (ended < 0 and current_player == -1):
                    results['white_wins'] += 1
                else:
                    results['black_wins'] += 1
                break
        
        if moves >= 200:
            results['draws'] += 1
            game_lengths.append(moves)
        
        logger.info(f"Game {game_idx + 1}: {moves} moves")
    
    # Print statistics
    print(f"\nSelf-play results over {num_games} games:")
    print(f"White wins: {results['white_wins']} ({results['white_wins']/num_games*100:.1f}%)")
    print(f"Black wins: {results['black_wins']} ({results['black_wins']/num_games*100:.1f}%)")
    print(f"Draws: {results['draws']} ({results['draws']/num_games*100:.1f}%)")
    print(f"Average game length: {np.mean(game_lengths):.1f} moves")


def main():
    parser = argparse.ArgumentParser(description='Evaluate Katamill model')
    parser.add_argument('--model', type=str, required=True, help='Model checkpoint path')
    parser.add_argument('--command', choices=['analyze', 'compare', 'selfplay'],
                       default='analyze', help='Evaluation command')
    parser.add_argument('--fen', type=str, help='FEN string for position to analyze')
    parser.add_argument('--num-games', type=int, default=10,
                       help='Number of self-play games')
    
    args = parser.parse_args()
    
    # Load position from FEN if provided
    board = None
    if args.fen:
        # TODO: Implement FEN parsing for Nine Men's Morris
        logger.warning("FEN parsing not yet implemented, using initial position")
    
    if args.command == 'analyze':
        analyze_position(args.model, board)
    elif args.command == 'compare':
        compare_with_heuristics(args.model, board)
    elif args.command == 'selfplay':
        self_play_analysis(args.model, args.num_games)


if __name__ == '__main__':
    main()
