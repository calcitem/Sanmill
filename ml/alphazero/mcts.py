#!/usr/bin/env python3
"""
Monte Carlo Tree Search (MCTS) for Alpha Zero

This module implements MCTS with neural network guidance for Nine Men's Morris.
Features UCB selection, neural network evaluation, and efficient tree management.
"""

import math
import numpy as np
import logging
from typing import Dict, List, Tuple, Optional, Any
from collections import defaultdict
import time

logger = logging.getLogger(__name__)


class MCTSNode:
    """
    Node in the MCTS tree.
    
    Stores visit counts, values, and child information for efficient search.
    """
    
    def __init__(self, state_hash: str, parent: Optional['MCTSNode'] = None, 
                 action: Optional[int] = None, prior_prob: float = 0.0):
        """
        Initialize MCTS node.
        
        Args:
            state_hash: String representation of board state
            parent: Parent node in tree
            action: Action that led to this node
            prior_prob: Prior probability from neural network
        """
        self.state_hash = state_hash
        self.parent = parent
        self.action = action
        self.prior_prob = prior_prob
        
        # MCTS statistics
        self.visit_count = 0
        self.value_sum = 0.0
        self.children: Dict[int, 'MCTSNode'] = {}
        
        # Node properties
        self.is_expanded = False
        self.is_terminal = False
        self.terminal_value = 0.0
        
        # Valid actions from this state
        self.valid_actions: Optional[np.ndarray] = None
    
    def is_leaf(self) -> bool:
        """Check if this is a leaf node."""
        return not self.is_expanded or self.is_terminal
    
    def get_value(self) -> float:
        """Get average value of this node."""
        if self.visit_count == 0:
            return 0.0
        return self.value_sum / self.visit_count
    
    def get_ucb_score(self, c_puct: float, parent_visits: int) -> float:
        """
        Calculate UCB score for action selection.
        
        Args:
            c_puct: Exploration constant
            parent_visits: Number of visits to parent node
            
        Returns:
            UCB score
        """
        if self.visit_count == 0:
            # Unvisited nodes get maximum priority
            return float('inf')
        
        # UCB formula: Q(s,a) + c_puct * P(s,a) * sqrt(N(s)) / (1 + N(s,a))
        exploitation = self.get_value()
        exploration = c_puct * self.prior_prob * math.sqrt(parent_visits) / (1 + self.visit_count)
        
        return exploitation + exploration
    
    def select_child(self, c_puct: float) -> 'MCTSNode':
        """
        Select child with highest UCB score.
        
        Args:
            c_puct: Exploration constant
            
        Returns:
            Selected child node
        """
        if not self.children:
            raise ValueError("No children to select from")
        
        best_score = -float('inf')
        best_child = None
        
        for child in self.children.values():
            score = child.get_ucb_score(c_puct, self.visit_count)
            if score > best_score:
                best_score = score
                best_child = child
        
        return best_child
    
    def add_child(self, action: int, state_hash: str, prior_prob: float) -> 'MCTSNode':
        """
        Add child node.
        
        Args:
            action: Action leading to child
            state_hash: Hash of child state
            prior_prob: Prior probability of action
            
        Returns:
            Created child node
        """
        child = MCTSNode(state_hash, parent=self, action=action, prior_prob=prior_prob)
        self.children[action] = child
        return child
    
    def backup(self, value: float):
        """
        Backup value through the tree.
        
        Args:
            value: Value to backup (from perspective of current player)
        """
        self.visit_count += 1
        self.value_sum += value
        
        if self.parent is not None:
            # Backup negated value (opponent's perspective)
            self.parent.backup(-value)
    
    def get_visit_counts(self, action_size: int) -> np.ndarray:
        """
        Get visit counts for all actions.
        
        Args:
            action_size: Total number of possible actions
            
        Returns:
            Array of visit counts
        """
        counts = np.zeros(action_size, dtype=int)
        for action, child in self.children.items():
            if action < action_size:
                counts[action] = child.visit_count
        return counts
    
    def get_action_probabilities(self, action_size: int, temperature: float = 1.0) -> np.ndarray:
        """
        Get action probabilities based on visit counts.
        
        Args:
            action_size: Total number of possible actions  
            temperature: Temperature for probability calculation
            
        Returns:
            Action probability distribution
        """
        if self.visit_count == 0:
            # If no visits, return uniform over valid actions
            if self.valid_actions is not None:
                probs = self.valid_actions / np.sum(self.valid_actions)
            else:
                probs = np.ones(action_size) / action_size
            return probs
        
        counts = self.get_visit_counts(action_size)
        
        if temperature == 0:
            # Deterministic selection
            best_action = np.argmax(counts)
            probs = np.zeros(action_size)
            probs[best_action] = 1.0
        else:
            # Temperature-based selection
            if temperature == 1.0:
                # Direct proportional
                counts_sum = np.sum(counts)
                if counts_sum > 0:
                    probs = counts / counts_sum
                else:
                    probs = np.ones(action_size) / action_size
            else:
                # Apply temperature
                counts = counts.astype(float)
                if temperature > 0:
                    counts = counts ** (1.0 / temperature)
                else:
                    # Very low temperature - almost deterministic
                    counts = counts ** 100
                
                counts_sum = np.sum(counts)
                if counts_sum > 0:
                    probs = counts / counts_sum
                else:
                    probs = np.ones(action_size) / action_size
        
        # Ensure we only select valid actions
        if self.valid_actions is not None:
            probs = probs * self.valid_actions
            probs_sum = np.sum(probs)
            if probs_sum > 0:
                probs = probs / probs_sum
            else:
                probs = self.valid_actions / np.sum(self.valid_actions)
        
        return probs


