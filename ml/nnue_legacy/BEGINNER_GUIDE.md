# NNUE 训练新手指南

## 🎯 什么是 NNUE？

NNUE (Efficiently Updatable Neural Network) 是一种高效的神经网络技术，用于棋类游戏的局面评估。它能让 AI 更好地理解棋局，提高下棋水平。

## 🚀 快速开始

### 方法 1: 一键训练（推荐新手）

```bash
# Windows 用户
双击 easy_train.bat

# Linux/Mac 用户
python easy_train.py
```

### 方法 2: 命令行训练

```bash
# 快速训练（5-10分钟，适合测试）
python easy_train.py --quick

# 标准训练（30-60分钟，推荐）
python easy_train.py

# 高质量训练（2-4小时，最佳效果）
python easy_train.py --high-quality
```

## 📋 训练前准备

### 1. 检查系统要求

- **Python**: 3.7 或更高版本
- **内存**: 至少 4GB RAM
- **存储**: 至少 1GB 可用空间
- **时间**: 10分钟到4小时（取决于训练模式）

### 2. 安装依赖

```bash
# 安装 Python 依赖
pip install torch numpy matplotlib

# 可选: 安装 GPU 支持（大幅加速训练）
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

### 3. 目录结构检查

确保您在正确的目录：
```
Sanmill/
  ml/
    nnue_training/         ← 您应该在这里
      easy_train.py        ← 训练脚本
      easy_train.bat       ← Windows 启动器
      train_nnue.py        ← 核心训练程序
      ...
```

## 🎮 训练模式详解

### 📚 快速训练（新手推荐）
- **时间**: 5-10 分钟
- **用途**: 学习和测试
- **特点**: 快速完成，了解训练流程
- **命令**: `python easy_train.py --quick`

**适合人群**: 第一次接触 NNUE 的用户

### ⚖️ 标准训练（日常推荐）
- **时间**: 30-60 分钟
- **用途**: 日常使用的模型
- **特点**: 平衡效果和时间
- **命令**: `python easy_train.py`

**适合人群**: 希望获得实用模型的用户

### 🎯 高质量训练（高级用户）
- **时间**: 2-4 小时
- **用途**: 追求最佳效果
- **特点**: 最强的模型性能
- **命令**: `python easy_train.py --high-quality`

**适合人群**: 有足够时间且追求最佳效果的用户

## 🔧 训练过程详解

### 第1步: 环境检查
脚本会自动检查：
- Python 版本
- 必需的依赖包
- GPU 可用性
- 训练脚本完整性

### 第2步: 配置选择
- 选择训练模式（快速/标准/高质量）
- 选择计算设备（CPU/GPU）
- 自动优化参数

### 第3步: 数据生成
- 自动生成训练数据
- 使用完美数据库确保质量
- 多线程加速生成

### 第4步: 模型训练
- 神经网络训练
- 实时显示进度
- 自动保存最佳模型

### 第5步: 模型验证
- 验证模型正确性
- 测试推理功能
- 生成性能报告

### 第6步: GUI 测试（可选）
- 启动图形界面
- 人机对战测试
- 验证模型效果

## 📊 理解训练输出

### 训练日志示例
```
Epoch 10/100:
  Training Loss: 0.0234
  Validation Loss: 0.0267
  Accuracy: 89.5%
  Learning Rate: 0.002
```

**指标含义**:
- **Training Loss**: 训练损失，越小越好
- **Validation Loss**: 验证损失，防止过拟合
- **Accuracy**: 准确率，越高越好
- **Learning Rate**: 学习率，自动调整

### 训练图表
训练完成后，在 `plots/` 目录中可以找到：
- 损失曲线图
- 准确率曲线图
- 学习率变化图

## 🎯 训练后操作

### 1. 查找训练的模型
```bash
# 模型通常保存在以下位置：
ls models/nnue_model_*.bin
ls nnue_model_*.bin
```

### 2. 测试模型
```bash
# 启动 GUI 测试
python nnue_pit.py --model models/nnue_model_*.bin --gui

# 快速启动（自动检测模型）
python start_nnue_gui.py
```

### 3. 验证模型
```bash
# 验证模型格式
python verify_model_consistency.py --analyze models/nnue_model_*.bin

# 测试模型兼容性
python test_model_formats.py
```

## 🚨 常见问题解决

### Q1: 训练过程中断了怎么办？
**A**: 重新运行训练脚本，它会从头开始。快速训练模式可以快速重试。

### Q2: GPU 不被识别？
**A**: 
1. 检查 GPU 驱动是否最新
2. 安装 CUDA 版本的 PyTorch：
   ```bash
   pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
   ```
3. 验证 GPU 可用性：
   ```python
   import torch
   print(torch.cuda.is_available())
   ```

### Q3: 内存不足错误？
**A**: 
1. 关闭其他占用内存的程序
2. 使用快速训练模式（参数更小）
3. 降低批处理大小

### Q4: 训练时间太长？
**A**:
1. 使用 GPU 加速（速度提升 3-10 倍）
2. 选择快速训练模式
3. 在性能更好的机器上训练

### Q5: 模型效果不好？
**A**:
1. 尝试高质量训练模式
2. 增加训练数据量
3. 调整网络结构参数

## 💡 进阶技巧

### 1. 自定义训练参数
编辑生成的配置文件来调整参数：
```bash
# 查看生成的配置
cat easy_train_*_config.json

# 使用自定义配置
python train_nnue.py --config my_custom_config.json
```

### 2. 批量训练
```bash
# 训练多个不同配置的模型
python easy_train.py --quick --auto
python easy_train.py --auto  
python easy_train.py --high-quality --auto
```

### 3. 模型对比
```bash
# 对比不同模型的性能
python nnue_pit.py --model model1.bin --gui
python nnue_pit.py --model model2.bin --gui
```

### 4. 模型部署
```bash
# 将训练好的模型复制到引擎目录
cp models/nnue_model_*.bin ../../src/
```

## 📚 学习资源

### 官方文档
- [NNUE 训练指南](README.md)
- [模型格式说明](MODEL_FORMATS.md)
- [使用示例](USAGE_EXAMPLES.md)

### 进阶主题
- [配置文件详解](CONFIGURATION_GUIDE.md)
- [硬件优化](HARDWARE_OPTIMIZATION.md)
- [模型验证](MODEL_VERIFICATION.md)

### 社区资源
- GitHub Issues: 问题反馈和讨论
- 示例代码: 查看 `example_*.py` 文件

## 🎉 成功案例

### 新手小张的经历
> "我是编程新手，按照指南用快速训练模式，10分钟就完成了我的第一个 NNUE 模型！虽然效果还不完美，但看到 AI 能够下棋真的很兴奋！"

### 学生小李的分享  
> "用了标准训练模式，1小时训练出来的模型已经能够战胜我了。现在我在尝试高质量训练，期待更强的 AI 对手！"

### 开发者老王的经验
> "作为开发者，我很欣赏这个工具的简洁性。从环境检查到模型验证，整个流程非常自动化。节省了大量配置时间。"

## 🎯 下一步

完成第一次训练后，您可以：

1. **实验不同参数**: 尝试不同的训练模式
2. **学习原理**: 深入了解 NNUE 技术
3. **优化模型**: 调整网络结构和训练参数
4. **集成应用**: 将模型集成到您的应用中
5. **分享经验**: 在社区分享您的训练经验

祝您 NNUE 训练愉快！🚀
