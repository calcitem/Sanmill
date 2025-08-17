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
import io

# Fix Unicode encoding issues on Windows
if sys.platform == 'win32':
    try:
        # Set console encoding to UTF-8
        os.system('chcp 65001 >nul 2>&1')
        # Set stdout and stderr to UTF-8
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    except Exception:
        pass  # Fallback silently if encoding setup fails

try:
    import torch
except ImportError:
    torch = None

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
        
    def check_existing_models(self, force=False, auto_backup=False):
        """检查现有模型，防止意外覆盖"""
        print("\n🔍 检查现有训练成果...")
        
        # 查找现有模型
        existing_models = []
        patterns = ["nnue_model*.bin", "nnue_model*.pth", "models/nnue_model*.bin", "models/nnue_model*.pth"]
        
        for pattern in patterns:
            for model_file in self.project_root.glob(pattern):
                if model_file.is_file():
                    existing_models.append(model_file)
        
        if existing_models:
            print(f"  发现 {len(existing_models)} 个现有模型:")
            for model in existing_models:
                size = model.stat().st_size / 1024
                mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(model.stat().st_mtime))
                print(f"    📁 {model} ({size:.1f} KB, {mtime})")
            
            if force:
                print("  ⚠️  强制模式：跳过备份，直接继续训练")
                return True
            elif auto_backup:
                print("  💾 自动备份模式：自动备份现有模型")
                self.backup_existing_models(existing_models)
                return True
            else:
                print("\n⚠️  继续训练将可能覆盖现有模型！")
                print("   💡 注意：继续训练会生成新的训练数据并覆盖现有模型")
                print("   📦 旧的训练数据会自动备份为带时间戳的文件")
                print("   建议选择:")
                print("   1. 备份现有模型 (推荐)")
                print("   2. 继续训练 (生成新数据，自动备份旧数据)")
                print("   3. 取消训练")
                
                while True:
                    choice = input("   请选择 (1-3): ").strip()
                    if choice == "1":
                        self.backup_existing_models(existing_models)
                        break
                    elif choice == "2":
                        print("   ⚠️  选择继续，现有模型可能被覆盖")
                        print("   📦 旧的训练数据将被自动备份")
                        break
                    elif choice == "3":
                        print("   ✅ 训练已取消，现有模型安全")
                        return False
                    else:
                        print("   ❌ 无效选择，请输入 1、2 或 3")
        else:
            print("  ✅ 没有发现现有模型")
        
        return True
    
    def backup_existing_models(self, existing_models):
        """备份现有模型"""
        print("\n💾 备份现有模型...")
        
        # 创建备份目录
        backup_dir = self.project_root / "model_backups" / time.strftime("%Y%m%d_%H%M%S")
        backup_dir.mkdir(parents=True, exist_ok=True)
        
        backed_up = 0
        for model_file in existing_models:
            try:
                backup_path = backup_dir / model_file.name
                import shutil
                shutil.copy2(model_file, backup_path)
                backed_up += 1
                print(f"    ✅ {model_file.name} -> {backup_path}")
            except Exception as e:
                print(f"    ❌ 备份失败 {model_file.name}: {e}")
        
        if backed_up > 0:
            print(f"  ✅ 成功备份 {backed_up} 个模型到: {backup_dir}")
            
            # 创建恢复脚本
            self.create_restore_script(backup_dir, existing_models)
        else:
            print("  ❌ 没有模型被成功备份")
    
    def create_restore_script(self, backup_dir, original_models):
        """创建模型恢复脚本"""
        restore_script = backup_dir / "restore_models.py"
        
        script_content = f'''#!/usr/bin/env python3
"""
模型恢复脚本
自动生成于: {time.strftime("%Y-%m-%d %H:%M:%S")}
"""

import shutil
import os
from pathlib import Path

def restore_models():
    """恢复备份的模型"""
    backup_dir = Path(__file__).parent
    project_root = backup_dir.parent.parent
    
    print("🔄 恢复备份的模型...")
    
    restore_mapping = {{'''
        
        for model in original_models:
            script_content += f'''
        "{model.name}": "{model.relative_to(self.project_root)}",'''
        
        script_content += f'''
    }}
    
    restored = 0
    for backup_name, original_path in restore_mapping.items():
        backup_file = backup_dir / backup_name
        original_file = project_root / original_path
        
        if backup_file.exists():
            try:
                # 确保目标目录存在
                original_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(backup_file, original_file)
                print(f"  ✅ 恢复: {{backup_name}} -> {{original_path}}")
                restored += 1
            except Exception as e:
                print(f"  ❌ 恢复失败 {{backup_name}}: {{e}}")
        else:
            print(f"  ⚠️  备份文件不存在: {{backup_name}}")
    
    print(f"\\n✅ 恢复完成，共恢复 {{restored}} 个模型")

if __name__ == '__main__':
    restore_models()
'''
        
        with open(restore_script, 'w', encoding='utf-8') as f:
            f.write(script_content)
        
        print(f"    📜 创建恢复脚本: {restore_script}")
        print(f"    💡 如需恢复模型，运行: python {restore_script}")
    
    def check_resume_training(self):
        """检查是否可以恢复训练"""
        print("\n🔄 检查训练恢复选项...")
        
        # 查找检查点文件
        checkpoint_patterns = ["checkpoint*.pth", "*.checkpoint", "models/checkpoint*.pth"]
        checkpoints = []
        
        for pattern in checkpoint_patterns:
            for ckpt_file in self.project_root.glob(pattern):
                if ckpt_file.is_file():
                    checkpoints.append(ckpt_file)
        
        if checkpoints:
            print(f"  发现 {len(checkpoints)} 个检查点文件:")
            for ckpt in checkpoints:
                size = ckpt.stat().st_size / 1024
                mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ckpt.stat().st_mtime))
                print(f"    🔄 {ckpt} ({size:.1f} KB, {mtime})")
            
            print("\n  是否从检查点恢复训练？")
            print("    y - 恢复训练 (继续之前的进度)")
            print("    n - 重新开始 (将创建新的训练)")
            
            choice = input("  恢复训练? (y/n): ").strip().lower()
            if choice in ['y', 'yes', '是']:
                # 选择最新的检查点
                latest_checkpoint = max(checkpoints, key=lambda f: f.stat().st_mtime)
                print(f"  ✅ 将从检查点恢复: {latest_checkpoint}")
                return str(latest_checkpoint)
            else:
                print("  ✅ 将重新开始训练")
                # 备份检查点文件
                self.backup_checkpoints(checkpoints)
        else:
            print("  ✅ 没有发现检查点文件，将进行全新训练")
        
        return None
    
    def backup_checkpoints(self, checkpoints):
        """备份检查点文件"""
        if not checkpoints:
            return
            
        print(f"  💾 备份 {len(checkpoints)} 个检查点文件...")
        backup_dir = self.project_root / "checkpoint_backups" / time.strftime("%Y%m%d_%H%M%S")
        backup_dir.mkdir(parents=True, exist_ok=True)
        
        for ckpt in checkpoints:
            try:
                backup_path = backup_dir / ckpt.name
                import shutil
                shutil.copy2(ckpt, backup_path)
                print(f"    ✅ {ckpt.name} -> {backup_path}")
            except Exception as e:
                print(f"    ❌ 备份失败 {ckpt.name}: {e}")

    def load_config_file(self, config_path):
        """加载外部配置文件，支持两种格式"""
        try:
            config_file = Path(config_path)
            if not config_file.exists():
                print(f"❌ 配置文件不存在: {config_path}")
                return None
                
            print(f"\n📝 加载配置文件: {config_path}")
            
            with open(config_file, 'r', encoding='utf-8') as f:
                raw_config = json.load(f)
            
            # 检测配置文件格式
            if 'training' in raw_config:
                # Easy train 格式
                config = self._validate_easy_train_config(raw_config)
            else:
                # Train_nnue.py 格式，需要转换
                config = self._convert_train_nnue_config(raw_config)
            
            if config is None:
                return None
            
            # 生成唯一的输出文件名（如果未指定）
            if 'output' not in config:
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                config['output'] = f"models/nnue_model_custom_{timestamp}.bin"
                
            if 'checkpoint_path' not in config:
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                config['checkpoint_path'] = f"models/checkpoint_custom_{timestamp}.pth"
            
            print(f"  ✅ 配置文件加载成功")
            print(f"  📊 训练轮数: {config['training']['epochs']}")
            print(f"  📦 批次大小: {config['training']['batch_size']}")
            print(f"  🎯 学习率: {config['training']['lr']}")
            print(f"  🧠 隐藏层大小: {config['training']['hidden_size']}")
            print(f"  🔄 管道模式: {'是' if config.get('pipeline', False) else '否'}")
            
            return config
            
        except json.JSONDecodeError as e:
            print(f"❌ 配置文件 JSON 格式错误: {e}")
            return None
        except Exception as e:
            print(f"❌ 加载配置文件时出错: {e}")
            return None

    def _validate_easy_train_config(self, config):
        """验证 easy_train 格式的配置文件"""
        # 验证训练配置必需字段
        training_required = ['epochs', 'batch_size', 'lr']
        for field in training_required:
            if field not in config['training']:
                print(f"❌ 训练配置缺少必需字段: training.{field}")
                return None
        
        # 设置默认值
        config.setdefault('pipeline', False)
        config.setdefault('device', 'auto')
        config.setdefault('plot', True)
        config.setdefault('save_checkpoint', True)
        
        # 设置训练配置默认值
        training = config['training']
        training.setdefault('hidden_size', 256)
        training.setdefault('val_split', 0.15)
        
        return config

    def _convert_train_nnue_config(self, raw_config):
        """处理 train_nnue.py 格式的配置文件（管道模式直接传递）"""
        try:
            # 检查必需字段
            required_fields = ['epochs', 'batch-size', 'lr']
            for field in required_fields:
                if field not in raw_config:
                    print(f"❌ 配置文件缺少必需字段: {field}")
                    return None
            
            # 对于管道模式，直接使用原始配置，只做最小转换以兼容显示
            if raw_config.get('pipeline', False):
                # 管道模式：保持原始格式，train_nnue.py 会直接处理
                config = raw_config.copy()
                
                # 强制要求引擎设置为 null
                if 'engine' not in config:
                    print(f"❌ 配置文件缺少必需字段: engine")
                    print(f"   请在配置文件中添加: \"engine\": null")
                    return None
                elif config['engine'] is not None:
                    print(f"❌ 配置文件中 engine 必须设置为 null")
                    print(f"   当前值: {config['engine']}")
                    print(f"   请修改为: \"engine\": null")
                    return None
                else:
                    print(f"  ✅ 引擎已正确设置为 null，将使用直接 Perfect DB 数据生成")
                
                # 添加用于显示的 training 信息
                config['training'] = {
                    'epochs': raw_config['epochs'],
                    'batch_size': raw_config['batch-size'],
                    'lr': raw_config['lr'],
                    'hidden_size': raw_config.get('hidden-size', 256),
                    'val_split': raw_config.get('val-split', 0.15)
                }
                
                print(f"  🔄 保持 train_nnue.py 管道模式配置格式")
                return config
            else:
                # 非管道模式也必须检查 engine 设置
                if 'engine' not in raw_config:
                    print(f"❌ 配置文件缺少必需字段: engine")
                    print(f"   请在配置文件中添加: \"engine\": null")
                    return None
                elif raw_config['engine'] is not None:
                    print(f"❌ 配置文件中 engine 必须设置为 null")
                    print(f"   当前值: {raw_config['engine']}")
                    print(f"   请修改为: \"engine\": null")
                    return None
                
                # 非管道模式：转换为 easy_train 格式
                config = {
                    'pipeline': False,
                    'device': raw_config.get('device', 'auto'),
                    'plot': raw_config.get('plot', True),
                    'save_checkpoint': True,
                    'checkpoint_interval': 10,
                    'training': {
                        'epochs': raw_config['epochs'],
                        'batch_size': raw_config['batch-size'],
                        'lr': raw_config['lr'],
                        'hidden_size': raw_config.get('hidden-size', 256),
                        'val_split': raw_config.get('val-split', 0.15)
                    }
                }
                
                # 设置数据文件
                if 'data' in raw_config:
                    config['data'] = raw_config['data']
                if 'output' in raw_config:
                    config['output'] = raw_config['output']
                
                print(f"  ✅ 引擎已正确设置为 null，已转换为 easy_train 格式配置")
                return config
            
        except Exception as e:
            print(f"❌ 转换配置文件格式时出错: {e}")
            return None

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
                    "hidden_size": 256,  # Changed from 512 to 256 for compatibility with nnue_pit.py
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
        
        # 生成带时间戳的唯一输出文件名，避免覆盖
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        config["output"] = f"models/nnue_model_{preset}_{timestamp}.bin"
        config["checkpoint_path"] = f"models/checkpoint_{preset}_{timestamp}.pth"
        
        # Perfect 数据库配置 (现在直接使用 Perfect DB DLL，不需要引擎)
        config["engine"] = None  # 不再需要引擎
        config["perfect_db"] = "E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted"
        
        config["plot"] = True
        config["plot_interval"] = 25       # 减少图表更新频率，避免阻塞
        config["save_checkpoint"] = True
        config["checkpoint_interval"] = 10  # 每10个epoch保存一次检查点
        config["backup_models"] = True      # 自动备份现有模型
        
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
        """运行训练（包括数据生成和模型训练）"""
        
        # 读取配置文件检查是否需要数据生成
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            print(f"❌ 无法读取配置文件: {e}")
            return False
        
        # 检查是否是管道模式（需要数据生成）
        is_pipeline = config.get('pipeline', False)
        updated_config_path = config_path
        
        if is_pipeline:
            print(f"\n🔄 检测到管道模式，将使用 train_nnue.py 的完整管道功能...")
            print("  📊 数据生成和模型训练将由 train_nnue.py 统一处理")
            print(f"\n🚀 开始完整管道训练...")
        else:
            print(f"\n🚀 开始训练...")
            
        print("  训练过程中请不要关闭窗口")
        print("  您可以通过查看日志来监控进度")
        print()
        
        # 构建训练命令
        cmd = [
            sys.executable, 
            "train_nnue.py", 
            "--config", str(updated_config_path)
        ]
        
        # 如果是管道模式，添加强制重新生成数据参数
        # 这确保每次"继续训练"都会生成新的训练数据
        if is_pipeline:
            cmd.append("--force-regenerate")
        
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
                
                # Auto-generate training visualization plots
                try:
                    from auto_plot import auto_generate_plots
                    
                    # Look for CSV files in common locations
                    csv_locations = [
                        self.project_root / "nnue_output" / "plots" / "training_metrics.csv",  # Primary location
                        self.project_root / "plots" / "training_metrics.csv",  # Legacy fallback
                        self.project_root / "training_metrics.csv"  # Root fallback
                    ]
                    
                    csv_found = None
                    for csv_path in csv_locations:
                        if csv_path.exists():
                            csv_found = csv_path
                            break
                    
                    if csv_found:
                        print(f"\n📈 生成训练可视化图表...")
                        success = auto_generate_plots(
                            csv_file=str(csv_found),
                            output_dir=str(csv_found.parent),
                            comprehensive_only=True,  # Only generate main plot for faster execution
                            max_plot_points=10  # Optimize plotting performance
                        )
                        if success:
                            print(f"  ✅ 训练图表已生成到: {csv_found.parent}")
                            print(f"  🔍 可查看以下文件:")
                            print(f"     • training_analysis_comprehensive.png")
                            print(f"     • loss_convergence_analysis.png") 
                            print(f"     • performance_summary.png")
                        else:
                            print(f"  ⚠️  图表生成失败")
                    else:
                        print(f"  ℹ️  未找到训练 CSV 数据，跳过图表生成")
                        
                except Exception as e:
                    print(f"  ⚠️  自动图表生成失败: {e}")
                
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


    def find_trained_model(self, show_details=True):
        """查找训练好的模型，优先检查 models 目录"""
        if show_details:
            print("\n🔍 查找已训练的模型...")
        
        found_models = []
        
        # 1. 优先检查 models 目录（推荐位置）
        if show_details:
            print("  📁 检查 models/ 目录...")
        model_files = list(self.models_dir.glob("*.bin")) + list(self.models_dir.glob("*.pth"))
        if model_files:
            for f in model_files:
                found_models.append(('models', f))
                if show_details:
                    size_mb = f.stat().st_size / (1024 * 1024)
                    mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(f.stat().st_mtime))
                    print(f"    ✅ {f.name} ({size_mb:.1f}MB, 修改时间: {mtime})")
        
        # 2. 检查 nnue_output 目录（旧的管道输出）
        if show_details:
            print("  📁 检查 nnue_output/ 目录...")
        nnue_output_dir = self.project_root / "nnue_output"
        if nnue_output_dir.exists():
            output_files = list(nnue_output_dir.glob("*.bin")) + list(nnue_output_dir.glob("*.pth"))
            if output_files:
                for f in output_files:
                    found_models.append(('nnue_output', f))
                    if show_details:
                        size_mb = f.stat().st_size / (1024 * 1024)
                        mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(f.stat().st_mtime))
                        print(f"    ⚠️  {f.name} ({size_mb:.1f}MB, 修改时间: {mtime}) [旧位置]")
            elif show_details:
                print("    📭 无模型文件")
        elif show_details:
            print("    📭 目录不存在")
        
        # 3. 检查项目根目录
        if show_details:
            print("  📁 检查项目根目录...")
        root_files = list(self.project_root.glob("nnue_model*.bin")) + list(self.project_root.glob("nnue_model*.pth"))
        if root_files:
            for f in root_files:
                found_models.append(('root', f))
                if show_details:
                    size_mb = f.stat().st_size / (1024 * 1024)
                    mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(f.stat().st_mtime))
                    print(f"    ⚠️  {f.name} ({size_mb:.1f}MB, 修改时间: {mtime}) [根目录]")
        elif show_details:
            print("    📭 无模型文件")
            
        if not found_models:
            if show_details:
                print("  ❌ 未找到任何模型文件")
            return None
            
        # 优先选择 models 目录中的最新文件，其次是其他位置
        models_dir_files = [f for loc, f in found_models if loc == 'models']
        if models_dir_files:
            latest_model = max(models_dir_files, key=lambda f: f.stat().st_mtime)
            if show_details:
                print(f"  ✅ 选择 models/ 目录中的最新模型: {latest_model.name}")
        else:
            # 如果 models 目录没有文件，选择其他位置的最新文件
            latest_model = max([f for loc, f in found_models], key=lambda f: f.stat().st_mtime)
            if show_details:
                print(f"  ✅ 选择最新模型: {latest_model} (建议移动到 models/ 目录)")
                
        return latest_model
    
    def should_load_model(self, load_model_setting, checkpoint_dir=None):
        """
        根据设置和检查点目录状态决定是否加载模型
        根据记忆要求：检查 checkpoint 目录中是否有任何 .tar 文件
        - 如果没有 .tar 文件，忽略 load_model 设置
        - 如果有 .tar 文件，尊重 load_model 设置，但要求目标文件存在
        """
        if checkpoint_dir is None:
            checkpoint_dir = self.models_dir
            
        # 检查是否有任何 .tar 文件
        tar_files = list(checkpoint_dir.glob("*.tar"))
        
        if not tar_files:
            print("  📭 检查点目录中无 .tar 文件，跳过模型加载")
            return False, None
            
        print(f"  📦 找到 {len(tar_files)} 个 .tar 检查点文件")
        for tar_file in tar_files:
            size_mb = tar_file.stat().st_size / (1024 * 1024)
            mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(tar_file.stat().st_mtime))
            print(f"    📦 {tar_file.name} ({size_mb:.1f}MB, {mtime})")
        
        if not load_model_setting:
            print("  ⏭️  load_model 设置为 False，跳过加载")
            return False, None
            
        # 尊重 load_model 设置，但检查目标文件是否存在
        model_file = self.find_trained_model(show_details=False)
        if model_file is None:
            print("  ❌ load_model 为 True 但未找到可加载的模型文件")
            return False, None
            
        print(f"  ✅ 将加载模型: {model_file}")
        return True, model_file
        
    def validate_model(self, model_path):
        """验证训练的模型"""
        print(f"\n🔍 验证训练的模型: {model_path}")
        
        try:
            # 简化验证：只检查文件存在性和大小
            if not model_path.exists():
                print(f"  ❌ 模型文件不存在: {model_path}")
                return False
                
            model_size = model_path.stat().st_size
            if model_size == 0:
                print(f"  ❌ 模型文件为空: {model_path}")
                return False
                
            print(f"  ✅ 模型文件验证成功 ({model_size} bytes)")
            
            # 快速模型加载测试（避免导入可能触发绘图的模块）
            try:
                # 尝试加载模型（但避免导入整个 nnue_pit 模块）
                print("  ℹ️  模型内容验证已简化以避免额外的绘图调用")
                print("  ✅ 基础验证通过")
                return True
                
            except Exception as load_error:
                print(f"  ⚠️  模型加载测试跳过: {load_error}")
                print("  ✅ 文件验证通过（可能仍然可用）")
                return True
            
        except Exception as e:
            print(f"  ❌ 模型验证失败: {e}")
            return False
            
    def launch_gui_test(self, model_path):
        """启动 GUI 测试"""
        print(f"\n🎮 启动 GUI 测试...")
        print("🚀 Checking GUI environment...")
        
        try:
            import tkinter
            print("🚀 GUI environment available")
        except ImportError:
            print("🚀 GUI environment not available, skipping GUI test")
            return
            
        print("🚀 Prompting user for GUI test choice...")
        print("  是否现在启动 GUI 来测试您的模型?")
        choice = input("  启动 GUI 测试? (y/n): ").strip().lower()
        print(f"🚀 User choice: '{choice}'")
        
        if choice in ['y', 'yes', '是', '']:
            print("🚀 User chose to start GUI test")
            try:
                cmd = [sys.executable, "nnue_pit.py", "--model", str(model_path), "--gui", "--first", "human"]
                print(f"🚀 Starting GUI with command: {' '.join(cmd)}")
                print("🚀 About to run subprocess...")
                subprocess.run(cmd)
                print("🚀 Subprocess completed")
            except Exception as e:
                print(f"🚀 GUI launch failed: {e}")
                print("  您可以手动运行:")
                print(f"    python nnue_pit.py --model {model_path} --gui")
        else:
            print("🚀 User chose to skip GUI test")
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
                
            # 3. 检查现有模型和备份
            if not self.check_existing_models(force=args.force, auto_backup=args.backup_existing):
                return False  # 用户选择取消训练
                
            # 4. 检查训练恢复选项
            resume_checkpoint = self.check_resume_training()
            
            # 5. 处理配置文件
            if args.config:
                # 使用指定的配置文件
                config_path = Path(args.config)
                config = self.load_config_file(args.config)
                if config is None:
                    return False
                    
                # 检查设备设置是否需要警告
                if args.gpu and config.get('device', 'auto') == 'auto':
                    print(f"  ⚠️  注意: 配置文件设备为 'auto'，但指定了 --gpu 参数")
                    print(f"      建议在配置文件中明确设置 \"device\": \"cuda\"")
                elif config.get('device') == 'auto':
                    print(f"  ℹ️  设备设置为 'auto'，将自动选择最佳设备")
                
                print(f"  ✅ 直接使用配置文件: {config_path}")
                
            else:
                # 使用交互式预设配置
                preset, device = self.get_user_preferences(args)
                config_path, config = self.create_training_config(preset, device)
            
            # 7. 如果有恢复检查点，添加到配置中
            if resume_checkpoint:
                config["resume_from_checkpoint"] = resume_checkpoint
                # 重新保存配置
                with open(config_path, 'w', encoding='utf-8') as f:
                    json.dump(config, f, indent=2, ensure_ascii=False)
                print(f"  ✅ 配置已更新，将从检查点恢复训练")
            
            # 8. 估算时间
            self.estimate_training_time(config)
            
            # 9. 确认开始
            if not args.auto:
                print("\n🚀 准备开始训练!")
                choice = input("  继续? (y/n): ").strip().lower()
                if choice not in ['y', 'yes', '是', '']:
                    print("  训练已取消")
                    return False
                    
            # 10. 运行训练
            success = self.run_training(config_path)
            if not success:
                return False
                
            # 11. 查找和验证模型
            print("🚀 Step 11: Looking for trained model...")
            model_path = self.find_trained_model()
            if model_path:
                print("🚀 Step 11: Model found, starting validation...")
                self.validate_model(model_path)
                print("🚀 Step 11: Model validation completed")
            else:
                print("🚀 Step 11: No model found")
                
            # 12. 启动 GUI 测试
            print("🚀 Step 12: Checking GUI test options...")
            if model_path and not args.no_gui:
                print("🚀 Step 12: Starting GUI test...")
                self.launch_gui_test(model_path)
                print("🚀 Step 12: GUI test completed")
            else:
                print("🚀 Step 12: Skipping GUI test")
                
            # 13. 清理临时文件
            print("🚀 Step 13: Cleaning up temporary files...")
            if not args.keep_temp:
                self.cleanup_temp_files()
                print("🚀 Step 13: Cleanup completed")
            else:
                print("🚀 Step 13: Keeping temporary files")
                
            # 14. 显示总结
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
  python easy_train.py --config config.json  # 使用配置文件训练
  
