#!/usr/bin/env python3
"""
Test loading the latest trained NNUE model
"""

import os
import sys
import torch
import json

# Add paths
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

def test_latest_model():
    """Test loading the latest trained model"""
    print("🧪 Testing latest trained NNUE model...")
    
    # Load configuration
    config_path = "nnue_pit_config.json"
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    model_path = config["model_path"]
    feature_set_name = config["feature_set"]
    
    print(f"📁 Model path: {model_path}")
    print(f"🔧 Feature set: {feature_set_name}")
    print(f"📏 Feature dimensions: {config['feature_size']}")
    
    # Check if model file exists
    if not os.path.exists(model_path):
        print(f"❌ Model file does not exist: {model_path}")
        print("\nAvailable model files:")
        for root, dirs, files in os.walk("logs"):
            for file in files:
                if file.endswith('.ckpt'):
                    full_path = os.path.join(root, file)
                    print(f"  - {full_path}")
        return False
    
    try:
        # Import necessary modules
        import model as M
        from features import get_feature_set_from_name
        
        print(f"✅ Model file exists: {model_path}")
        
        # Create feature set
        feature_set = get_feature_set_from_name(feature_set_name)
        print(f"✅ Feature set created successfully: {type(feature_set).__name__}")
        print(f"   Real features: {feature_set.num_real_features}")
        print(f"   Virtual features: {feature_set.num_virtual_features}")
        print(f"   Total features: {feature_set.num_features}")
        
        # Load model
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        print(f"🔧 Using device: {device}")
        
        nnue_model = M.NNUE.load_from_checkpoint(
            model_path,
            feature_set=feature_set,
            map_location=device
        )
        
        nnue_model.to(device)
        nnue_model.eval()
        
        print(f"✅ Model loaded successfully!")
        print(f"   Model type: {type(nnue_model).__name__}")
        print(f"   Parameter count: {sum(p.numel() for p in nnue_model.parameters()):,}")
        print(f"   Trainable parameters: {sum(p.numel() for p in nnue_model.parameters() if p.requires_grad):,}")
        
        # Initialize idx_offset (batch size 1 for inference)
        if hasattr(nnue_model, 'layer_stacks') and hasattr(nnue_model.layer_stacks, 'idx_offset'):
            if nnue_model.layer_stacks.idx_offset is None:
                batch_size = 1
                nnue_model.layer_stacks.idx_offset = torch.arange(
                    0,
                    batch_size * nnue_model.layer_stacks.count,
                    nnue_model.layer_stacks.count,
                    device=device
                )
                print(f"✅ Initialized idx_offset (batch_size={batch_size})")
        
        # Test model inference
        print("\n🔬 Testing model inference...")
        
        # Create test input (empty board state)
        batch_size = 1
        us = torch.tensor([[1.0]], dtype=torch.float32, device=device)
        them = torch.tensor([[0.0]], dtype=torch.float32, device=device)
        
        # Empty sparse features
        white_indices = torch.zeros((batch_size, 1), dtype=torch.int32, device=device)
        white_values = torch.zeros((batch_size, 1), dtype=torch.float32, device=device)
        black_indices = torch.zeros((batch_size, 1), dtype=torch.int32, device=device)
        black_values = torch.zeros((batch_size, 1), dtype=torch.float32, device=device)
        
        psqt_indices = torch.tensor([0], dtype=torch.long, device=device)
        layer_stack_indices = torch.tensor([0], dtype=torch.long, device=device)
        
        # Forward inference
        with torch.no_grad():
            output = nnue_model(
                us, them,
                white_indices, white_values,
                black_indices, black_values,
                psqt_indices, layer_stack_indices
            )
        
        print(f"✅ Model inference successful!")
        print(f"   Output shape: {output.shape}")
        print(f"   Output value: {output.item():.6f}")
        
        return True
        
    except Exception as e:
        print(f"❌ Model loading failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_latest_model()
    if success:
        print("\n🎉 Model test successful! You can now use nnue_pit.py for games.")
        print("\nLaunch command:")
        print("  python nnue_pit.py --config nnue_pit_config.json --gui")
    else:
        print("\n❌ Model test failed, please check configuration and model files.")
