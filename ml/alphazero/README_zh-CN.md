# Nine Men's Morris AlphaZero 训练系统

```
python3 main.py --config my_config.yaml
python pit.py --gui --first human
```

本目录实现了九子棋的 AlphaZero 训练与评估系统，支持：

- 🎯 **监督学习**：从完美数据库快速学习最优策略
- 🔄 **强化学习**：通过自对弈不断改进
- 🏆 **混合训练**：结合监督学习和强化学习的优势
- 🎮 **多种对战**：人机对战、AI评估、完美库测试

## 🚀 快速开始

### 1. 环境准备
```bash
# 确保引擎存在
ls /mnt/d/Repo/Sanmill/src/sanmill

# 准备完美数据库路径（Windows → WSL）
# Windows: E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted
# WSL:     /mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted
```

### 2. 配置训练参数
```bash
# 生成配置模板
python3 main.py --create-template

# 复制并编辑配置
cp config_template.yaml my_config.yaml
# 编辑 my_config.yaml，修改 teacherDBPath 为你的数据库路径
```

### 3. 开始训练
```bash
# 使用配置文件训练
python3 main.py --config my_config.yaml

# 或直接指定路径
python3 main.py --config my_config.yaml \
  --engine /mnt/d/Repo/Sanmill/src/sanmill \
  --db /mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted
```

### 4. 对战体验
```bash
# 人机对战
python3 pit.py

# 评估 AI 对完美库的表现
python3 pit.py --mode ai-vs-perfect --games 20 \
  --perfect-db /mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted
```

## 📋 训练模式

### 🎯 模式一：监督学习（快速基线）
从完美数据库直接学习，快速获得强基线模型。

**用途**：
- 快速获得可用模型（分钟级）
- 作为强化学习的预训练基础
- 验证网络架构和训练管道

**使用方法**：
```bash
# 直接运行
python3 perfect_supervised.py -v

# 设置样本数量
export SANMILL_PERFECT_TOTAL="5000"
python3 perfect_supervised.py -v

# 测试训练结果
python3 pit.py --mode human-vs-ai
```

**输出**：保存模型为 `./temp/best_epoch.pth.tar`

### 🔄 模式二：强化学习（纯 AlphaZero）
传统 AlphaZero 训练：自对弈生成数据 → 训练网络 → 新旧对战评估。

**配置示例**：

```yaml
# config.yaml
numIters: 10
numEps: 50
usePerfectTeacher: false
load_model: false  # 从零开始
```

### 🏆 模式三：混合训练（推荐）
结合监督学习和强化学习，在每轮 AlphaZero 训练中混入完美库样本。

**配置示例**：
```yaml
# config.yaml
numIters: 10
numEps: 20
usePerfectTeacher: true
teacherExamplesPerIter: 1000
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'
pitAgainstPerfect: true
load_model: true  # 基于现有模型
```

**优势**：
- 更快收敛
- 更稳定训练
- 更强最终棋力

## 🎮 对战与评估

### 人机对战
```bash
# 基础对战
python3 pit.py

# 自定义难度和强度
python3 pit.py --mcts-sims 1000 --difficulty 0.8
```

**操作说明**：
- 放子：`a1`, `d4` 等
- 移子：`a1-a4` 或 `a1a4`
- 取子：`xd1` 或 `d1`
- 坐标：a-g（列），1-7（行）

### AI 评估
```bash
# AI vs AI
python3 pit.py --mode ai-vs-ai --games 10

# AI vs 完美库（绝对强度测试）
python3 pit.py --mode ai-vs-perfect --games 20 \
  --perfect-db /path/to/database

# 人类挑战完美库
python3 pit.py --mode human-vs-perfect \
  --perfect-db /path/to/database
```

**评估指标**：
- 对完美库：**和棋率**是关键（不可能获胜）
- 典型期望：监督模型 20-40%，混合训练模型 40-60%

## ⚙️ 配置文件详解

### 📋 完整参数说明

