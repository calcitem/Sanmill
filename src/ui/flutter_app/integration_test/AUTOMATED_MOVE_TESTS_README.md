# Automated Move Integration Tests

## 概述

这些集成测试使用**真实的 C++ AI 引擎**来测试游戏逻辑和 AI 行为。它们通过 MethodChannel 与 native code 通信，因此必须在真实的平台上运行。

## 文件说明

- `automated_move_test_data.dart` - 测试用例数据定义
- `automated_move_test_models.dart` - 测试模型和数据结构
- `automated_move_test_runner.dart` - 测试运行器（使用真实 AI 引擎）
- `automated_move_integration_test.dart` - 集成测试入口

## 运行测试

### Linux 平台

```bash
cd /home/ubuntu/Sanmill/src/ui/flutter_app
flutter test integration_test/automated_move_integration_test.dart -d linux
```

### Android 平台

```bash
cd /home/ubuntu/Sanmill/src/ui/flutter_app
flutter test integration_test/automated_move_integration_test.dart -d android
```

### macOS 平台

```bash
cd /home/ubuntu/Sanmill/src/ui/flutter_app
flutter test integration_test/automated_move_integration_test.dart -d macos
```

### Windows 平台

```bash
cd /home/ubuntu/Sanmill/src/ui/flutter_app
flutter test integration_test/automated_move_integration_test.dart -d windows
```

## 与单元测试的区别

| 特性 | 单元测试 (`flutter test`) | 集成测试 (`flutter test integration_test/`) |
|------|---------------------------|------------------------------------------|
| 运行环境 | Dart VM | 真实平台 (Linux/Android/iOS/etc) |
| Native Code | ❌ 不可用 | ✅ 可用 |
| AI 引擎 | ❌ 需要 mock | ✅ 使用真实引擎 |
| 速度 | ⚡ 快速 | 🐌 较慢 |
| 适用场景 | Widget 测试、纯 Dart 逻辑 | AI 行为测试、平台集成测试 |

## 首次运行

首次运行这些测试时，由于 AI 行为的不确定性，测试可能会失败。这是正常的。请：

1. 检查测试输出中的实际 AI 走法序列
2. 验证 AI 的走法是否合理
3. 如果合理，将实际序列更新到 `automated_move_test_data.dart` 中的 `expectedSequences`
4. 再次运行测试以验证

## 调试

如果测试失败，检查以下内容：

1. **AI 配置**: 测试会打印当前的 AI 设置（技能等级、搜索时间等）
2. **导入状态**: 测试会显示导入前后的棋盘状态
3. **AI 输出**: 测试会显示 AI 实际生成的走法序列
4. **错误消息**: 任何异常都会被捕获并打印

## 添加新测试

要添加新的测试用例，编辑 `automated_move_test_data.dart`:

```dart
static final MoveListTestCase myNewTest = MoveListTestCase(
  id: 'my_test_id',
  description: 'Test description',
  moveList: '1. a1 2. b2 3. c3',  // 棋谱
  expectedSequences: [
    '1. a1 2. b2 3. c3 4. d4',  // 期望的 AI 走法
  ],
  enabled: true,
);
```

然后将其添加到某个测试配置中。

## 注意事项

1. 这些测试**不能**用 `flutter test test/` 运行，会报 `MissingPluginException`
2. 必须在真实平台上运行：`flutter test integration_test/ -d <platform>`
3. AI 行为可能因配置不同而异，确保测试环境配置一致
4. 长时间运行的测试可能需要调整 `maxWaitTimeMs` 参数

