#!/usr/bin/env python3
"""
Comprehensive testing script for symmetry system.
"""

import numpy as np
from symmetry import (
    build_geometric_transforms, 
    apply_geometry_to_features,
    apply_color_flip_to_features,
    apply_geometry_to_pi,
    apply_geometry_to_pos_vector,
    validate_symmetry_consistency,
    test_all_symmetries,
    get_symmetry_statistics
)

def test_geometric_transforms():
    """Test geometric transform construction."""
    print("Testing geometric transforms construction...")
    
    transforms = build_geometric_transforms()
    print(f"✓ Built {len(transforms)} geometric transforms")
    
    # Validate transform structure
    for i, transform in enumerate(transforms[:3]):  # Test first 3
        rot = transform['rot']
        flip = transform['flip']
        print(f"  Transform {i}: rot={rot}, flip={flip}")
        
        # Validate mapping ranges
        pos_map = transform['pos_map24']
        action_map = transform['action_map576']
        
        assert pos_map.shape == (24,), f"pos_map24 wrong shape: {pos_map.shape}"
        assert action_map.shape == (576,), f"action_map576 wrong shape: {action_map.shape}"
        
        assert np.all(pos_map >= 0) and np.all(pos_map < 24), "Invalid pos_map24 range"
        assert np.all(action_map >= 0) and np.all(action_map < 576), "Invalid action_map576 range"
    
    print("✓ Transform structure validation passed")
    return True

def test_feature_transformations():
    """Test feature transformation functions."""
    print("Testing feature transformations...")
    
    # Create test features
    test_features = np.random.rand(32, 7, 7).astype(np.float32)
    
    # Test geometric transformation
    transformed_geom = apply_geometry_to_features(test_features, rot=1, flip=True)
    print(f"✓ Geometric transformation: {test_features.shape} -> {transformed_geom.shape}")
    
    # Test color flip
    transformed_color = apply_color_flip_to_features(test_features)
    print(f"✓ Color flip transformation: {test_features.shape} -> {transformed_color.shape}")
    
    # Validate shape preservation
    assert transformed_geom.shape == test_features.shape, "Geometric transform changed shape"
    assert transformed_color.shape == test_features.shape, "Color flip changed shape"
    
    print("✓ Feature transformations working correctly")
    return True

def test_policy_transformations():
    """Test policy transformation functions."""
    print("Testing policy transformations...")
    
    # Create test policy
    test_policy = np.random.rand(576).astype(np.float32)
    test_policy = test_policy / np.sum(test_policy)  # Normalize
    
    transforms = build_geometric_transforms()
    transform = transforms[1]  # Use second transform
    
    transformed_policy = apply_geometry_to_pi(test_policy, transform['action_map576'])
    
    # Validate policy properties
    original_sum = np.sum(test_policy)
    transformed_sum = np.sum(transformed_policy)
    
    print(f"✓ Policy transformation: sum before={original_sum:.6f}, after={transformed_sum:.6f}")
    assert abs(original_sum - transformed_sum) < 1e-6, "Policy sum not preserved"
    
    print("✓ Policy transformations working correctly")
    return True

def test_position_transformations():
    """Test position vector transformation functions."""
    print("Testing position vector transformations...")
    
    # Create test ownership vector
    test_ownership = np.random.rand(24).astype(np.float32) * 2 - 1  # [-1, 1]
    
    transforms = build_geometric_transforms()
    transform = transforms[2]  # Use third transform
    
    transformed_ownership = apply_geometry_to_pos_vector(test_ownership, transform['pos_map24'])
    
    print(f"✓ Ownership transformation: shape {test_ownership.shape} -> {transformed_ownership.shape}")
    assert transformed_ownership.shape == test_ownership.shape, "Shape not preserved"
    
    print("✓ Position vector transformations working correctly")
    return True

