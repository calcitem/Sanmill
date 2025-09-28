# Flutter 自动化测试使用指南

## 概述

我已经为您实现了完整的Flutter自动化测试系统，用于测试AI在导入move list后的行棋行为。

## 实现的功能

### ✅ 已完成的功能

1. **Move List 导入和解析**
   - 支持标准的move list格式（如您提供的示例）
   - 自动解析带编号的棋谱（1. b2 f6, 2. g7 e5 等）
   - 处理复杂的走法（如 b6xa1, d5xe5xc5, f2-d2xd1xd3）

2. **真实AI引擎集成**
   - 使用真实的C++引擎，不是模拟
   - 应用GUI界面的所有配置（AI难度、算法、规则等）
   - 支持"move now"功能触发AI走棋

3. **测试配置系统**
   - 可配置的测试用例（ID、描述、move list、期望结果）
   - 支持多个备选期望结果
   - 可启用/禁用特定测试用例
   - 超时保护机制

4. **结果验证和报告**
   - 详细的测试执行日志
   - 失败测试的详细信息
   - 成功率统计
   - 执行时间记录

## 文件结构

```
src/ui/flutter_app/
├── test/game/
│   ├── automated_move_test_models.dart      # 数据模型
│   ├── automated_move_test_runner.dart      # 测试执行引擎
│   ├── automated_move_test_data.dart        # 测试数据和配置
│   ├── automated_move_test.dart             # 单元测试（框架测试）
│   ├── AUTOMATED_MOVE_TESTS_README.md       # 详细文档
│   └── USAGE_GUIDE.md                       # 本文件
└── integration_test/
    └── automated_move_integration_test.dart  # 集成测试（真实AI）
```

## 如何使用

### 1. 运行真实AI测试

```bash
cd src/ui/flutter_app

# 运行集成测试（使用真实AI引擎）
flutter test integration_test/automated_move_integration_test.dart --verbose
```

### 2. 查看当前配置

测试会显示当前的AI配置：
```
[IntegrationTest] Current AI Settings:
[IntegrationTest] Skill Level: 2
[IntegrationTest] Move Time: 0
[IntegrationTest] Search Algorithm: SearchAlgorithm.mtdf
[IntegrationTest] Perfect Database: false
[IntegrationTest] Pieces Count: 12
[IntegrationTest] Has Diagonal Lines: true
[IntegrationTest] May Fly: false
```

### 3. 添加自定义测试用例

在 `automated_move_test_data.dart` 中添加：

```dart
static const MoveListTestCase myTestCase = MoveListTestCase(
  id: 'my_custom_test',
  description: '测试特定开局的AI响应',
  moveList: '''
 1.    b2    f6
 2.    g7    e5
 3.    b4    a1
''',
  expectedSequences: [
    'PLACEHOLDER_EXPECTED_SEQUENCE', // 首次运行后替换为实际结果
  ],
);
```

### 4. 更新期望结果

首次运行测试后，检查输出中的实际AI走法：
```
[IntegrationTest] Final sequence: "1. b2 f6 2. g7 e5 3. b4 a1 4. d2 ..."
```

然后更新测试数据中的 `expectedSequences`。

## 测试流程

1. **重置游戏状态** → Human vs Human模式
2. **导入move list** → 使用真实的ImportService
3. **执行"move now"** → 触发真实AI引擎
4. **等待AI完成** → 可能连续走多步（如吃子后继续）
5. **验证结果** → 与期望序列比较
6. **生成报告** → 显示通过/失败状态

## 配置选项

### AI设置影响
- **技能等级**：影响AI强度
- **思考时间**：影响AI计算深度
- **搜索算法**：MTDF、Alpha-Beta等
- **完美数据库**：是否使用残局库
- **AI行为**：懒惰AI、陷阱感知等

### 规则设置影响
- **棋子数量**：9子棋、12子棋等
- **对角线**：是否启用对角线
- **飞行规则**：剩余棋子数量限制

## 故障排除

### 常见问题

1. **"MissingPluginException"错误**
   - 原因：在单元测试中使用了真实引擎
   - 解决：使用集成测试 `flutter test integration_test/...`

2. **导入失败**
   - 检查move list格式是否正确
   - 确保使用标准记谱法

3. **AI不响应**
   - 检查游戏模式是否正确设置
   - 确保C++引擎已编译

### 调试技巧

1. **查看详细日志**：使用 `--verbose` 参数
2. **检查AI设置**：测试开始时会打印当前配置
3. **验证导入**：检查导入后的move count

## 示例输出

```
[IntegrationTest] Current AI Settings:
[IntegrationTest] Skill Level: 2
[IntegrationTest] Executing test case: sample_game_1
[IntegrationTest] Description: Test AI behavior after importing a complete game sequence
[IntegrationTest] Initial sequence: ""
[IntegrationTest] Initial move count: 0
[IntegrationTest] Importing move list...
[IntegrationTest] After import sequence: "1. b2 f6 2. g7 e5 ..."
[IntegrationTest] After import move count: 31
[IntegrationTest] Executing move now to trigger AI...
[IntegrationTest] Final sequence: "1. b2 f6 2. g7 e5 ... 17. d3"
[IntegrationTest] Final move count: 32
[IntegrationTest] AI made 1 moves
[IntegrationTest] [FAILED] sample_game_1
[IntegrationTest] Expected one of:
[IntegrationTest]   - PLACEHOLDER_EXPECTED_SEQUENCE_1
[IntegrationTest] Actual: 1. b2 f6 2. g7 e5 ... 17. d3
```

## 新增测试用例

已成功添加14个新的测试用例：

1. **short_capture_game** - 短游戏吃子序列 (4步)
2. **short_simple_game** - 短游戏简单序列 (4步)
3. **five_move_opening** - 5步开局序列
4. **six_move_development** - 6步发展序列
5. **complex_movement_game** - 复杂移动游戏 (16步)
6. **twelve_move_midgame** - 12步中局序列
7. **complex_capture_game** - 复杂吃子游戏 (13步)
8. **advanced_tactical_game** - 高级战术游戏 (14步)
9. **long_tactical_game** - 长战术游戏 (15步)
10. **alt_long_tactical_game** - 替代长战术游戏 (13步)
11. **complex_endgame_positioning** - 复杂残局定位 (13步)
12. **strategic_positioning_game** - 战略定位游戏 (12步)
13. **very_long_tactical_game** - 非常长的战术游戏 (25步)
14. **standard_twelve_move_opening** - 标准12步开局

### 运行新测试用例

```bash
# 运行包含新测试用例的配置
flutter test test/game/automated_move_test.dart -t "Run new test cases"

# 运行集成测试（推荐）
flutter test integration_test/automated_move_integration_test.dart
```

## 下一步

1. **运行测试**：使用集成测试查看AI实际行为
2. **更新期望值**：根据AI输出更新测试数据
3. **修复记谱法问题**：某些复杂移动可能需要调整格式
4. **配置CI/CD**：将测试集成到持续集成流程中

## 注意事项

- ⚠️ 测试使用您当前的GUI设置，更改设置会影响AI行为
- ⚠️ 确保C++引擎已正确编译
- ⚠️ 首次运行时测试会失败，这是正常的
- ⚠️ 使用集成测试而不是单元测试来测试真实AI
