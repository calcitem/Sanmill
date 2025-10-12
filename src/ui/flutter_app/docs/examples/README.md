# Code Examples for Sanmill Flutter Application

This directory contains practical, runnable code examples demonstrating common patterns and best practices for Sanmill development.

## Overview

These examples are designed to:
- Illustrate real-world usage patterns
- Demonstrate best practices
- Provide copy-paste starting points
- Show integration between components

## Example Categories

### State Management
- [`hive_persistence_example.dart`](state_management/hive_persistence_example.dart) - Using Hive for persistent settings
- [`notifier_pattern_example.dart`](state_management/notifier_pattern_example.dart) - ValueNotifier for reactive UI
- [`game_state_example.dart`](state_management/game_state_example.dart) - Managing game state with GameController

### Widgets
- [`custom_widget_example.dart`](widgets/custom_widget_example.dart) - Creating a custom widget
- [`stateful_widget_example.dart`](widgets/stateful_widget_example.dart) - Stateful widget with proper lifecycle
- [`composed_widget_example.dart`](widgets/composed_widget_example.dart) - Widget composition pattern

### Animations
- [`custom_painter_example.dart`](animations/custom_painter_example.dart) - Creating custom painters
- [`piece_animation_example.dart`](animations/piece_animation_example.dart) - Animating game pieces
- [`animation_manager_example.dart`](animations/animation_manager_example.dart) - Using AnimationManager

### Internationalization
- [`localization_example.dart`](i18n/localization_example.dart) - Using localized strings
- [`plural_forms_example.dart`](i18n/plural_forms_example.dart) - Handling plurals

### Testing
- [`widget_test_example.dart`](testing/widget_test_example.dart) - Writing widget tests
- [`integration_test_example.dart`](testing/integration_test_example.dart) - Integration testing

## How to Use Examples

### 1. Reading Examples

Each example file is self-contained and heavily commented:

```dart
/// Example: Widget Composition
///
/// This example demonstrates how to break down complex widgets
/// into smaller, reusable components.
///
/// Key concepts:
/// - Widget composition over inheritance
/// - Single responsibility principle
/// - Const constructors for performance
```

### 2. Running Examples

Most examples are complete Flutter apps that can be run:

```bash
# Navigate to example directory
cd src/ui/flutter_app

# Run an example
flutter run examples/widgets/custom_widget_example.dart
```

### 3. Adapting Examples

Examples are designed to be adapted to your needs:
1. Copy the example file
2. Modify for your use case
3. Integrate into your feature
4. Remove example comments

## Quick Reference

| Task | Example |
|------|---------|
| Save user settings | [`hive_persistence_example.dart`](state_management/hive_persistence_example.dart) |
| Update UI reactively | [`notifier_pattern_example.dart`](state_management/notifier_pattern_example.dart) |
| Create custom widget | [`custom_widget_example.dart`](widgets/custom_widget_example.dart) |
| Add animation | [`piece_animation_example.dart`](animations/piece_animation_example.dart) |
| Custom painting | [`custom_painter_example.dart`](animations/custom_painter_example.dart) |
| Localize strings | [`localization_example.dart`](i18n/localization_example.dart) |
| Write widget test | [`widget_test_example.dart`](testing/widget_test_example.dart) |

## Contributing Examples

When adding new examples:

1. **Follow the template**: See [`example_template.dart`](template/example_template.dart)
2. **Make it complete**: Runnable without external dependencies
3. **Comment thoroughly**: Explain why, not just what
4. **Show best practices**: Demonstrate proper patterns
5. **Keep it focused**: One concept per example
6. **Update this README**: Add to the appropriate category

## Related Documentation

- [BEST_PRACTICES.md](../BEST_PRACTICES.md): Coding standards
- [WORKFLOWS.md](../WORKFLOWS.md): Development workflows
- [COMPONENTS.md](../COMPONENTS.md): Available components
- [API Documentation](../api/): Component API reference

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

