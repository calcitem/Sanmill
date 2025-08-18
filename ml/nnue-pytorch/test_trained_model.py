#!/usr/bin/env python3
"""
Simple test script for the trained NNUE model
"""

import os
import sys
import torch

def test_model():
    """Test the trained model"""
    print("Testing trained NNUE model...")
    
    model_path = "logs/lightning_logs/version_7/checkpoints/last.ckpt"
    
    if not os.path.exists(model_path):
        print(f"❌ Model not found: {model_path}")
        return False
    
    try:
        # Import required modules
        import model as M
        from features import get_feature_set_from_name
        
        # Load feature set
        feature_set = get_feature_set_from_name("NineMill")
        print(f"✅ Feature set loaded: {feature_set}")
        
        # Load model
        nnue_model = M.NNUE.load_from_checkpoint(
            model_path,
            feature_set=feature_set,
            map_location='cpu'
        )
        
        print(f"✅ Model loaded successfully")
        print(f"   Parameters: {sum(p.numel() for p in nnue_model.parameters()):,}")
        
        # Test with dummy data
        batch_size = 1
        us = torch.tensor([[1.0]], dtype=torch.float32)
        them = torch.tensor([[0.0]], dtype=torch.float32)
        
        # Empty position test
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
            print(f"✅ Model evaluation: {output.item():.6f}")
        
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_model()
    if success:
        print("\n🎉 训练成果测试成功！")
        print("模型可以正常加载和推理")
    else:
        print("\n❌ 测试失败")
