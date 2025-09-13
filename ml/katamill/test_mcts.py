#!/usr/bin/env python3
"""
Comprehensive testing script for MCTS implementation.
"""

import torch
import numpy as np
from config import MCTSConfig
from neural_network import KatamillNet, KatamillWrapper
from mcts import MCTS, MCTSNode

class MockBoard:
    def __init__(self):
        self.pieces = np.zeros((7, 7), dtype=int)
        self.allowed_places = np.array([
            [True, False, False, True, False, False, True],
            [False, True, False, True, False, True, False],
            [False, False, True, True, True, False, False],
            [True, True, True, False, True, True, True],
            [False, False, True, True, True, False, False],
            [False, True, False, True, False, True, False],
            [True, False, False, True, False, False, True]
        ])
        self.period = 1
        self.put_pieces = 4
        self.move_counter = 10
        
    def count(self, player):
        return np.sum(self.pieces == player)

class MockGame:
    def getActionSize(self):
        return 576
    
    def getValidMoves(self, board, player):
        valid = np.zeros(576)
        valid[:10] = 1  # First 10 actions are valid
        return valid
    
    def getNextState(self, board, player, action):
        # Simulate Nine Men's Morris consecutive moves
        if action < 5:  # Normal moves - player changes
            return board, -player
        else:  # Consecutive moves - same player (removal after mill)
            return board, player
    
    def getGameEnded(self, board, player):
        return 0  # Game continues
    
    def stringRepresentation(self, board):
        return str(hash(str(board.pieces.tobytes())))
    
    def getCanonicalForm(self, board, player):
        return board

class MockWrapper:
    def predict(self, board, player):
        policy = np.random.random(576)
        policy = policy / np.sum(policy)  # Normalize
        value = np.random.random() * 2 - 1  # [-1, 1]
        return policy, value

def test_mcts_node():
    """Test MCTS node functionality."""
    print("Testing MCTS Node...")
    
    board = MockBoard()
    node = MCTSNode(board, 1, action=None, parent=None, prior_prob=0.5)
    
    print(f"✓ Node created: player={node.current_player}, prior={node.prior_prob}")
    print(f"✓ Initial visit count: {node.visit_count}")
    print(f"✓ Initial value: {node.get_value()}")
    
    # Test value backup
    node.backup(0.3)
    node.backup(0.7)
    print(f"✓ After 2 backups: visits={node.visit_count}, value={node.get_value():.3f}")
    
    # Test variance calculation
    variance = node.get_value_variance()
    print(f"✓ Value variance: {variance:.3f}")
    
    # Test virtual loss
    node.add_virtual_loss()
    effective_visits = node.get_effective_visit_count()
    print(f"✓ With virtual loss: effective_visits={effective_visits}")
    
    node.remove_virtual_loss()
    effective_visits_after = node.get_effective_visit_count()
    print(f"✓ After removing virtual loss: effective_visits={effective_visits_after}")
    
    # Test consecutive move detection
    parent_node = MCTSNode(board, 1, action=0, parent=None, prior_prob=0.3)
    child_same_player = MCTSNode(board, 1, action=1, parent=parent_node, prior_prob=0.2)
    child_diff_player = MCTSNode(board, -1, action=2, parent=parent_node, prior_prob=0.2)
    
    print(f"✓ Consecutive move detection:")
    print(f"  Same player child: {child_same_player.is_consecutive_move}")
    print(f"  Different player child: {child_diff_player.is_consecutive_move}")
    
    return True

def test_mcts_search():
    """Test MCTS search functionality."""
    print("Testing MCTS Search...")
    
    game = MockGame()
    wrapper = MockWrapper()
    board = MockBoard()
    
    # Test with minimal simulations
    config = MCTSConfig.fast()
    config.num_simulations = 5  # Very small for testing
    
    mcts = MCTS(game, wrapper, config.__dict__)
    
    # Test search statistics structure
    stats = mcts.get_search_statistics()
    required_stats = ['total_simulations', 'transposition_hits', 'consecutive_moves_found', 
                      'terminal_nodes_reached', 'max_depth_reached', 'depth_limit_hits']
    
    for stat_name in required_stats:
        assert stat_name in stats, f'Missing statistic: {stat_name}'
    
    print(f"✓ Search statistics structure correct")
    print(f"✓ Max search depth: {mcts.max_search_depth}")
    
    # Test policy generation (basic functionality)
    try:
        probs = mcts.get_action_probabilities(board, 1, temperature=1.0)
        
        print(f"✓ Policy generated: shape={probs.shape}")
        print(f"✓ Policy sum: {np.sum(probs):.6f}")
        
        # Validate policy properties
        assert probs.shape[0] == 576, f'Policy size mismatch: {probs.shape}'
        assert abs(np.sum(probs) - 1.0) < 1e-5, f'Policy not normalized: sum={np.sum(probs)}'
        assert np.all(probs >= 0), 'Policy has negative probabilities'
        
        # Check search statistics after search
        final_stats = mcts.get_search_statistics()
        print(f"✓ Simulations completed: {final_stats['total_simulations']}")
        print(f"✓ Max depth reached: {final_stats['max_depth_reached']}")
        
        return True
        
    except Exception as e:
        print(f"✗ MCTS search failed: {e}")
        return False

def main():
    """Run all MCTS tests."""
    print("=== MCTS Component Testing ===")
    
    success = True
    
    try:
        success &= test_mcts_node()
        print()
        success &= test_mcts_search()
        
        if success:
            print("\\n✓ All MCTS tests passed successfully")
        else:
            print("\\n✗ Some MCTS tests failed")
            
    except Exception as e:
        print(f"\\n✗ MCTS testing failed with error: {e}")
        success = False
    
    return success

if __name__ == '__main__':
    main()