def test_input_validation():
    """Test input validation for symmetry functions."""
    print("Testing input validation...")
    
    # Test invalid feature shape
    try:
        apply_color_flip_to_features(np.random.rand(5, 5))  # Wrong shape
        print("✗ Should have caught invalid shape")
        return False
    except ValueError as e:
        print(f"✓ Correctly caught invalid shape: {e}")
    
    # Test valid feature shape
    try:
        valid_features = np.random.rand(32, 7, 7)
        result = apply_color_flip_to_features(valid_features)
        print("✓ Valid features processed correctly")
    except Exception as e:
        print(f"✗ Valid features failed: {e}")
        return False
    
    print("✓ Input validation working correctly")
    return True

def test_symmetry_consistency():
    """Test symmetry consistency validation."""
    print("Testing symmetry consistency validation...")
    
    # Create test data
    test_features = np.random.rand(32, 7, 7).astype(np.float32)
    test_policy = np.random.rand(576).astype(np.float32)
    test_policy = test_policy / np.sum(test_policy)  # Normalize
    
    test_aux = {
        'ownership': np.random.rand(24).astype(np.float32) * 2 - 1,
        'mill_potential': np.random.rand(24).astype(np.float32),
        'score': np.array([0.5], dtype=np.float32)
    }
    
    # Test first few transforms
    transforms = build_geometric_transforms()
    for i in range(min(3, len(transforms))):
        is_valid = validate_symmetry_consistency(test_features, test_policy, test_aux, i)
        print(f"✓ Transform {i} consistency: {is_valid}")
        if not is_valid:
            print(f"✗ Transform {i} failed consistency check")
            return False
    
    print("✓ Symmetry consistency validation passed")
    return True

def test_comprehensive_validation():
    """Test comprehensive symmetry validation."""
    print("Testing comprehensive symmetry validation...")
    
    try:
        results = test_all_symmetries()
        passed = sum(results.values())
        total = len(results)
        print(f"✓ Comprehensive validation: {passed}/{total} transforms passed")
        
        if passed < total:
            print("⚠ Some transforms failed validation:")
            for name, result in results.items():
                if not result:
                    print(f"  ✗ {name}")
        
        return passed == total
        
    except Exception as e:
        print(f"✗ Comprehensive validation failed: {e}")
        return False

def test_statistics():
    """Test symmetry statistics."""
    print("Testing symmetry statistics...")
    
    try:
        stats = get_symmetry_statistics()
        
        print(f"✓ Geometric transforms: {stats['num_geometric_transforms']}")
        print(f"✓ Total variants: {stats['num_total_variants']}")
        print(f"✓ Position mapping size: {stats['position_mapping_size']}")
        print(f"✓ Action mapping size: {stats['action_mapping_size']}")
        
        # Validate statistics
        assert stats['num_geometric_transforms'] == 8, "Should have 8 geometric transforms"
        assert stats['num_total_variants'] == 16, "Should have 16 total variants"
        assert stats['position_mapping_size'] == 24, "Should have 24 position mappings"
        assert stats['action_mapping_size'] == 576, "Should have 576 action mappings"
        
        print("✓ Statistics validation passed")
        return True
        
    except Exception as e:
        print(f"✗ Statistics test failed: {e}")
        return False

def main():
    """Run all symmetry tests."""
    print("=== Symmetry System Component Testing ===")
    
    tests = [
        test_geometric_transforms,
        test_feature_transformations,
        test_policy_transformations,
        test_position_transformations,
        test_input_validation,
        test_symmetry_consistency,
        test_comprehensive_validation,
        test_statistics
    ]
    
    success = True
    for test_func in tests:
        try:
            result = test_func()
            success &= result
            print()
        except Exception as e:
            print(f"✗ Test {test_func.__name__} failed with error: {e}")
            success = False
    
    if success:
        print("✓ All symmetry tests passed successfully")
    else:
        print("✗ Some symmetry tests failed")
    
    return success

if __name__ == '__main__':
    main()
