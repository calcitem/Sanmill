#!/usr/bin/env python3
"""
Easy NNUE Training Script - 全自动多轮迁移学习训练工具
========================================================

这个脚本实现完全自动化的多轮 NNUE 训练，支持迁移学习和智能参数优化。
用户只需配置好配置文件，运行脚本即可完成整个训练流程。

特性:
- 🔄 自动多轮训练（默认6轮）
- 🧠 智能迁移学习（每轮从前一轮最佳模型开始）
- 📈 动态参数调整（学习率、数据量等）
- 📊 完整的训练监控和日志
- 🎯 零交互，完全自动化

使用方法:
  1. 编辑 configs/easy_multiround.json 配置文件
  2. 运行: python easy_train.py
  3. 等待训练完成

作者: AI Assistant
版本: 2.0
"""

import os
import sys
import json
import time
import logging
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple
import datetime

# Fix Unicode encoding issues on Windows
if sys.platform == 'win32':
    try:
        os.system('chcp 65001 >nul 2>&1')
    except Exception:
        pass

# 设置日志
def setup_logging(log_file: Path = None) -> logging.Logger:
    """设置日志系统"""
    logger = logging.getLogger('easy_train')
    logger.setLevel(logging.INFO)
    
    # 清除已有的处理器
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # 创建格式化器
    formatter = logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # 控制台处理器
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # 文件处理器
    if log_file:
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    
    return logger