#### 🎯 训练核心参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `numIters` | int | 100 | 总训练迭代次数 | 快速测试：3；正常：10-50；长期：100+ |
| `numEps` | int | 100 | 每轮迭代的自对弈局数 | 快速测试：6；平衡：20-50；高质量：100+ |
| `tempThreshold` | int | 80 | 温度策略切换点（多少步后从采样变贪婪） | 通常保持 80，控制前期探索性 |
| `updateThreshold` | float | 0.55 | 新模型接受阈值（胜率超过此值才接受） | 0.55-0.6，过高难接受新模型 |
| `maxlenOfQueue` | int | 200000 | 保留的训练样本最大数量 | 内存不足时减少到 50000-100000 |
| `numMCTSSims` | int | 40 | 每步 MCTS 模拟次数 | 越高越强但越慢：20-100 |
| `arenaCompare` | int | 20 | 新旧模型对战局数 | 快速测试：4-10；准确评估：20+ |
| `cpuct` | float | 1.5 | UCB 探索参数 | 通常保持 1.5，控制探索与利用平衡 |

#### 💾 文件管理参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `checkpoint` | string | './temp/' | 模型和样本保存目录 | 可改为其他路径，如 './models/' |
| `load_model` | bool | false | 是否从检查点恢复训练 | true：继续训练；false：重新开始 |
| `load_folder_file` | list | ['temp/', 'best.pth.tar'] | 加载的模型文件路径 | 通常保持默认 |
| `numItersForTrainExamplesHistory` | int | 5 | 保留几轮历史训练样本 | 2-10，影响内存使用和训练稳定性 |

#### ⚙️ 系统设置参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `num_processes` | int | 5 | 自对弈并行进程数 | 教师模式：1；纯 AlphaZero：2-4 |
| `cuda` | bool | true | 是否使用 GPU | true：快速训练；false：稳定但慢 |

#### 🧠 神经网络参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `lr` | float | 0.002 | 学习率 | 快速收敛：0.005；稳定：0.002；微调：0.001 |
| `dropout` | float | 0.3 | Dropout 正则化率 | 0.2-0.5，防止过拟合 |
| `epochs` | int | 10 | 每轮迭代的训练轮数 | 快速：5；正常：10；充分：20 |
| `batch_size` | int | 1024 | 训练批大小 | 内存不足时减少：256/512 |
| `num_channels` | int | 256 | 网络宽度（通道数） | 小网络：128；标准：256；大网络：512 |

#### 👨‍🏫 完美数据库教师参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `usePerfectTeacher` | bool | false | 是否启用教师混合训练 | **强烈建议 true** |
| `teacherExamplesPerIter` | int | 0 | 每轮迭代教师样本数 | 快速：100；平衡：1000；重度监督：2000+ |
| `teacherBatch` | int | 256 | 教师数据采样批大小 | 通常保持默认 |
| `teacherDBPath` | string | null | 完美数据库路径 | **必须修改为你的数据库路径** |
| `teacherAnalyzeTimeout` | int | 120 | 分析超时时间（秒） | 快速磁盘：60；网络存储：300+ |
| `teacherThreads` | int | 1 | 引擎线程数 | 保持 1 确保稳定性 |
| `pitAgainstPerfect` | bool | false | 是否每轮评估对完美库表现 | **建议 true** 跟踪绝对进度 |

#### 🐛 调试与日志参数
| 参数 | 类型 | 默认值 | 说明 | 建议配置 |
|------|------|--------|------|----------|
| `verbose_games` | int | 1 | 每轮详细记录的对局数 | 调试时增加，正常训练保持 1 |
| `log_detailed_moves` | bool | true | 是否记录详细走法 | 调试时 true，生产时可设为 false |
| `enable_training_log` | bool | true | 是否保存训练结果到表格 | **建议 true**，便于分析训练效果 |

### 🎨 配置文件格式

**统一使用 YAML 格式**（支持注释，更易读）：
- `config_template.yaml` - 通用配置模板，包含所有场景说明

