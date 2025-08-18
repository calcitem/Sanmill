# NNUE GUI 棋盘程序使用说明

## 概述

基于 ml-stable 分支上 `pit.py` 的设计思路，为 NNUE 模型创建了一个 GUI 棋盘程序，支持人机对战验证 NNUE 模型效果。

## 功能特性

- **GUI 界面**: 基于 Tkinter 的图形界面，支持鼠标点击下棋
- **NNUE 模型加载**: 支持 `.bin` 和 `.pth` 格式的 NNUE 模型文件
- **人机对战**: 人类玩家 vs NNUE AI，可配置谁先手
- **配置文件支持**: 支持 JSON/YAML 格式的配置文件
- **实时评估**: NNUE 模型实时评估局面并决策

## 安装依赖

```bash
# 确保在 nnue 分支
git checkout nnue

# 安装 Python 依赖
cd ml/nnue_training
pip install -r requirements.txt

# 安装额外依赖（如需要）
pip install PyYAML  # 支持 YAML 配置文件
```

## 基本使用

### 1. 使用配置文件启动

```bash
python nnue_pit.py --config nnue_pit_config.json --gui --first human
```

### 2. 直接指定模型文件

```bash
python nnue_pit.py --model nnue_model.bin --gui
```

### 3. 创建示例配置文件

```bash
python nnue_pit.py --create-config my_config.json
```

## 命令行参数

- `--config CONFIG`: 配置文件路径 (JSON/YAML 格式)
- `--model MODEL`: NNUE 模型文件路径 (.bin 或 .pth)
- `--gui`: 启用 GUI 模式（必需）
- `--first {human,ai}`: 指定谁先手（默认：human）
- `--games GAMES`: 游戏局数（默认：1）
- `--depth DEPTH`: AI 搜索深度（默认：3）
- `--feature-size SIZE`: NNUE 特征维度（默认：115）
- `--hidden-size SIZE`: NNUE 隐藏层大小（默认：256）

## 配置文件格式

### JSON 配置示例

```json
{
  "model_path": "nnue_model.bin",
  "feature_size": 115,
  "hidden_size": 256,
  "search_depth": 3,
  "human_first": true,
  "gui": true,
  "games": 1,
  "log_level": "INFO",
  "show_evaluation": true,
  "show_thinking_time": true,
  "time_per_move": 3.0,
  "use_time_management": false,
  "device": "auto",
  "batch_size": 1,
  "temperature": 1.0
}
```

### YAML 配置示例

```yaml
# NNUE Pit Configuration
model_path: nnue_model.bin
feature_size: 115
hidden_size: 256
search_depth: 3
human_first: true
gui: true
games: 1
log_level: INFO
```

## GUI 操作说明

### 棋盘界面

- **白色圆圈**: 白棋（通常为人类玩家）
- **黑色圆圈**: 黑棋（通常为 AI）
- **灰色小圆**: 有效的棋盘位置
- **红色高亮**: 选中的棋子位置

### 下棋方式

#### 落子阶段（Placing Phase）
- 直接点击空的有效位置即可落子
- 轮流下子，直到双方各下完 9 个子

#### 走子阶段（Moving Phase）
- 先点击自己的棋子选择要移动的子
- 再点击目标空位置完成移动
- 红色高亮显示当前选中的棋子

### 控制按钮

- **Restart**: 重新开始游戏
- **Quit**: 退出程序

### 状态信息

状态栏显示：
- 当前游戏阶段（Placing/Moving）
- 当前轮到谁下棋（Human/AI）
- 双方棋子数量信息

## NNUE 模型要求

### 支持的模型格式

1. **二进制格式 (.bin)**
   - C++ 兼容的二进制格式
   - 包含量化权重和偏置
   - 文件头：`SANMILL1`

2. **PyTorch 格式 (.pth/.tar)**
   - PyTorch 保存的模型状态字典
   - 支持 checkpoint 格式

### 模型架构要求

- **输入**: 115 维特征向量
- **隐藏层**: 256 个神经元（可配置）
- **输出**: 单一评估值
- **激活函数**: ReLU

### 特征编码

NNUE 模型期望的输入特征：
- 位置 0-47: 棋子位置特征（白子24维 + 黑子24维）
- 位置 48-50: 游戏阶段特征（3维 one-hot）
- 位置 51-54: 棋子数量特征（4维归一化）
- 位置 55: 当前行动方（1维）
- 位置 56: 移动计数（1维归一化）
- 位置 57-114: 预留给战术特征（将来扩展）

## 技术架构

### 核心组件

1. **NNUEModelLoader**: 模型加载器
   - 支持多种模型格式
   - 自动权重反量化
   - 设备自动选择

2. **NNUEPlayer**: AI 玩家
   - NNUE 模型推理
   - Minimax 搜索算法
   - 局面评估

3. **SimpleGameState**: 游戏状态
   - 棋盘表示
   - 规则逻辑
   - 特征提取

4. **NNUEGameGUI**: 图形界面
   - Tkinter 实现
   - 事件处理
   - 实时渲染

### 搜索算法

- **Minimax**: 经典极小极大搜索
- **深度**: 可配置搜索深度（默认3层）
- **评估**: NNUE 模型提供叶节点评估
- **优化**: 多线程 AI 思考，避免 GUI 冻结

## 使用示例

### 基本人机对战

```bash
# 人类先手，使用预训练模型
python nnue_pit.py --model pretrained_model.bin --gui --first human

# AI 先手，配置搜索深度
python nnue_pit.py --model nnue_model.bin --gui --first ai --depth 4
```

### 使用配置文件

```bash
# 创建配置文件
python nnue_pit.py --create-config my_config.json

# 编辑配置文件 my_config.json
# 然后使用配置启动
python nnue_pit.py --config my_config.json
```

### 批量测试

```bash
# 连续对战 5 局
python nnue_pit.py --model nnue_model.bin --gui --games 5
```

## 故障排除

### 常见错误

1. **模型文件未找到**
   ```
   Error: Model path required. Use --model or specify in config file.
   ```
   解决方案：确保指定正确的模型文件路径

2. **Tkinter 不可用**
   ```
   RuntimeError: Tkinter not available. GUI mode requires tkinter.
   ```
   解决方案：安装 tkinter 库（通常随 Python 一起安装）

3. **模型格式错误**
   ```
   ValueError: Invalid header: b'...'
   ```
   解决方案：确保使用正确格式的 NNUE 模型文件

4. **维度不匹配**
   ```
   Model dimensions (X, Y) differ from expected (115, 256)
   ```
   解决方案：在配置文件中指定正确的 feature_size 和 hidden_size

### 调试技巧

1. **启用详细日志**
   ```bash
   python nnue_pit.py --model model.bin --gui --config debug_config.json
   ```
   在配置文件中设置 `"log_level": "DEBUG"`

2. **检查模型信息**
   ```bash
   python verify_model_consistency.py --analyze model.bin
   ```

3. **测试配置文件**
   ```bash
   python config_loader.py test_config.json
   ```

## 扩展功能

### 计划中的功能

- [ ] 网络对战支持
- [ ] 更多棋类规则变体
- [ ] 评估值可视化
- [ ] 对局记录和回放
- [ ] 多种 AI 强度级别
- [ ] 开局库支持

### 自定义扩展

可以通过修改以下文件来扩展功能：

- `nnue_pit.py`: 主程序逻辑
- `config_loader.py`: 配置文件处理
- `SimpleGameState`: 游戏规则实现
- `NNUEPlayer`: AI 算法改进

## 许可证

遵循 Sanmill 项目的 GPL-3.0 许可证。
