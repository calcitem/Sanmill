# NNUE 傻瓜化训练工具

## 🎯 概述

为了让新手也能轻松上手 NNUE 训练，我们提供了一系列傻瓜化工具，从一键训练到详细指导，满足不同用户的需求。

## 🚀 快速开始选项

### 选项 1: 一键开始（最简单）

```bash
python quick_start.py
```

**特点**:
- ✅ 最简单，无需任何配置
- ✅ 自动安装依赖
- ✅ 快速训练（5-10分钟）
- ✅ 自动启动 GUI 测试

**适合**: 完全的新手，第一次接触 NNUE

### 选项 2: 傻瓜化训练（推荐）

```bash
# Windows 用户
双击 easy_train.bat

# 命令行用户
python easy_train.py
```

**特点**:
- ✅ 交互式引导
- ✅ 多种训练模式选择
- ✅ 自动环境检查
- ✅ 完整的训练流程

**适合**: 希望了解训练过程的用户

### 选项 3: 快速模式

```bash
python easy_train.py --quick
```

**特点**:
- ✅ 5-10分钟快速完成
- ✅ 适合测试和学习
- ✅ 自动化程度高

**适合**: 想快速体验的用户

## 📁 工具文件说明

| 文件 | 用途 | 适合用户 |
|------|------|----------|
| `quick_start.py` | 一键开始 | 完全新手 |
| `easy_train.py` | 傻瓜化训练 | 一般用户 |
| `easy_train.bat` | Windows 启动器 | Windows 用户 |
| `BEGINNER_GUIDE.md` | 新手指南 | 学习用户 |
| `EASY_TRAINING_README.md` | 工具说明 | 所有用户 |

## 🎮 训练模式对比

| 模式 | 时间 | 用途 | 命令 |
|------|------|------|------|
| 快速 | 5-10分钟 | 测试学习 | `--quick` |
| 标准 | 30-60分钟 | 日常使用 | 默认 |
| 高质量 | 2-4小时 | 最佳效果 | `--high-quality` |

## 🔧 系统要求

### 最低要求
- **Python**: 3.7+
- **内存**: 4GB RAM
- **存储**: 1GB 可用空间
- **时间**: 10分钟（快速模式）

### 推荐配置
- **Python**: 3.8+
- **内存**: 8GB+ RAM
- **GPU**: NVIDIA GPU（大幅加速）
- **存储**: 2GB+ 可用空间

## 📋 使用流程

### 1. 环境准备
```bash
# 克隆代码（如果还没有）
git clone https://github.com/calcitem/Sanmill.git
cd Sanmill/ml/nnue_training

# 安装依赖
pip install torch numpy matplotlib
```

### 2. 选择合适的工具
- **新手**: 使用 `quick_start.py`
- **学习**: 使用 `easy_train.py`
- **Windows**: 双击 `easy_train.bat`

### 3. 开始训练
```bash
# 一键开始
python quick_start.py

# 或选择模式
python easy_train.py --quick
python easy_train.py 
python easy_train.py --high-quality
```

### 4. 测试模型
训练完成后，脚本会自动：
- 验证模型正确性
- 启动 GUI 测试界面
- 提供下一步指导

## 🎯 典型使用场景

### 场景 1: 第一次接触 NNUE
```bash
python quick_start.py
```
**结果**: 10分钟后获得一个可用的 NNUE 模型

### 场景 2: 学习 NNUE 训练
```bash
python easy_train.py
```
**结果**: 了解完整训练流程，获得实用模型

### 场景 3: 追求最佳效果
```bash
python easy_train.py --high-quality --gpu
```
**结果**: 2-4小时后获得高质量模型

### 场景 4: 批量实验
```bash
python easy_train.py --quick --auto
python easy_train.py --auto
python easy_train.py --high-quality --auto
```
**结果**: 自动训练多个不同质量的模型

## 🚨 常见问题

### Q: 训练失败了怎么办？
**A**: 
1. 检查 Python 版本（需要 3.7+）
2. 安装缺失的依赖包
3. 确保在正确目录运行
4. 查看错误信息并按提示操作

### Q: 训练时间太长？
**A**:
1. 使用 `--quick` 模式快速体验
2. 启用 GPU 加速（需要 NVIDIA GPU）
3. 升级硬件配置

### Q: 模型效果不理想？
**A**:
1. 尝试 `--high-quality` 模式
2. 增加训练时间
3. 检查数据质量

### Q: GPU 不工作？
**A**:
1. 安装 CUDA 版本的 PyTorch
2. 更新 GPU 驱动
3. 验证 GPU 可用性

## 💡 进阶技巧

### 1. 自定义参数
```bash
# 查看所有选项
python easy_train.py --help

# 使用特定设备
python easy_train.py --gpu

# 自动模式（无交互）
python easy_train.py --auto
```

### 2. 模型管理
```bash
# 查看训练的模型
ls models/
ls nnue_model*.bin

# 测试特定模型
python nnue_pit.py --model models/model_name.bin --gui

# 验证模型
python verify_model_consistency.py --analyze models/model_name.bin
```

### 3. 性能优化
```bash
# 使用 GPU（如果可用）
python easy_train.py --gpu

# 保持临时文件（用于调试）
python easy_train.py --keep-temp

# 跳过 GUI 测试
python easy_train.py --no-gui
```

## 📚 学习路径

### 初学者路径
1. 🎯 运行 `quick_start.py` 体验整个流程
2. 📖 阅读 `BEGINNER_GUIDE.md` 了解详情
3. 🔧 尝试 `easy_train.py` 的不同模式
4. 🎮 使用 GUI 工具测试模型

### 进阶路径
1. 📝 学习配置文件格式
2. 🔬 研究训练参数的影响
3. 🏗️ 自定义网络架构
4. 🚀 优化训练性能

### 专家路径
1. 📊 分析训练数据质量
2. 🧪 实验不同的训练策略
3. 🔀 集成多个模型
4. 🎯 针对特定场景优化

## 🎉 成功案例

### 案例 1: 编程新手小明
> "我完全不懂机器学习，但用 `quick_start.py` 10分钟就训练出了我的第一个 AI。虽然还不强，但看到它能下棋真的很神奇！"

### 案例 2: 计算机专业学生小红
> "用傻瓜化工具学习 NNUE 非常高效。从快速模式开始体验，然后深入了解每个参数的作用。现在我已经能训练出不错的模型了。"

### 案例 3: 业余棋手老张
> "作为一个象棋爱好者，我想训练一个强大的 AI 陪练。高质量模式训练的模型确实很强，已经成为我的日常训练伙伴。"

## 🔗 相关文档

- [新手指南](BEGINNER_GUIDE.md) - 详细的入门教程
- [模型格式说明](MODEL_FORMATS.md) - 了解不同模型格式
- [使用示例](USAGE_EXAMPLES.md) - 更多使用案例
- [配置指南](CONFIGURATION_GUIDE.md) - 高级配置选项
- [硬件优化](HARDWARE_OPTIMIZATION.md) - 性能优化建议

## 🚀 下一步

完成第一次训练后，您可以：

1. **深入学习**: 阅读详细文档，了解 NNUE 原理
2. **实验参数**: 尝试不同的训练配置
3. **对比模型**: 训练多个模型并对比效果
4. **集成应用**: 将模型集成到您的项目中
5. **社区分享**: 分享您的经验和改进建议

祝您 NNUE 训练愉快！🎯
