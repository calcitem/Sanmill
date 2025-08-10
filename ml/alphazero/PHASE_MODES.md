# 训练阶段模式说明

## 默认行为（推荐）

```bash
# 默认自动两阶段模式：先 CPU 采样，再 GPU 训练
python main.py --config win_config.yaml
```

**自动执行：**
1. 🔍 采样阶段：CPU 多进程 (4-16 进程)
2. 🎯 训练阶段：GPU 单进程 + AMP

## 其他运行模式

### 原始单阶段模式
```bash
# 采样和训练在同一进程中进行（原始行为）
python main.py --config win_config.yaml --single-phase
```

### 仅采样
```bash
# 只运行采样阶段，跳过训练
python main.py --config win_config.yaml --sampling-only
```

### 仅训练
```bash
# 只运行训练阶段，需要已有样本文件
python main.py --config win_config.yaml --training-only
```

### 显式自动阶段
```bash
# 等同于默认行为，显式指定
python main.py --config win_config.yaml --auto-phases
```

## 进程数调整

| 配置文件设置 | 采样时进程数 | 训练时进程数 |
|-------------|-------------|-------------|
| `num_processes: 1` | 4 | 1 |
| `num_processes: 2` | 8 | 1 |
| `num_processes: 4` | 16 | 1 |

## 环境变量覆盖

```bash
# 强制指定采样进程数
$env:SANMILL_TRAIN_PROCESSES="12"
python main.py --config win_config.yaml

# 强制禁用 CUDA（采样用）
$env:SANMILL_TRAIN_CUDA="0"
python main.py --config win_config.yaml --sampling-only
```

## 推荐配置

### win_config.yaml
```yaml
# 这些设置会被自动阶段模式优化
cuda: true              # 训练时启用
num_processes: 1        # 采样时自动调整为 4
batch_size: 768         # 4090 24GB 推荐
num_channels: 256
use_amp: true           # 可选，默认启用
```

### 效果对比
- **默认自动阶段**：采样快（多核CPU），训练快（GPU+AMP），无OOM
- **原始单阶段**：采样慢（GPU空转），可能OOM，兼容性好
