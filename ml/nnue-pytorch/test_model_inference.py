#!/usr/bin/env python3
"""
Test script to verify NNUE model inference works correctly
"""

import os
import sys
import torch

# Add paths for imports
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.join(current_dir, '..')
sys.path.insert(0, ml_dir)
sys.path.insert(0, current_dir)

from model import NNUE
from features_mill import NineMillFeatures

def test_model_loading():
    """Test if the model can be loaded and used for inference"""
    model_path = "logs/lightning_logs/version_7/checkpoints/last.ckpt"
    
    if not os.path.exists(model_path):
        print(f"Model not found: {model_path}")
        return False
        
    print(f"Loading model from: {model_path}")
    
    try:
        # Load the model
        model = NNUE.load_from_checkpoint(model_path)
        model.eval()
        
        print(f"✅ Model loaded successfully")
        print(f"   Feature set: {model.feature_set}")
        print(f"   Model device: {next(model.parameters()).device}")
        
        # Create a simple test position
        test_position = {
            'white_pieces': [(0, 0), (3, 0), (6, 0)],  # 3 white pieces
            'black_pieces': [(0, 6), (3, 6), (6, 6)],  # 3 black pieces  
            'side_to_move': 'white'
        }
        
        print(f"Testing with position: {test_position}")
        
        # Get features
        white_features, black_features = model.feature_set.get_active_features(test_position)
        print(f"   White features shape: {white_features.shape}")
        print(f"   Black features shape: {black_features.shape}")
        print(f"   White active features: {torch.sum(white_features).item()}")
        print(f"   Black active features: {torch.sum(black_features).item()}")
        
        # Convert to sparse format
        white_indices = torch.nonzero(white_features, as_tuple=False).flatten()
        white_values = white_features[white_indices]
        black_indices = torch.nonzero(black_features, as_tuple=False).flatten()
        black_values = black_features[black_indices]
        
        print(f"   White sparse: {len(white_indices)} indices")
        print(f"   Black sparse: {len(black_indices)} indices")
        
        # Ensure we have at least one feature
        if len(white_indices) == 0:
            white_indices = torch.tensor([0], dtype=torch.long)
            white_values = torch.tensor([0.0], dtype=torch.float32)
        if len(black_indices) == 0:
            black_indices = torch.tensor([0], dtype=torch.long)
            black_values = torch.tensor([0.0], dtype=torch.float32)
            
        # Move to model device
        device = next(model.parameters()).device
        
        # Create batch tensors (batch size = 1)
        batch_size = 1
        max_features = 64  # Reasonable maximum
        
        us = torch.tensor([1.0], dtype=torch.float32).unsqueeze(0).to(device)  # [1, 1]
        them = torch.tensor([0.0], dtype=torch.float32).unsqueeze(0).to(device)  # [1, 1]
        
        # Pad indices and values to fixed size
        white_indices_batch = torch.zeros((batch_size, max_features), dtype=torch.int32).to(device)
        white_values_batch = torch.zeros((batch_size, max_features), dtype=torch.float32).to(device)
        black_indices_batch = torch.zeros((batch_size, max_features), dtype=torch.int32).to(device)
        black_values_batch = torch.zeros((batch_size, max_features), dtype=torch.float32).to(device)
        
        # Fill actual values
        n_white = min(len(white_indices), max_features)
        n_black = min(len(black_indices), max_features)
        
        white_indices_batch[0, :n_white] = white_indices[:n_white].int().to(device)
        white_values_batch[0, :n_white] = white_values[:n_white].to(device)
        black_indices_batch[0, :n_black] = black_indices[:n_black].int().to(device)
        black_values_batch[0, :n_black] = black_values[:n_black].to(device)
        
        # Dummy PSQT and layer stack indices
        psqt_indices = torch.zeros(batch_size, dtype=torch.long).to(device)
        layer_stack_indices = torch.zeros(batch_size, dtype=torch.long).to(device)
        
        print(f"   Input tensor shapes:")
        print(f"     us: {us.shape}")
        print(f"     them: {them.shape}")
        print(f"     white_indices: {white_indices_batch.shape}")
        print(f"     white_values: {white_values_batch.shape}")
        print(f"     black_indices: {black_indices_batch.shape}")
        print(f"     black_values: {black_values_batch.shape}")
        print(f"     psqt_indices: {psqt_indices.shape}")
        print(f"     layer_stack_indices: {layer_stack_indices.shape}")
        
        # Test inference
        with torch.no_grad():
            try:
                evaluation = model(
                    us, them,
                    white_indices_batch, white_values_batch,
                    black_indices_batch, black_values_batch,
                    psqt_indices, layer_stack_indices
                )
                print(f"✅ Inference successful!")
                print(f"   Evaluation: {evaluation.item():.4f}")
                return True
                
            except Exception as e:
                print(f"❌ Inference failed: {e}")
                import traceback
                traceback.print_exc()
                return False
        
    except Exception as e:
        print(f"❌ Model loading failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    print("Testing NNUE model inference...")
    success = test_model_loading()
    if success:
        print("\n✅ All tests passed!")
    else:
        print("\n❌ Tests failed!")
    sys.exit(0 if success else 1)