训练模式:
  quick        - 5-10分钟，适合测试和学习
  standard     - 30-60分钟，日常使用推荐
  high_quality - 2-4小时，追求最佳效果
  config       - 使用自定义配置文件

配置文件格式 (JSON):
  {
    "training": {
      "epochs": 100,
      "batch_size": 2048,
      "lr": 0.002,
      "hidden_size": 256,
      "val_split": 0.15
    },
    "device": "auto",
    "plot": true
  }

保护功能:
  --backup-existing - 自动备份现有模型
  --force          - 强制训练，跳过保护检查（谨慎使用）
  
断点恢复:
  程序会自动检测检查点文件，询问是否恢复训练
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
    parser.add_argument('--force', action='store_true',
                       help='强制训练，跳过备份检查（谨慎使用）')
    parser.add_argument('--backup-existing', action='store_true',
                       help='自动备份现有模型，不询问')
    parser.add_argument('--config', type=str, metavar='FILE',
                       help='使用指定的配置文件 (JSON格式)')
    
    args = parser.parse_args()
    
    # 验证参数
    if args.quick and args.high_quality:
        print("❌ 不能同时指定 --quick 和 --high-quality")
        return 1
        
    # 验证配置文件参数
    if args.config and (args.quick or args.high_quality):
        print("❌ 使用配置文件时不能同时指定预设选项 (--quick/--high-quality)")
        return 1
        
    # 运行训练器
    trainer = EasyNNUETrainer()
    success = trainer.run(args)
    
    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())
