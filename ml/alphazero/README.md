## AlphaZero Sanmill
一个适用于直棋（Sanmill）的 AlphaZero 训练与测试项目，基于开源项目 [alpha-zero-general](https://github.com/suragnair/alpha-zero-general)。内置多进程自对弈与动态难度的人机对弈。

### 直棋（Sanmill）规则（本项目采用的变体）
- 棋盘上有 4 条斜线可走
- 超过 100 步自动判和
- 任一方剩 3 枚棋子时可“飞棋”（任意落点）
- 允许吃“三连”中的子（形成三连后进入“吃子阶段”再落子）

### 主要优化点
- 多进程加速 Self-Play 与 Pitting 对弈
- 使用 orjson 加速训练样本的序列化/反序列化
- 奖励函数重构：更重视对局步数，并加入子力差权重
- Loss 忽略无效 action 项的计算（仅对有效动作归一化）
- 每个 epoch 后进行 Validation，自动挑选最优 epoch 权重
- Backbone 采用类似 ViT 的注意力结构并分 period 分支头
- MCTS 细节适配直棋规则与 period 切换
- 人机对弈加入 EMA 动态难度自平衡机制

## 快速开始（Windows / Linux / macOS）
### 1）准备环境
- 安装 Python 3.8+（推荐 3.10/3.11）
- 可选：安装 CUDA 与对应版本的 PyTorch（见 PyTorch 官网安装指引）

### 2）克隆项目
```bash
git clone https://github.com/yourname/AlphaZero-Sanmill.git
cd AlphaZero-Sanmill
```

### 3）创建虚拟环境并安装依赖
- 方式 A：直接安装必要依赖（CPU 版 PyTorch）
```bash
python -m venv .venv
.\.venv\Scripts\activate  # Windows PowerShell
# source .venv/bin/activate # Linux/macOS
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install numpy tqdm coloredlogs orjson
```
- 方式 B：GPU 版 PyTorch 请按官网命令安装后，再执行：
```bash
pip install numpy tqdm coloredlogs orjson
```

### 4）首次训练
```bash
python main.py
```
首次运行将：
- 创建游戏与神经网络实例（自动检测 CUDA）
- 多进程进行自对弈收集样本
- 训练新模型，并与旧模型对弈（Pitting）
- 若新模型胜率 ≥ `updateThreshold`，写入 `./temp/best.pth.tar`
- 每个 epoch 进行验证，保留最优 epoch 权重到 `best_epoch.pth.tar`（训练结束后自动加载）

## 目录结构概览
- `main.py`：训练入口；设置全局 `args`
- `Coach.py`：自对弈、样本缓存/持久化、训练、Pitting 主流程
- `MCTS.py`：蒙特卡洛树搜索（适配 period 逻辑）
- `Arena.py`：对弈管理（含多进程与 EMA 难度自平衡）
- `pit.py`：人机/机机对弈脚本
- `sanmill/`：直棋逻辑与网络
  - `SanmillLogic.py`：棋盘 `Board` 及规则、合法走子生成、period 切换
  - `SanmillGame.py`：AlphaZero 接口封装（状态、动作、对称性、奖励）
  - `pytorch/SanmillNNet.py`：模型（ViT 风格主干 + period 分支头）
  - `pytorch/NNet.py`：训练/验证/推理封装与保存/加载
- `utils.py`：工具类（`AverageMeter`、`EMA`、`dotdict`、`SanmillDataset`）

## 训练与复现详解
### 训练命令
```bash
python main.py
```

### 关键参数（位于 `main.py` 内的 `args`）
- `numIters`：总迭代轮数（Iteration 数）
- `numEps`：每轮的自对弈局数；必须为 `num_processes` 的整数倍
- `tempThreshold`：自对弈步数超过该阈值后，行为由抽样转为贪心（温度=0）
- `updateThreshold`：Pitting 时，新网络胜率超过该阈值才接受为“最佳模型”
- `maxlenOfQueue`：每轮缓存的训练样本上限
- `numMCTSSims`：每步 MCTS 模拟次数（直接影响强度与耗时）
- `arenaCompare`：Pitting 对局数；必须为 `2*num_processes` 的整数倍
- `cpuct`：MCTS 探索/利用平衡系数
- `checkpoint`：模型与样本的保存目录（默认 `./temp/`）
- `load_model`：是否从 `load_folder_file` 加载已有模型并继续训练
- `load_folder_file`：模型加载路径（例如 `('temp', 'best.pth.tar')`）
- `numItersForTrainExamplesHistory`：训练样本保留的最近轮数
- `num_processes`：自对弈与 Pitting 的进程数（Windows 下自动设置 `spawn`）
- `lr`、`dropout`、`epochs`、`batch_size`、`cuda`、`num_channels`：训练与模型超参

### 训练产物
- `./temp/best.pth.tar`：通过 Pitting 验证的“最佳模型”
- `./temp/best_epoch.pth.tar`：单次训练中验证集最优 epoch 的模型
- `./temp/checkpoint_x.pth.tar.examples`：自对弈样本（orjson 序列化），用于断点续训

### 断点续训
编辑 `main.py`：
```python
args.load_model = True
args.load_folder_file = ('temp','best.pth.tar')
```
运行后会加载模型与 `checkpoint_x.pth.tar.examples`，继续训练。

### 多进程与性能建议
- Windows 默认采用 `spawn`，源码已在 `num_processes > 1` 时设置
- 请确保：`numEps % num_processes == 0` 且 `arenaCompare % (2*num_processes) == 0`
- 提升强度：适度增大 `numMCTSSims`；若不收敛，可减小 `lr`
- 显示更详细日志：在 `main.py` 将 `coloredlogs.install(level='INFO')` 改为 `DEBUG`

## 对弈与测试
### 人机对弈（需已有模型）
```bash
python pit.py
```
默认设置：
- `human_vs_cpu = True`
- 加载 `./temp/best.pth.tar`
- AI 侧 `args1 = {numMCTSSims: 500, cpuct: 0.5, eat_factor: 2}`（可改）

输入走法：
- 落子/吃子阶段（period in [0,3]）：输入 `x y`
- 移子/飞子阶段（period in [1,2]）：输入 `x0 y0 x1 y1`
脚本会打印所有合法走法作为提示，坐标范围为 0..6（左上为 0,0）。

难度调节（动态难度）：
- `pit.py` 中 `args.difficulty ∈ [-1, 1]`，结合 EMA 的评估值自动选择更保守/激进的动作

### 机机对弈
将 `pit.py` 中 `human_vs_cpu = False`，并为双方各自配置 MCTS 参数。

## 直棋 period 与网络结构说明
- period 0：落子阶段（双方轮流落子，至 18 手后进入移动阶段）
- period 1：移子阶段（沿线邻接移动）
- period 2：飞子阶段（任一方仅剩 3 子时，可任意落点）
- period 3：吃子阶段（形成三连后可移除对方一子，移除后回到落子逻辑）
- period 4：训练时用于“对手 3 子但我方 >3 子”的特殊分支（见网络实现）

网络对不同 period 使用不同“分支头”（`SanmillNNet.branch`），并在训练时按照样本 period 路由到对应分支，以适配规则差异。

## 常见问题（FAQ）
- 运行 `pit.py` 报 “No model in path ./temp/best.pth.tar”：请先完成一次训练，或将你的模型放到该路径
- Windows 多进程卡住/不启动：请用 `python main.py` 直接运行（不要在交互式 REPL 中），并确认 `if __name__ == "__main__":` 存在；必要时将 `num_processes` 设为 1
- 显存不足/训练慢：
  - 减小 `num_channels`、`batch_size` 或 `numMCTSSims`
  - 降低 `epochs` 或提高 `tempThreshold`
- 不收敛或震荡：
  - 降低学习率 `lr`
  - 增大 `numMCTSSims` 提高搜索强度
  - 增加 `arenaCompare` 提高模型接受门槛稳定性

## 参考与致谢
- [alpha-zero-general](https://github.com/suragnair/alpha-zero-general)
- [Sanmill](https://github.com/calcitem/Sanmill)
