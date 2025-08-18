#!/usr/bin/env python3

"""
Example usage of the Nine Men's Morris NNUE training system.

This script demonstrates how to:
1. Create training data
2. Set up feature extraction
3. Train a network
4. Serialize the trained model
"""

import os
import torch
import numpy as np
from features_mill import NineMillFeatures, FactorizedNineMillFeatures
from data_loader import create_mill_data_loader, MillPosition
from features import FeatureSet
import model as M
from serialize import NNUEWriter


def create_sample_training_data(filename: str, num_positions: int = 1000):
    """Create sample training data for demonstration."""
    print(f"Creating {num_positions} sample positions...")
    
    positions = []
    for i in range(num_positions):
        # Create random positions for demonstration
        # In practice, these would come from actual games
        
        # Random piece placement (simplified)
        white_pieces = np.random.choice(24, size=np.random.randint(3, 9), replace=False).tolist()
        black_pieces = np.random.choice(
            [pos for pos in range(24) if pos not in white_pieces], 
            size=np.random.randint(3, 9), 
            replace=False
        ).tolist()
        
        # Create FEN-like string for Nine Men's Morris
        board = ['*'] * 24
        for pos in white_pieces:
            board[pos] = 'O'
        for pos in black_pieces:
            board[pos] = '@'
        
        board_str = ''.join(board)
        side = 'w' if i % 2 == 0 else 'b'
        phase = 'p' if np.random.random() < 0.5 else 'm'
        action = 'p' if phase == 'p' else 's'
        
        # Random game state values
        white_on_board = len(white_pieces)
        white_in_hand = max(0, 9 - white_on_board)
        black_on_board = len(black_pieces)
        black_in_hand = max(0, 9 - black_on_board)
        
        # Random evaluation and result
        evaluation = np.random.normal(0, 100)  # Centered around 0
        result = np.random.choice([-1.0, 0.0, 1.0], p=[0.4, 0.2, 0.4])
        best_move = "a1"  # Placeholder
        
        # Create training data line
        fen = f"{board_str} {side} {phase} {action} {white_on_board} {white_in_hand} {black_on_board} {black_in_hand} 0 0 0 0 0 0"
        line = f"{fen} {evaluation:.1f} {best_move} {result}"
        positions.append(line)
    
    # Write to file
    os.makedirs(os.path.dirname(filename) if os.path.dirname(filename) else '.', exist_ok=True)
    with open(filename, 'w') as f:
        for line in positions:
            f.write(line + '\n')
    
    print(f"Sample data written to {filename}")


def demonstrate_feature_extraction():
    """Demonstrate feature extraction for Nine Men's Morris."""
    print("\n=== Feature Extraction Demo ===")
    
    # Create feature sets
    basic_features = NineMillFeatures()
    factorized_features = FactorizedNineMillFeatures()
    
    print(f"Basic features: {basic_features.name}")
    print(f"Feature dimensions: {basic_features.num_features}")
    print(f"Factorized features: {factorized_features.name}")
    print(f"Total features (real + virtual): {factorized_features.num_features}")
    
    # Example position
    board_state = {
        'white_pieces': [8, 16, 24],  # 3 white pieces
        'black_pieces': [9, 17, 25],  # 3 black pieces  
        'side_to_move': 'white'
    }
    
    # Extract features
    white_features, black_features = basic_features.get_active_features(board_state)
    print(f"Active white features: {torch.sum(white_features).item()}")
    print(f"Active black features: {torch.sum(black_features).item()}")
    
    # Show PSQT values
    psqt_values = basic_features.get_initial_psqt_features()
    print(f"PSQT values range: [{min(psqt_values):.1f}, {max(psqt_values):.1f}]")


def demonstrate_training():
    """Demonstrate the training setup."""
    print("\n=== Training Demo ===")
    
    # Create sample data
    train_file = "sample_data/train.txt"
    val_file = "sample_data/val.txt"
    
    create_sample_training_data(train_file, 500)
    create_sample_training_data(val_file, 100)
    
    # Set up feature set
    feature_set = FeatureSet([NineMillFeatures()])
    print(f"Using feature set: {feature_set.name}")
    
    # Create data loaders
    train_loader = create_mill_data_loader(
        [train_file], feature_set, batch_size=32, shuffle=True
    )
    val_loader = create_mill_data_loader(
        [val_file], feature_set, batch_size=32, shuffle=False
    )
    
    print(f"Training batches: {len(train_loader)}")
    print(f"Validation batches: {len(val_loader)}")
    
    # Create model
    model = M.NNUE(
        feature_set=feature_set,
        max_epoch=10,  # Small number for demo
        lr=1e-3
    )
    
    print(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")
    
    # Test forward pass
    for batch in train_loader:
        # Set up model for batch processing
        if hasattr(model, 'layer_stacks') and hasattr(model.layer_stacks, 'idx_offset'):
            model.layer_stacks.idx_offset = torch.arange(
                0, len(batch['us']) * model.layer_stacks.count, 
                model.layer_stacks.count
            )
        
        output = model(
            batch['us'], batch['them'],
            batch['white_indices'], batch['white_values'],
            batch['black_indices'], batch['black_values'],
            batch['psqt_indices'], batch['layer_stack_indices']
        )
        print(f"Forward pass successful, output shape: {output.shape}")
        break
    
    return model


def demonstrate_serialization(model):
    """Demonstrate model serialization."""
    print("\n=== Serialization Demo ===")
    
    # Serialize the model
    writer = NNUEWriter(model, description="Demo Nine Men's Morris NNUE network")
    
    # Save to file
    output_file = "sample_models/demo_mill.nnue"
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    with open(output_file, 'wb') as f:
        f.write(writer.buf)
    
    file_size = len(writer.buf)
    print(f"Model serialized to {output_file}")
    print(f"File size: {file_size} bytes ({file_size/1024:.1f} KB)")


def main():
    """Run all demonstrations."""
    print("Nine Men's Morris NNUE Training System Demo")
    print("=" * 50)
    
    # Set random seed for reproducibility
    torch.manual_seed(42)
    np.random.seed(42)
    
    try:
        # Demonstrate feature extraction
        demonstrate_feature_extraction()
        
        # Demonstrate training setup
        model = demonstrate_training()
        
        # Demonstrate serialization
        demonstrate_serialization(model)
        
        print("\n=== Demo Completed Successfully ===")
        print("\nTo train a real network:")
        print("1. Prepare actual training data from Nine Men's Morris games")
        print("2. Run: python train.py your_training_data.txt")
        print("3. Use the trained model in your Nine Men's Morris engine")
        
    except Exception as e:
        print(f"Demo failed with error: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        # Cleanup demo files
        import shutil
        for dir_name in ["sample_data", "sample_models"]:
            if os.path.exists(dir_name):
                shutil.rmtree(dir_name)
                print(f"Cleaned up {dir_name}/")


if __name__ == "__main__":
    main()
