#!/usr/bin/env python3
"""
多轮 NNUE 训练使用示例
演示如何使用多轮训练脚本进行参数优化
"""

import subprocess
import sys
from pathlib import Path

def run_multiround_training():
    """运行多轮训练示例"""
    
    # 配置文件路径
    config_file = "configs/multiround_base.json"
    output_dir = "example_multiround_output"
    
    # 检查配置文件是否存在
    if not Path(config_file).exists():
        print(f"❌ 配置文件不存在: {config_file}")
        print("请先确保配置文件存在，或使用其他配置文件")
        return False
    
    print("🚀 开始多轮 NNUE 训练示例")
    print(f"📝 配置文件: {config_file}")
    print(f"📁 输出目录: {output_dir}")
    print()
    
    # 构建训练命令
    cmd = [
        sys.executable,  # python
        "train_multiround.py",
        "--config", config_file,
        "--output-dir", output_dir,
        "--max-rounds", "6",
        "--resume"  # 支持恢复训练
    ]
    
    print(f"🔧 执行命令: {' '.join(cmd)}")
    print()
    
    try:
        # 执行训练
        result = subprocess.run(cmd, cwd=Path(__file__).parent)
        
        if result.returncode == 0:
            print("✅ 多轮训练完成！")
            print(f"📊 查看结果: {output_dir}/")
            print(f"📈 训练日志: {output_dir}/multiround_training.log")
            print(f"💾 训练状态: {output_dir}/training_state.json")
            return True
        else:
            print("❌ 训练过程中出现错误")
            return False
            
    except KeyboardInterrupt:
        print("\n⏹️ 训练被用户中断")
        print("💡 可以使用 --resume 参数恢复训练")
        return False
    except Exception as e:
        print(f"❌ 执行训练时出错: {e}")
        return False

def show_usage():
    """显示使用说明"""
    print("📖 多轮 NNUE 训练使用说明")
    print("=" * 50)
    print()
    
    print("🎯 基本用法:")
    print("python train_multiround.py --config configs/multiround_base.json")
    print()
    
    print("⚙️ 主要参数:")
    print("  --config CONFIG_FILE     基础配置文件路径")
    print("  --output-dir OUTPUT_DIR  输出目录（默认: multiround_output）")
    print("  --max-rounds N           最大训练轮次（默认: 6）")
    print("  --resume                 恢复之前的训练")
    print()
    
    print("🔄 训练策略:")
    print("  轮次 1: 探索阶段   - 30k位置，80轮，lr=0.003")
    print("  轮次 2: 稳定学习   - 50k位置，120轮，lr=0.002")
    print("  轮次 3: 深化学习   - 80k位置，150轮，lr=0.0015")
    print("  轮次 4: 精细调整   - 100k位置，180轮，lr=0.001")
    print("  轮次 5: 优化阶段   - 120k位置，200轮，lr=0.0008")
    print("  轮次 6: 收敛阶段   - 150k位置，250轮，lr=0.0005")
    print()
    
    print("🧠 智能特性:")
    print("  ✅ 自动参数继承（学习率、优化器状态）")
    print("  ✅ 动态学习率调整（基于训练效果）")
    print("  ✅ 完整的检查点系统")
    print("  ✅ 训练状态恢复")
    print("  ✅ 详细的训练日志和可视化")
    print()
    
    print("📁 输出结构:")
    print("  multiround_output/")
    print("  ├── round_01/              # 第1轮训练结果")
    print("  ├── round_02/              # 第2轮训练结果")
    print("  ├── ...                    # 其他轮次")
    print("  ├── multiround_training.log # 总体训练日志")
    print("  └── training_state.json    # 训练状态文件")
    print()
    
    print("💡 使用建议:")
    print("  1. 首次运行使用默认配置，观察训练效果")
    print("  2. 根据硬件性能调整批量大小和位置数量")
    print("  3. 使用 --resume 参数可以随时恢复中断的训练")
    print("  4. 关注 training_state.json 中的参数继承情况")

def main():
    """主函数"""
    if len(sys.argv) > 1:
        if sys.argv[1] in ["-h", "--help", "help"]:
            show_usage()
            return
        elif sys.argv[1] == "run":
            run_multiround_training()
            return
    
    print("🎮 多轮 NNUE 训练示例脚本")
    print()
    print("选择操作:")
    print("1. 运行多轮训练示例")
    print("2. 显示使用说明")
    print("3. 退出")
    print()
    
    while True:
        try:
            choice = input("请输入选择 (1-3): ").strip()
            
            if choice == "1":
                run_multiround_training()
                break
            elif choice == "2":
                show_usage()
                break
            elif choice == "3":
                print("👋 再见！")
                break
            else:
                print("❌ 无效选择，请输入 1-3")
                
        except KeyboardInterrupt:
            print("\n👋 再见！")
            break
        except EOFError:
            print("\n👋 再见！")
            break

if __name__ == "__main__":
    main()