class EasyMultiRoundTrainer:
    """全自动多轮 NNUE 训练器"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent
        self.config_file = self.project_root / "configs" / "easy_multiround.json"
        self.output_dir = None
        self.logger = None
        
        # 训练状态
        self.config = {}
        self.round_history = []
        self.best_val_loss = float('inf')
        self.best_round = 0
        self.current_round = 0
        self.start_time = None
        
        # 迁移学习状态
        self.last_checkpoint = None
        
        # 时间估算历史（用于改进预测准确性）
        self.time_estimation_history = []
        
    def initialize(self) -> bool:
        """初始化训练器"""
        print("🚀 Easy NNUE 多轮训练器 v2.0")
        print("=" * 50)
        
        # 检查配置文件
        if not self.config_file.exists():
            print(f"❌ 配置文件不存在: {self.config_file}")
            print("请确保 configs/easy_multiround.json 文件存在")
            return False
        
        # 加载配置
        try:
            with open(self.config_file, 'r', encoding='utf-8') as f:
                self.config = json.load(f)
            print(f"✅ 配置文件加载成功: {self.config_file.name}")
        except Exception as e:
            print(f"❌ 配置文件加载失败: {e}")
            return False
        
        # 创建输出目录
        self.output_dir = Path(self.config.get("output-dir", "./easy_multiround_output"))
        self.output_dir.mkdir(exist_ok=True)
        
        # 设置日志
        log_file = self.output_dir / "easy_training.log"
        self.logger = setup_logging(log_file)
        
        # 验证环境
        return self._validate_environment()
    
    def _validate_environment(self) -> bool:
        """验证训练环境"""
        self.logger.info("🔍 验证训练环境...")
        
        # 检查 Python 环境
        try:
            import torch
            self.logger.info(f"✅ PyTorch 版本: {torch.__version__}")
            if torch.cuda.is_available():
                self.logger.info(f"✅ CUDA 可用: {torch.cuda.get_device_name()}")
            else:
                self.logger.info("⚠️ CUDA 不可用，将使用 CPU 训练")
        except ImportError:
            self.logger.error("❌ PyTorch 未安装")
            return False
        
        # 检查 Perfect Database
        perfect_db = self.config.get("perfect-db")
        if not perfect_db:
            self.logger.error("❌ 配置文件中未设置 perfect-db 路径")
            return False
        
        perfect_db_path = Path(perfect_db)
        if not perfect_db_path.exists():
            self.logger.error(f"❌ Perfect Database 不存在: {perfect_db}")
            self.logger.info("请在配置文件中设置正确的 perfect-db 路径")
            return False
        
        self.logger.info(f"✅ Perfect Database: {perfect_db}")
        
        # 检查训练脚本
        train_script = self.project_root / "train_nnue.py"
        if not train_script.exists():
            self.logger.error(f"❌ 训练脚本不存在: {train_script}")
            return False
        
        self.logger.info("✅ 环境验证完成")
        return True
    
    def _get_round_config(self, round_num: int) -> Tuple[Dict[str, Any], str]:
        """获取指定轮次的训练配置"""
        
        # 基础配置
        round_config = self.config.copy()
        
        # 轮次特定的训练策略
        strategies = {
            1: {
                "positions": 30000,
                "epochs": 80,
                "lr": 0.003,
                "batch-size": 4096,
                "description": "探索阶段：快速收敛"
            },
            2: {
                "positions": 50000,
                "epochs": 120,
                "lr": 0.002,
                "batch-size": 6144,
                "description": "稳定学习：平衡优化"
            },
            3: {
                "positions": 80000,
                "epochs": 150,
                "lr": 0.0015,
                "batch-size": 8192,
                "description": "深化学习：增加数据"
            },
            4: {
                "positions": 100000,
                "epochs": 180,
                "lr": 0.001,
                "batch-size": 8192,
                "description": "精细调整：大数据集"
            },
            5: {
                "positions": 120000,
                "epochs": 200,
                "lr": 0.0008,
                "batch-size": 10240,
                "description": "优化阶段：降低学习率"
            },
            6: {
                "positions": 150000,
                "epochs": 250,
                "lr": 0.0005,
                "batch-size": 10240,
                "description": "收敛阶段：最终优化"
            }
        }
        
        # 应用轮次策略
        if round_num <= len(strategies):
            strategy = strategies[round_num]
        else:
            # 超出预定义策略，使用最后一个策略并继续降低学习率
            strategy = strategies[len(strategies)].copy()
            strategy["lr"] *= (0.8 ** (round_num - len(strategies)))
            strategy["description"] = f"扩展轮次 {round_num}：继续优化"
        
        round_config.update(strategy)
        
        # 设置输出路径
        round_output_dir = self.output_dir / f"round_{round_num:02d}"
        round_output_dir.mkdir(exist_ok=True)
        
        round_config["output"] = str(round_output_dir / f"nnue_model_round_{round_num:02d}.bin")
        round_config["output-dir"] = str(round_output_dir)
        
        # 迁移学习配置
        if self.last_checkpoint and round_num > 1:
            round_config["transfer-from"] = self.last_checkpoint
            
            # 根据轮次选择迁移学习策略
            if round_num <= 3:
                round_config["transfer-strategy"] = "full"
                round_config["transfer-lr-scale"] = 0.5
            elif round_num <= 5:
                round_config["transfer-strategy"] = "fine-tune"
                round_config["transfer-lr-scale"] = 0.3
            else:
                round_config["transfer-strategy"] = "fine-tune"
                round_config["transfer-lr-scale"] = 0.1
        
        return round_config, strategy["description"]
    
    def _estimate_training_time(self, positions: int, epochs: int, batch_size: int, round_num: int) -> float:
        """智能估算训练时间"""
        
        if len(self.time_estimation_history) == 0:
            # 首次估算：基于经验公式
            base_time_per_1k_samples = 0.8  # 每1000个样本约0.8秒
            estimated_seconds = (positions * epochs * base_time_per_1k_samples) / 1000
            return max(0.5, estimated_seconds / 60)
        
        # 基于历史数据的线性回归估算
        if len(self.time_estimation_history) >= 2:
            # 计算每个样本的平均处理时间
            total_samples = sum(h['positions'] * h['epochs'] for h in self.time_estimation_history)
            total_time = sum(h['actual_time'] for h in self.time_estimation_history)
            
            if total_samples > 0:
                time_per_sample = total_time / total_samples
                estimated_seconds = positions * epochs * time_per_sample
                return max(0.5, estimated_seconds / 60)
        
        # 使用最近一次的数据进行估算
        last_history = self.time_estimation_history[-1]
        last_time_per_sample = last_history['actual_time'] / (last_history['positions'] * last_history['epochs'])
        
        # 考虑数据量增长的影响（稍微增加时间）
        scale_factor = 1.0 + (positions - last_history['positions']) / last_history['positions'] * 0.1
        
        estimated_seconds = positions * epochs * last_time_per_sample * scale_factor
        return max(0.5, estimated_seconds / 60)
    
    def _update_time_estimation_history(self, round_num: int, round_config: Dict[str, Any], actual_time: float):
        """更新时间估算历史数据"""
        history_entry = {
            'round': round_num,
            'positions': round_config['positions'],
            'epochs': round_config['epochs'],
            'batch_size': round_config['batch-size'],
            'actual_time': actual_time / 60,  # 转换为分钟
            'samples_per_second': (round_config['positions'] * round_config['epochs']) / actual_time
        }
        
        self.time_estimation_history.append(history_entry)
        
        # 保持历史记录不超过5条（避免过度拟合）
        if len(self.time_estimation_history) > 5:
            self.time_estimation_history.pop(0)
        
        # 记录实际性能数据
        samples_per_sec = history_entry['samples_per_second']
        self.logger.info(f"📊 实际处理速度: {samples_per_sec:,.0f} 样本/秒")
    
    def _run_single_round(self, round_num: int) -> bool:
        """执行单轮训练"""
        self.logger.info(f"\n{'='*60}")
        self.logger.info(f"🔄 开始第 {round_num} 轮训练")
        self.logger.info(f"{'='*60}")
        
        # 获取轮次配置
        round_config, description = self._get_round_config(round_num)
        
        # 保存轮次配置
        config_file = self.output_dir / f"round_{round_num:02d}_config.json"
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(round_config, f, indent=2, ensure_ascii=False)
        
        # 显示轮次信息
        self.logger.info(f"📝 轮次 {round_num} 配置:")
        self.logger.info(f"  - 描述: {description}")
        self.logger.info(f"  - 位置数量: {round_config['positions']:,}")
        self.logger.info(f"  - 训练轮数: {round_config['epochs']}")
        self.logger.info(f"  - 学习率: {round_config['lr']:.6f}")
        self.logger.info(f"  - 批量大小: {round_config['batch-size']:,}")
        
        if "transfer-from" in round_config:
            self.logger.info(f"  - 迁移学习: {round_config['transfer-strategy']}")
            self.logger.info(f"  - LR缩放: {round_config['transfer-lr-scale']}")
        
        # 构建训练命令
        cmd = [
            sys.executable,
            str(self.project_root / "train_nnue.py"),
            "--config", str(config_file),
            "--pipeline",
            "--perfect-db", round_config["perfect-db"]
        ]
        
        # 添加迁移学习参数
        if "transfer-from" in round_config:
            cmd.extend([
                "--transfer-from", round_config["transfer-from"],
                "--transfer-strategy", round_config["transfer-strategy"],
                "--transfer-lr-scale", str(round_config["transfer-lr-scale"])
            ])
        
        self.logger.info(f"⚡ 开始执行第 {round_num} 轮训练...")
        
        # 更准确的时间估算（基于实际观测数据）
        # 考虑因素：GPU性能、数据量、批量大小
        positions = round_config['positions']
        epochs = round_config['epochs']
        batch_size = round_config['batch-size']
        
        # 智能时间估算
        estimated_minutes = self._estimate_training_time(positions, epochs, batch_size, round_num)
        
        if len(self.time_estimation_history) > 0:
            self.logger.info(f"⏰ 预计训练时间: {epochs} 轮次，约 {estimated_minutes:.1f} 分钟 (基于历史数据)")
        else:
            self.logger.info(f"⏰ 预计训练时间: {epochs} 轮次，约 {estimated_minutes:.1f} 分钟 (初步估算)")
        
        # 执行训练
        round_start_time = time.time()
        
        try:
            # 使用实时输出而不是捕获输出
            self.logger.info(f"📋 执行命令: {' '.join(cmd)}")
            self.logger.info("=" * 50)
            
            result = subprocess.run(
                cmd, 
                cwd=self.project_root,
                # 不捕获输出，让训练过程实时显示
                text=True,
                encoding='utf-8'
            )
            
            round_time = time.time() - round_start_time
            
            self.logger.info("=" * 50)
            if result.returncode == 0:
                self.logger.info(f"✅ 第 {round_num} 轮训练完成，耗时: {round_time/60:.1f} 分钟")
                
                # 更新时间估算历史
                self._update_time_estimation_history(round_num, round_config, round_time)
                
                # 分析训练结果
                round_results = self._analyze_round_results(round_num, round_time)
                self.round_history.append(round_results)
                
                # 更新最佳模型记录
                if round_results["success"] and round_results["val_loss"] < self.best_val_loss:
                    self.best_val_loss = round_results["val_loss"]
                    self.best_round = round_num
                    self.logger.info(f"🏆 新的最佳模型！验证损失: {self.best_val_loss:.6f}")
                
                # 更新迁移学习检查点
                self._update_checkpoint_for_next_round(round_results)
                
                return True
                
            else:
                self.logger.error(f"❌ 第 {round_num} 轮训练失败，返回码: {result.returncode}")
                return False
                
        except Exception as e:
            self.logger.error(f"❌ 执行第 {round_num} 轮训练时出错: {e}")
            return False
    
    def _analyze_round_results(self, round_num: int, train_time: float) -> Dict[str, Any]:
        """分析轮次训练结果"""
        results = {
            "round": round_num,
            "success": False,
            "val_loss": float('inf'),
            "train_time": train_time,
            "model_path": None,
            "checkpoint_path": None
        }
        
        try:
            round_dir = self.output_dir / f"round_{round_num:02d}"
            
            # 查找 CSV 文件获取验证损失
            csv_files = list(round_dir.glob("plots/*.csv"))
            if not csv_files:
                csv_files = list(round_dir.glob("*.csv"))
                
            if csv_files:
                try:
                    import pandas as pd
                    df = pd.read_csv(csv_files[0])
                    
                    # 检查列名（支持大小写变体）
                    val_loss_col = None
                    if 'Val_Loss' in df.columns:
                        val_loss_col = 'Val_Loss'
                    elif 'val_loss' in df.columns:
                        val_loss_col = 'val_loss'
                    
                    if val_loss_col and len(df) > 0:
                        # 获取最后一个非无穷大的验证损失值
                        val_loss_series = df[val_loss_col]
                        # 过滤掉无穷大和NaN值
                        valid_losses = val_loss_series[~val_loss_series.isin([float('inf'), float('-inf')]) & val_loss_series.notna()]
                        if len(valid_losses) > 0:
                            results["val_loss"] = float(valid_losses.iloc[-1])
                            results["success"] = True
                            self.logger.info(f"Round {round_num}: 成功读取验证损失 {results['val_loss']:.6f}")
                        else:
                            self.logger.warning(f"Round {round_num}: CSV文件中没有有效的验证损失值")
                            
                except ImportError:
                    self.logger.warning("pandas 未安装，使用手动解析 CSV")
                    # 手动解析 CSV 文件
                    with open(csv_files[0], 'r') as f:
                        lines = f.readlines()
                        if len(lines) > 1:  # 有数据行
                            header = lines[0].strip().split(',')
                            val_loss_idx = -1
                            if 'Val_Loss' in header:
                                val_loss_idx = header.index('Val_Loss')
                            elif 'val_loss' in header:
                                val_loss_idx = header.index('val_loss')
                            
                            if val_loss_idx >= 0:
                                # 从最后一行开始向前查找有效的验证损失值
                                for line in reversed(lines[1:]):
                                    parts = line.strip().split(',')
                                    if len(parts) > val_loss_idx:
                                        try:
                                            val_loss = float(parts[val_loss_idx])
                                            if not (val_loss == float('inf') or val_loss == float('-inf') or val_loss != val_loss):  # 检查是否为inf或NaN
                                                results["val_loss"] = val_loss
                                                results["success"] = True
                                                self.logger.info(f"Round {round_num}: 手动解析得到验证损失 {val_loss:.6f}")
                                                break
                                        except ValueError:
                                            continue
                except Exception as e:
                    self.logger.error(f"解析 CSV 文件时出错: {e}")
            
            # 查找模型文件
            model_files = list(round_dir.glob("*.bin"))
            checkpoint_files = list(round_dir.glob("*.checkpoint"))
            
            if model_files:
                results["model_path"] = str(model_files[0])
            
            if checkpoint_files:
                results["checkpoint_path"] = str(checkpoint_files[0])
                
        except Exception as e:
            self.logger.warning(f"分析第 {round_num} 轮结果时出错: {e}")
        
        return results
    
    def _update_checkpoint_for_next_round(self, round_results: Dict[str, Any]):
        """更新下一轮使用的检查点"""
        if round_results["checkpoint_path"]:
            self.last_checkpoint = round_results["checkpoint_path"]
            checkpoint_name = Path(self.last_checkpoint).name
            self.logger.info(f"🔄 下轮将使用检查点: {checkpoint_name}")
        elif round_results["model_path"]:
            # 如果没有检查点文件，尝试使用模型文件
            # 注意：这种情况下迁移学习可能不完整
            self.last_checkpoint = round_results["model_path"]
            model_name = Path(self.last_checkpoint).name
            self.logger.info(f"🔄 下轮将使用模型文件: {model_name}")
    
    def _save_training_summary(self):
        """保存训练总结"""
        summary = {
            "start_time": self.start_time.isoformat() if self.start_time else None,
            "end_time": datetime.datetime.now().isoformat(),
            "total_rounds": len(self.round_history),
            "best_round": self.best_round,
            "best_val_loss": self.best_val_loss,
            "round_history": self.round_history,
            "config_used": self.config
        }
        
        summary_file = self.output_dir / "training_summary.json"
        with open(summary_file, 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)
        
        self.logger.info(f"📊 训练总结已保存: {summary_file}")
    
    def _print_final_summary(self):
        """打印最终训练总结"""
        self.logger.info(f"\n{'='*60}")
        self.logger.info("🎯 多轮训练完成总结")
        self.logger.info(f"{'='*60}")
        
        if not self.round_history:
            self.logger.info("❌ 没有成功完成的训练轮次")
            return
        
        total_time = sum(r["train_time"] for r in self.round_history)
        successful_rounds = [r for r in self.round_history if r["success"]]
        
        self.logger.info(f"✅ 完成轮次: {len(successful_rounds)}/{len(self.round_history)}")
        self.logger.info(f"🏆 最佳轮次: {self.best_round}")
        self.logger.info(f"📊 最佳验证损失: {self.best_val_loss:.6f}")
        self.logger.info(f"⏱️ 总训练时间: {total_time/3600:.2f} 小时")
        
        # 显示每轮结果
        self.logger.info(f"\n📈 轮次详情:")
        for result in self.round_history:
            status = "✅" if result["success"] else "❌"
            star = " 🏆" if result["round"] == self.best_round else ""
            self.logger.info(
                f"  轮次 {result['round']:2d}: {status} "
                f"验证损失: {result['val_loss']:8.6f} "
                f"训练时间: {result['train_time']/60:5.1f}分钟{star}"
            )
        
        # 最佳模型位置
        best_result = next((r for r in self.round_history if r["round"] == self.best_round), None)
        if best_result and best_result.get("model_path"):
            self.logger.info(f"\n🎯 最佳模型位置:")
            self.logger.info(f"  {best_result['model_path']}")
        
        # 时间估算准确性分析
        if len(self.time_estimation_history) > 0:
            avg_samples_per_sec = sum(h['samples_per_second'] for h in self.time_estimation_history) / len(self.time_estimation_history)
            self.logger.info(f"\n⚡ 训练性能分析:")
            self.logger.info(f"  平均处理速度: {avg_samples_per_sec:,.0f} 样本/秒")
            self.logger.info(f"  GPU利用效率: {'高' if avg_samples_per_sec > 50000 else '中' if avg_samples_per_sec > 20000 else '低'}")
    
    def run(self) -> bool:
        """运行多轮训练"""
        if not self.initialize():
            return False
        
        self.start_time = datetime.datetime.now()
        max_rounds = self.config.get("max_rounds", 6)
        
        self.logger.info(f"🚀 开始多轮 NNUE 训练")
        self.logger.info(f"📅 开始时间: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        self.logger.info(f"🔢 计划轮次: {max_rounds}")
        self.logger.info(f"📁 输出目录: {self.output_dir}")
        self.logger.info(f"🎯 Perfect DB: {self.config.get('perfect-db', 'N/A')}")
        self.logger.info(f"💾 初始批量大小: {self.config.get('batch-size', 4096)}")
        self.logger.info(f"📊 初始位置数量: {self.config.get('positions', 30000):,}")
        self.logger.info("")
        
        # 执行多轮训练
        for round_num in range(1, max_rounds + 1):
            self.current_round = round_num
            
            self.logger.info(f"🔄 准备开始第 {round_num}/{max_rounds} 轮训练...")
            
            success = self._run_single_round(round_num)
            if not success:
                self.logger.error(f"❌ 第 {round_num} 轮训练失败，停止多轮训练")
                break
            
            # 轮次间的分隔
            if round_num < max_rounds:
                self.logger.info(f"\n⏸️  第 {round_num} 轮完成，准备下一轮...")
                time.sleep(2)  # 短暂暂停，让用户看到进度
        
        # 保存训练总结
        self._save_training_summary()
        
        # 打印最终总结
        self._print_final_summary()
        
        return len(self.round_history) > 0

def main():
    """主函数"""
    # 简单的帮助信息
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help', 'help']:
        print(__doc__)
        print("\n📋 配置说明:")
        print("  请编辑 configs/easy_multiround.json 文件")
        print("  主要需要修改的配置项:")
        print("    - perfect-db: Perfect Database 路径")
        print("    - max_rounds: 训练轮次（默认6轮）")
        print("    - batch-size: 根据GPU内存调整")
        print("    - positions: 根据需要调整数据量")
        return
    
    # 创建训练器并运行
    trainer = EasyMultiRoundTrainer()
    
    try:
        success = trainer.run()
        
        if success:
            print("\n🎉 训练完成！查看输出目录了解详细结果。")
            sys.exit(0)
        else:
            print("\n❌ 训练失败，请查看日志了解详情。")
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n⏹️ 训练被用户中断")
        if trainer.logger:
            trainer.logger.info("训练被用户中断")
        sys.exit(1)
        
    except Exception as e:
        print(f"\n💥 训练过程中发生错误: {e}")
        if trainer.logger:
            trainer.logger.error(f"训练过程中发生错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
