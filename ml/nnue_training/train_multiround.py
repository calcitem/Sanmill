#!/usr/bin/env python3
"""
多轮 NNUE 训练脚本
支持参数继承、动态调整和智能优化策略
"""

import os
import sys
import json
import time
import logging
import argparse
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
import torch
import numpy as np

# 添加项目根目录到路径
sys.path.insert(0, str(Path(__file__).parent))

from train_nnue import main as train_single_round

logger = logging.getLogger(__name__)


class MultiRoundTrainer:
    """多轮 NNUE 训练器，支持参数继承和动态优化"""
    
    def __init__(self, config_path: str, output_dir: str = "multiround_output"):
        self.config_path = Path(config_path)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # 加载基础配置
        with open(self.config_path, 'r', encoding='utf-8') as f:
            self.base_config = json.load(f)
        
        # 训练状态管理
        self.round_history = []
        self.best_val_loss = float('inf')
        self.best_round = 0
        self.current_round = 0
        
        # 参数继承状态
        self.inherited_lr = None
        self.inherited_scheduler_state = None
        self.last_model_path = None
        
        # 设置日志
        self._setup_logging()
        
    def _setup_logging(self):
        """设置日志系统"""
        log_file = self.output_dir / "multiround_training.log"
        
        # 创建格式化器
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # 文件处理器
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(formatter)
        
        # 控制台处理器
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(formatter)
        
        # 配置 logger
        logger.setLevel(logging.INFO)
        logger.addHandler(file_handler)
        logger.addHandler(console_handler)
        
    def create_round_config(self, round_num: int) -> Dict[str, Any]:
        """为指定轮次创建训练配置"""
        config = self.base_config.copy()
        
        # 根据轮次调整参数
        round_params = self._get_round_parameters(round_num)
        config.update(round_params)
        
        # 设置输出路径
        round_output_dir = self.output_dir / f"round_{round_num:02d}"
        round_output_dir.mkdir(exist_ok=True)
        
        config["output"] = str(round_output_dir / f"nnue_model_round_{round_num:02d}.bin")
        config["output-dir"] = str(round_output_dir)
        
        # 参数继承
        if self.inherited_lr is not None:
            config["lr"] = self.inherited_lr
            logger.info(f"Round {round_num}: 继承学习率 {self.inherited_lr:.6f}")
        
        # 迁移学习：从前一轮模型开始训练
        if self.last_model_path and round_num > 1:
            config["transfer-from"] = self.last_model_path
            
            # 根据轮次选择迁移学习策略
            if round_num <= 3:
                config["transfer-strategy"] = "full"  # 前期：完全迁移
                config["transfer-lr-scale"] = 0.5     # 适中的学习率缩放
            elif round_num <= 5:
                config["transfer-strategy"] = "fine-tune"  # 中期：微调
                config["transfer-lr-scale"] = 0.3          # 较小的学习率缩放
            else:
                config["transfer-strategy"] = "fine-tune"  # 后期：精细微调
                config["transfer-lr-scale"] = 0.1          # 很小的学习率缩放
                
            logger.info(f"Round {round_num}: 启用迁移学习，策略={config['transfer-strategy']}, LR缩放={config['transfer-lr-scale']}")
            
        return config
        
    def _get_round_parameters(self, round_num: int) -> Dict[str, Any]:
        """根据轮次获取参数配置"""
        
        # 定义多轮训练策略
        strategies = {
            1: {  # 探索阶段
                "positions": 30000,
                "epochs": 80,
                "lr": 0.003,
                "batch-size": 4096,
                "_description": "探索阶段：较高学习率，快速收敛"
            },
            2: {  # 稳定学习阶段
                "positions": 50000, 
                "epochs": 120,
                "lr": 0.002,
                "batch-size": 6144,
                "_description": "稳定学习：平衡数据量和学习率"
            },
            3: {  # 深化学习
                "positions": 80000,
                "epochs": 150,
                "lr": 0.0015,
                "batch-size": 8192,
                "_description": "深化学习：增加数据量，降低学习率"
            },
            4: {  # 精细调整
                "positions": 100000,
                "epochs": 180,
                "lr": 0.001,
                "batch-size": 8192,
                "_description": "精细调整：大数据集，适中学习率"
            },
            5: {  # 优化阶段
                "positions": 120000,
                "epochs": 200,
                "lr": 0.0008,
                "batch-size": 10240,
                "_description": "优化阶段：最大数据集，较低学习率"
            },
            6: {  # 收敛阶段
                "positions": 150000,
                "epochs": 250,
                "lr": 0.0005,
                "batch-size": 10240,
                "_description": "收敛阶段：超大数据集，最低学习率"
            }
        }
        
        # 如果轮次超出预定义策略，使用最后一个策略
        if round_num > len(strategies):
            params = strategies[len(strategies)].copy()
            # 继续降低学习率
            params["lr"] *= 0.8 ** (round_num - len(strategies))
            params["_description"] = f"扩展轮次 {round_num}：继续优化"
        else:
            params = strategies[round_num].copy()
            
        return params
        
    def analyze_round_results(self, round_num: int, round_dir: Path) -> Dict[str, Any]:
        """分析轮次训练结果"""
        results = {
            "round": round_num,
            "success": False,
            "val_loss": float('inf'),
            "train_time": 0,
            "model_path": None
        }
        
        try:
            # 查找训练日志或CSV文件
            csv_files = list(round_dir.glob("plots/*.csv"))
            if not csv_files:
                csv_files = list(round_dir.glob("*.csv"))
            
            if csv_files:
                # 从CSV文件读取最终验证损失
                try:
                    import pandas as pd
                    df = pd.read_csv(csv_files[0])
                    if 'Val_Loss' in df.columns and len(df) > 0:
                        # 获取最后一个非无穷大的验证损失值
                        val_loss_series = df['Val_Loss']
                        # 过滤掉无穷大和NaN值
                        valid_losses = val_loss_series[~val_loss_series.isin([float('inf'), float('-inf')]) & val_loss_series.notna()]
                        if len(valid_losses) > 0:
                            results["val_loss"] = float(valid_losses.iloc[-1])
                            results["success"] = True
                            logger.info(f"Round {round_num}: 成功读取验证损失 {results['val_loss']:.6f}")
                        else:
                            logger.warning(f"Round {round_num}: CSV文件中没有有效的验证损失值")
                    elif 'val_loss' in df.columns and len(df) > 0:
                        # 兼容小写列名
                        val_loss_series = df['val_loss']
                        valid_losses = val_loss_series[~val_loss_series.isin([float('inf'), float('-inf')]) & val_loss_series.notna()]
                        if len(valid_losses) > 0:
                            results["val_loss"] = float(valid_losses.iloc[-1])
                            results["success"] = True
                            logger.info(f"Round {round_num}: 成功读取验证损失 {results['val_loss']:.6f}")
                        else:
                            logger.warning(f"Round {round_num}: CSV文件中没有有效的验证损失值")
                except ImportError:
                    logger.warning("pandas 未安装，使用手动解析 CSV")
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
                                                logger.info(f"Round {round_num}: 手动解析得到验证损失 {val_loss:.6f}")
                                                break
                                        except ValueError:
                                            continue
                except Exception as e:
                    logger.error(f"解析 CSV 文件时出错: {e}")
                    
            # 查找模型文件（优先检查点文件）
            checkpoint_files = list(round_dir.glob("*.checkpoint"))
            model_files = list(round_dir.glob("*.bin"))
            
            if checkpoint_files:
                results["model_path"] = str(checkpoint_files[0])
                results["has_checkpoint"] = True
            elif model_files:
                results["model_path"] = str(model_files[0])
                results["has_checkpoint"] = False
                
        except Exception as e:
            logger.warning(f"分析第 {round_num} 轮结果时出错: {e}")
            
        return results
        
    def update_inherited_parameters(self, round_results: Dict[str, Any]):
        """根据轮次结果更新继承参数"""
        if not round_results["success"]:
            return
            
        val_loss = round_results["val_loss"]
        
        # 更新最佳模型记录
        if val_loss < self.best_val_loss:
            self.best_val_loss = val_loss
            self.best_round = round_results["round"]
            logger.info(f"🏆 新的最佳模型！轮次 {self.best_round}，验证损失: {val_loss:.6f}")
            
        # 动态调整学习率
        if len(self.round_history) >= 2:
            prev_loss = self.round_history[-1]["val_loss"]
            improvement = (prev_loss - val_loss) / prev_loss
            
            if improvement > 0.05:  # 显著改善，保持或略微增加学习率
                self.inherited_lr = self.inherited_lr * 1.05 if self.inherited_lr else 0.002
                logger.info(f"📈 训练改善显著 ({improvement:.2%})，学习率调整为 {self.inherited_lr:.6f}")
                
            elif improvement < 0.01:  # 改善缓慢，降低学习率
                self.inherited_lr = self.inherited_lr * 0.8 if self.inherited_lr else 0.001
                logger.info(f"📉 训练改善缓慢 ({improvement:.2%})，学习率降低为 {self.inherited_lr:.6f}")
                
            else:  # 适中改善，保持学习率
                logger.info(f"📊 训练改善适中 ({improvement:.2%})，保持当前学习率")
        
        # 更新模型路径（优先使用检查点文件用于迁移学习）
        if round_results["model_path"]:
            # 检查是否有对应的检查点文件
            model_path = Path(round_results["model_path"])
            checkpoint_path = model_path.with_suffix('.checkpoint')
            
            if checkpoint_path.exists():
                self.last_model_path = str(checkpoint_path)
                logger.info(f"🔄 下轮将使用检查点文件进行迁移学习: {checkpoint_path.name}")
            else:
                self.last_model_path = round_results["model_path"]
                logger.info(f"🔄 下轮将使用模型文件进行迁移学习: {model_path.name}")
            
    def save_training_state(self):
        """保存训练状态"""
        state = {
            "current_round": self.current_round,
            "round_history": self.round_history,
            "best_val_loss": self.best_val_loss,
            "best_round": self.best_round,
            "inherited_lr": self.inherited_lr,
            "last_model_path": self.last_model_path,
            "base_config": self.base_config
        }
        
        state_file = self.output_dir / "training_state.json"
        with open(state_file, 'w', encoding='utf-8') as f:
            json.dump(state, f, indent=2, ensure_ascii=False)
            
    def load_training_state(self) -> bool:
        """加载训练状态"""
        state_file = self.output_dir / "training_state.json"
        if not state_file.exists():
            return False
            
        try:
            with open(state_file, 'r', encoding='utf-8') as f:
                state = json.load(f)
                
            self.current_round = state.get("current_round", 0)
            self.round_history = state.get("round_history", [])
            self.best_val_loss = state.get("best_val_loss", float('inf'))
            self.best_round = state.get("best_round", 0)
            self.inherited_lr = state.get("inherited_lr")
            self.last_model_path = state.get("last_model_path")
            
            logger.info(f"✅ 成功加载训练状态，当前轮次: {self.current_round}")
            return True
            
        except Exception as e:
            logger.error(f"❌ 加载训练状态失败: {e}")
            return False
            
    def run_training(self, max_rounds: int = 6, resume: bool = True):
        """执行多轮训练"""
        logger.info(f"🚀 开始多轮 NNUE 训练，最大轮次: {max_rounds}")
        
        # 尝试恢复训练状态
        if resume:
            self.load_training_state()
            
        start_round = self.current_round + 1
        
        for round_num in range(start_round, max_rounds + 1):
            logger.info(f"\n{'='*60}")
            logger.info(f"🔄 开始第 {round_num}/{max_rounds} 轮训练")
            logger.info(f"{'='*60}")
            
            self.current_round = round_num
            
            # 创建轮次配置
            round_config = self.create_round_config(round_num)
            config_file = self.output_dir / f"round_{round_num:02d}_config.json"
            
            with open(config_file, 'w', encoding='utf-8') as f:
                json.dump(round_config, f, indent=2, ensure_ascii=False)
                
            logger.info(f"📝 轮次 {round_num} 配置:")
            logger.info(f"  - 位置数量: {round_config['positions']:,}")
            logger.info(f"  - 训练轮数: {round_config['epochs']}")
            logger.info(f"  - 学习率: {round_config['lr']:.6f}")
            logger.info(f"  - 批量大小: {round_config['batch-size']:,}")
            logger.info(f"  - 描述: {round_config.get('_description', 'N/A')}")
            
            # 执行训练
            round_start_time = time.time()
            
            try:
                # 构建训练命令参数
                train_args = [
                    "--config", str(config_file),
                ]
                
                # 添加必要的管道参数
                if round_config.get("pipeline", True):
                    train_args.extend([
                        "--pipeline",
                        "--perfect-db", round_config["perfect-db"]
                    ])
                
                # 执行训练 (这里需要调用 train_nnue.py 的主函数)
                # 注意：这是简化实现，实际需要适配参数传递
                logger.info(f"⚡ 执行训练命令: python train_nnue.py {' '.join(train_args)}")
                
                # 实际调用训练函数 (需要适配)
                success = self._run_single_round(train_args)
                
                round_time = time.time() - round_start_time
                
                if success:
                    logger.info(f"✅ 第 {round_num} 轮训练完成，耗时: {round_time/60:.1f} 分钟")
                    
                    # 分析结果
                    round_dir = self.output_dir / f"round_{round_num:02d}"
                    results = self.analyze_round_results(round_num, round_dir)
                    results["train_time"] = round_time
                    
                    # 更新历史记录
                    self.round_history.append(results)
                    
                    # 更新继承参数
                    self.update_inherited_parameters(results)
                    
                    # 保存状态
                    self.save_training_state()
                    
                else:
                    logger.error(f"❌ 第 {round_num} 轮训练失败")
                    break
                    
            except Exception as e:
                logger.error(f"❌ 第 {round_num} 轮训练出错: {e}")
                break
                
        # 训练完成总结
        self._print_training_summary()
        
    def _run_single_round(self, train_args) -> bool:
        """执行单轮训练"""
        try:
            # 这里应该调用 train_nnue.py 的主函数
            # 由于当前实现的限制，这里使用系统调用
            import subprocess
            
            cmd = ["python", "train_nnue.py"] + train_args
            result = subprocess.run(cmd, cwd=Path(__file__).parent, 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                return True
            else:
                logger.error(f"训练命令失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"执行训练时出错: {e}")
            return False
            
    def _print_training_summary(self):
        """打印训练总结"""
        logger.info(f"\n{'='*60}")
        logger.info("🎯 多轮训练完成总结")
        logger.info(f"{'='*60}")
        
        if not self.round_history:
            logger.info("❌ 没有成功完成的训练轮次")
            return
            
        logger.info(f"✅ 完成轮次: {len(self.round_history)}")
        logger.info(f"🏆 最佳轮次: {self.best_round}")
        logger.info(f"📊 最佳验证损失: {self.best_val_loss:.6f}")
        
        if self.last_model_path:
            logger.info(f"📁 最终模型: {self.last_model_path}")
            
        # 显示每轮结果
        logger.info(f"\n📈 轮次详情:")
        for result in self.round_history:
            status = "✅" if result["success"] else "❌"
            logger.info(f"  轮次 {result['round']:2d}: {status} "
                       f"验证损失: {result['val_loss']:8.6f} "
                       f"训练时间: {result['train_time']/60:5.1f}分钟")


def main():
    parser = argparse.ArgumentParser(description="多轮 NNUE 训练脚本")
    parser.add_argument("--config", required=True, help="基础配置文件路径")
    parser.add_argument("--output-dir", default="multiround_output", help="输出目录")
    parser.add_argument("--max-rounds", type=int, default=6, help="最大训练轮次")
    parser.add_argument("--resume", action="store_true", help="恢复之前的训练")
    
    args = parser.parse_args()
    
    # 创建多轮训练器
    trainer = MultiRoundTrainer(args.config, args.output_dir)
    
    # 开始训练
    trainer.run_training(args.max_rounds, args.resume)


if __name__ == "__main__":
    main()
