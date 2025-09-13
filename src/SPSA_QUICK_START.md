# SPSA Parameter Tuning - Quick Start Guide

**⚠️ 重要提醒：此SPSA系统仅适用于传统搜索算法（Alpha-Beta、PVS、MTD(f)），不支持MCTS算法！**

## 快速开始

### 1. 编译系统

```bash
cd src
make -f spsa_tuner_makefile
```

### 2. 创建示例配置文件

```bash
make -f spsa_tuner_makefile examples
```

这将创建：
- `spsa_config_example.txt` - 配置文件示例
- `spsa_params_example.txt` - 参数文件示例

### 3. 运行基础调优

```bash
# 快速测试（200次迭代，50场对局）
./run_spsa_tuning.sh --fast

# 标准调优（1000次迭代，100场对局）
./run_spsa_tuning.sh --standard

# 深度调优（2000次迭代，200场对局）
./run_spsa_tuning.sh --thorough
```

### 4. 交互模式

```bash
./spsa_tuner --interactive
```

交互命令：
- `start` - 开始调优
- `status` - 查看状态
- `params` - 查看参数
- `stop` - 停止调优
- `quit` - 退出

### 5. 自定义配置

```bash
# 使用自定义配置文件
./spsa_tuner --config my_config.txt --params my_params.txt

# 指定输出文件
./spsa_tuner --output optimized_params.txt --log detailed.log

# 从检查点恢复
./spsa_tuner --resume checkpoint.txt
```

## 重要参数说明

### 核心SPSA参数
- **learning_rate (a)**: 学习率，控制参数更新步长（0.05-0.5）
- **perturbation (c)**: 扰动大小，控制参数探索范围（0.01-0.1）
- **alpha**: 学习率衰减指数，推荐0.602
- **gamma**: 扰动衰减指数，推荐0.101

### 评估参数
- **games_per_evaluation**: 每次评估的对局数（50-500）
- **max_iterations**: 最大迭代次数（100-5000）
- **max_threads**: 并行线程数（建议等于CPU核心数）

## 可调优的引擎参数

| 参数名 | 描述 | 类型 | 范围 |
|--------|------|------|------|
| exploration_parameter | MCTS探索因子 | 浮点 | 0.1-2.0 |
| bias_factor | MCTS偏置因子 | 浮点 | 0.0-0.2 |
| alpha_beta_depth | 搜索深度 | 整数 | 3-12 |
| piece_value | 基础棋子价值 | 整数 | 1-20 |
| piece_inhand_value | 手中棋子价值 | 整数 | 1-20 |
| piece_onboard_value | 棋盘棋子价值 | 整数 | 1-20 |
| piece_needremove_value | 待移除棋子价值 | 整数 | 1-20 |
| mobility_weight | 机动性权重 | 浮点 | 0.0-3.0 |

## 输出文件

- **spsa_tuning.log**: 详细的迭代日志
- **spsa_checkpoint.txt**: 检查点文件，用于恢复
- **best_parameters.txt**: 当前最佳参数
- **final_parameters.txt**: 最终优化参数

## 性能建议

### 快速测试
```bash
./run_spsa_tuning.sh --iterations 100 --games 30 --threads 4
```

### 生产调优
```bash
./run_spsa_tuning.sh --iterations 2000 --games 200 --threads 16
```

### 超长时间调优
```bash
./run_spsa_tuning.sh --ultra  # 5000次迭代，500场对局
```

## 故障排除

### 编译问题
```bash
# 手动编译
g++ -std=c++17 -O3 -Wall -pthread -I. \
    spsa_tuner.cpp spsa_main.cpp [其他源文件...] \
    -o spsa_tuner -pthread
```

### 运行时问题
- 确保有足够的内存（建议8GB+）
- 检查线程数不超过CPU核心数
- 验证参数范围合理
- 查看日志文件获取详细错误信息

### 收敛问题
- 减小学习率（learning_rate）
- 增加每次评估的对局数
- 调整参数边界
- 检查初始参数是否合理

## 示例配置文件

### 快速测试配置
```ini
learning_rate=0.2
perturbation=0.08
max_iterations=200
games_per_evaluation=50
max_threads=4
convergence_threshold=0.005
```

### 精确调优配置
```ini
learning_rate=0.12
perturbation=0.03
max_iterations=3000
games_per_evaluation=300
max_threads=16
convergence_threshold=0.0005
```

## 验证结果

调优完成后，建议进行验证：

```bash
# 使用优化后的参数与原始参数对战
./spsa_tuner --params final_parameters.txt --games 1000 --output validation_results.txt
```

## 进阶用法

### 分阶段调优
1. 先调优主要参数（piece values, depth）
2. 再调优次要参数（mobility weights等）
3. 最后整体微调

### 自定义参数
修改 `spsa_tuner.cpp` 中的 `initialize_default_parameters()` 函数添加新参数。

### 多目标优化
可以修改评估函数，同时考虑胜率和游戏时长等多个指标。
