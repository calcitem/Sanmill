#!/usr/bin/env python3
"""
Test script for loading NNUE models in nnue-pytorch
"""

import os
import sys
import torch

# Add paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

def test_pytorch_lightning_model():
    """Test loading PyTorch Lightning model"""
    print("Testing PyTorch Lightning model loading...")
    
    try:
        import model as M
        from features import get_feature_set_from_name
        
        model_path = "logs/lightning_logs/version_7/checkpoints/last.ckpt"
        
        if not os.path.exists(model_path):
            print(f"❌ Model file not found: {model_path}")
            return False
        
        print(f"📁 Model file found: {model_path}")
        
        # Create feature set
        feature_set = get_feature_set_from_name("NineMill")
        print(f"✅ Feature set created: {feature_set}")
        
        # Load model
        nnue_model = M.NNUE.load_from_checkpoint(
            model_path,
            feature_set=feature_set,
            map_location='cpu'
        )
        
        nnue_model.eval()
        print(f"✅ Model loaded successfully")
        print(f"   Model type: {type(nnue_model)}")
        print(f"   Device: {next(nnue_model.parameters()).device}")
        
        # Test evaluation
        print("\n🔬 Testing model evaluation...")
        
        # Create dummy input
        batch_size = 1
        us = torch.tensor([[1.0]], dtype=torch.float32)
        them = torch.tensor([[0.0]], dtype=torch.float32)
        
        # Dummy sparse features (empty position)
        white_indices = torch.zeros((batch_size, 1), dtype=torch.int32)
        white_values = torch.zeros((batch_size, 1), dtype=torch.float32)
        black_indices = torch.zeros((batch_size, 1), dtype=torch.int32)
        black_values = torch.zeros((batch_size, 1), dtype=torch.float32)
        
        psqt_indices = torch.tensor([0], dtype=torch.long)
        layer_stack_indices = torch.tensor([0], dtype=torch.long)
        
        with torch.no_grad():
            output = nnue_model(
                us, them,
                white_indices, white_values,
                black_indices, black_values,
                psqt_indices, layer_stack_indices
            )
            print(f"✅ Model evaluation successful: {output.item():.6f}")
        
        return True
        
    except Exception as e:
        print(f"❌ PyTorch Lightning model test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_model_file_exists():
    """Test if model files exist"""
    print("Checking for model files...")
    
    model_paths = [
        "logs/lightning_logs/version_7/checkpoints/last.ckpt",
        "logs/checkpoints/last.ckpt",
        "mill_nnue_final.pth"
    ]
    
    for path in model_paths:
        if os.path.exists(path):
            size = os.path.getsize(path) / (1024 * 1024)  # MB
            print(f"✅ Found: {path} ({size:.1f} MB)")
        else:
            print(f"❌ Missing: {path}")

def main():
    """Main test function"""
    print("NNUE Model Loading Test for nnue-pytorch")
    print("=" * 50)
    
    # Check model files
    test_model_file_exists()
    
    print("\n" + "=" * 50)
    
    # Test PyTorch Lightning model loading
    success = test_pytorch_lightning_model()
    
    print("\n" + "=" * 50)
    if success:
        print("🎉 Model loading test completed successfully!")
        print("\n📋 Next steps:")
        print("  1. Test GUI: python nnue_pit.py --config nnue_pit_config.json --gui")
        print("  2. Test console: python nnue_pit.py --model logs/lightning_logs/version_7/checkpoints/last.ckpt")
    else:
        print("❌ Model loading test failed")
        print("Please check the model file and dependencies")

if __name__ == "__main__":
    main()
