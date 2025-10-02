# Testing Guide for Sanmill Flutter App

## 测试类型

### 1. 单元测试 (Unit Tests)

**位置**: `test/`  
**运行命令**: `flutter test`  
**运行环境**: Dart VM  
**特点**:
- ✅ 快速执行
- ✅ 不需要真实设备或模拟器
- ❌ **无法访问 native code**（如 C++ AI 引擎）
- ❌ 需要 mock MethodChannel 通信

**适用场景**:
- Widget 测试
- 纯 Dart 逻辑测试
- UI 组件测试
- 数据模型测试

**当前状态**: ✅ **27 个通过，4 个失败**
- 失败的测试是原有的 `import_export` 和 `position` 测试问题，与迁移无关

### 2. 集成测试 (Integration Tests)

**位置**: `integration_test/`  
**运行命令**: 
```bash
# Linux
flutter test integration_test/ -d linux

# Android  
flutter test integration_test/ -d android

# macOS
flutter test integration_test/ -d macos

# Windows
flutter test integration_test/ -d windows
```

**运行环境**: 真实平台 (Linux/Android/iOS/macOS/Windows)  
**特点**:
- ✅ **可以访问 native code**（C++ AI 引擎）
- ✅ 使用真实的 AI 引擎进行测试
- ✅ 完整的端到端测试
- ❌ 执行较慢
- ❌ 需要真实设备或模拟器

**适用场景**:
- **AI 行为测试** ⭐
- 平台集成测试
- 端到端功能测试
- 性能测试

## AI 测试迁移说明

### 为什么迁移？

之前 AI 测试在 `test/game/` 目录中，运行 `flutter test` 时会遇到以下错误：

```
MissingPluginException(No implementation found for method send on channel com.calcitem.sanmill/engine)
```

**原因**: `flutter test` 运行在 Dart VM 上，无法通过 MethodChannel 与 C++ native code 通信。

### 迁移内容

以下文件已从 `test/game/` 迁移到 `integration_test/`:

- ✅ `automated_move_test_data.dart` - 测试数据
- ✅ `automated_move_test_models.dart` - 测试模型
- ✅ `automated_move_test_runner.dart` - 测试运行器（**已移除所有 mock 代码**）
- ✅ `automated_move_integration_test.dart` - 集成测试入口（更新）
- ✅ `AUTOMATED_MOVE_TESTS_README.md` - 使用文档

### 如何运行 AI 测试

```bash
cd /home/ubuntu/Sanmill/src/ui/flutter_app

# 在 Linux 上测试真实 AI 引擎
flutter test integration_test/automated_move_integration_test.dart -d linux
```

**重要**: 这些测试**必须**在真实平台上运行，不能用 `flutter test test/` 运行！

## 测试文件结构

```
src/ui/flutter_app/
├── test/                          # 单元测试（Dart VM）
│   ├── array_helper_test.dart
│   ├── game/
│   │   ├── game_controller_test.dart
│   │   ├── header_test.dart
│   │   ├── import_export_test.dart
│   │   └── position_test.dart
│   ├── helpers/
│   │   └── mocks/                 # Mock 对象
│   ├── pointed_list/
│   └── widget_test.dart
│
└── integration_test/              # 集成测试（真实平台）
    ├── automated_move_test_data.dart       # AI 测试数据
    ├── automated_move_test_models.dart     # AI 测试模型
    ├── automated_move_test_runner.dart     # AI 测试运行器（真实引擎）
    ├── automated_move_integration_test.dart # AI 测试入口
    ├── AUTOMATED_MOVE_TESTS_README.md      # AI 测试文档
    ├── app_test.dart
    ├── custom_functions.dart
    ├── init_test_environment.dart
    ├── localization_screenshot_test.dart
    ├── test_runner.dart
    └── test_scenarios.dart
```

## 常见问题

### Q: 为什么 `flutter test` 不能测试 AI？

A: `flutter test` 运行在 Dart VM 上，没有 Flutter 引擎和平台支持，无法通过 MethodChannel 调用 native C++ 代码。必须使用 `flutter test integration_test/ -d <platform>` 在真实平台上运行。

### Q: 如何添加新的 AI 测试用例？

A: 编辑 `integration_test/automated_move_test_data.dart`，添加新的 `MoveListTestCase`，然后将其添加到相应的测试配置中。详见 `integration_test/AUTOMATED_MOVE_TESTS_README.md`。

### Q: AI 测试失败怎么办？

A: 首次运行时，由于 AI 行为可能不确定，测试可能失败。检查测试输出中的实际 AI 走法，如果合理，更新 `expectedSequences` 为实际序列。

### Q: 单元测试中的 4 个失败是什么？

A: 这些是原有的测试问题（`import_export_test` 和 `position_test`），与 AI 测试迁移无关，需要单独修复。

## 最佳实践

1. **快速迭代**: 使用 `flutter test` 进行快速反馈
2. **AI 验证**: 使用 `flutter test integration_test/` 验证 AI 行为
3. **CI/CD**: 在 CI 中同时运行两种测试
4. **Mock 优先**: 单元测试中优先使用 mock，保持测试快速
5. **真实验证**: 集成测试中使用真实组件，确保端到端功能

## 相关文档

- [Integration Test README](integration_test/AUTOMATED_MOVE_TESTS_README.md) - AI 测试详细文档
- [AGENTS.md](../../AGENTS.md) - AI Agent 工作指南
- [Flutter Testing](https://docs.flutter.dev/testing) - Flutter 官方测试文档

