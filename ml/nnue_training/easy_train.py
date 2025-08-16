#!/usr/bin/env python3
"""
Easy NNUE Training Script - 傻瓜化 NNUE 训练工具
==================================================

这个脚本让新手也能轻松训练 NNUE 模型，无需复杂配置。

使用方法:
  python easy_train.py                    # 使用默认设置训练
  python easy_train.py --quick            # 快速训练（用于测试）
  python easy_train.py --high-quality     # 高质量训练（更长时间）
  python easy_train.py --gpu              # 强制使用 GPU
  python easy_train.py --help             # 查看帮助
"""

import os
import sys
import json
import time
import subprocess
import argparse
from pathlib import Path
import logging

# 设置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

class EasyNNUETrainer:
    """傻瓜化 NNUE 训练器"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent
        self.models_dir = self.project_root / "models"
        self.data_dir = self.project_root / "training_data"
        self.engine_path = self.project_root / "../../sanmill"
        
        # 确保目录存在
        self.models_dir.mkdir(exist_ok=True)
        self.data_dir.mkdir(exist_ok=True)
        
    def print_banner(self):
        """打印欢迎横幅"""
        print("=" * 60)
        print("🎯 Sanmill NNUE 傻瓜化训练工具")
        print("=" * 60)
        print("这个工具会帮助您:")
        print("  1. 检查环境和依赖")
        print("  2. 生成训练数据")
        print("  3. 训练 NNUE 模型")
        print("  4. 验证训练结果")
        print("  5. 启动 GUI 测试")
        print("=" * 60)
        print()
        
    def check_environment(self):
        """检查训练环境"""
        print("🔍 检查训练环境...")
        
        issues = []
        
        # 检查 Python 版本
        if sys.version_info < (3, 7):
            issues.append("Python 版本需要 3.7 或更高")
        else:
            print(f"  ✅ Python {sys.version_info.major}.{sys.version_info.minor}")
            
        # 检查依赖包
        required_packages = ['torch', 'numpy']
        for package in required_packages:
            try:
                __import__(package)
                print(f"  ✅ {package}")
            except ImportError:
                issues.append(f"缺少依赖包: {package}")
                
        # 检查 GPU 可用性
        try:
            import torch
            if torch.cuda.is_available():
                gpu_name = torch.cuda.get_device_name(0)
                print(f"  ✅ GPU 可用: {gpu_name}")
                self.has_gpu = True
            else:
                print("  ⚠️  GPU 不可用，将使用 CPU 训练")
                self.has_gpu = False
        except:
            self.has_gpu = False
            
        # 检查训练脚本
        if not (self.project_root / "train_nnue.py").exists():
            issues.append("找不到 train_nnue.py")
        else:
            print("  ✅ 训练脚本")
            
        if issues:
            print("\n❌ 发现问题:")
            for issue in issues:
                print(f"  - {issue}")
            print("\n请先解决这些问题:")
            print("  1. 升级 Python: https://www.python.org/downloads/")
            print("  2. 安装依赖: pip install torch numpy matplotlib")
            print("  3. 确保在正确的目录运行脚本")
            return False
            
        print("  ✅ 环境检查通过!")
        return True
        
    def get_user_preferences(self, args):
        """获取用户偏好设置"""
        print("\n⚙️  配置训练参数...")
        
        if args.quick:
            preset = "quick"
            print("  📊 使用快速训练预设")
        elif args.high_quality:
            preset = "high_quality"
            print("  🎯 使用高质量训练预设")
        else:
            print("\n  请选择训练模式:")
            print("    1. 快速训练 (5-10分钟，适合测试)")
            print("    2. 标准训练 (30-60分钟，推荐)")
            print("    3. 高质量训练 (2-4小时，最佳效果)")
            
            while True:
                choice = input("  请输入选择 (1-3): ").strip()
                if choice == "1":
                    preset = "quick"
                    break
                elif choice == "2":
                    preset = "standard"
                    break
                elif choice == "3":
                    preset = "high_quality"
                    break
                else:
                    print("  ❌ 无效选择，请输入 1、2 或 3")
                    
        # 设备选择
        if args.gpu and self.has_gpu:
            device = "cuda"
            print("  🖥️  强制使用 GPU")
        elif self.has_gpu:
            print(f"\n  检测到 GPU，是否使用? (推荐)")
            choice = input("  使用 GPU 训练? (y/n): ").strip().lower()
            device = "cuda" if choice in ['y', 'yes', '是', ''] else "cpu"
        else:
            device = "cpu"
            print("  💻 使用 CPU 训练")
            
        return preset, device
        
    def create_training_config(self, preset, device):
        """创建训练配置"""
        print(f"\n📝 创建 {preset} 训练配置...")
        
        configs = {
            "quick": {
                "description": "快速训练配置 - 用于测试和学习",
                "pipeline": True,
                "data_generation": {
                    "positions": 1000,
                    "threads": 2,
                    "timeout": 5
                },
                "training": {
                    "epochs": 10,
                    "batch_size": 512,
                    "lr": 0.003,
                    "hidden_size": 128,
                    "val_split": 0.2
                }
            },
            "standard": {
                "description": "标准训练配置 - 平衡效果和时间",
                "pipeline": True,
                "data_generation": {
                    "positions": 10000,
                    "threads": 4,
                    "timeout": 10
                },
                "training": {
                    "epochs": 100,
                    "batch_size": 2048,
                    "lr": 0.002,
                    "hidden_size": 256,
                    "val_split": 0.15
                }
            },
            "high_quality": {
                "description": "高质量训练配置 - 追求最佳效果",
                "pipeline": True,
                "data_generation": {
                    "positions": 50000,
                    "threads": 8,
                    "timeout": 20
                },
                "training": {
                    "epochs": 300,
                    "batch_size": 4096,
                    "lr": 0.002,
                    "hidden_size": 512,
                    "val_split": 0.1
                }
            }
        }
        
        config = configs[preset].copy()
        
        # 根据设备调整配置
        if device == "cpu":
            # CPU 优化
            config["training"]["batch_size"] = min(config["training"]["batch_size"], 1024)
            config["data_generation"]["threads"] = min(config["data_generation"]["threads"], 2)
            config["training"]["hidden_size"] = min(config["training"]["hidden_size"], 256)
            print("  🔧 已针对 CPU 优化配置")
        else:
            print("  🚀 已针对 GPU 优化配置")
            
        config["device"] = device
        config["output"] = f"models/nnue_model_{preset}_{int(time.time())}.bin"
        config["plot"] = True
        config["save_checkpoint"] = True
        
        # 保存配置文件
        config_path = self.project_root / f"easy_train_{preset}_config.json"
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            
        print(f"  ✅ 配置已保存: {config_path}")
        return config_path, config
        
    def estimate_training_time(self, config):
        """估算训练时间"""
        preset_times = {
            "quick": (5, 10),
            "standard": (30, 60),
            "high_quality": (120, 240)
        }
        
        for preset, (min_time, max_time) in preset_times.items():
            if preset in str(config):
                device_factor = 0.3 if config.get("device") == "cuda" else 1.0
                estimated_min = int(min_time * device_factor)
                estimated_max = int(max_time * device_factor)
                
                print(f"\n⏱️  预计训练时间: {estimated_min}-{estimated_max} 分钟")
                return estimated_min, estimated_max
                
        return 30, 60
        
    def run_training(self, config_path):
        """运行训练"""
        print(f"\n🚀 开始训练...")
        print("  训练过程中请不要关闭窗口")
        print("  您可以通过查看日志来监控进度")
        print()
        
        # 构建训练命令
        cmd = [
            sys.executable, 
            "train_nnue.py", 
            "--config", str(config_path)
        ]
        
        print(f"  执行命令: {' '.join(cmd)}")
        print("  " + "=" * 50)
        
        try:
            # 运行训练
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )
            
            # 实时显示输出
            for line in process.stdout:
                print(f"  {line.rstrip()}")
                
            process.wait()
            
            if process.returncode == 0:
                print("  " + "=" * 50)
                print("  ✅ 训练完成!")
                return True
            else:
                print("  " + "=" * 50)
                print(f"  ❌ 训练失败，返回码: {process.returncode}")
                return False
                
        except KeyboardInterrupt:
            print("\n  ⏹️  训练被用户中断")
            process.terminate()
            return False
        except Exception as e:
            print(f"  ❌ 训练过程出错: {e}")
            return False
            
    def find_trained_model(self):
        """查找训练好的模型"""
        model_files = list(self.models_dir.glob("*.bin")) + list(self.models_dir.glob("*.pth"))
        if not model_files:
            # 也检查当前目录
            model_files = list(self.project_root.glob("nnue_model*.bin")) + list(self.project_root.glob("nnue_model*.pth"))
            
        if model_files:
            # 返回最新的模型
            latest_model = max(model_files, key=lambda f: f.stat().st_mtime)
            return latest_model
        return None
        
    def validate_model(self, model_path):
        """验证训练的模型"""
        print(f"\n🔍 验证训练的模型: {model_path}")
        
        try:
            # 尝试加载模型
            from nnue_pit import NNUEModelLoader
            loader = NNUEModelLoader(str(model_path))
            model = loader.load_model()
            print("  ✅ 模型加载成功")
            
            # 测试推理
            from nnue_pit import SimpleGameState
            import torch
            
            game_state = SimpleGameState()
            features = game_state.to_nnue_features()
            features_tensor = torch.from_numpy(features).unsqueeze(0).to(loader.device)
            side_to_move_tensor = torch.tensor([0], dtype=torch.long).to(loader.device)
            
            with torch.no_grad():
                evaluation = model(features_tensor, side_to_move_tensor)
                eval_score = float(evaluation.squeeze().cpu())
                
            print(f"  ✅ 推理测试成功，评估分数: {eval_score:.4f}")
            return True
            
        except Exception as e:
            print(f"  ❌ 模型验证失败: {e}")
            return False
            
    def launch_gui_test(self, model_path):
        """启动 GUI 测试"""
        print(f"\n🎮 启动 GUI 测试...")
        
        try:
            import tkinter
            print("  GUI 环境可用")
        except ImportError:
            print("  ❌ GUI 环境不可用，跳过 GUI 测试")
            return
            
        print("  是否现在启动 GUI 来测试您的模型?")
        choice = input("  启动 GUI 测试? (y/n): ").strip().lower()
        
        if choice in ['y', 'yes', '是', '']:
            try:
                cmd = [sys.executable, "nnue_pit.py", "--model", str(model_path), "--gui", "--first", "human"]
                print(f"  启动命令: {' '.join(cmd)}")
                subprocess.run(cmd)
            except Exception as e:
                print(f"  ❌ GUI 启动失败: {e}")
                print("  您可以手动运行:")
                print(f"    python nnue_pit.py --model {model_path} --gui")
        else:
            print("  跳过 GUI 测试")
            print("  您可以稍后手动启动:")
            print(f"    python nnue_pit.py --model {model_path} --gui")
            
    def cleanup_temp_files(self):
        """清理临时文件"""
        temp_patterns = ["easy_train_*_config.json", "training_data_*.txt", "*.tmp"]
        
        print("\n🧹 清理临时文件...")
        cleaned = 0
        
        for pattern in temp_patterns:
            for temp_file in self.project_root.glob(pattern):
                try:
                    temp_file.unlink()
                    cleaned += 1
                except:
                    pass
                    
        if cleaned > 0:
            print(f"  ✅ 清理了 {cleaned} 个临时文件")
        else:
            print("  ✅ 没有需要清理的临时文件")
            
    def show_summary(self, model_path, training_time):
        """显示训练总结"""
        print("\n" + "=" * 60)
        print("🎉 训练完成总结")
        print("=" * 60)
        
        if model_path:
            model_size = model_path.stat().st_size / 1024
            print(f"📁 训练的模型: {model_path}")
            print(f"📏 模型大小: {model_size:.1f} KB")
        else:
            print("❌ 没有找到训练的模型")
            
        if training_time:
            hours = training_time // 3600
            minutes = (training_time % 3600) // 60
            if hours > 0:
                print(f"⏱️  训练用时: {hours} 小时 {minutes} 分钟")
            else:
                print(f"⏱️  训练用时: {minutes} 分钟")
                
        print("\n🎯 下一步操作:")
        print("  1. 测试模型:")
        print(f"     python nnue_pit.py --model {model_path} --gui")
        print("  2. 查看训练图表:")
        print("     ls plots/")
        print("  3. 继续训练:")
        print("     python easy_train.py --high-quality")
        print("  4. 部署模型:")
        print("     将 .bin 文件复制到引擎目录")
        
        print("=" * 60)
        
    def run(self, args):
        """运行完整的训练流程"""
        start_time = time.time()
        
        try:
            # 1. 显示欢迎信息
            self.print_banner()
            
            # 2. 检查环境
            if not self.check_environment():
                return False
                
            # 3. 获取用户偏好
            preset, device = self.get_user_preferences(args)
            
            # 4. 创建配置
            config_path, config = self.create_training_config(preset, device)
            
            # 5. 估算时间
            self.estimate_training_time(config)
            
            # 6. 确认开始
            if not args.auto:
                print("\n🚀 准备开始训练!")
                choice = input("  继续? (y/n): ").strip().lower()
                if choice not in ['y', 'yes', '是', '']:
                    print("  训练已取消")
                    return False
                    
            # 7. 运行训练
            success = self.run_training(config_path)
            if not success:
                return False
                
            # 8. 查找和验证模型
            model_path = self.find_trained_model()
            if model_path:
                self.validate_model(model_path)
                
            # 9. 启动 GUI 测试
            if model_path and not args.no_gui:
                self.launch_gui_test(model_path)
                
            # 10. 清理临时文件
            if not args.keep_temp:
                self.cleanup_temp_files()
                
            # 11. 显示总结
            training_time = time.time() - start_time
            self.show_summary(model_path, training_time)
            
            return True
            
        except KeyboardInterrupt:
            print("\n⏹️  训练被用户中断")
            return False
        except Exception as e:
            print(f"\n❌ 训练过程出错: {e}")
            import traceback
            traceback.print_exc()
            return False

def main():
    parser = argparse.ArgumentParser(
        description='NNUE 傻瓜化训练工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python easy_train.py                    # 交互式训练
  python easy_train.py --quick            # 快速训练
  python easy_train.py --high-quality     # 高质量训练
  python easy_train.py --gpu --auto       # 自动 GPU 训练
  
训练模式:
  quick        - 5-10分钟，适合测试和学习
  standard     - 30-60分钟，日常使用推荐
  high_quality - 2-4小时，追求最佳效果
        """
    )
    
    parser.add_argument('--quick', action='store_true',
                       help='使用快速训练预设 (5-10分钟)')
    parser.add_argument('--high-quality', action='store_true', 
                       help='使用高质量训练预设 (2-4小时)')
    parser.add_argument('--gpu', action='store_true',
                       help='强制使用 GPU (如果可用)')
    parser.add_argument('--auto', action='store_true',
                       help='自动模式，不询问确认')
    parser.add_argument('--no-gui', action='store_true',
                       help='训练完成后不启动 GUI')
    parser.add_argument('--keep-temp', action='store_true',
                       help='保留临时文件')
    
    args = parser.parse_args()
    
    # 验证参数
    if args.quick and args.high_quality:
        print("❌ 不能同时指定 --quick 和 --high-quality")
        return 1
        
    # 运行训练器
    trainer = EasyNNUETrainer()
    success = trainer.run(args)
    
    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())
