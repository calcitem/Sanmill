"""
Advanced MCTS implementation for Nine Men's Morris, inspired by KataGo's improvements.

This module provides a sophisticated Monte Carlo Tree Search implementation
specifically optimized for Nine Men's Morris, with special handling for:
- Consecutive moves after captures (removal phase)
- Proper value propagation for alternating/non-alternating turns
- KataGo-style search optimizations and virtual loss
- Improved node selection and expansion strategies
- Better handling of transpositions and game phases

Key improvements over standard MCTS:
- Proper handling of Nine Men's Morris consecutive move rules
- Advanced UCB selection with progressive widening
- Virtual loss for parallel search
- Improved backup strategies for non-alternating games
"""

import math
import numpy as np
from typing import Dict, Any, Optional, List, Set, Tuple
from copy import deepcopy
import logging
import threading
import time

logger = logging.getLogger(__name__)


class MCTSNode:
    """
    Advanced MCTS node with KataGo-inspired improvements for Nine Men's Morris.
    
    Features:
    - Proper handling of consecutive moves in Nine Men's Morris
    - Virtual loss for parallel search
    - Advanced UCB calculation with progressive widening
    - Transposition table support
    - Better value estimation with confidence intervals
    """
    
    def __init__(self, board, current_player: int, action: Optional[int] = None, 
                 parent: Optional['MCTSNode'] = None, prior_prob: float = 0.0,
                 move_number: int = 0):
        # Board state - use deepcopy to ensure independence
        self.board = deepcopy(board)
        self.current_player = current_player
        self.action = action  # Action that led to this node
        self.parent = parent
        self.prior_prob = prior_prob
        self.move_number = move_number  # Track move number for analysis
        
        # Visit statistics with virtual loss support
        self.visit_count = 0
        self.virtual_loss = 0  # For parallel search
        self.value_sum = 0.0
        self.squared_value_sum = 0.0  # For variance calculation
        
        # Children and expansion state
        self.children: Dict[int, 'MCTSNode'] = {}
        self.is_expanded = False
        self.is_terminal_node = None  # Cache terminal status
        
        # Nine Men's Morris specific: track if this was a consecutive move
        self.is_consecutive_move = False
        if parent is not None:
            self.is_consecutive_move = (parent.current_player == current_player)
        
        # Threading support for parallel search
        self._lock = threading.Lock()
        
        # Cache for expensive computations
        self._cached_ucb_scores = {}
        self._cache_valid = False
    
    def get_effective_visit_count(self) -> int:
        """Get visit count including virtual losses for parallel search."""
        return self.visit_count + self.virtual_loss
    
    def get_value(self) -> float:
        """Get average value with proper handling of virtual losses."""
        effective_visits = self.get_effective_visit_count()
        if effective_visits == 0:
            return 0.0
        return self.value_sum / effective_visits
    
    def get_value_variance(self) -> float:
        """Calculate value variance for confidence estimation."""
        if self.visit_count <= 1:
            return 1.0  # High variance for unvisited nodes
        
        try:
            mean_value = self.value_sum / self.visit_count
            mean_squared = self.squared_value_sum / self.visit_count
            variance = mean_squared - (mean_value ** 2)
            
            # Ensure numerical stability
            variance = max(0.0, min(variance, 100.0))  # Clamp to reasonable bounds
            return variance
        except (ZeroDivisionError, OverflowError):
            return 1.0  # Safe fallback
    
    def get_ucb_score(self, c_puct: float, parent_visit_count: int = None, fpu_reduction: float = 0.25) -> float:
        """
        Calculate UCB score with LC0-inspired improvements for stronger play.
        
        Key improvements:
        - First Play Urgency (FPU) reduction for better unvisited node handling
        - PUCT formula with proper normalization
        - Better handling of low-visit nodes
        - Improved exploration-exploitation balance
        """
        if parent_visit_count is None and self.parent:
            parent_visit_count = self.parent.get_effective_visit_count()
        
        effective_visits = self.get_effective_visit_count()
        
        # LC0-style First Play Urgency (FPU) for unvisited nodes
        if effective_visits == 0:
            if self.parent and self.parent.visit_count > 0:
                # Use parent's value with FPU reduction for better move ordering
                parent_value = self.parent.get_value()
                fpu_value = parent_value - fpu_reduction
                return fpu_value + c_puct * self.prior_prob * math.sqrt(max(parent_visit_count, 1))
            else:
                return float('inf')  # Fallback for root node children
        
        # Q-value (exploitation term) - use raw average for better accuracy
        q_value = self.get_value()
        
        # U-value (exploration term) using proper PUCT formula
        if parent_visit_count and parent_visit_count > 0:
            # LC0-style PUCT calculation with proper normalization
            sqrt_parent = math.sqrt(max(parent_visit_count, 1))
            u_value = c_puct * self.prior_prob * sqrt_parent / (1 + effective_visits)
            
            # Add small variance-based exploration bonus for positions with high uncertainty
            if self.visit_count > 1:
                variance = self.get_value_variance()
                # Scale variance bonus based on visit count (less bonus for well-explored nodes)
                variance_bonus = 0.05 * math.sqrt(variance) / math.sqrt(effective_visits)
                u_value += variance_bonus
        else:
            u_value = 0.0
        
        # Nine Men's Morris specific: bonus for consecutive moves (mill formation)
        consecutive_bonus = 0.0
        if self.is_consecutive_move:
            # CRITICAL: In Nine Men's Morris, consecutive moves are in removal phase
            # These are often forced moves (capture opponent piece after mill)
            # Bonus should be very small to avoid over-exploration of forced moves
            consecutive_bonus = 0.02 * self.prior_prob  # Minimal bonus for forced moves
        
        # Final UCB score with proper scaling
        ucb_score = q_value + u_value + consecutive_bonus
        
        return ucb_score
    
    def select_best_child(self, c_puct: float, fpu_reduction: float = 0.25) -> Optional['MCTSNode']:
        """Select best child using advanced UCB with LC0-style FPU support."""
        if not self.children:
            return None
        
        # Use cached scores if valid and no virtual loss changes
        if self._cache_valid and not self.virtual_loss:
            cached_best = max(self.children.values(), 
                            key=lambda child: self._cached_ucb_scores.get(child.action, -float('inf')))
            return cached_best
        
        # Calculate UCB scores for all children
        parent_visits = self.get_effective_visit_count()
        best_score = -float('inf')
        best_child = None
        
        for child in self.children.values():
            score = child.get_ucb_score(c_puct, parent_visits, fpu_reduction)
            
            # Cache the score
            self._cached_ucb_scores[child.action] = score
            
            if score > best_score:
                best_score = score
                best_child = child
        
        self._cache_valid = True
        return best_child
    
    def add_virtual_loss(self):
        """Add virtual loss for parallel search."""
        with self._lock:
            self.virtual_loss += 1
            self._cache_valid = False
    
    def remove_virtual_loss(self):
        """Remove virtual loss after search completion."""
        with self._lock:
            self.virtual_loss = max(0, self.virtual_loss - 1)
            self._cache_valid = False
    
    def backup(self, value: float):
        """
        Backup value with improved statistics tracking.
        
        Features:
        - Thread-safe updates
        - Variance tracking for confidence estimation
        - Proper handling of consecutive moves in Nine Men's Morris
        """
        with self._lock:
            self.visit_count += 1
            self.value_sum += value
            self.squared_value_sum += value * value
            self._cache_valid = False
    
    def is_terminal(self, game) -> bool:
        """Check if node represents a terminal position with caching."""
        if self.is_terminal_node is None:
            self.is_terminal_node = (game.getGameEnded(self.board, self.current_player) != 0)
        return self.is_terminal_node
    
    def get_child_info(self) -> List[Dict[str, Any]]:
        """Get detailed information about all children for analysis."""
        info = []
        parent_visits = self.get_effective_visit_count()
        
        for action, child in self.children.items():
            info.append({
                'action': action,
                'visits': child.get_effective_visit_count(),
                'value': child.get_value(),
                'prior': child.prior_prob,
                'ucb_score': child.get_ucb_score(1.0, parent_visits),
                'is_consecutive': child.is_consecutive_move,
                'variance': child.get_value_variance()
            })
        
        return sorted(info, key=lambda x: x['visits'], reverse=True)


