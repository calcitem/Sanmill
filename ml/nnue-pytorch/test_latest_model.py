#!/usr/bin/env python3
"""
测试最新训练的 NNUE 模型加载
"""

import os
import sys
import torch
import json

# 添加路径
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

def test_latest_model():
    """测试加载最新训练的模型"""
    print("🧪 测试最新训练的 NNUE 模型...")
    
    # 加载配置
    config_path = "nnue_pit_config.json"
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    model_path = config["model_path"]
    feature_set_name = config["feature_set"]
    
    print(f"📁 模型路径: {model_path}")
    print(f"🔧 特征集: {feature_set_name}")
    print(f"📏 特征维度: {config['feature_size']}")
    
    # 检查模型文件是否存在
    if not os.path.exists(model_path):
        print(f"❌ 模型文件不存在: {model_path}")
        print("\n可用的模型文件:")
        for root, dirs, files in os.walk("logs"):
            for file in files:
                if file.endswith('.ckpt'):
                    full_path = os.path.join(root, file)
                    print(f"  - {full_path}")
        return False
    
    try:
        # 导入必要的模块
        import model as M
        from features import get_feature_set_from_name
        
        print(f"✅ 模型文件存在: {model_path}")
        
        # 创建特征集
        feature_set = get_feature_set_from_name(feature_set_name)
        print(f"✅ 特征集创建成功: {type(feature_set).__name__}")
        print(f"   实际特征数: {feature_set.num_real_features}")
        print(f"   虚拟特征数: {feature_set.num_virtual_features}")
        print(f"   总特征数: {feature_set.num_features}")
        
        # 加载模型
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        print(f"🔧 使用设备: {device}")
        
        nnue_model = M.NNUE.load_from_checkpoint(
            model_path,
            feature_set=feature_set,
            map_location=device
        )
        
        nnue_model.to(device)
        nnue_model.eval()
        
        print(f"✅ 模型加载成功!")
        print(f"   模型类型: {type(nnue_model).__name__}")
        print(f"   参数数量: {sum(p.numel() for p in nnue_model.parameters()):,}")
        print(f"   可训练参数: {sum(p.numel() for p in nnue_model.parameters() if p.requires_grad):,}")
        
        # 初始化 idx_offset (推理时批量大小为1)
        if hasattr(nnue_model, 'layer_stacks') and hasattr(nnue_model.layer_stacks, 'idx_offset'):
            if nnue_model.layer_stacks.idx_offset is None:
                batch_size = 1
                nnue_model.layer_stacks.idx_offset = torch.arange(
                    0,
                    batch_size * nnue_model.layer_stacks.count,
                    nnue_model.layer_stacks.count,
                    device=device
                )
                print(f"✅ 初始化 idx_offset (batch_size={batch_size})")
        
        # 测试模型推理
        print("\n🔬 测试模型推理...")
        
        # 创建测试输入（空棋盘状态）
        batch_size = 1
        us = torch.tensor([[1.0]], dtype=torch.float32, device=device)
        them = torch.tensor([[0.0]], dtype=torch.float32, device=device)
        
        # 空的稀疏特征
        white_indices = torch.zeros((batch_size, 1), dtype=torch.int32, device=device)
        white_values = torch.zeros((batch_size, 1), dtype=torch.float32, device=device)
        black_indices = torch.zeros((batch_size, 1), dtype=torch.int32, device=device)
        black_values = torch.zeros((batch_size, 1), dtype=torch.float32, device=device)
        
        psqt_indices = torch.tensor([0], dtype=torch.long, device=device)
        layer_stack_indices = torch.tensor([0], dtype=torch.long, device=device)
        
        # 前向推理
        with torch.no_grad():
            output = nnue_model(
                us, them,
                white_indices, white_values,
                black_indices, black_values,
                psqt_indices, layer_stack_indices
            )
        
        print(f"✅ 模型推理成功!")
        print(f"   输出形状: {output.shape}")
        print(f"   输出值: {output.item():.6f}")
        
        return True
        
    except Exception as e:
        print(f"❌ 模型加载失败: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_latest_model()
    if success:
        print("\n🎉 模型测试成功! 可以使用 nnue_pit.py 进行对弈了。")
        print("\n启动命令:")
        print("  python nnue_pit.py --config nnue_pit_config.json --gui")
    else:
        print("\n❌ 模型测试失败，请检查配置和模型文件。")
