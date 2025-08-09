#!/usr/bin/env python3
"""
Simple configuration template generator.
Uses the actual default values from main.py to avoid duplication.
"""

import os
import sys


def copy_template_file():
    """Copy the existing template file if it doesn't exist."""
    template_source = 'config_template.yaml'
    
    # Check if template already exists
    if os.path.exists(template_source):
        return f"✅ Template already exists: {template_source}"
    
    # If template doesn't exist, create a minimal one
    minimal_template = """# AlphaZero Training Configuration
# Copy this file as 'my_config.yaml' and modify as needed

# === 基本训练参数 ===
numIters: 10               # 训练轮数
numEps: 20                 # 每轮自对弈对局数
tempThreshold: 80          # 温度策略切换点
updateThreshold: 0.55      # 新模型接受阈值
maxlenOfQueue: 200000      # 训练样本队列长度
numMCTSSims: 40           # MCTS 每步模拟次数
arenaCompare: 10          # 新旧模型对战局数
cpuct: 1.5                # UCB 探索参数

# === 文件管理 ===
checkpoint: './temp/'                    # 模型保存目录
load_model: true                         # 是否从检查点恢复
load_folder_file: ['temp/', 'best.pth.tar']  # 加载的模型文件
numItersForTrainExamplesHistory: 5       # 保留历史样本轮数

# === 系统设置 ===
num_processes: 1          # 并行进程数（教师模式建议1）
cuda: false              # 是否使用GPU

# === 神经网络参数 ===
lr: 0.002                # 学习率
dropout: 0.3             # Dropout率
epochs: 10               # 每轮训练轮数
batch_size: 1024         # 批大小
num_channels: 256        # 网络通道数

# === 完美数据库教师 ===
usePerfectTeacher: true                    # 启用教师混合
teacherExamplesPerIter: 1000              # 每轮教师样本数
teacherBatch: 256                         # 教师采样批大小
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'  # 数据库路径（必须修改）
teacherAnalyzeTimeout: 120                # 分析超时时间
teacherThreads: 1                         # 引擎线程数
pitAgainstPerfect: true                   # 每轮评估对完美库表现

# === 调试选项 ===
verbose_games: 1          # 详细记录的对局数
log_detailed_moves: true  # 是否记录详细走法

# === 使用场景示例 ===
# 快速测试: numIters: 3, numEps: 6, teacherExamplesPerIter: 100
# 高质量训练: numIters: 50+, numEps: 100+, num_channels: 512
# 纯AlphaZero: usePerfectTeacher: false, num_processes: 2-4
"""
    
    with open(template_source, 'w', encoding='utf-8') as f:
        f.write(minimal_template)
    
    return f"✅ Created template: {template_source}"


def main():
    """Create configuration template."""
    try:
        result = copy_template_file()
        print(result)
        
        print("\n🚀 Quick start:")
        print("   cp config_template.yaml my_config.yaml")
        print("   # Edit my_config.yaml with your database path")
        print("   python3 main.py --config my_config.yaml")
        print("\n💡 All parameters are documented in the config file")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        print("💡 Try running this script from the alphazero directory")


if __name__ == '__main__':
    main()
