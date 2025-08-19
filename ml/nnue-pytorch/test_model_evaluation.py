#!/usr/bin/env python3
"""
测试训练好的 NNUE 模型的评估功能
"""

import os
import sys
import torch
import json

# 添加路径
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from game.Game import Game

def test_model_evaluation():
    """测试模型对不同局面的评估"""
    print("🎯 测试 NNUE 模型评估功能...")
    
    # 加载配置和模型
    config_path = "nnue_pit_config.json"
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    try:
        from nnue_pit import NNUEModelLoader, NNUEGameAdapter, NNUEPlayer
        
        # 加载模型
        model_loader = NNUEModelLoader(
            model_path=config["model_path"],
            feature_size=config["feature_size"],
            feature_set_name=config["feature_set"]
        )
        
        model = model_loader.load_model()
        print("✅ NNUE 模型加载成功")
        
        # 创建NNUE玩家（用于评估）
        nnue_player = NNUEPlayer(model_loader, search_depth=1)  # 深度1用于快速评估
        
        # 创建游戏适配器
        adapter = NNUEGameAdapter()
        
        # 测试不同的局面
        test_positions = [
            {
                "name": "开局状态",
                "description": "游戏开始，空棋盘"
            },
            {
                "name": "放子阶段",
                "description": "放置一些棋子后",
                "moves": [(3, 3), (1, 1), (3, 1), (5, 5)]
            },
            {
                "name": "复杂局面",
                "description": "多个棋子的复杂局面",
                "moves": [(3, 3), (1, 1), (3, 1), (5, 5), (3, 5), (1, 3), (5, 3), (3, 0)]
            }
        ]
        
        for i, pos in enumerate(test_positions):
            print(f"\n🔍 测试局面 {i+1}: {pos['name']}")
            print(f"   描述: {pos['description']}")
            
            # 重置游戏
            adapter = NNUEGameAdapter()
            
            # 执行移动
            if 'moves' in pos:
                valid_moves = adapter.get_valid_moves()
                for move in pos['moves']:
                    if move in valid_moves:
                        adapter.make_move(move)
                        print(f"   执行移动: {move}")
                    else:
                        print(f"   无效移动: {move} (可用移动: {len(valid_moves)})")
                        break
            
            # 评估当前局面
            try:
                evaluation = nnue_player.evaluate_position(adapter)
                print(f"   🧠 NNUE 评估: {evaluation:.6f}")
                
                # 显示当前局面信息
                print(f"   🎮 当前玩家: {'白方' if adapter.side_to_move == 0 else '黑方'}")
                print(f"   📊 白方棋子: {adapter.white_pieces_on_board}")
                print(f"   📊 黑方棋子: {adapter.black_pieces_on_board}")
                print(f"   🎯 游戏阶段: {adapter.phase}")
                
            except Exception as e:
                print(f"   ❌ 评估失败: {e}")
        
        print(f"\n🎉 模型评估测试完成!")
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_model_evaluation()
    if success:
        print("\n✅ NNUE 模型评估功能正常!")
        print("现在可以使用以下方式进行对弈:")
        print("  1. GUI界面: python nnue_pit.py --config nnue_pit_config.json --gui")
        print("  2. 命令行: python nnue_pit.py --config nnue_pit_config.json --games 1")
    else:
        print("\n❌ 模型评估测试失败，请检查配置。")
