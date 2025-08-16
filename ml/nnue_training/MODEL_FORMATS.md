# NNUE 模型格式说明

## 支持的格式

NNUE GUI 支持两种主要的模型格式：

### 1. 二进制格式 (.bin)

**文件头**: `SANMILL1`  
**结构**:
```
Header: "SANMILL1" (8 bytes)
Dimensions: feature_size (4 bytes), hidden_size (4 bytes)
Input weights: feature_size × hidden_size × int16 (2 bytes each)
Input biases: hidden_size × int32 (4 bytes each)
Output weights: hidden_size × 2 × int8 (1 byte each)
Output bias: 1 × int32 (4 bytes)
```

**特点**:
- ✅ 文件小，加载快
- ✅ C++ 引擎直接支持
- ✅ 量化权重，内存友好
- ❌ 精度有轻微损失
- ❌ 不便于调试

**适用场景**: 生产部署，嵌入式系统，对性能要求高的场景

### 2. PyTorch 格式 (.pth/.tar)

**结构**: PyTorch state_dict 或完整 checkpoint
```python
{
    'model_state_dict': {...},
    'feature_size': 115,
    'hidden_size': 256,
    'epoch': 100,
    'optimizer_state_dict': {...},  # 可选
    'loss': 0.001  # 可选
}
```

**特点**:
- ✅ 完整精度，无损存储
- ✅ 包含丰富元数据
- ✅ 便于调试和分析
- ✅ 可继续训练
- ❌ 文件较大
- ❌ 需要 PyTorch 环境

**适用场景**: 开发调试，模型分析，继续训练

## 格式转换

### PyTorch → 二进制

```python
from train_nnue import MillNNUE, save_model_c_format

# 加载 PyTorch 模型
model = MillNNUE(feature_size=115, hidden_size=256)
checkpoint = torch.load('model.pth')
model.load_state_dict(checkpoint['model_state_dict'])

# 保存为二进制格式
save_model_c_format(model, 'model.bin')
```

### 二进制 → PyTorch

```python
from nnue_pit import NNUEModelLoader

# 加载二进制模型
loader = NNUEModelLoader('model.bin')
model = loader.load_model()

# 保存为 PyTorch 格式
torch.save({
    'model_state_dict': model.state_dict(),
    'feature_size': 115,
    'hidden_size': 256
}, 'model.pth')
```

## 选择建议

### 开发阶段
- 使用 `.pth` 格式进行训练
- 便于调试和迭代
- 可以查看详细的训练信息

```bash
# 训练时保存 PyTorch 格式
python train_nnue.py --config configs/default.json --output model.pth

# 开发测试
python nnue_pit.py --model model.pth --gui
```

### 生产部署
- 转换为 `.bin` 格式
- 更高的运行效率
- 更小的存储空间

```bash
# 转换为二进制格式
python train_nnue.py --convert-to-binary model.pth model.bin

# 生产使用
python nnue_pit.py --model model.bin --gui
```

## 性能对比

| 格式 | 文件大小 | 加载时间 | 精度 | C++ 兼容 |
|------|----------|----------|------|----------|
| .bin | ~15KB | 快 | 高 | ✅ |
| .pth | ~30KB | 中等 | 完整 | ❌ |

## 验证模型

### 检查二进制格式

```bash
python verify_model_consistency.py --analyze model.bin
```

### 检查 PyTorch 格式

```python
import torch
checkpoint = torch.load('model.pth')
print("Keys:", list(checkpoint.keys()))
print("Feature size:", checkpoint.get('feature_size', 'Unknown'))
print("Hidden size:", checkpoint.get('hidden_size', 'Unknown'))
```

## 故障排除

### 常见错误

1. **Invalid header**: 
   - 文件不是有效的 NNUE 二进制格式
   - 解决：检查文件是否损坏，重新生成

2. **Model dimensions mismatch**:
   - 模型结构与预期不符
   - 解决：在配置中指定正确的 feature_size 和 hidden_size

3. **Cannot load PyTorch model**:
   - PyTorch 版本不兼容
   - 解决：使用 `map_location='cpu'` 加载

### 模型验证

```bash
# 快速验证模型是否有效
python -c "
from nnue_pit import NNUEModelLoader
try:
    loader = NNUEModelLoader('your_model.bin')
    model = loader.load_model()
    print('✅ Model loaded successfully')
except Exception as e:
    print(f'❌ Error: {e}')
"
```

## 最佳实践

1. **开发流程**:
   ```bash
   # 训练 → PyTorch 格式
   python train_nnue.py --output model.pth
   
   # 测试 → PyTorch 格式
   python nnue_pit.py --model model.pth --gui
   
   # 优化 → 转换为二进制格式
   python convert_model.py model.pth model.bin
   
   # 部署 → 二进制格式
   python nnue_pit.py --model model.bin --gui
   ```

2. **版本管理**:
   - PyTorch 格式用于版本控制（包含完整信息）
   - 二进制格式用于发布（体积小，高效）

3. **备份策略**:
   - 保留 PyTorch 格式作为主备份
   - 二进制格式可以随时重新生成