**配置文件特点**：
- ✅ **单一文件**：所有场景的配置都在一个文件中
- ✅ **详细注释**：每个参数都有说明和不同场景的建议值
- ✅ **场景示例**：文件底部有 6 种常见训练场景的配置说明
- ✅ **易于定制**：复制后只需修改数据库路径即可使用

**也支持 JSON 格式**（如果你有特殊需求）：
```bash
# 系统会自动识别文件格式
python3 main.py --config my_config.json
```

### 🔧 常见配置场景

#### 🚀 场景一：快速测试（验证环境）
```yaml
numIters: 3
numEps: 6
teacherExamplesPerIter: 100
num_channels: 128
epochs: 5
usePerfectTeacher: true
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'
```

#### 🎯 场景二：平衡训练（推荐新手）
```yaml
numIters: 20
numEps: 30
teacherExamplesPerIter: 1000
num_channels: 256
usePerfectTeacher: true
num_processes: 1
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'
```

#### 🏆 场景三：高质量训练（追求性能）
```yaml
numIters: 50
numEps: 100
teacherExamplesPerIter: 1000
num_channels: 512
numMCTSSims: 80
epochs: 15
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'
```

#### 🔬 场景四：纯 AlphaZero（无教师）
```yaml
usePerfectTeacher: false
teacherExamplesPerIter: 0
num_processes: 3
numEps: 80
numIters: 100
```

#### 📚 场景五：重度监督学习
```yaml
teacherExamplesPerIter: 3000
numEps: 10
usePerfectTeacher: true
lr: 0.005
teacherDBPath: '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'
```

### ⚠️ 重要注意事项

1. **数据库路径**：`teacherDBPath` 必须修改为你的实际路径
2. **内存限制**：如遇内存不足，减少 `batch_size` 和 `maxlenOfQueue`
3. **进程数**：使用教师模式时建议 `num_processes: 1`
4. **超时设置**：网络存储增加 `teacherAnalyzeTimeout` 至 300+
5. **恢复训练**：设置 `load_model: true` 可从中断处继续

## 🔧 模型管理

### 文件说明
- `best.pth.tar` - 竞技场冠军模型（用于对战）
- `best_epoch.pth.tar` - 单次训练最佳模型
- `checkpoint_x.pth.tar.examples` - 训练样本历史

### 训练恢复
系统自动支持训练中断恢复：
```bash
# 直接重新运行相同命令即可继续
python3 main.py --config my_config.yaml
```

### 文件管理策略
```bash
# 备份现有模型
mkdir -p temp/backup_$(date +%Y%m%d_%H%M%S)
mv temp/*.pth.tar* temp/backup_*/

# 从零开始：设置配置文件中 load_model: false
# 继续训练：设置配置文件中 load_model: true（默认）
```

## 📚 进阶使用

### 📊 训练结果记录与分析

系统会自动记录每轮训练的效果到表格文件：

**记录内容**：
- 训练参数：迭代次数、自对弈局数、教师样本数
- 性能指标：胜率、和棋率、模型接受情况
- 时间统计：每轮耗时、累计时间
- 完美库评估：对完美数据库的表现

**输出文件**：
```bash
temp/
├── training_teacher_iter10_eps20_1210_1430_log.csv  # CSV表格
├── training_teacher_iter10_eps20_1210_1430_log.json # JSON详细数据
├── best.pth.tar                                      # 最佳模型
└── checkpoint_x.pth.tar.examples                    # 训练样本
```

**使用示例**：
```bash
# 查看训练结果表格
cat temp/*_log.csv | head -10

# 在Excel中分析训练进度
open temp/*_log.csv

# 控制日志记录（配置文件中）
enable_training_log: true   # 启用记录
enable_training_log: false  # 禁用记录
```

