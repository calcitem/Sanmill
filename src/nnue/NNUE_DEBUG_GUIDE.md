# NNUE 调试指南

## 概述

NNUE 系统现在配备了详细的调试打印功能，可以帮助开发者在调试时确认每个环节是否符合预期。

## 调试功能特性

### 1. 运行时调试控制
- 可以通过代码动态开启/关闭调试打印
- 默认启用，但可在运行时调整

### 2. 全覆盖调试打印
- **初始化阶段**: 构造函数、模型加载、权重初始化
- **特征提取**: 棋子位置、游戏阶段、战术特征、机动性
- **网络计算**: 隐藏层激活、输出计算、数值范围检查
- **对称性处理**: 规范形式查找、变换应用
- **模型 I/O**: 加载/保存过程的详细状态

## 使用方法

### 编译时配置
```cpp
// 在 nnue.h 中，NNUE_DEBUG 默认为 1
#define NNUE_DEBUG 1  // 启用调试打印
```

### 运行时控制
```cpp
// 启用调试打印
NNUE::set_nnue_debug(true);

// 禁用调试打印
NNUE::set_nnue_debug(false);

// 检查当前状态
bool debug_enabled = NNUE::get_nnue_debug();
```

## 调试输出示例

### 初始化阶段
```
[NNUE DEBUG] Constructing NNUEEvaluator...
[NNUE DEBUG] NNUE Network dimensions: 115 features -> 256 hidden -> 1 output
[NNUE DEBUG] Initializing symmetry transformations...
[NNUE DEBUG] Initializing input weights with Xavier scale: 0.093242
[NNUE DEBUG] Initializing output weights with Xavier scale: 0.062500
[NNUE DEBUG] NNUEEvaluator construction completed
```

### 模型加载
```
[NNUE DEBUG] Loading NNUE model from: model.bin
[NNUE DEBUG] Model header verified: SANMILL1
[NNUE DEBUG] Model dimensions: 115 features, 256 hidden
[NNUE DEBUG] Expected dimensions: 115 features, 256 hidden
[NNUE DEBUG] Dimensions verified, loading weights...
[NNUE DEBUG] Loaded 29440 input weights
[NNUE DEBUG] Loaded 256 input biases
[NNUE DEBUG] Loaded 512 output weights
[NNUE DEBUG] Loaded output bias: 0
[NNUE DEBUG] Model loaded successfully!
```

### 位置评估
```
[NNUE DEBUG] Starting NNUE evaluation...
[NNUE DEBUG] Position FEN: ************************ 0 0
[NNUE DEBUG] Side to move: WHITE
[NNUE DEBUG] Phase: 1
[NNUE DEBUG] Starting symmetry-aware evaluation...
[NNUE DEBUG] Canonical symmetry operation: 0
```

### 特征提取
```
[NNUE DEBUG] Starting feature extraction...
[NNUE DEBUG] Extracting piece placement features...
[NNUE DEBUG] White pieces bitboard: 0x0
[NNUE DEBUG] Black pieces bitboard: 0x0
[NNUE DEBUG] Piece placement: 0 white, 0 black pieces
[NNUE DEBUG] Extracting game phase features...
[NNUE DEBUG] Current phase: 1
[NNUE DEBUG] Phase feature set: PLACING (index 48)
[NNUE DEBUG] Feature extraction completed: 7/115 features active
```

### 网络计算
```
[NNUE DEBUG] Hidden layer: 128/256 active neurons, avg activation: 1024
[NNUE DEBUG] Computing output for side: WHITE
[NNUE DEBUG] Current side contribution: 12345
[NNUE DEBUG] Opponent side contribution: -6789
[NNUE DEBUG] Final output: 5556
```

## 调试策略

### 1. 检查特征提取
- 确认棋子位置正确映射到特征
- 验证游戏阶段和计数特征
- 检查战术特征的合理性

### 2. 验证网络计算
- 监控隐藏层激活模式
- 检查输出计算的数值稳定性
- 确认没有数值溢出

### 3. 调试对称性
- 验证规范形式的选择
- 检查变换的正确应用
- 确认颜色交换的处理

### 4. 模型一致性
- 确认模型加载无错误
- 验证权重和偏置的合理范围
- 检查保存/加载的往返一致性

## 性能注意事项

调试打印会显著影响性能，建议：

1. **开发调试时**: 启用详细调试
2. **性能测试时**: 禁用调试打印
3. **生产环境**: 编译时禁用 (`NNUE_DEBUG 0`)

## 故障排除

### 常见问题
1. **特征数量异常**: 检查棋子计数和位置映射
2. **网络输出极值**: 检查权重初始化和数值溢出
3. **对称性错误**: 验证坐标系转换
4. **模型加载失败**: 检查文件格式和维度匹配

### 调试技巧
1. 逐步启用不同阶段的调试
2. 比较相同位置的不同对称形式
3. 使用简单位置验证基础功能
4. 检查边界条件和极端情况

## 扩展调试

如需更详细的调试信息，可以：

1. 在关键函数中添加更多 `NNUE_DEBUG_PRINT`
2. 输出中间计算结果
3. 添加统计信息收集
4. 创建专门的验证函数

这套调试系统确保了 NNUE 开发过程中每个环节都可以被充分验证和调试。
