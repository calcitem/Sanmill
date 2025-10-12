# Flutter/Dart Best Practices for Sanmill

## Overview

This document defines code quality standards and best practices for the Sanmill Flutter application. These guidelines help maintain consistency, readability, and maintainability across the codebase.

**Target Audience**: Developers (human and AI) contributing to Sanmill

## Table of Contents

- [Code Style](#code-style)
- [Widget Design](#widget-design)
- [State Management](#state-management)
- [Performance](#performance)
- [Accessibility](#accessibility)
- [Internationalization](#internationalization)
- [Testing](#testing)
- [Error Handling](#error-handling)
- [Documentation](#documentation)
- [Security and Privacy](#security-and-privacy)

---

## Code Style

### File Headers

**✅ DO**: Include GPL v3 header in all Dart files

```dart
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// filename.dart
```

### Imports

**✅ DO**: Order imports: Dart SDK → Flutter → External packages → Internal

```dart
// Dart SDK
import 'dart:async';
import 'dart:io';

// Flutter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// External packages
import 'package:hive_ce_flutter/hive_flutter.dart';

// Internal (relative imports)
import '../../shared/database/database.dart';
import '../models/settings.dart';
```

**✅ DO**: Use relative imports for internal files

```dart
// ✅ Good
import '../../shared/database/database.dart';

// ❌ Bad
import 'package:sanmill/shared/database/database.dart';
```

### Naming Conventions

**✅ DO**: Follow Dart naming conventions

```dart
// Classes, enums, typedefs: UpperCamelCase
class GameController {}
enum Phase { placing, moving }

// Variables, functions, parameters: lowerCamelCase
int pieceCount = 0;
void makeMove() {}

// Constants: lowerCamelCase
const int maxPieces = 12;

// Private members: _leadingUnderscore
int _internalState = 0;
void _helperMethod() {}
```

**❌ DON'T**: Use Hungarian notation or type prefixes

```dart
// ❌ Bad
String strUserName;
int iCounter;
bool bIsActive;

// ✅ Good
String userName;
int counter;
bool isActive;
```

### Code Formatting

**✅ DO**: Run `dart format` before committing (automatically done by `./format.sh s`)

**✅ DO**: Keep lines under 80 characters when reasonable

```dart
// ✅ Good
final result = someFunction(
  parameter1: value1,
  parameter2: value2,
  parameter3: value3,
);

// ❌ Bad (too long)
final result = someFunction(parameter1: value1, parameter2: value2, parameter3: value3);
```

**✅ DO**: Use trailing commas for better diffs

```dart
// ✅ Good
Column(
  children: [
    Text('Item 1'),
    Text('Item 2'),
    Text('Item 3'),  // Trailing comma
  ],
)

// ❌ Bad
Column(
  children: [
    Text('Item 1'),
    Text('Item 2'),
    Text('Item 3')  // No trailing comma
  ],
)
```

---

## Widget Design

### Widget Composition

**✅ DO**: Prefer composition over inheritance

```dart
// ✅ Good: Compose smaller widgets
class GamePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          GameHeader(),
          GameBoard(),
          GameControls(),
        ],
      ),
    );
  }
}

// ❌ Bad: Monolithic widget
class GamePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 500 lines of inline widgets
        ],
      ),
    );
  }
}
```

### Stateless vs. Stateful

**✅ DO**: Use `StatelessWidget` when possible

```dart
// ✅ Good: No state needed
class GameHeader extends StatelessWidget {
  const GameHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title);
  }
}
```

**✅ DO**: Use `StatefulWidget` only when you need mutable state

```dart
// ✅ Good: Legitimate state
class AnimatedPiece extends StatefulWidget {
  @override
  State<AnimatedPiece> createState() => _AnimatedPieceState();
}

class _AnimatedPieceState extends State<AnimatedPiece>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(/* ... */);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(/* ... */);
  }
}
```

### Const Constructors

**✅ DO**: Use `const` constructors wherever possible

```dart
// ✅ Good: Const constructor
class GameButton extends StatelessWidget {
  const GameButton({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {},
      child: Text(label),
    );
  }
}

// Usage:
const GameButton(label: 'Start')  // Can be const!
```

**✅ DO**: Use `const` for literal widgets

```dart
// ✅ Good
const Text('Hello')
const Icon(Icons.star)
const SizedBox(width: 10)

// ❌ Bad
Text('Hello')  // Not const (unnecessary rebuild)
```

### Widget Keys

**✅ DO**: Use keys for list items and stateful widgets

```dart
// ✅ Good: Keys preserve state
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return MyWidget(
      key: ValueKey(items[index].id),
      item: items[index],
    );
  },
)

// ❌ Bad: No keys (state lost on reorder)
ListView.builder(
  itemBuilder: (context, index) {
    return MyWidget(item: items[index]);
  },
)
```

### Extract Widgets vs. Extract Methods

**✅ DO**: Extract widgets for reusable UI components

```dart
// ✅ Good: Reusable widget
class PlayerIcon extends StatelessWidget {
  const PlayerIcon({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
```

**✅ DO**: Extract methods for non-reusable UI logic

```dart
// ✅ Good: Helper method (not reused elsewhere)
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildBody(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(/* ... */);
  }

  Widget _buildBody() {
    return Container(/* ... */);
  }
}
```

---

## State Management

### Database Usage

**✅ DO**: Use the Database singleton for all persistent state

```dart
// ✅ Good
final settings = DB().generalSettings;
DB().generalSettings = settings.copyWith(aiLevel: 10);

// ❌ Bad: Direct Hive access
final box = Hive.box<GeneralSettings>('generalSettings');
```

### Immutable Updates

**✅ DO**: Use `copyWith` for model updates

```dart
// ✅ Good: Immutable update
final updated = settings.copyWith(
  aiLevel: 10,
  isAutoRestart: true,
);
DB().generalSettings = updated;

// ❌ Bad: Mutation (won't work - fields are final)
settings.aiLevel = 10;  // Compile error
```

### ValueNotifier Usage

**✅ DO**: Use `ValueNotifier` for transient UI state

```dart
// ✅ Good
class MyController {
  final statusNotifier = ValueNotifier<String>('');
  
  void updateStatus(String newStatus) {
    statusNotifier.value = newStatus;
  }
}

// In widget:
ValueListenableBuilder<String>(
  valueListenable: controller.statusNotifier,
  builder: (context, status, _) => Text(status),
)
```

**❌ DON'T**: Use `setState` for data that should be in a notifier

```dart
// ❌ Bad: setState for controller state
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  String status = '';

  void updateStatus() {
    setState(() {
      status = 'New status';  // Should be in controller/notifier
    });
  }
}
```

### Dispose Pattern

**✅ DO**: Always dispose controllers, streams, and notifiers

```dart
// ✅ Good
class _MyWidgetState extends State<MyWidget> {
  late final ValueNotifier<int> _counter;
  late final AnimationController _animController;
  late final StreamSubscription _subscription;

  @override
  void initState() {
    super.initState();
    _counter = ValueNotifier(0);
    _animController = AnimationController(/* ... */);
    _subscription = stream.listen(/* ... */);
  }

  @override
  void dispose() {
    _counter.dispose();
    _animController.dispose();
    _subscription.cancel();
    super.dispose();  // ALWAYS call super.dispose() LAST
  }
}
```

---

## Performance

### Build Method Optimization

**✅ DO**: Keep `build()` methods fast and pure

```dart
// ✅ Good: Fast, pure build
@override
Widget build(BuildContext context) {
  final settings = DB().generalSettings;
  
  return Text(settings.userName);
}

// ❌ Bad: Expensive operations in build
@override
Widget build(BuildContext context) {
  final data = expensiveComputation();  // Recomputed every rebuild!
  saveToDatabase(data);  // Side effect!
  
  return Text(data);
}
```

**✅ DO**: Cache expensive computations

```dart
// ✅ Good: Compute once
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final String _cachedValue;

  @override
  void initState() {
    super.initState();
    _cachedValue = expensiveComputation();  // Once
  }

  @override
  Widget build(BuildContext context) {
    return Text(_cachedValue);  // Reuse
  }
}
```

### Minimize Rebuilds

**✅ DO**: Use `const` to prevent unnecessary rebuilds

```dart
// ✅ Good: Const widgets never rebuild
Column(
  children: const [
    Text('Static text'),
    Icon(Icons.star),
  ],
)
```

**✅ DO**: Use `ValueListenableBuilder` to rebuild only affected widgets

```dart
// ✅ Good: Only Text rebuilds
Column(
  children: [
    const Text('Static header'),  // Never rebuilds
    ValueListenableBuilder<int>(
      valueListenable: counter,
      builder: (context, value, _) => Text('$value'),  // Only this rebuilds
    ),
    const Text('Static footer'),  // Never rebuilds
  ],
)

// ❌ Bad: Entire column rebuilds
Column(
  children: [
    Text('Static header'),
    Text('$_counter'),  // Whole build() reruns on setState
    Text('Static footer'),
  ],
)
```

### RepaintBoundary

**✅ DO**: Use `RepaintBoundary` for expensive custom paints

```dart
// ✅ Good: Isolate expensive repaints
RepaintBoundary(
  child: CustomPaint(
    painter: ComplexBoardPainter(),
  ),
)
```

### Image Optimization

**✅ DO**: Provide multiple image resolutions

```
assets/images/
  piece.png      (1x)
  2.0x/piece.png (2x)
  3.0x/piece.png (3x)
```

**✅ DO**: Use appropriate image formats

- **Photos**: WebP (best compression)
- **Icons/logos**: PNG with transparency
- **Simple graphics**: SVG (if supported)

---

## Accessibility

### Semantic Labels

**✅ DO**: Provide semantic labels for all interactive elements

```dart
// ✅ Good
Semantics(
  label: S.of(context).placePieceButton,
  button: true,
  child: GestureDetector(
    onTap: placePiece,
    child: const Icon(Icons.add_circle),
  ),
)

// ❌ Bad: No semantics
GestureDetector(
  onTap: placePiece,
  child: const Icon(Icons.add_circle),
)
```

**✅ DO**: Use built-in semantic widgets

```dart
// ✅ Good: Built-in semantics
IconButton(
  icon: const Icon(Icons.add_circle),
  tooltip: S.of(context).placePieceButton,
  onPressed: placePiece,
)
```

### Screen Reader Support

**✅ DO**: Announce important state changes

```dart
// ✅ Good
void makeMove(Move move) {
  position.makeMove(move);
  
  // Announce to screen reader
  controller.boardSemanticsNotifier.announce(
    S.of(context).pieceMoved(move.from, move.to),
  );
}
```

### Text Sizing

**✅ DO**: Use theme-based text styles (respects user's font scale)

```dart
// ✅ Good: Scales with user preference
Text(
  'Hello',
  style: Theme.of(context).textTheme.bodyMedium,
)

// ❌ Bad: Fixed size
Text(
  'Hello',
  style: const TextStyle(fontSize: 14),
)
```

### Color Contrast

**✅ DO**: Ensure sufficient contrast (4.5:1 for normal text)

```dart
// ✅ Good: Use theme colors (already tested)
color: Theme.of(context).colorScheme.primary

// ⚠️ Check custom colors
color: const Color(0xFF1E3A5F)  // Verify contrast
```

---

## Internationalization

### String Externalization

**✅ DO**: Externalize all user-facing strings

```dart
// ✅ Good: Localized
Text(S.of(context).welcomeMessage)

// ❌ Bad: Hardcoded
Text('Welcome!')
```

**❌ DON'T**: Concatenate localized strings

```dart
// ❌ Bad: Different word order in other languages
Text(S.of(context).hello + ' ' + userName)

// ✅ Good: Parameter in string
Text(S.of(context).helloUser(userName))

// In intl_en.arb:
// "helloUser": "Hello, {userName}!"
```

### Plural Support

**✅ DO**: Use pluralization for count-dependent strings

```dart
// ✅ Good: Proper pluralization
Text(S.of(context).piecesRemaining(count))

// In intl_en.arb:
// "piecesRemaining": "{count, plural, =0{No pieces} =1{1 piece} other{{count} pieces}}"

// ❌ Bad: English-only grammar
Text('$count piece${count == 1 ? '' : 's'}')
```

### Date and Number Formatting

**✅ DO**: Use localized formatters

```dart
// ✅ Good: Localized
import 'package:intl/intl.dart';

final formatter = DateFormat.yMd(Localizations.localeOf(context).toString());
Text(formatter.format(DateTime.now()))

// ❌ Bad: English format only
Text('${date.month}/${date.day}/${date.year}')
```

---

## Testing

### Unit Tests

**✅ DO**: Test business logic

```dart
// ✅ Good
test('GeneralSettings copyWith updates fields', () {
  const original = GeneralSettings(aiLevel: 1);
  final updated = original.copyWith(aiLevel: 10);
  
  expect(updated.aiLevel, 10);
  expect(original.aiLevel, 1);  // Original unchanged
});
```

### Widget Tests

**✅ DO**: Test widget rendering and interaction

```dart
// ✅ Good
testWidgets('Button triggers callback', (tester) async {
  bool tapped = false;
  
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ElevatedButton(
          onPressed: () => tapped = true,
          child: const Text('Tap me'),
        ),
      ),
    ),
  );
  
  await tester.tap(find.text('Tap me'));
  
  expect(tapped, true);
});
```

### Test Data

**✅ DO**: Use realistic test data

```dart
// ✅ Good: Realistic
final testSettings = GeneralSettings(
  aiLevel: 10,
  isAutoRestart: true,
  screenReaderSupport: false,
);

// ❌ Bad: Unrealistic
final testSettings = GeneralSettings(aiLevel: -1);  // Invalid
```

---

## Error Handling

### Assertions

**✅ DO**: Use assertions for preconditions (Sanmill C++ convention)

```dart
// ✅ Good: Assert precondition
void makeMove(Move move) {
  assert(move != null, 'Move cannot be null');
  assert(isLegalMove(move), 'Move must be legal');
  
  // Proceed with move
}
```

**❌ DON'T**: Use try-catch in normal control flow (Sanmill C++ convention)

```dart
// ❌ Bad: Exception for control flow
try {
  makeMove(move);
} catch (e) {
  // Handle as normal case
}

// ✅ Good: Check before calling
if (isLegalMove(move)) {
  makeMove(move);
} else {
  showError('Illegal move');
}
```

### Logging

**✅ DO**: Use the logger service

```dart
import '../../shared/services/logger.dart';

logger.i('Information message');
logger.w('Warning message');
logger.e('Error message');
logger.d('Debug message');
logger.t('Trace message');

// ❌ Bad: print() statements
print('Debug info');  // Don't use
```

### User-Facing Errors

**✅ DO**: Show localized error messages

```dart
// ✅ Good
SnackBarService.showRootSnackBar(
  S.of(context).errorInvalidMove,
);

// ❌ Bad
SnackBarService.showRootSnackBar('Invalid move!');
```

---

## Documentation

### Code Comments

**✅ DO**: Write doc comments for public APIs

```dart
/// Brief one-sentence description.
///
/// Longer description explaining:
/// - What this does
/// - When to use it
/// - Important behaviors
///
/// Example:
/// ```dart
/// final controller = GameController();
/// await controller.newGame();
/// ```
class GameController {
  /// Start a new game.
  ///
  /// Resets all game state and initializes a fresh position.
  /// Returns a [Future] that completes when initialization is done.
  Future<void> newGame() async {
    // ...
  }
}
```

**✅ DO**: Use single-line comments for implementation details

```dart
// Optimization: Cache mill lines to avoid recomputation
final cachedMills = _computeMillLines();
```

**❌ DON'T**: Comment obvious code

```dart
// ❌ Bad: Obvious
int counter = 0;  // Initialize counter to 0

// ✅ Good: Explains WHY
int counter = 0;  // Start from 0 to match C++ engine indexing
```

### TODO Comments

**✅ DO**: Use TODO comments for future work

```dart
// TODO(username): Add support for 12 men's morris
// TODO: Optimize performance (Issue #123)

// ❌ Bad: No context
// TODO: fix this
```

---

## Security and Privacy

### Data Privacy

**✅ DO**: Store all data locally

```dart
// ✅ Good: Local storage
DB().generalSettings = settings;

// ❌ Bad: Cloud storage (without user consent)
cloudService.save(settings);
```

**✅ DO**: Request permissions before sensitive operations

```dart
// ✅ Good
if (await Permission.storage.request().isGranted) {
  saveToFile(data);
}

// ❌ Bad: Assume permission
saveToFile(data);  // May crash
```

### License Compliance

**✅ DO**: Include GPL v3 header in all source files

**✅ DO**: Ensure all dependencies are GPL v3 compatible

**✅ DO**: Attribute third-party code and assets

```dart
// ✅ Good: Attribution
// Based on algorithm from:
// https://example.com/original-source
// License: MIT (GPL v3 compatible)
```

---

## Quick Reference

### Code Review Checklist

Before submitting code, verify:

- [ ] GPL v3 header present
- [ ] All strings localized
- [ ] No hardcoded strings
- [ ] Semantic labels for interactive elements
- [ ] `const` constructors used
- [ ] Resources disposed properly
- [ ] No `print()` statements (use `logger`)
- [ ] Documentation added/updated
- [ ] Tests added/passing
- [ ] Code formatted (`./format.sh s`)
- [ ] No linter warnings

### Common Pitfalls

| ❌ Don't | ✅ Do |
|----------|-------|
| Hardcode strings | Use `S.of(context)` |
| Use `print()` | Use `logger` |
| Mutate models | Use `copyWith()` |
| Forget `dispose()` | Always dispose |
| Use `setState` for global state | Use `ValueNotifier` or DB |
| Skip `const` | Use `const` everywhere possible |
| Create new objects in `build()` | Cache in `initState()` |
| Ignore accessibility | Add semantic labels |
| Use fixed font sizes | Use theme text styles |

---

## References

- [Effective Dart](https://dart.dev/guides/language/effective-dart)
- [Flutter Best Practices](https://flutter.dev/docs/development/ui/best-practices)
- [ARCHITECTURE.md](ARCHITECTURE.md): Project architecture
- [WORKFLOWS.md](WORKFLOWS.md): Development workflows
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md): State management details

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

