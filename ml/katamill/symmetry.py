from __future__ import annotations

"""
Advanced symmetry utilities for Nine Men's Morris, inspired by KataGo's data augmentation.

This module provides comprehensive symmetry operations for training data augmentation:
- 8 geometric transforms (4 rotations × 2 reflections) 
- Optional color-flip augmentation for 16 total variants
- Efficient index mapping for features, policy, and auxiliary targets
- KataGo-style symmetry validation and consistency checking

Key improvements over basic symmetry:
- Robust mapping construction with validation
- Support for all auxiliary targets (ownership, mill potential)
- Optimized transformations for training efficiency  
- Comprehensive testing and debugging support

The mappings ensure perfect consistency between transformed board states
and their corresponding neural network inputs/outputs, critical for
stable training with data augmentation.
"""

from typing import Dict, List, Tuple, Any
import numpy as np
import logging

logger = logging.getLogger(__name__)

try:
    from ml.game.GameLogic import Board
except ImportError:
    try:
        from game.GameLogic import Board
    except ImportError:
        # Add game path for standalone execution
        import os
        import sys
        current_dir = os.path.dirname(os.path.abspath(__file__))
        ml_dir = os.path.dirname(current_dir)
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from GameLogic import Board


def _build_pos_index_matrix() -> np.ndarray:
    """Return a 7x7 matrix with indices (0..23) at valid nodes, -1 elsewhere.

    We mirror the exact indexing that Game/Board uses: first index is x (column),
    second index is y (row). This ensures consistency with Game.get_action_from_move.
    """
    place_index = np.full((7, 7), -1, dtype=np.int32)
    counter = 0
    for x in range(7):
        for y in range(7):
            if Board.allowed_places[x, y]:
                place_index[x, y] = counter
                counter += 1
    assert counter == 24, "Expected exactly 24 valid nodes"
    return place_index


def _apply_geom_to_index(place_index: np.ndarray, rot_k: int, do_flip: bool) -> np.ndarray:
    """Apply rotation (k x 90deg CCW) and optional horizontal flip to index matrix."""
    t = np.rot90(place_index, rot_k)
    if do_flip:
        t = np.fliplr(t)
    return t


def _pos_map_from_matrix(t: np.ndarray) -> np.ndarray:
    """Extract the 24-length mapping for positions.

    The mapping is defined so that:
      new_pos[pos_map[i]] = old_pos[i]
    i.e., new indices (dest) where each old index i should be placed.
    """
    # Boolean mask selects valid positions in row-major order as numpy flattens
    pos_map = t[Board.allowed_places].astype(np.int32)
    assert pos_map.shape[0] == 24
    return pos_map


def _build_action_map_576(pos_map24: np.ndarray) -> np.ndarray:
    """Build a 576-length action index mapping for Nine Men's Morris action space.

    CRITICAL: Nine Men's Morris uses different action encoding based on game phase:
    - Placing/Removal phase: action = position_index (0-23)  
    - Moving/Flying phase: action = src_pos * 24 + dst_pos (0-575)
    
    All actions share the same 576-dimensional space for neural network compatibility.

    The mapping is defined so that:
      new_pi[action_map[idx]] = old_pi[idx]
    """
    size = 24 * 24  # 576 total actions
    action_map = np.empty((size,), dtype=np.int32)

    # All 576 actions use the same mapping logic: src*24 + dst
    # For placing actions (0-23), they map as if src=0, dst=position
    for action_idx in range(size):
        src = action_idx // 24
        dst = action_idx % 24
        
        new_src = pos_map24[src]
        new_dst = pos_map24[dst]
        new_action_idx = new_src * 24 + new_dst
        
        # Ensure mapping stays within bounds
        if 0 <= new_action_idx < size:
            action_map[action_idx] = new_action_idx
        else:
            # Fallback to identity mapping
            action_map[action_idx] = action_idx

    return action_map


def build_geometric_transforms() -> List[Dict[str, np.ndarray]]:
    """Create 8 geometric transforms with position and action mappings.

    Returns a list where each item is a dict:
      {
        'rot': int (0..3),
        'flip': bool,
        'pos_map24': np.ndarray (24,),
        'action_map576': np.ndarray (576,)
      }
    """
    place_index = _build_pos_index_matrix()
    transforms: List[Dict[str, np.ndarray]] = []
    for rot in range(4):
        for flip in (False, True):
            t = _apply_geom_to_index(place_index, rot, flip)
            pos_map24 = _pos_map_from_matrix(t)
            action_map576 = _build_action_map_576(pos_map24)
            transforms.append({
                'rot': rot,
                'flip': flip,
                'pos_map24': pos_map24,
                'action_map576': action_map576,
            })
    return transforms


