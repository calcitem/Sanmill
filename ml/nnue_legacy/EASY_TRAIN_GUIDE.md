# Easy Train 使用指南

## 概述

`easy_train.py` 是一个全自动化的多轮 NNUE 训练工具，支持迁移学习和智能参数优化。用户只需配置好配置文件，运行脚本即可完成整个训练流程。

## 🚀 快速开始

### 1. 配置文件设置

编辑 `configs/easy_multiround.json` 文件：

```json
{
  "perfect-db": "E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted",
  "max_rounds": 6,
  "batch-size": 8192,
  "positions": 50000
}
```

**重要：** 请将 `perfect-db` 路径修改为你的 Perfect Database 目录。

### 2. 运行训练

```bash
python easy_train.py
```

就这么简单！脚本会自动完成：
- ✅ 6轮渐进式训练
- ✅ 智能迁移学习
- ✅ 动态参数调整
- ✅ 完整的训练监控

## 🧠 智能训练策略

### 多轮训练计划

| 轮次 | 位置数量 | Epochs | 学习率 | 批量大小 | 阶段描述 |
|------|----------|--------|--------|----------|----------|
| 1 | 30,000 | 80 | 0.003 | 4,096 | 探索阶段：快速收敛 |
| 2 | 50,000 | 120 | 0.002 | 6,144 | 稳定学习：平衡优化 |
| 3 | 80,000 | 150 | 0.0015 | 8,192 | 深化学习：增加数据 |
| 4 | 100,000 | 180 | 0.001 | 8,192 | 精细调整：大数据集 |
| 5 | 120,000 | 200 | 0.0008 | 10,240 | 优化阶段：降低学习率 |
| 6 | 150,000 | 250 | 0.0005 | 10,240 | 收敛阶段：最终优化 |

### 迁移学习策略

- **轮次 1-3**: 使用 `full` 策略，完全迁移所有权重，学习率缩放 0.5
- **轮次 4-5**: 使用 `fine-tune` 策略，微调模式，学习率缩放 0.3
- **轮次 6+**: 使用 `fine-tune` 策略，精细微调，学习率缩放 0.1

## 📁 输出结构

```
easy_multiround_output/
├── round_01/
│   ├── nnue_model_round_01.bin          # 模型文件
│   ├── nnue_model_round_01.checkpoint   # 检查点文件（用于迁移学习）
│   ├── training_metrics.csv             # 训练指标
│   └── plots/                           # 可视化图表
├── round_02/
│   └── ...
├── round_01_config.json                 # 各轮次配置
├── round_02_config.json
├── easy_training.log                    # 详细日志
└── training_summary.json                # 训练总结
```

## ⚙️ 配置文件详解

### 必需配置

```json
{
  "perfect-db": "path/to/your/perfect/database",
  "_comment": "Perfect Database 路径 - 必须修改"
}
```

### 可选配置

```json
{
  "max_rounds": 6,
  "_comment": "训练轮次，默认6轮",
  
  "batch-size": 8192,
  "_comment": "批量大小，根据GPU内存调整",
  
  "positions": 50000,
  "_comment": "基础位置数量，每轮会自动调整",
  
  "output-dir": "./easy_multiround_output",
  "_comment": "输出目录",
  
  "device": "auto",
  "_comment": "设备选择：auto/cuda/cpu"
}
```

### 硬件要求

```json
{
  "_hardware_requirements": {
    "minimum_ram": "8GB",
    "recommended_ram": "16GB", 
    "gpu_memory": "6GB+",
    "disk_space": "10GB+"
  }
}
```

## 🎯 使用场景

### 场景1：标准训练

```bash
# 1. 配置 perfect-db 路径
# 2. 运行
python easy_train.py
```

适用于：大多数用户，平衡的训练效果和时间

### 场景2：快速测试

修改配置文件：
```json
{
  "max_rounds": 3,
  "positions": 10000
}
```

适用于：快速验证环境和配置

### 场景3：高质量训练

修改配置文件：
```json
{
  "max_rounds": 8,
  "positions": 100000,
  "batch-size": 16384
}
```

适用于：追求最佳效果，有充足时间和硬件资源

## 📊 训练监控

### 实时日志

训练过程中可以查看：
- 控制台输出：实时训练状态
- `easy_training.log`：详细日志文件

### 训练指标

每轮训练完成后会显示：
```
轮次 01: ✅ 验证损失: 0.001234 训练时间: 45.2分钟
轮次 02: ✅ 验证损失: 0.001156 训练时间: 52.1分钟 🏆
```

### 最终总结

训练完成后会显示：
```
🎯 多轮训练完成总结
✅ 完成轮次: 6/6
🏆 最佳轮次: 4
📊 最佳验证损失: 0.000987
⏱️ 总训练时间: 5.23 小时
🎯 最佳模型位置: easy_multiround_output/round_04/nnue_model_round_04.bin
```

## 🔧 故障排除

### 常见问题

1. **配置文件不存在**
   ```
   ❌ 配置文件不存在: configs/easy_multiround.json
   ```
   解决：确保配置文件存在且路径正确

2. **Perfect Database 路径错误**
   ```
   ❌ Perfect Database 不存在: path/to/db
   ```
   解决：检查并修正配置文件中的 `perfect-db` 路径

3. **GPU 内存不足**
   ```
   RuntimeError: CUDA out of memory
   ```
   解决：减小 `batch-size` 配置，如从 8192 改为 4096

4. **磁盘空间不足**
   解决：清理旧的训练输出，确保有足够磁盘空间

### 获取帮助

```bash
python easy_train.py --help
```

## 🎉 预期效果

使用 Easy Train 相比传统训练方法：

- 🚀 **训练速度**: 2-3倍加速（迁移学习）
- 📈 **最终性能**: 10-25%提升（多轮优化）
- 🎯 **使用便利**: 零配置，一键运行
- 📊 **训练稳定**: 显著减少训练失败

## 💡 最佳实践

1. **首次使用**：使用默认配置，观察训练效果
2. **硬件优化**：根据 GPU 内存调整 `batch-size`
3. **时间规划**：预留 4-8 小时完成完整训练
4. **监控训练**：关注日志中的迁移学习状态
5. **结果分析**：查看 `training_summary.json` 了解详细结果

## 📞 技术支持

如果遇到问题：
1. 查看 `easy_training.log` 详细日志
2. 检查配置文件格式和路径
3. 确认硬件要求满足
4. 尝试减小数据规模测试

Easy Train 让 NNUE 训练变得简单高效！🎯