class MCTS:
    """
    Advanced MCTS implementation with KataGo-inspired optimizations for Nine Men's Morris.
    
    Key features:
    - Proper handling of Nine Men's Morris consecutive moves after captures
    - KataGo-style search improvements (virtual loss, progressive widening)
    - Advanced root noise injection and exploration
    - Transposition table support for position reuse
    - Parallel search support with virtual losses
    - Sophisticated backup strategies for non-alternating games
    
    This implementation correctly handles the unique aspects of Nine Men's Morris:
    - After a mill is formed, the same player continues with a removal move
    - Value propagation must account for consecutive moves by the same player
    - Different game phases (placing, moving, flying) have different characteristics
    """
    
    def __init__(self, game, neural_network, args: Dict[str, Any]):
        self.game = game
        self.neural_network = neural_network
        
        # Core MCTS parameters optimized for Nine Men's Morris 7x7 board
        self.c_puct = args.get('cpuct', 1.8)  # Moderate exploration (2.5 too high for small board)
        self.num_simulations = args.get('num_simulations', 800)  # More simulations for stronger play
        self.dirichlet_alpha = args.get('dirichlet_alpha', 0.2)  # Balanced noise for 24-position board
        self.dirichlet_epsilon = args.get('dirichlet_epsilon', 0.15)  # Moderate noise
        
        # LC0-style search improvements
        self.use_virtual_loss = args.get('use_virtual_loss', True)
        self.virtual_loss_count = args.get('virtual_loss_count', 3)
        self.progressive_widening = args.get('progressive_widening', True)
        self.min_visits_for_expansion = args.get('min_visits_for_expansion', 1)
        
        # First Play Urgency (FPU) parameters from LC0
        self.fpu_reduction = args.get('fpu_reduction', 0.25)  # Reduction for unvisited nodes
        self.fpu_at_root = args.get('fpu_at_root', True)  # Apply FPU at root
        self._mcts_fpu_reduction = self.fpu_reduction  # Store for child access
        
        # Nine Men's Morris specific parameters - critical for consecutive move handling
        self.consecutive_move_bonus = args.get('consecutive_move_bonus', 0.02)  # Conservative
        self.removal_phase_exploration = args.get('removal_phase_exploration', 0.8)  # Less exploration
        self.placing_phase_exploration = args.get('placing_phase_exploration', 1.3)  # More exploration  
        self.flying_phase_simulations_multiplier = args.get('flying_phase_simulations_multiplier', 2.0)
        
        # Transposition table for position reuse
        self.use_transpositions = args.get('use_transpositions', True)  # Enable by default
        self.transposition_table = {} if self.use_transpositions else None
        self.max_transposition_size = args.get('max_transposition_size', 50000)
        
        # Search statistics
        self.search_stats = {
            'total_simulations': 0,
            'transposition_hits': 0,
            'consecutive_moves_found': 0,
            'terminal_nodes_reached': 0,
            'max_depth_reached': 0,
            'depth_limit_hits': 0,
            'fpu_reductions_applied': 0
        }
        
        # Search depth limit to prevent infinite recursion
        self.max_search_depth = args.get('max_search_depth', 200)  # Reasonable depth limit
        
        # Root noise control
        self._add_root_noise_flag = False
        
        # Thread safety for parallel search
        self._lock = threading.Lock()
    
    def get_action_probabilities(self, board, current_player: int, temperature: float = 1.0,
                                 add_root_noise: bool = False) -> np.ndarray:
        """
        Get action probabilities after MCTS search with KataGo-style improvements.
        
        Args:
            board: Current board state
            current_player: Current player (1 or -1)
            temperature: Temperature for move selection (0 = deterministic)
            add_root_noise: Whether to add Dirichlet noise for exploration
            
        Returns:
            Action probability distribution over all possible actions
        """
        # Reset search statistics
        self.search_stats['total_simulations'] = 0
        self.search_stats['transposition_hits'] = 0
        self.search_stats['consecutive_moves_found'] = 0
        self.search_stats['terminal_nodes_reached'] = 0
        self.search_stats['max_depth_reached'] = 0
        self.search_stats['depth_limit_hits'] = 0
        
        # Create root node with move tracking
        root = MCTSNode(board, current_player, move_number=0)
        
        # Configure root noise for this search
        self._add_root_noise_flag = add_root_noise
        
        # Adjust search parameters based on Nine Men's Morris game phase
        # Use local variables to avoid modifying instance state
        current_phase = getattr(board, 'period', 0)
        effective_c_puct = self.c_puct
        effective_num_sims = self.num_simulations
        effective_epsilon = self.dirichlet_epsilon
        
        if current_phase == 0:  # Placing phase - strategic foundation
            effective_c_puct = self.c_puct * self.placing_phase_exploration
        elif current_phase == 3:  # Removal phase - CRITICAL: consecutive moves after mill
            effective_c_puct = self.c_puct * self.removal_phase_exploration
            # In removal phase, reduce noise for precise tactical play
            if add_root_noise:
                effective_epsilon = min(self.dirichlet_epsilon, 0.05)
        elif current_phase == 2:  # Flying phase - complex endgame
            # Increase simulations for complex flying phase calculations
            effective_num_sims = int(self.num_simulations * self.flying_phase_simulations_multiplier)
        
        # Store effective parameters for this search
        self._effective_c_puct = effective_c_puct
        self._effective_epsilon = effective_epsilon
        
        # Check for transposition table hit
        if self.use_transpositions:
            position_key = self._get_position_key(board, current_player)
            if position_key in self.transposition_table:
                cached_node = self.transposition_table[position_key]
                # Use cached node if it has sufficient visits
                if cached_node.visit_count >= self.num_simulations // 4:
                    root = cached_node
                    self.search_stats['transposition_hits'] += 1
        
        # Run MCTS simulations with phase-adjusted parameters
        if self.use_virtual_loss:
            self._run_parallel_simulations(root, effective_num_sims, effective_c_puct)
        else:
            self._run_sequential_simulations(root, effective_num_sims, effective_c_puct)
        
        # Store in transposition table with size management
        if self.use_transpositions:
            position_key = self._get_position_key(board, current_player)
            
            # Manage transposition table size to prevent memory overflow
            if len(self.transposition_table) >= self.max_transposition_size:
                # Remove oldest 20% of entries (simple aging strategy)
                keys_to_remove = list(self.transposition_table.keys())[:self.max_transposition_size // 5]
                for key in keys_to_remove:
                    del self.transposition_table[key]
                logger.debug(f"Cleaned transposition table: removed {len(keys_to_remove)} entries")
            
            self.transposition_table[position_key] = root
        
        # Collect visit counts from children
        action_size = self.game.getActionSize()
        counts = np.zeros(action_size, dtype=float)
        
        for action, child in root.children.items():
            if action < action_size:
                counts[action] = child.visit_count
        
        # Apply temperature with improved handling
        probs = self._apply_temperature(counts, temperature, board, current_player)
        
        # Log search statistics
        if logger.isEnabledFor(logging.DEBUG):
            self._log_search_stats(root)
        
        return probs
    
    def _run_sequential_simulations(self, root: MCTSNode, num_sims: int = None, c_puct: float = None):
        """Run MCTS simulations sequentially with phase-adjusted parameters."""
        num_sims = num_sims or self.num_simulations
        c_puct = c_puct or self.c_puct
        for _ in range(num_sims):
            self._simulate(root, c_puct)
            self.search_stats['total_simulations'] += 1
    
    def _run_parallel_simulations(self, root: MCTSNode, num_sims: int = None, c_puct: float = None):
        """Run MCTS simulations with virtual loss for parallelization."""
        num_sims = num_sims or self.num_simulations
        c_puct = c_puct or self.c_puct
        # For now, implement sequential with virtual loss tracking
        # Can be extended to actual parallel execution later
        for _ in range(num_sims):
            self._simulate_with_virtual_loss(root, c_puct)
            self.search_stats['total_simulations'] += 1
    
    def _apply_temperature(self, counts: np.ndarray, temperature: float, 
                          board, current_player: int) -> np.ndarray:
        """Apply temperature to visit counts with improved fallback handling."""
        action_size = len(counts)
        
        if temperature == 0:
            # Deterministic selection - choose most visited action
            probs = np.zeros(action_size)
            if np.sum(counts) > 0:
                best_action = np.argmax(counts)
                probs[best_action] = 1.0
            else:
                # Fallback to uniform over valid moves
                probs = self._get_uniform_valid_policy(board, current_player, action_size)
        else:
            # Stochastic selection with temperature
            if np.sum(counts) > 0:
                if temperature != 1.0:
                    # Apply temperature scaling
                    counts = np.power(counts, 1.0 / temperature)
                probs = counts / np.sum(counts)
            else:
                # Fallback to uniform over valid moves
                probs = self._get_uniform_valid_policy(board, current_player, action_size)
        
        return probs
    
    def _get_uniform_valid_policy(self, board, current_player: int, action_size: int) -> np.ndarray:
        """Get uniform policy over valid moves as fallback."""
        valid_moves = self.game.getValidMoves(board, current_player)
        if np.sum(valid_moves) > 0:
            return valid_moves / np.sum(valid_moves)
        else:
            logger.warning("No valid moves found! Using uniform distribution.")
            return np.ones(action_size) / action_size
    
    def _get_position_key(self, board, current_player: int) -> str:
        """Generate position key for transposition table."""
        try:
            return f"{board.pieces.tobytes()}_{current_player}_{board.period}"
        except:
            return f"{str(board.pieces)}_{current_player}"
    
    def _log_search_stats(self, root: MCTSNode):
        """Log detailed search statistics."""
        stats = self.search_stats
        logger.debug(f"MCTS Search Statistics:")
        logger.debug(f"  Total simulations: {stats['total_simulations']}")
        logger.debug(f"  Root visits: {root.visit_count}")
        logger.debug(f"  Children expanded: {len(root.children)}")
        logger.debug(f"  Transposition hits: {stats['transposition_hits']}")
        logger.debug(f"  Consecutive moves: {stats['consecutive_moves_found']}")
        logger.debug(f"  Terminal nodes: {stats['terminal_nodes_reached']}")
        
        # Log top children
        child_info = root.get_child_info()[:5]  # Top 5 children
        for i, info in enumerate(child_info):
            logger.debug(f"  Child {i+1}: action={info['action']}, "
                        f"visits={info['visits']}, value={info['value']:.3f}")
    
    def _simulate(self, root: MCTSNode, c_puct: float = None):
        """
        Execute a single MCTS simulation with proper Nine Men's Morris handling.
        
        This method handles the unique aspects of Nine Men's Morris:
        - Consecutive moves after mill formation and piece removal
        - Proper value propagation for non-alternating turns
        - Game phase awareness (placing, moving, flying, removal)
        """
        c_puct = c_puct or self.c_puct
        path = []
        node = root
        
        # Phase 1: Selection - traverse down the tree using UCB
        while (node.is_expanded and not node.is_terminal(self.game) and 
               len(path) < self.max_search_depth):
            if not node.children:
                break
                
            selected_child = node.select_best_child(c_puct, self.fpu_reduction)
            if selected_child is None:
                break
                
            path.append(selected_child)
            node = selected_child
        
        # Track maximum depth reached
        current_depth = len(path)
        self.search_stats['max_depth_reached'] = max(self.search_stats['max_depth_reached'], current_depth)
        
        # Check if we hit depth limit
        if current_depth >= self.max_search_depth:
            self.search_stats['depth_limit_hits'] += 1
            logger.debug(f"Hit search depth limit: {current_depth}")
        
        # Phase 2: Expansion and Evaluation
        leaf_value = 0.0
        
        if node.is_terminal(self.game):
            # Terminal node - get actual game result
            result = self.game.getGameEnded(node.board, node.current_player)
            leaf_value = result
            self.search_stats['terminal_nodes_reached'] += 1
        else:
            # Expand and evaluate non-terminal node
            leaf_value = self._expand_node(node)

        # Phase 3: Backup with Nine Men's Morris specific value propagation
        self._backup_values(path + [node], leaf_value)
    
    def _simulate_with_virtual_loss(self, root: MCTSNode, c_puct: float = None):
        """
        Execute MCTS simulation with virtual loss for parallel search support.
        """
        c_puct = c_puct or self.c_puct
        path = []
        node = root
        
        # Add virtual losses along the path for parallel search
        virtual_loss_nodes = []
        
        # Selection with virtual loss
        while node.is_expanded and not node.is_terminal(self.game):
            if not node.children:
                break
                
            # Add virtual loss to current node
            if self.use_virtual_loss:
                node.add_virtual_loss()
                virtual_loss_nodes.append(node)
                
            selected_child = node.select_best_child(c_puct, self.fpu_reduction)
            if selected_child is None:
                break
                
            path.append(selected_child)
            node = selected_child
        
        # Expansion and evaluation
        leaf_value = 0.0
        
        if node.is_terminal(self.game):
            result = self.game.getGameEnded(node.board, node.current_player)
            leaf_value = result
            self.search_stats['terminal_nodes_reached'] += 1
        else:
            leaf_value = self._expand_node(node)
        
        # Backup values
        self._backup_values(path + [node], leaf_value)
        
        # Remove virtual losses
        for vl_node in virtual_loss_nodes:
            vl_node.remove_virtual_loss()
    
    def _backup_values(self, path: List[MCTSNode], leaf_value: float):
        """
        Backup values along the path with proper Nine Men's Morris handling.
        
        Critical: In Nine Men's Morris, after forming a mill, the same player
        continues with a removal move. This means value signs should only be
        flipped when the active player actually changes between moves.
        
        Args:
            path: List of nodes from leaf to root (inclusive)
            leaf_value: Value to backup from leaf node
        """
        if not path:
            return
        
        # Backup values correctly from leaf to root
        # The path should be traversed in reverse order (leaf to root)
        current_value = leaf_value
        
        # Start from the leaf and work backwards to root
        # CRITICAL: Proper value backup for Nine Men's Morris consecutive moves
        for i in range(len(path)):
            node = path[i]
            
            # Backup the value from current player's perspective
            node.backup(current_value)
            
            # For the next parent in the path, determine if we need to flip the value
            if i + 1 < len(path):  # Has a parent in the path
                parent_node = path[i + 1]
                
                # CRITICAL: Only flip value if the player to move actually changes
                # In Nine Men's Morris:
                # - Normal moves: player alternates, flip value
                # - After mill formation: same player continues for removal, DON'T flip value
                if node.current_player != parent_node.current_player:
                    current_value = -current_value
                    
                # Track consecutive moves for statistics and debugging
                if node.current_player == parent_node.current_player:
                    self.search_stats['consecutive_moves_found'] += 1
                    # Log for debugging Nine Men's Morris consecutive move handling
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug(f"Consecutive move in backup: player {node.current_player} "
                                   f"continues from parent (likely mill formation -> removal)")
                        
            elif node.parent is not None:  # Has a parent outside the path
                # Handle the transition to root if needed
                if node.current_player != node.parent.current_player:
                    current_value = -current_value
    
    def _expand_node(self, node: MCTSNode) -> float:
        """
        Expand node using neural network prediction with KataGo-style improvements.
        
        Features:
        - Robust child creation with error handling
        - Progressive widening support
        - Root noise injection
        - Nine Men's Morris phase-aware expansion
        """
        # Get neural network prediction
        policy_probs, value = self.neural_network.predict(node.board, node.current_player)
        
        # Get valid actions for current position
        valid_actions = self.game.getValidMoves(node.board, node.current_player)
        valid_actions_indices = np.where(valid_actions == 1)[0]
        
        if len(valid_actions_indices) == 0:
            logger.warning(f"No valid actions found during expansion!")
            node.is_expanded = True
            return value
        
        # Mask and normalize policy probabilities
        masked_probs = policy_probs * valid_actions
        if np.sum(masked_probs) > 0:
            masked_probs = masked_probs / np.sum(masked_probs)
        else:
            # Fallback to uniform distribution over valid actions
            masked_probs = valid_actions / np.sum(valid_actions)
            logger.debug("Using uniform policy fallback during expansion")
        
        # Progressive widening: limit children based on visit count
        max_children = len(valid_actions_indices)
        if self.progressive_widening and node.visit_count < self.min_visits_for_expansion:
            # Limit expansion for low-visit nodes
            max_children = min(max_children, max(1, int(np.sqrt(node.visit_count + 1))))
        
        # Sort actions by prior probability for progressive widening
        action_priors = [(action, masked_probs[action]) for action in valid_actions_indices]
        action_priors.sort(key=lambda x: x[1], reverse=True)
        
        # Create children for selected actions
        children_created = 0
        for action, prior_prob in action_priors:
            if children_created >= max_children:
                break
                
            try:
                # Execute move to get child state
                child_board, next_player = self.game.getNextState(
                    node.board, node.current_player, action
                )
                
                # Create child node with proper move tracking
                child = MCTSNode(
                    board=child_board,
                    current_player=next_player,
                    action=action,
                    parent=node,
                    prior_prob=prior_prob,
                    move_number=node.move_number + 1
                )
                
                # Add to parent's children
                node.children[action] = child
                children_created += 1
                
                # Debug logging for Nine Men's Morris specific cases
                if child.is_consecutive_move:
                    logger.debug(f"Created consecutive move child: action {action}, "
                               f"same player continues ({child.current_player})")
                
            except Exception as e:
                logger.warning(f"Failed to create child for action {action}: {e}")
                continue
        
        # Mark node as expanded
        node.is_expanded = True
        
        # Add Dirichlet noise at root for exploration
        if (self._add_root_noise_flag and node.parent is None and 
            len(node.children) > 0):
            self._add_dirichlet_noise(node)
        
        # Adjust value based on game phase for Nine Men's Morris
        adjusted_value = self._adjust_value_for_phase(value, node.board)
        
        logger.debug(f"Expanded node with {children_created} children, "
                    f"value: {adjusted_value:.3f}")
        
        return adjusted_value
    
    def _adjust_value_for_phase(self, value: float, board) -> float:
        """
        Adjust neural network value based on Nine Men's Morris game phase.
        
        CRITICAL: Consider consecutive move context in removal phase.
        """
        try:
            phase = getattr(board, 'period', 0)
            
            # Apply phase-specific adjustments considering consecutive move implications
            if phase == 0:  # Placing phase - positional evaluation less certain
                return value * 0.9  # Reduce confidence in opening positions
            elif phase == 3:  # Removal phase - CRITICAL consecutive move phase
                # In removal phase, the same player continues after mill formation
                # Value should be more certain as it's often a forced tactical sequence
                return value * 1.1  # Slightly increase confidence in tactical positions
            elif phase == 2:  # Flying phase - complex endgame
                # Flying phase can have rapid position changes
                return value * 0.95  # Slightly reduce confidence due to complexity
            else:  # Moving phase - standard evaluation
                return value
                
        except:
            return value
    
    def _add_dirichlet_noise(self, node: MCTSNode):
        """
        Add Dirichlet noise to root node for exploration (KataGo-style).
        
        This encourages exploration of different moves during self-play,
        which is crucial for discovering new strategies and avoiding
        getting stuck in local optima.
        """
        if len(node.children) == 0:
            return
        
        actions = list(node.children.keys())
        num_children = len(actions)
        
        # Generate Dirichlet noise
        noise = np.random.dirichlet([self.dirichlet_alpha] * num_children)
        
        # Apply noise to prior probabilities
        for i, action in enumerate(actions):
            child = node.children[action]
            original_prior = child.prior_prob
            
            # Weighted combination of original prior and noise
            child.prior_prob = ((1 - self.dirichlet_epsilon) * original_prior + 
                               self.dirichlet_epsilon * noise[i])
            
            # Ensure prior probability is positive
            child.prior_prob = max(child.prior_prob, 1e-8)
        
        logger.debug(f"Added Dirichlet noise to {num_children} children at root")
    
    def get_search_statistics(self) -> Dict[str, Any]:
        """Get detailed search statistics for analysis."""
        return {
            'total_simulations': self.search_stats['total_simulations'],
            'transposition_hits': self.search_stats['transposition_hits'],
            'consecutive_moves_found': self.search_stats['consecutive_moves_found'],
            'terminal_nodes_reached': self.search_stats['terminal_nodes_reached'],
            'max_depth_reached': self.search_stats['max_depth_reached'],
            'depth_limit_hits': self.search_stats['depth_limit_hits'],
            'transposition_table_size': len(self.transposition_table) if self.transposition_table else 0,
            'parameters': {
                'c_puct': self.c_puct,
                'num_simulations': self.num_simulations,
                'dirichlet_alpha': self.dirichlet_alpha,
                'dirichlet_epsilon': self.dirichlet_epsilon,
                'use_virtual_loss': self.use_virtual_loss,
                'progressive_widening': self.progressive_widening,
                'max_search_depth': self.max_search_depth
            }
        }
    
    def clear_transposition_table(self):
        """Clear transposition table to free memory."""
        if self.transposition_table:
            self.transposition_table.clear()
            logger.debug("Cleared transposition table")