**📝 文件管理说明**：
- 所有训练产生的文件已配置在 `.gitignore` 中
- 模型文件 (`*.pth.tar`)、训练样本 (`*.examples`)、日志文件 (`*_log.csv/json`) 不会被提交到版本控制
- 用户配置文件 (`my_config.yaml`) 也会被忽略，避免个人配置冲突
- 只有模板文件 (`config_template.*`) 会被版本控制

**表格字段说明**：
| 字段 | 说明 | 示例值 |
|------|------|--------|
| `iteration` | 迭代轮次 | 1, 2, 3... |
| `win_rate` | 新模型胜率 | 0.650 |
| `model_accepted` | 是否接受新模型 | 是/否 |
| `perfect_draw_rate` | 对完美库和棋率 | 0.450 |
| `iteration_time` | 本轮耗时(秒) | 1200.5 |
| `notes` | 训练模式 | 教师模式/纯AlphaZero |

### 训练策略建议
1. **新用户**：监督学习 → 混合训练 → 人机对战
2. **快速验证**：配置文件设置小参数进行测试
3. **高质量训练**：监督预训练 + 长期混合训练
4. **性能调优**：增加 `numIters`、`teacherExamplesPerIter`

### 参数调优指南
- **提升训练效果**：增加 `numIters`、`numEps`、`teacherExamplesPerIter`
- **提升 AI 强度**：增加 `--mcts-sims`（对战时）
- **加速训练**：减少 `numEps`，使用 CPU 模式
- **稳定训练**：`num_processes: 1`，适当的 `teacherAnalyzeTimeout`

### 环境变量覆盖
```bash
# 强制 CPU 模式
SANMILL_TRAIN_CUDA=0 python3 main.py --config my_config.yaml

# 调整进程数
SANMILL_TRAIN_PROCESSES=2 python3 main.py --config my_config.yaml

# 设置完美库路径
SANMILL_PERFECT_DB=/path/to/db python3 perfect_supervised.py
```

## 🐛 故障排除

### 常见问题
1. **完美库未加载**
   - 检查路径格式（WSL 路径）
   - 增加 `teacherAnalyzeTimeout`（建议 120-300 秒）
   - 确认 `teacherThreads: 1`

2. **训练中断**
   - 直接重新运行相同命令
   - 检查磁盘空间
   - 查看详细日志

3. **模型性能差**
   - 增加训练样本数
   - 检查完美库是否正确加载
   - 尝试监督预训练

### 调试工具
```bash
# 详细日志
python3 perfect_supervised.py -v

# 测试配置生成
python3 main.py --create-template

# 检查模型文件
ls -la temp/

# 验证配置文件
python3 -c "import yaml; print(yaml.safe_load(open('my_config.yaml')))"
```

## 📖 技术细节

### 完美数据库目标构造
- **策略头 `pi`**：对最优着法集合均匀分布（有赢选赢，无赢选和，全输选慢输）
- **价值头 `v`**：WDL 映射 +1/0/-1，用步数做轻微调整（快赢>慢赢，慢输>快输）
- **数据增强**：使用对称性扩充样本

### 网络架构
- 多头设计：不同游戏阶段使用不同输出头
- Period 路由：placing/moving/flying/capture 分别处理
- 支持 CUDA 和 CPU 模式

## 🎯 命令速查

```bash
# 生成配置
python3 main.py --create-template

# 混合训练（推荐）
python3 main.py --config config_examples/teacher_training.yaml \
  --engine /path/to/sanmill --db /path/to/database

# 监督学习
python3 perfect_supervised.py -v

# 人机对战
python3 pit.py

# AI 评估
python3 pit.py --mode ai-vs-perfect --games 20 --perfect-db /path/to/db

# AI vs AI
python3 pit.py --mode ai-vs-ai --games 10
```

## 🔗 相关文件

- `main.py` - 主训练入口
- `perfect_supervised.py` - 监督学习
- `pit.py` - 统一对战脚本
- `config.py` - 配置文件支持
- `create_configs.py` - 配置模板生成
- `Coach.py` - 训练循环
- `game/` - 游戏规则和网络架构