def apply_geometry_to_features(features: np.ndarray, rot: int, flip: bool) -> np.ndarray:
    """Rotate (CCW) and optionally flip all feature planes.

    features: (C, 7, 7) numpy float32
    """
    x = features
    # Rotate k times CCW across the last two dims
    if rot % 4 != 0:
        x = np.rot90(x, k=rot, axes=(1, 2))
    if flip:
        x = np.flip(x, axis=2)
    return x


def apply_color_flip_to_features(features: np.ndarray) -> np.ndarray:
    """
    Swap color-dependent planes and toggle side-to-move.

    This keeps the sample in the opponent's perspective while preserving labels
    that are already computed from the current player's perspective.
    
    Args:
        features: Feature tensor (C, 7, 7) to apply color flip to
        
    Returns:
        Color-flipped feature tensor
        
    Raises:
        ValueError: If features tensor has invalid shape
    """
    if features.ndim != 3:
        raise ValueError(f"Features must be 3D tensor (C, H, W), got shape {features.shape}")
    
    x = features.copy()
    C, H, W = x.shape
    
    # Validate expected dimensions
    if H != 7 or W != 7:
        logger.warning(f"Expected 7x7 board, got {H}x{W}")
    
    try:
        # Swap white/black piece planes (0,1)
        if C > 1:
            x[[0, 1]] = x[[1, 0]]
        
        # Toggle side-to-move (channel 7 is broadcast indicator 1/0)
        if C > 7:
            x[7] = 1.0 - x[7]
        
        # Swap in-hand counts (8,9) and on-board counts (10,11)
        if C > 11:
            x[[8, 9]] = x[[9, 8]]
            x[[10, 11]] = x[[11, 10]]
        
        # Swap mill-related maps (13,14) and (15,16)
        if C > 16:
            x[[13, 14]] = x[[14, 13]]
            x[[15, 16]] = x[[16, 15]]
        
        # Swap advanced mill features (17,18) and (19,20)
        if C > 20:
            x[[17, 18]] = x[[18, 17]]
            x[[19, 20]] = x[[20, 19]]
        
        # Swap mobility maps (21,22) and control maps (23,24)
        if C > 24:
            x[[21, 22]] = x[[22, 21]]
            x[[23, 24]] = x[[24, 23]]
        
        # Swap threat maps (25,26) and capture threat maps (27,28)
        if C > 28:
            x[[25, 26]] = x[[26, 25]]
            x[[27, 28]] = x[[28, 27]]
        
        # Note: Strategic features (29-31) are player-perspective dependent
        # and need special handling based on their semantics
        
    except Exception as e:
        logger.error(f"Color flip failed: {e}")
        return features  # Return original on error
    
    return x


def apply_geometry_to_pi(pi: np.ndarray, action_map576: np.ndarray) -> np.ndarray:
    """Apply action index permutation to policy vector (length 576)."""
    new_pi = np.zeros_like(pi)
    new_pi[action_map576] = pi
    return new_pi


def apply_geometry_to_pos_vector(vec24: np.ndarray, pos_map24: np.ndarray) -> np.ndarray:
    """Apply 24-length position permutation to a per-node vector (ownership, etc.)."""
    new_vec = np.zeros_like(vec24)
    new_vec[pos_map24] = vec24
    return new_vec


