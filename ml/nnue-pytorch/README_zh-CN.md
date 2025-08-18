# 九子棋 NNUE PyTorch 训练与使用指南

这是专门为九子棋（Nine Men's Morris）位置评估而设计的 NNUE（Efficiently Updatable Neural Network）PyTorch 实现。本项目将原本用于国际象棋的 NNUE 架构适配到九子棋，提供了完整的训练和推理解决方案。

## 📋 目录

- [概述](#概述)
- [环境配置](#环境配置)
- [训练数据准备](#训练数据准备)
- [模型训练](#模型训练)
- [模型使用](#模型使用)
- [配置文件](#配置文件)
- [常见问题](#常见问题)
- [高级功能](#高级功能)

## 🎯 概述

### 主要特性

- **九子棋专用特征表示**：针对 24 个位置的棋盘设计的 `NineMillFeatures` 类
- **完整训练流程**：支持从数据准备到模型部署的全流程
- **Perfect Database 集成**：可使用 Perfect Database 生成高质量训练数据
- **多种特征集**：支持基础和因式分解特征集
- **GPU 加速**：支持 CUDA 训练和推理
- **可视化界面**：提供 GUI 界面进行人机对弈

### 与原版 NNUE PyTorch 的主要区别

- **特征表示**：从 64 格国际象棋棋盘改为 24 位置九子棋棋盘
- **训练数据格式**：使用文本格式替代二进制 .binpack 格式
- **网络架构**：调整网络规模和评估缩放以适应九子棋
- **游戏阶段**：支持九子棋特有的放置、移动和飞行阶段

## ⚙️ 环境配置

### 系统要求

**最低配置：**
- RAM: 8GB
- GPU 显存: 4GB (支持 CUDA)
- 磁盘空间: 10GB

**推荐配置：**
- RAM: 32GB
- GPU 显存: 16GB
- 磁盘空间: 50GB

**使用对称性增强时：**
- RAM: 64GB
- GPU 显存: 24GB
- 磁盘空间: 100GB

### Docker 环境（推荐）

使用 Docker 可以避免复杂的环境配置和 C++ 编译问题。

#### 前置要求

**AMD 用户：**
- Docker
- 最新的 ROCm 驱动

**NVIDIA 用户：**
- Docker
- 最新的 NVIDIA 驱动
- NVIDIA Container Toolkit

#### 启动容器

```bash
./run_docker.sh
```

系统会提示选择 GPU 厂商和数据目录路径。容器包含 CUDA 12.x/ROCm 和所有必需依赖。

### 本地环境安装

如果不使用 Docker，可以按以下步骤配置本地环境：

```bash
# 安装 Python 依赖
pip install -r requirements.txt

# 安装 PyTorch（根据你的 CUDA 版本）
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 安装 PyTorch Lightning
pip install pytorch-lightning
```

## 📊 训练数据准备

### 数据格式说明

九子棋 NNUE 使用文本格式的训练数据，每行包含一个位置的完整信息：

```
棋盘状态 执子方 阶段 动作 白棋在盘 白棋在手 黑棋在盘 黑棋在手 白棋待移除 黑棋待移除 ... 评估值 最佳着法 游戏结果
```

### FEN 格式详解

**棋盘状态**：24 个字符，用 '/' 分隔（对应 A/B/C 列，1-8 行）
- `O` = 白棋
- `@` = 黑棋  
- `*` = 空位
- `X` = 标记位置

**其他字段**：
- **执子方**：`w`（白棋）或 `b`（黑棋）
- **阶段**：`r`（准备）、`p`（放置）、`m`（移动）、`o`（游戏结束）
- **动作**：`p`（放置）、`s`（选择）、`r`（移除）、`?`（无动作）

**示例**：
```
O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1 50.0 a1 1.0
```

### 使用 Perfect Database 生成训练数据

Perfect Database 可以提供理论上最优的位置评估，是训练高质量 NNUE 模型的最佳数据源。

#### 基础数据生成

```bash
# 生成基础训练数据
python generate_training_data.py \
    --perfect-db /path/to/perfect/database \
    --output training_data.txt \
    --positions 50000

# 生成验证数据
python generate_training_data.py \
    --perfect-db /path/to/perfect/database \
    --output validation_data.txt \
    --positions 5000
```

#### 使用对称性增强（推荐）

```bash
# 包含 16 种对称性变换（数据量增加 16 倍）
python generate_training_data.py \
    --perfect-db /path/to/perfect/database \
    --output training_data_symmetries.txt \
    --positions 10000 \
    --symmetries
```

对称性变换包括：
- **几何变换**（8种）：旋转 90°/180°/270°、垂直/水平镜像、对角线镜像、恒等变换
- **颜色交换变换**（8种）：颜色交换 + 各种几何变换

### 手动创建训练数据

如果没有 Perfect Database，也可以通过游戏引擎生成训练数据：

```bash
# 使用示例脚本创建训练数据
python create_training_data_example.py
```

## 🚀 模型训练

### 快速开始

#### 基础训练

```bash
# 使用基础特征集训练
python train.py training_data.txt \
    --validation-data validation_data.txt \
    --features "NineMill" \
    --batch-size 8192 \
    --max_epochs 400
```

#### 因式分解特征训练（推荐）

```bash
# 使用因式分解特征集，提供更好的泛化能力
python train.py training_data.txt \
    --validation-data validation_data.txt \
    --features "NineMill^" \
    --batch-size 8192 \
    --max_epochs 400
```

### 特征集对比

| 特征集 | 描述 | 特征数 | 训练速度 | 模型大小 | 推荐用途 |
|--------|------|--------|----------|----------|----------|
| `NineMill` | 基础位置-棋子编码 | 1152 | 更快 | 更小 | 初期实验、快速训练 |
| `NineMill^` | 因式分解特征 | 1152 + 虚拟特征 | 较慢 | 较大 | 生产模型、更好泛化 |

### 高级训练选项

#### 使用自动化训练脚本

```bash
# 完整功能的自动化训练
python scripts/easy_train.py \
    --experiment-name my_mill_experiment \
    --training-dataset training_data.txt \
    --validation-dataset validation_data.txt \
    --workspace-path ./mill_train_data \
    --features "NineMill" \
    --batch-size 8192 \
    --max-epochs 400 \
    --gpus "0" \
    --tui true
```

#### 多 GPU 训练

```bash
# 使用多个 GPU 训练
python train.py training_data.txt \
    --validation-data validation_data.txt \
    --features "NineMill" \
    --batch-size 16384 \
    --gpus "0,1,2,3" \
    --max_epochs 400
```

#### 从检查点恢复训练

```bash
# 从之前的检查点继续训练
python train.py training_data.txt \
    --validation-data validation_data.txt \
    --resume-from-model logs/lightning_logs/version_X/checkpoints/last.ckpt \
    --max_epochs 800
```

### 主要训练参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--features` | "NineMill" | 特征集类型 |
| `--batch-size` | 8192 | 批处理大小 |
| `--max_epochs` | 800 | 最大训练轮数 |
| `--lr` | 8.75e-4 | 学习率 |
| `--gamma` | 0.992 | 学习率衰减因子 |
| `--gpus` | "0" | 使用的 GPU 设备 |
| `--precision` | 16 | 训练精度（16 或 32） |

### 训练监控

#### TensorBoard

```bash
# 启动 TensorBoard
tensorboard --logdir=logs

# 在浏览器中访问
# http://localhost:6006/
```

#### 训练指标

训练过程中会记录以下指标：
- **训练损失**：模型在训练集上的损失
- **验证损失**：模型在验证集上的损失
- **学习率**：当前学习率
- **批处理时间**：每个批次的处理时间

## 🎮 模型使用

### GUI 界面使用

#### 启动 GUI

```bash
# 使用配置文件启动
python nnue_pit.py --config nnue_pit_config.json --gui

# 直接指定模型文件
python nnue_pit.py --model logs/lightning_logs/version_7/checkpoints/last.ckpt --gui
```

#### GUI 功能

- **人机对弈**：与 NNUE AI 进行九子棋对战
- **位置评估**：实时显示当前位置的评估值
- **思考时间**：显示 AI 的思考时间和搜索深度
- **着法提示**：显示 AI 推荐的最佳着法

### 编程接口使用

#### 基础使用

```python
from nnue_pit import NNUEModelLoader, NNUEPlayer, NNUEGameAdapter

# 加载模型
model_loader = NNUEModelLoader(
    model_path="logs/lightning_logs/version_7/checkpoints/last.ckpt",
    feature_set_name="NineMill"
)

# 创建 NNUE 玩家
nnue_player = NNUEPlayer(model_loader, search_depth=8)

# 创建游戏状态适配器
game_adapter = NNUEGameAdapter()

# 评估当前位置
evaluation = nnue_player.evaluate_position(game_adapter)
print(f"位置评估: {evaluation}")

# 获取最佳着法
best_move = nnue_player.get_best_move(game_adapter)
print(f"最佳着法: {best_move}")
```

#### 批量位置评估

```python
# 批量评估多个位置
positions = [
    "O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1",
    "@*@*@***/*******/*******/ b p p 3 6 0 9 0 0 0 0 0 0 0 0 1"
]

evaluations = []
for pos_fen in positions:
    game_adapter.load_from_fen(pos_fen)
    eval_score = nnue_player.evaluate_position(game_adapter)
    evaluations.append(eval_score)

print("批量评估结果:", evaluations)
```

### 模型转换

#### 转换为部署格式

```bash
# 将 PyTorch Lightning 模型转换为 ONNX
python convert_model.py \
    --input logs/lightning_logs/version_7/checkpoints/last.ckpt \
    --output model.onnx \
    --format onnx

# 转换为 TensorRT（需要 TensorRT 环境）
python convert_model.py \
    --input logs/lightning_logs/version_7/checkpoints/last.ckpt \
    --output model.trt \
    --format tensorrt
```

## 📝 配置文件

### 训练配置示例

创建 `train_config.json`：

```json
{
  "training_data": "perfect_db_training_data.txt",
  "validation_data": "perfect_db_validation_data.txt",
  
  "model": {
    "features": "NineMill",
    "batch_size": 8192,
    "max_epochs": 400,
    "learning_rate": 8.75e-4,
    "precision": 16
  },
  
  "training": {
    "gpus": "0",
    "num_workers": 4,
    "pin_memory": true,
    "drop_last": true
  },
  
  "logging": {
    "experiment_name": "my_nnue_experiment",
    "log_dir": "logs/my_experiment",
    "tensorboard": true
  }
}
```

### GUI 配置示例

创建 `gui_config.json`：

```json
{
  "model_path": "logs/lightning_logs/version_7/checkpoints/last.ckpt",
  "feature_set": "NineMill",
  "search_depth": 8,
  "human_first": true,
  "gui": true,
  "show_evaluation": true,
  "show_thinking_time": true,
  "time_per_move": 3.0,
  "device": "auto"
}
```

### Perfect Database 配置

创建 `perfect_db_config.json`：

```json
{
  "perfect_db": {
    "database_path": "/path/to/perfect/database",
    "positions": 50000,
    "use_symmetries": true,
    "batch_size": 1000,
    "seed": 42
  },
  
  "data_generation": {
    "placement_ratio": 0.45,
    "moving_ratio": 0.35,
    "flying_ratio": 0.20
  }
}
```

## ❓ 常见问题

### 训练相关问题

**Q: 训练时出现 CUDA 内存不足错误？**

A: 尝试以下解决方案：
```bash
# 减小批处理大小
python train.py training_data.txt --batch-size 4096

# 使用混合精度训练
python train.py training_data.txt --precision 16

# 减少工作进程数
python train.py training_data.txt --num-workers 2
```

**Q: 训练损失不下降？**

A: 检查以下方面：
- 学习率是否合适（尝试 1e-3 到 1e-5）
- 训练数据质量和数量
- 特征集是否正确
- 模型架构是否适合数据

**Q: 如何选择合适的特征集？**

A: 
- 初期实验使用 `NineMill`
- 生产环境使用 `NineMill^`
- 数据量大时使用因式分解特征

### 使用相关问题

**Q: 模型加载时出现 AssertionError？**

A: 这通常是设备不匹配问题：
```python
# 确保设备设置正确
model_loader = NNUEModelLoader(
    model_path="model.ckpt",
    force_cpu=None  # 自动检测设备要求
)
```

**Q: GUI 界面启动失败？**

A: 检查以下配置：
- 模型文件路径是否正确
- 配置文件格式是否有效
- 依赖库是否完整安装

**Q: 评估速度太慢？**

A: 优化建议：
- 使用 GPU 推理
- 减少搜索深度
- 启用置换表缓存

### Perfect Database 相关问题

**Q: Perfect Database 连接失败？**

A: 确认以下设置：
- Database 路径正确
- perfect_db.dll 文件存在
- 权限设置正确

**Q: 对称性增强占用内存过多？**

A: 解决方案：
- 减少基础位置数量
- 分批处理对称性变换
- 增加系统内存

## 🔧 高级功能

### 自定义特征集

如果需要创建自定义特征集：

```python
# 在 features_mill.py 中添加新的特征类
class CustomNineMillFeatures(FeatureSet):
    def __init__(self):
        super().__init__("CustomNineMill", 2304)  # 自定义特征数
    
    def get_active_features(self, board_state):
        # 实现自定义特征提取逻辑
        pass
```

### 模型集成

将多个模型组合使用：

```python
class EnsembleNNUE:
    def __init__(self, model_paths):
        self.models = [
            NNUEPlayer(NNUEModelLoader(path))
            for path in model_paths
        ]
    
    def evaluate_position(self, game_state):
        evaluations = [
            model.evaluate_position(game_state)
            for model in self.models
        ]
        return sum(evaluations) / len(evaluations)
```

### 性能优化

#### 批处理推理

```python
# 批量评估位置以提高效率
def batch_evaluate(nnue_player, positions):
    # 实现批处理评估逻辑
    pass
```

#### 缓存优化

```python
# 使用置换表缓存评估结果
nnue_player = NNUEPlayer(
    model_loader, 
    search_depth=8,
    tt_size_mb=128  # 增加置换表大小
)
```

## 📚 参考资源

### 相关文档

- [NNUE 架构详解](docs/nnue.md)
- [特征工程指南](docs/features.md)
- [Perfect Database 集成](PERFECT_DB_INTEGRATION.md)
- [九子棋适配说明](NINE_MENS_MORRIS_ADAPTATION.md)

### 示例脚本

- `scripts/easy_train.py` - 自动化训练脚本
- `scripts/mill_train_example.sh` - 完整训练示例
- `example_perfect_db_training.py` - Perfect Database 训练示例

### 工具程序

- `test_model_loading.py` - 模型加载测试
- `test_trained_model.py` - 训练模型测试
- `visualize.py` - 训练过程可视化

## 🤝 贡献指南

欢迎贡献代码和改进建议！请遵循以下步骤：

1. Fork 项目仓库
2. 创建特性分支
3. 提交更改
4. 创建 Pull Request

## 📄 许可证

本项目基于原 NNUE PyTorch 项目，继承其开源许可证。

## 🙏 致谢

- 原 NNUE PyTorch 项目团队
- Sopel - 高性能稀疏数据加载器
- connormcmonigle - NNUE 架构和损失函数建议
- 九子棋 Perfect Database 项目

---

如有问题或需要帮助，请查看 [常见问题](#常见问题) 部分或提交 Issue。
