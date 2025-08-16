# NNUE GUI 使用示例

## 快速开始

### 最简单的启动方式

```bash
# 自动检测模型并启动 GUI
python start_nnue_gui.py
```

或者在 Windows 上直接双击 `start_nnue_gui.bat`

### 指定模型文件启动

```bash
# 使用特定的模型文件
python nnue_pit.py --model nnue_model.bin --gui --first human
```

### 使用配置文件启动

```bash
# 创建配置文件
python nnue_pit.py --create-config my_config.json

# 编辑配置文件，然后启动
python nnue_pit.py --config my_config.json
```

## 详细使用示例

### 1. 人类先手 vs AI

```bash
python nnue_pit.py --model nnue_model.bin --gui --first human --depth 3
```

**说明**: 人类玩家先手，AI 搜索深度为 3 层

### 2. AI 先手 vs 人类

```bash
python nnue_pit.py --model nnue_model.bin --gui --first ai --depth 4
```

**说明**: AI 先手，使用更深的搜索深度（4层）

### 3. 使用不同模型格式

```bash
# 使用 PyTorch 模型
python nnue_pit.py --model checkpoint.pth --gui

# 使用二进制模型
python nnue_pit.py --model nnue_weights.bin --gui

# 使用训练检查点
python nnue_pit.py --model best_model.tar --gui
```

### 4. 自定义模型参数

```bash
# 如果模型使用不同的网络结构
python nnue_pit.py --model custom_model.bin --gui \
    --feature-size 95 --hidden-size 128 --depth 5
```

### 5. 批量测试

```bash
# 连续对战 10 局
python nnue_pit.py --model nnue_model.bin --gui --games 10
```

## 配置文件示例

### 基础配置（nnue_basic.json）

```json
{
  "model_path": "nnue_model.bin",
  "gui": true,
  "human_first": true,
  "search_depth": 3,
  "log_level": "INFO"
}
```

使用方式：
```bash
python nnue_pit.py --config nnue_basic.json
```

### 高级配置（nnue_advanced.json）

```json
{
  "model_path": "advanced_model.bin",
  "feature_size": 115,
  "hidden_size": 512,
  "search_depth": 5,
  "human_first": false,
  "gui": true,
  "games": 5,
  "time_per_move": 5.0,
  "show_evaluation": true,
  "show_thinking_time": true,
  "device": "cuda",
  "log_level": "DEBUG"
}
```

### 快速测试配置（nnue_quick.json）

```json
{
  "model_path": "quick_model.bin",
  "search_depth": 2,
  "human_first": true,
  "gui": true,
  "time_per_move": 1.0,
  "log_level": "WARNING"
}
```

## 常用操作组合

### 开发测试流程

```bash
# 1. 训练模型
python train_nnue.py --config configs/fast.json --data training_data.txt

# 2. 验证模型一致性
python verify_model_consistency.py --analyze nnue_model.bin

# 3. 启动 GUI 测试
python nnue_pit.py --model nnue_model.bin --gui --first human
```

### 模型评估流程

```bash
# 1. 使用不同搜索深度测试
python nnue_pit.py --model model_v1.bin --gui --depth 2 --games 3
python nnue_pit.py --model model_v1.bin --gui --depth 4 --games 3

# 2. 对比不同模型
python nnue_pit.py --model model_v1.bin --gui --games 5
python nnue_pit.py --model model_v2.bin --gui --games 5
```

### 调试模式

```bash
# 启用详细日志
python nnue_pit.py --model debug_model.bin --gui --config debug_config.json

# debug_config.json 内容：
{
  "model_path": "debug_model.bin",
  "gui": true,
  "log_level": "DEBUG",
  "show_evaluation": true,
  "show_thinking_time": true,
  "search_depth": 2
}
```

## 错误处理示例

### 模型文件问题

```bash
# 检查模型文件是否存在
ls -la *.bin *.pth *.tar

# 分析模型文件结构
python verify_model_consistency.py --analyze model.bin

# 使用正确路径
python nnue_pit.py --model ./models/nnue_model.bin --gui
```

### 依赖问题

```bash
# 检查 Python 版本
python --version

# 安装依赖
pip install torch numpy matplotlib

# 检查 Tkinter（GUI 必需）
python -c "import tkinter; print('Tkinter available')"
```

### 配置问题

```bash
# 创建默认配置
python nnue_pit.py --create-config default.json

# 验证配置语法
python -m json.tool my_config.json

# 使用最小配置
echo '{"model_path": "model.bin", "gui": true}' > minimal.json
python nnue_pit.py --config minimal.json
```

## 性能优化示例

### GPU 加速

```json
{
  "model_path": "nnue_model.bin",
  "device": "cuda",
  "batch_size": 1,
  "gui": true
}
```

### 降低计算量

```json
{
  "model_path": "nnue_model.bin",
  "search_depth": 2,
  "device": "cpu",
  "time_per_move": 1.0,
  "gui": true
}
```

### 内存优化

```json
{
  "model_path": "nnue_model.bin",
  "hidden_size": 256,
  "batch_size": 1,
  "device": "auto",
  "gui": true
}
```

## 扩展使用

### 与其他工具集成

```bash
# 导出对局记录
python nnue_pit.py --model model.bin --gui --games 1 > game_log.txt

# 批处理测试
for model in models/*.bin; do
    echo "Testing $model"
    python nnue_pit.py --model "$model" --gui --games 1 --first ai
done
```

### 自动化测试

```bash
#!/bin/bash
# 自动测试脚本

models=(
    "model_v1.bin"
    "model_v2.bin"
    "model_v3.bin"
)

for model in "${models[@]}"; do
    echo "Testing $model with human first..."
    python nnue_pit.py --model "$model" --gui --first human --games 1
    
    echo "Testing $model with AI first..."
    python nnue_pit.py --model "$model" --gui --first ai --games 1
done
```

## 故障排除检查清单

### 启动前检查

1. 确认在正确目录：`ls nnue_pit.py`
2. 检查 Python 版本：`python --version`
3. 验证模型文件：`ls *.bin *.pth *.tar`
4. 测试依赖：`python -c "import torch, tkinter"`

### 运行时问题

1. GUI 无响应：重启程序，降低搜索深度
2. 模型加载失败：检查文件路径和格式
3. 内存不足：使用较小的模型或降低批处理大小
4. 性能缓慢：切换到 CPU 模式或降低搜索深度

### 调试命令

```bash
# 检查模型信息
python -c "
import torch
model = torch.load('model.pth', map_location='cpu')
print(f'Model keys: {list(model.keys())}')
"

# 测试配置文件
python -c "
import json
with open('config.json') as f:
    config = json.load(f)
print('Configuration loaded successfully')
print(f'Model path: {config.get(\"model_path\")}')
"

# 验证 NNUE 模块
python -c "
from train_nnue import MillNNUE
model = MillNNUE()
print('NNUE model created successfully')
"
```