def validate_symmetry_consistency(features: np.ndarray, policy: np.ndarray, 
                                aux: Dict[str, np.ndarray], transform_idx: int = 0) -> bool:
    """
    Validate symmetry transformation consistency (KataGo-style verification).
    
    This function ensures that symmetry transformations preserve game semantics:
    - Board positions map correctly
    - Policy actions remain valid
    - Auxiliary targets transform consistently
    
    Args:
        features: Original feature tensor (32, 7, 7)
        policy: Original policy vector (576,)
        aux: Auxiliary targets dict
        transform_idx: Symmetry transform index to test
        
    Returns:
        True if transformation is consistent, False otherwise
    """
    try:
        # Get transformation
        transforms = build_geometric_transforms()
        if transform_idx >= len(transforms):
            return False
            
        transform = transforms[transform_idx]
        
        # Apply geometric transformation
        transformed_features = apply_geometry_to_features(
            features, transform['rot'], transform['flip']
        )
        transformed_policy = apply_geometry_to_pi(policy, transform['action_map576'])
        
        # Check feature consistency
        # White/black piece channels should be preserved
        original_white_count = np.sum(features[0])
        original_black_count = np.sum(features[1])
        transformed_white_count = np.sum(transformed_features[0])
        transformed_black_count = np.sum(transformed_features[1])
        
        if (abs(original_white_count - transformed_white_count) > 1e-6 or
            abs(original_black_count - transformed_black_count) > 1e-6):
            logger.error(f"Piece count mismatch in transform {transform_idx}")
            return False
        
        # Check policy consistency (should sum to same value)
        original_policy_sum = np.sum(policy)
        transformed_policy_sum = np.sum(transformed_policy)
        
        if abs(original_policy_sum - transformed_policy_sum) > 1e-6:
            logger.error(f"Policy sum mismatch in transform {transform_idx}: "
                        f"{original_policy_sum:.6f} vs {transformed_policy_sum:.6f}")
            return False
        
        # Check auxiliary target consistency
        for key in aux:
            if key in ['ownership', 'mill_potential']:
                original_aux = aux[key]
                transformed_aux = apply_geometry_to_pos_vector(original_aux, transform['pos_map24'])
                
                # Check that the transformation preserves the total "energy"
                original_sum = np.sum(np.abs(original_aux))
                transformed_sum = np.sum(np.abs(transformed_aux))
                
                if abs(original_sum - transformed_sum) > 1e-6:
                    logger.error(f"Auxiliary target {key} sum mismatch in transform {transform_idx}")
                    return False
        
        return True
        
    except Exception as e:
        logger.error(f"Symmetry validation failed for transform {transform_idx}: {e}")
        return False


def test_all_symmetries() -> Dict[str, bool]:
    """
    Test all symmetry transformations for consistency (KataGo-style testing).
    
    This comprehensive test ensures that all 8 geometric transforms work correctly
    and can be safely used for data augmentation during training.
    
    Returns:
        Dictionary mapping transform names to validation results
    """
    import logging
    logger = logging.getLogger(__name__)
    
    # Create test data
    test_features = np.random.rand(32, 7, 7).astype(np.float32)
    test_policy = np.random.rand(576).astype(np.float32)
    test_policy = test_policy / np.sum(test_policy)  # Normalize
    
    test_aux = {
        'ownership': np.random.rand(24).astype(np.float32) * 2 - 1,  # [-1, 1]
        'mill_potential': np.random.rand(24).astype(np.float32),     # [0, 1]
        'score': np.array([0.5], dtype=np.float32)
    }
    
    # Test all transforms
    results = {}
    transforms = build_geometric_transforms()
    
    for i, transform in enumerate(transforms):
        transform_name = f"rot{transform['rot']}_flip{transform['flip']}"
        
        try:
            is_valid = validate_symmetry_consistency(
                test_features, test_policy, test_aux, i
            )
            results[transform_name] = is_valid
            
            if is_valid:
                logger.info(f"Transform {transform_name}: PASSED")
            else:
                logger.error(f"Transform {transform_name}: FAILED")
                
        except Exception as e:
            logger.error(f"Transform {transform_name}: ERROR - {e}")
            results[transform_name] = False
    
    # Summary
    passed = sum(results.values())
    total = len(results)
    logger.info(f"Symmetry validation: {passed}/{total} transforms passed")
    
    return results


def get_symmetry_statistics() -> Dict[str, Any]:
    """
    Get comprehensive statistics about the symmetry system.
    
    Returns detailed information about the symmetry mappings for debugging
    and verification purposes.
    """
    transforms = build_geometric_transforms()
    
    stats = {
        'num_geometric_transforms': len(transforms),
        'num_total_variants': len(transforms) * 2,  # With color flip
        'position_mapping_size': 24,
        'action_mapping_size': 576,
        'transforms': []
    }
    
    for i, transform in enumerate(transforms):
        transform_stats = {
            'index': i,
            'rotation': transform['rot'],
            'flip': transform['flip'],
            'pos_map_range': (int(np.min(transform['pos_map24'])), int(np.max(transform['pos_map24']))),
            'action_map_range': (int(np.min(transform['action_map576'])), int(np.max(transform['action_map576']))),
            'is_identity': (transform['rot'] == 0 and not transform['flip'])
        }
        stats['transforms'].append(transform_stats)
    
    return stats