class MCTS:
    """
    Monte Carlo Tree Search implementation for Alpha Zero.
    
    Combines neural network guidance with tree search for move selection.
    """
    
    def __init__(self, game, neural_network, args: Dict[str, Any]):
        """
        Initialize MCTS.
        
        Args:
            game: Game engine instance
            neural_network: Neural network for position evaluation
            args: MCTS configuration parameters
        """
        self.game = game
        self.neural_network = neural_network
        self.args = args
        
        # MCTS parameters
        self.c_puct = args.get('c_puct', 1.0)
        self.num_simulations = args.get('num_mcts_sims', 100)
        self.add_dirichlet_noise = args.get('add_dirichlet_noise', True)
        self.dirichlet_alpha = args.get('dirichlet_alpha', 0.3)
        self.dirichlet_epsilon = args.get('dirichlet_epsilon', 0.25)
        
        # Tree storage
        self.root: Optional[MCTSNode] = None
        self.nodes: Dict[str, MCTSNode] = {}  # State hash -> Node
        
        # Statistics
        self.stats = {
            'total_simulations': 0,
            'cache_hits': 0,
            'neural_net_calls': 0,
            'tree_size': 0
        }
        
        logger.info(f"MCTS initialized: {self.num_simulations} sims, c_puct={self.c_puct}")
    
    def search(self, board, current_player: int, num_simulations: Optional[int] = None) -> np.ndarray:
        """
        Perform MCTS search and return action probabilities.
        
        Args:
            board: Current board state
            current_player: Current player (1 or -1)
            num_simulations: Number of simulations (overrides default)
            
        Returns:
            Action probability distribution
        """
        num_sims = num_simulations or self.num_simulations
        
        # Get canonical board representation
        canonical_board = self.game.getCanonicalForm(board, current_player)
        root_hash = self.game.stringRepresentation(canonical_board)
        
        # Initialize or reuse root node
        if root_hash not in self.nodes:
            self.root = MCTSNode(root_hash)
            self.nodes[root_hash] = self.root
        else:
            self.root = self.nodes[root_hash]
        
        # Expand root if needed
        if not self.root.is_expanded:
            self._expand_node(self.root, canonical_board, current_player)
        
        # Add Dirichlet noise to root for exploration
        if self.add_dirichlet_noise and self.root.children:
            self._add_dirichlet_noise_to_root()
        
        # Perform simulations
        start_time = time.time()
        for sim in range(num_sims):
            self._simulate(canonical_board, current_player)
            
            # Progress logging for long searches
            if num_sims > 100 and (sim + 1) % (num_sims // 10) == 0:
                elapsed = time.time() - start_time
                logger.debug(f"MCTS simulation {sim + 1}/{num_sims} "
                           f"({elapsed:.2f}s, {(sim + 1) / elapsed:.1f} sim/s)")
        
        # Update statistics
        self.stats['total_simulations'] += num_sims
        self.stats['tree_size'] = len(self.nodes)
        
        # Return action probabilities
        action_size = self.game.getActionSize()
        probabilities = self.root.get_action_probabilities(action_size, temperature=1.0)
        
        return probabilities
    
    def _simulate(self, board, current_player: int):
        """
        Perform a single MCTS simulation.
        
        Args:
            board: Starting board state
            current_player: Starting player
        """
        path = []  # (node, board, player) tuples
        node = self.root
        current_board = board
        player = current_player
        
        # Selection: traverse tree until leaf
        while not node.is_leaf():
            # Select best child
            child = node.select_child(self.c_puct)
            
            # Take action to reach child state
            action = child.action
            current_board, player = self.game.getNextState(current_board, player, action)
            current_board = self.game.getCanonicalForm(current_board, player)
            
            path.append((node, current_board, player))
            node = child
        
        # Check if game is over
        game_result = self.game.getGameEnded(current_board, player)
        
        if game_result != 0:
            # Terminal node
            node.is_terminal = True
            node.terminal_value = game_result
            value = game_result
        else:
            # Expansion and evaluation
            if not node.is_expanded:
                value = self._expand_node(node, current_board, player)
            else:
                # Re-evaluate with neural network
                _, value = self.neural_network.predict(current_board, player)
        
        # Backup value through path
        node.backup(value)
    
    def _expand_node(self, node: MCTSNode, board, current_player: int) -> float:
        """
        Expand a leaf node using neural network.
        
        Args:
            node: Node to expand
            board: Board state at this node
            current_player: Current player
            
        Returns:
            Value estimate from neural network
        """
        # Get neural network predictions
        policy_probs, value = self.neural_network.predict(board, current_player)
        self.stats['neural_net_calls'] += 1
        
        # Get valid moves
        valid_actions = self.game.getValidMoves(board, current_player)
        node.valid_actions = valid_actions
        
        # Mask invalid actions and renormalize
        masked_probs = policy_probs * valid_actions
        prob_sum = np.sum(masked_probs)
        
        if prob_sum > 0:
            masked_probs = masked_probs / prob_sum
        else:
            # Fallback to uniform over valid actions
            masked_probs = valid_actions / np.sum(valid_actions)
        
        # Create children for valid actions
        for action in range(len(valid_actions)):
            if valid_actions[action] > 0:
                # Get next state
                next_board, next_player = self.game.getNextState(board, current_player, action)
                next_canonical = self.game.getCanonicalForm(next_board, next_player)
                next_hash = self.game.stringRepresentation(next_canonical)
                
                # Create or reuse child node
                if next_hash in self.nodes:
                    child = self.nodes[next_hash]
                    node.children[action] = child
                    self.stats['cache_hits'] += 1
                else:
                    child = node.add_child(action, next_hash, masked_probs[action])
                    self.nodes[next_hash] = child
        
        node.is_expanded = True
        return value
    
    def _add_dirichlet_noise_to_root(self):
        """Add Dirichlet noise to root node for exploration."""
        if not self.root.children:
            return
        
        actions = list(self.root.children.keys())
        noise = np.random.dirichlet([self.dirichlet_alpha] * len(actions))
        
        for i, action in enumerate(actions):
            child = self.root.children[action]
            # Mix prior with noise
            child.prior_prob = ((1 - self.dirichlet_epsilon) * child.prior_prob + 
                               self.dirichlet_epsilon * noise[i])
    
    def get_action_probabilities(self, board, current_player: int, 
                               temperature: float = 1.0) -> np.ndarray:
        """
        Get action probabilities after MCTS search.
        
        Args:
            board: Board state
            current_player: Current player
            temperature: Temperature for action selection
            
        Returns:
            Action probability distribution
        """
        probabilities = self.search(board, current_player)
        
        if temperature == 0:
            # Deterministic selection
            action_size = len(probabilities)
            best_action = np.argmax(probabilities)
            deterministic_probs = np.zeros(action_size)
            deterministic_probs[best_action] = 1.0
            return deterministic_probs
        elif temperature != 1.0:
            # Apply temperature
            if temperature > 0:
                probabilities = probabilities ** (1.0 / temperature)
            else:
                # Very low temperature
                probabilities = probabilities ** 100
            
            # Renormalize
            prob_sum = np.sum(probabilities)
            if prob_sum > 0:
                probabilities = probabilities / prob_sum
        
        return probabilities
    
    def select_action(self, board, current_player: int, temperature: float = 1.0) -> int:
        """
        Select an action using MCTS.
        
        Args:
            board: Board state
            current_player: Current player
            temperature: Temperature for selection
            
        Returns:
            Selected action
        """
        probabilities = self.get_action_probabilities(board, current_player, temperature)
        
        if temperature == 0:
            # Deterministic selection
            return int(np.argmax(probabilities))
        else:
            # Stochastic selection
            return int(np.random.choice(len(probabilities), p=probabilities))
    
    def update_root(self, action: int):
        """
        Update root to child after taking an action.
        
        Args:
            action: Action taken
        """
        if self.root and action in self.root.children:
            # Move root to child
            self.root = self.root.children[action]
            self.root.parent = None
        else:
            # Reset tree if action not in tree
            self.reset_tree()
    
    def reset_tree(self):
        """Reset the search tree."""
        self.root = None
        self.nodes.clear()
        self.stats['tree_size'] = 0
        logger.debug("MCTS tree reset")
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get MCTS statistics."""
        stats = self.stats.copy()
        
        if self.root:
            stats['root_visits'] = self.root.visit_count
            stats['root_value'] = self.root.get_value()
            stats['root_children'] = len(self.root.children)
        
        return stats
    
    def print_tree_info(self, max_depth: int = 3):
        """
        Print information about the current search tree.
        
        Args:
            max_depth: Maximum depth to print
        """
        if not self.root:
            print("No tree exists")
            return
        
        print(f"\nMCTS Tree Information:")
        print(f"Root visits: {self.root.visit_count}")
        print(f"Root value: {self.root.get_value():.4f}")
        print(f"Tree size: {len(self.nodes)} nodes")
        print(f"Root children: {len(self.root.children)}")
        
        if self.root.children:
            print(f"\nTop child actions:")
            children_info = []
            for action, child in self.root.children.items():
                children_info.append((
                    action, 
                    child.visit_count, 
                    child.get_value(),
                    child.prior_prob
                ))
            
            # Sort by visit count
            children_info.sort(key=lambda x: x[1], reverse=True)
            
            for i, (action, visits, value, prior) in enumerate(children_info[:10]):
                print(f"  Action {action}: {visits} visits, "
                      f"value {value:.4f}, prior {prior:.4f}")
                
                if i >= 5:  # Limit output
                    break


class MCTSPlayer:
    """
    Player that uses MCTS for move selection.
    
    Provides a simple interface for using MCTS in games.
    """
    
    def __init__(self, game, neural_network, mcts_args: Dict[str, Any]):
        """
        Initialize MCTS player.
        
        Args:
            game: Game engine
            neural_network: Neural network for evaluation
            mcts_args: MCTS configuration
        """
        self.game = game
        self.mcts = MCTS(game, neural_network, mcts_args)
        self.mcts_args = mcts_args
        
        # Player settings
        self.temperature_threshold = mcts_args.get('temperature_threshold', 10)
        self.move_count = 0
        
    def get_action(self, board, current_player: int) -> int:
        """
        Get action for current board state.
        
        Args:
            board: Board state
            current_player: Current player
            
        Returns:
            Selected action
        """
        # Use temperature early in game, then deterministic
        temperature = 1.0 if self.move_count < self.temperature_threshold else 0.0
        
        action = self.mcts.select_action(board, current_player, temperature)
        self.move_count += 1
        
        return action
    
    def update_with_move(self, action: int):
        """
        Update internal state after a move.
        
        Args:
            action: Action that was taken
        """
        self.mcts.update_root(action)
    
    def reset_for_new_game(self):
        """Reset for a new game."""
        self.mcts.reset_tree()
        self.move_count = 0
    
    def get_move_probabilities(self, board, current_player: int) -> np.ndarray:
        """
        Get move probabilities without selecting.
        
        Args:
            board: Board state
            current_player: Current player
            
        Returns:
            Action probabilities
        """
        temperature = 1.0 if self.move_count < self.temperature_threshold else 0.0
        return self.mcts.get_action_probabilities(board, current_player, temperature)
