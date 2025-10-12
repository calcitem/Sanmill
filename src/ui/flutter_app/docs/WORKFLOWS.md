# Development Workflows for Sanmill Flutter Application

## Overview

This document defines the "Golden Paths" for common development tasks in the Sanmill Flutter application. These workflows represent the recommended, battle-tested approaches that ensure code quality, consistency, and maintainability.

These workflows are designed for both human developers and AI agents to follow, providing clear step-by-step procedures for frequent tasks.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Workflow 1: Adding a New UI Feature](#workflow-1-adding-a-new-ui-feature)
- [Workflow 2: Adding a New Game Rule Variant](#workflow-2-adding-a-new-game-rule-variant)
- [Workflow 3: Integrating a Third-Party Library](#workflow-3-integrating-a-third-party-library)
- [Workflow 4: Fixing a Bug](#workflow-4-fixing-a-bug)
- [Workflow 5: Refactoring Existing Code](#workflow-5-refactoring-existing-code)
- [Workflow 6: Adding Internationalization (i18n) Strings](#workflow-6-adding-internationalization-i18n-strings)
- [Workflow 7: Creating a New Settings Option](#workflow-7-creating-a-new-settings-option)
- [Workflow 8: Adding a Custom Painter/Animation](#workflow-8-adding-a-custom-painteranimation)
- [Workflow 9: Implementing Accessibility Features](#workflow-9-implementing-accessibility-features)
- [Workflow 10: Performance Optimization](#workflow-10-performance-optimization)

---

## Prerequisites

Before starting any workflow, ensure:

1. **Environment is set up**:
   ```bash
   ./flutter-init.sh
   cd src/ui/flutter_app
   flutter doctor  # Verify installation
   ```

2. **Dependencies are up to date**:
   ```bash
   flutter pub get
   ```

3. **Code is formatted**:
   ```bash
   cd ../../..  # Back to repo root
   ./format.sh s  # Format without committing
   ```

4. **You understand the architecture**:
   - Read [ARCHITECTURE.md](ARCHITECTURE.md)
   - Read [COMPONENTS.md](COMPONENTS.md)
   - Read [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)

---

## Workflow 1: Adding a New UI Feature

### Goal
Add a new user interface feature while maintaining consistency and quality.

### Steps

#### 1. **Define Requirements**
- What does the feature do?
- Which module does it belong to? (game_page, settings, misc)
- What user interactions are needed?
- What state needs to be managed?

#### 2. **Identify Reusable Components**
```bash
# Search for similar existing components
grep -r "similar_feature" lib/
```

Check [COMPONENTS.md](COMPONENTS.md) for components you can reuse:
- UI widgets in `lib/shared/widgets/`
- Settings components in `lib/shared/widgets/settings/`
- Custom painters in `lib/game_page/services/painters/`

#### 3. **Determine State Management Approach**

**For persistent preferences:**
- Add field to appropriate model (GeneralSettings, DisplaySettings, etc.)
- Use `DB()` for storage

**For transient UI state:**
- Use `ValueNotifier` for simple state
- Use `StatefulWidget` for complex component state

**Example:**
```dart
// Persistent: Add to DisplaySettings
@HiveField(10)
final bool showNewFeature;

// Transient: Create notifier
class NewFeatureNotifier extends ValueNotifier<bool> {
  NewFeatureNotifier() : super(false);
}
```

#### 4. **Create the Widget**

**Location:** Choose based on feature type:
- Game feature → `lib/game_page/widgets/`
- Settings UI → `lib/*_settings/widgets/`
- Shared widget → `lib/shared/widgets/`
- Standalone page → `lib/misc/`

**Template:**
```dart
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// your_feature_widget.dart

import 'package:flutter/material.dart';

/// Brief description of what this widget does.
///
/// Longer description if needed, explaining:
/// - Purpose
/// - Usage context
/// - Key behaviors
class YourFeatureWidget extends StatelessWidget {
  const YourFeatureWidget({
    required this.parameter,
    super.key,
  });

  final String parameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Implementation
    );
  }
}
```

#### 5. **Add Internationalization Support**

Add strings to `lib/l10n/intl_en.arb`:
```json
{
  "yourFeatureTitle": "Feature Title",
  "@yourFeatureTitle": {
    "description": "Title for the new feature"
  },
  "yourFeatureDescription": "Feature description",
  "@yourFeatureDescription": {
    "description": "Description text for the new feature"
  }
}
```

Generate localization code:
```bash
flutter gen-l10n
```

Use in widget:
```dart
import '../../generated/intl/l10n.dart';

// In build method:
Text(S.of(context).yourFeatureTitle)
```

#### 6. **Integrate with Existing UI**

Add navigation or integration point:
```dart
// In parent widget:
YourFeatureWidget(
  parameter: value,
)

// Or add to drawer menu:
CustomDrawerItem(
  icon: FluentIcons.feature_24_regular,
  title: S.of(context).yourFeatureTitle,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const YourFeaturePage(),
      ),
    );
  },
)
```

#### 7. **Add Tests** (Optional but Recommended)

```dart
// test/widgets/your_feature_widget_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('YourFeatureWidget displays correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YourFeatureWidget(parameter: 'test'),
      ),
    );
    
    expect(find.text('test'), findsOneWidget);
  });
}
```

Run tests:
```bash
flutter test
```

#### 8. **Format and Commit**

```bash
cd ../../..  # Back to repo root
./format.sh s  # Format code
git add .
git commit -m "Add new feature: [feature name]

Implement [feature description].
- Add YourFeatureWidget
- Add localization strings
- Integrate with [parent component]

Refs #[issue_number]"
```

### Example: Adding a "Game Timer Display"

```dart
// 1. Define: Show remaining time for each player
// 2. Reuse: PlayerTimer service already exists
// 3. State: Use existing PlayerTimer notifier
// 4. Create widget:

class GameTimerDisplay extends StatelessWidget {
  const GameTimerDisplay({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.playerTimer.timeNotifier,
      builder: (context, time, _) {
        return Text(
          _formatDuration(time),
          style: Theme.of(context).textTheme.titleLarge,
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// 5. i18n: (already has "time" strings)
// 6. Integrate: Add to GameHeader
// 7. Test: (verify timer updates)
// 8. Commit
```

---

## Workflow 2: Adding a New Game Rule Variant

### Goal
Add support for a new Mill game variant with different rules.

### Steps

#### 1. **Identify Rule Differences**
Document how the new variant differs:
- Board size/layout?
- Number of pieces?
- Special capture rules?
- Win conditions?

#### 2. **Update RuleSettings Model**

Add new fields to `lib/rule_settings/models/rule_settings.dart`:

```dart
@HiveField(X)  // Use next available field number
final bool newRuleOption;

// Add to constructor:
const RuleSettings({
  // ...
  this.newRuleOption = false,
});

// Add to copyWith:
RuleSettings copyWith({
  // ...
  bool? newRuleOption,
}) {
  return RuleSettings(
    // ...
    newRuleOption: newRuleOption ?? this.newRuleOption,
  );
}
```

#### 3. **Update Engine Configuration**

In `lib/game_page/services/engine/engine.dart`, add option:

```dart
Future<void> setOptions() async {
  // ...
  final ruleSettings = DB().ruleSettings;
  
  await _sendOptions('NewRuleOption', ruleSettings.newRuleOption);
}
```

#### 4. **Update Position Logic**

Modify `lib/game_page/services/engine/position.dart`:

```dart
// In relevant methods:
bool makeMove(Move move) {
  // ...
  if (DB().ruleSettings.newRuleOption) {
    // Apply new rule logic
  } else {
    // Standard logic
  }
  // ...
}
```

#### 5. **Update UI (Settings Page)**

Add control in `lib/rule_settings/widgets/rule_settings_page.dart`:

```dart
SettingsListTile(
  titleString: S.of(context).newRuleOptionTitle,
  subtitleString: S.of(context).newRuleOptionDescription,
  trailing: Switch(
    value: ruleSettings.newRuleOption,
    onChanged: (bool value) {
      DB().ruleSettings = ruleSettings.copyWith(
        newRuleOption: value,
      );
    },
  ),
)
```

#### 6. **Add Localization**

In `lib/l10n/intl_en.arb`:
```json
{
  "newRuleOptionTitle": "New Rule Variant",
  "@newRuleOptionTitle": {
    "description": "Title for new rule option"
  },
  "newRuleOptionDescription": "Enable the new rule variant",
  "@newRuleOptionDescription": {
    "description": "Description of what the new rule does"
  }
}
```

#### 7. **Update C++ Engine** (if needed)

If rule requires C++ engine changes:
1. Update `src/rule.cpp` and `src/rule.h`
2. Rebuild engine: `cd src && make build all`
3. Test: `./sanmill` (manual testing)

#### 8. **Add Tests**

Test rule logic:
```dart
test('New rule variant behaves correctly', () {
  final settings = RuleSettings(newRuleOption: true);
  DB().ruleSettings = settings;
  
  final position = Position();
  // Test new rule behavior
});
```

#### 9. **Document**

Add to relevant docs:
- Update ARCHITECTURE.md if significant
- Add example to COMPONENTS.md
- Document in rule_settings model docstring

#### 10. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Add support for [rule variant name]

Implement [variant description].
- Update RuleSettings model
- Modify Position logic
- Add UI controls
- Add localization
[- Update C++ engine]

Refs #[issue_number]"
```

---

## Workflow 3: Integrating a Third-Party Library

### Goal
Safely integrate an external Dart/Flutter package.

### Steps

#### 1. **Evaluate License Compatibility**

**Required:** Package must be GPL v3 compatible

✅ **Compatible licenses:**
- MIT
- BSD (2-clause, 3-clause)
- Apache 2.0
- GPL v3 or later

❌ **Incompatible:**
- Proprietary
- Non-commercial licenses

Check license:
```bash
# On pub.dev, check "License" tab
# Or check LICENSE file in package repo
```

#### 2. **Assess Necessity**

Ask:
- Is this functionality truly needed?
- Can we implement it ourselves (if small)?
- Does an existing dependency provide this?
- Is the package actively maintained?

#### 3. **Add Dependency**

Edit `pubspec.yaml`:
```yaml
dependencies:
  new_package: ^1.0.0
```

Install:
```bash
flutter pub get
```

#### 4. **Create Abstraction Layer**

**Don't use third-party packages directly throughout codebase!**

Create a wrapper service:

```dart
// lib/shared/services/new_feature_service.dart

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'package:new_package/new_package.dart' as pkg;

/// Service wrapper for [new_package].
///
/// Provides abstraction layer to:
/// - Isolate third-party dependency
/// - Adapt API to our conventions
/// - Allow easy replacement if needed
class NewFeatureService {
  NewFeatureService._();
  
  static final NewFeatureService instance = NewFeatureService._();
  
  /// Description of what this method does.
  Future<Result> doSomething(String input) async {
    // Wrap third-party call
    final pkgResult = await pkg.someFunction(input);
    
    // Adapt to our types
    return Result(
      data: pkgResult.data,
      success: pkgResult.isSuccess,
    );
  }
}

class Result {
  const Result({required this.data, required this.success});
  
  final String data;
  final bool success;
}
```

#### 5. **Use Through Abstraction**

```dart
// In application code:
import '../../shared/services/new_feature_service.dart';

// Use our service, not the package directly
final result = await NewFeatureService.instance.doSomething('input');
```

#### 6. **Update Documentation**

Add entry to `pubspec.yaml` comments:
```yaml
dependencies:
  # New feature support
  # License: MIT (GPL v3 compatible)
  # Used for: [specific purpose]
  new_package: ^1.0.0
```

Add to ARCHITECTURE.md Technology Stack if significant.

#### 7. **Test Integration**

```dart
test('NewFeatureService integrates correctly', () async {
  final result = await NewFeatureService.instance.doSomething('test');
  expect(result.success, true);
});
```

#### 8. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Integrate [package_name] for [purpose]

Add [package_name] (License: MIT) to provide [functionality].
- Create NewFeatureService abstraction layer
- Add to pubspec.yaml
- Add tests

Refs #[issue_number]"
```

---

## Workflow 4: Fixing a Bug

### Goal
Systematically fix a bug while preventing regressions.

### Steps

#### 1. **Reproduce the Bug**

- Document steps to reproduce
- Identify affected version/platform
- Determine severity (crash, visual, minor)

#### 2. **Locate the Source**

Use debugging tools:
```bash
# Add logging:
logger.d('Variable value: $value');

# Run in debug mode:
flutter run --dart-define dev_mode=true

# Use DevTools:
flutter pub global activate devtools
flutter pub global run devtools
```

Search codebase:
```bash
grep -r "relevant_function" lib/
```

Check Git history:
```bash
git log --all --full-history --source -- path/to/file.dart
git blame path/to/file.dart
```

#### 3. **Write a Failing Test** (Test-Driven)

```dart
// test/bug_fixes/issue_XXX_test.dart
test('Issue #XXX: [bug description]', () {
  // Setup
  final widget = BuggyWidget();
  
  // Reproduce bug
  widget.doSomething();
  
  // Assert expected behavior
  expect(widget.state, expectedValue);
  // Currently fails!
});
```

#### 4. **Implement Fix**

Fix the root cause (not symptoms):

```dart
// Before (buggy):
void buggyMethod() {
  // Problem: null check missing
  value.doSomething();
}

// After (fixed):
void fixedMethod() {
  // Add null check
  if (value != null) {
    value!.doSomething();
  } else {
    logger.w('value is null');
  }
}
```

#### 5. **Verify Fix**

Run the test:
```bash
flutter test test/bug_fixes/issue_XXX_test.dart
```

Test manually:
- Follow original reproduction steps
- Test edge cases
- Test on affected platforms

#### 6. **Check for Regressions**

Run full test suite:
```bash
flutter test
```

Test related features manually.

#### 7. **Update Documentation** (if needed)

If bug revealed missing documentation:
- Add clarifying comments
- Update API docs
- Add to BEST_PRACTICES.md if relevant

#### 8. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Fix: [brief bug description]

[Detailed explanation of the bug]

Root cause: [explain what was wrong]
Solution: [explain the fix]

- Add null check in buggyMethod()
- Add test for Issue #XXX
- [Other changes]

Fix #XXX"
```

### Example: Fixing Null Pointer Exception

```dart
// Bug: Crash when tapping square before game starts

// 1. Reproduce: Launch app → tap board → crash
// 2. Locate: lib/game_page/widgets/game_board.dart:150
// 3. Write test:
testWidgets('Can tap board before game starts', (tester) async {
  await tester.pumpWidget(GameBoardWidget());
  await tester.tap(find.byType(GameBoard));
  // Should not crash!
});

// 4. Fix:
void onBoardTap(int square) {
  // Add check
  if (!controller.isControllerReady) {
    return;  // Ignore taps before ready
  }
  controller.select(square);
}

// 5. Verify: Test passes
// 6. Regressions: All tests pass
// 7. Document: (not needed, code is clear)
// 8. Commit
```

---

## Workflow 5: Refactoring Existing Code

### Goal
Improve code structure without changing behavior.

### Steps

#### 1. **Identify Refactoring Need**

Common indicators:
- Code duplication
- Long methods (>50 lines)
- Deep nesting (>3 levels)
- Unclear naming
- Tight coupling
- Low test coverage

#### 2. **Ensure Test Coverage**

Before refactoring, add tests:
```dart
// Test current behavior
test('Original behavior works', () {
  final result = originalFunction();
  expect(result, expectedValue);
});
```

#### 3. **Plan the Refactoring**

Document:
- What will change (structure)
- What won't change (behavior)
- Impact scope (files affected)
- Approach (small steps vs. big rewrite)

**Prefer small, incremental steps!**

#### 4. **Execute Refactoring**

Common refactorings:

**Extract Method:**
```dart
// Before:
void complexMethod() {
  // 50 lines of code
  // doing multiple things
}

// After:
void complexMethod() {
  _stepOne();
  _stepTwo();
  _stepThree();
}

void _stepOne() { /* ... */ }
void _stepTwo() { /* ... */ }
void _stepThree() { /* ... */ }
```

**Extract Widget:**
```dart
// Before:
class BigWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 100 lines of widgets
      ],
    );
  }
}

// After:
class BigWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeaderSection(),
        _BodySection(),
        _FooterSection(),
      ],
    );
  }
}

class _HeaderSection extends StatelessWidget { /* ... */ }
```

**Rename for Clarity:**
```dart
// Before:
void process(String d) {  // Unclear
  final r = calculate(d);
  return r;
}

// After:
void processGameMove(String moveNotation) {
  final result = calculateMoveOutcome(moveNotation);
  return result;
}
```

#### 5. **Run Tests After Each Step**

```bash
flutter test
```

If test fails, undo and try smaller step.

#### 6. **Update Documentation**

- Update docstrings for changed APIs
- Update ARCHITECTURE.md if structure changed
- Update examples in COMPONENTS.md

#### 7. **Review Changes**

```bash
git diff
```

Ensure:
- No behavior changes (unless intentional)
- Tests still pass
- Code is clearer
- No regressions

#### 8. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Refactor: [component name] for improved [aspect]

[Explanation of what was improved]

Changes:
- Extract [methods/widgets]
- Rename [old] to [new]
- Simplify [complex logic]

No behavior changes.

Refs #[issue_number]"
```

---

## Workflow 6: Adding Internationalization (i18n) Strings

### Goal
Add new user-facing strings with full localization support.

### Steps

#### 1. **Add to Master File**

Edit `lib/l10n/intl_en.arb` (English is master):

```json
{
  "yourNewStringKey": "Your New String",
  "@yourNewStringKey": {
    "description": "Description of where/how this string is used",
    "context": "Optional context information"
  }
}
```

**Naming convention:**
- `pageNameTitle`: Page titles
- `pageNameDescription`: Descriptions
- `buttonNameLabel`: Button text
- `errorMessageName`: Error messages
- `tooltipName`: Tooltips

#### 2. **Handle Parameters** (if needed)

```json
{
  "greetingMessage": "Hello, {userName}!",
  "@greetingMessage": {
    "description": "Greeting message with user name",
    "placeholders": {
      "userName": {
        "type": "String",
        "example": "John"
      }
    }
  }
}
```

#### 3. **Handle Plurals** (if needed)

```json
{
  "piecesRemaining": "{count, plural, =0{No pieces} =1{1 piece} other{{count} pieces}}",
  "@piecesRemaining": {
    "description": "Number of pieces remaining",
    "placeholders": {
      "count": {
        "type": "int",
        "example": "5"
      }
    }
  }
}
```

#### 4. **Generate Localization Code**

```bash
flutter gen-l10n
```

This creates `lib/generated/intl/l10n.dart`

#### 5. **Use in Code**

```dart
import '../../generated/intl/l10n.dart';

// In build method:
Text(S.of(context).yourNewStringKey)

// With parameters:
Text(S.of(context).greetingMessage('Alice'))

// With plurals:
Text(S.of(context).piecesRemaining(count))
```

#### 6. **Test Localization**

Test with different locales:
```dart
testWidgets('Shows localized text', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      home: YourWidget(),
    ),
  );
  
  expect(find.text('Your New String'), findsOneWidget);
});
```

#### 7. **Translation** (Optional)

Translations are managed via Weblate (external):
- Don't manually edit other language files
- Weblate will sync translations
- If urgent, can manually add to specific locale files

#### 8. **Format and Commit**

```bash
./format.sh s
git add lib/l10n/intl_en.arb lib/generated/
git commit -m "Add localization string: [string_key]

Add [yourNewStringKey] for [purpose].

Refs #[issue_number]"
```

---

## Workflow 7: Creating a New Settings Option

### Goal
Add a new user-configurable setting with full persistence.

### Steps

#### 1. **Determine Settings Category**

Choose appropriate model:
- `GeneralSettings`: App behavior, AI, sound
- `RuleSettings`: Game rules
- `DisplaySettings`: Visual appearance, language
- `ColorSettings`: Colors and themes

#### 2. **Add to Data Model**

Example: Add `enableNewFeature` to `GeneralSettings`

Edit `lib/general_settings/models/general_settings.dart`:

```dart
@HiveField(XX)  // Use next available number!
final bool enableNewFeature;

// In constructor:
const GeneralSettings({
  // ...
  this.enableNewFeature = false,
});

// In copyWith:
GeneralSettings copyWith({
  // ...
  bool? enableNewFeature,
}) {
  return GeneralSettings(
    // ...
    enableNewFeature: enableNewFeature ?? this.enableNewFeature,
  );
}
```

#### 3. **Add Localization Strings**

In `lib/l10n/intl_en.arb`:
```json
{
  "enableNewFeatureTitle": "Enable New Feature",
  "@enableNewFeatureTitle": {
    "description": "Title for new feature setting"
  },
  "enableNewFeatureDescription": "When enabled, [what it does]",
  "@enableNewFeatureDescription": {
    "description": "Description of new feature setting"
  }
}
```

Generate:
```bash
flutter gen-l10n
```

#### 4. **Add UI Control**

Edit appropriate settings page (e.g., `lib/general_settings/widgets/general_settings_page.dart`):

```dart
// In build method, add SettingsListTile:
SettingsListTile(
  titleString: S.of(context).enableNewFeatureTitle,
  subtitleString: S.of(context).enableNewFeatureDescription,
  trailing: Switch(
    value: generalSettings.enableNewFeature,
    onChanged: (bool value) {
      DB().generalSettings = generalSettings.copyWith(
        enableNewFeature: value,
      );
    },
  ),
)
```

#### 5. **Use the Setting**

In code where feature is implemented:

```dart
final settings = DB().generalSettings;

if (settings.enableNewFeature) {
  // New feature code
} else {
  // Standard behavior
}
```

For reactive UI:
```dart
ValueListenableBuilder<Box<GeneralSettings>>(
  valueListenable: DB().listenGeneralSettings,
  builder: (context, box, _) {
    final settings = box.get(DB.generalSettingsKey)!;
    
    if (settings.enableNewFeature) {
      return NewFeatureWidget();
    } else {
      return StandardWidget();
    }
  },
)
```

#### 6. **Handle Engine Integration** (if needed)

If setting affects AI engine:

Edit `lib/game_page/services/engine/engine.dart`:
```dart
Future<void> setOptions() async {
  // ...
  await _sendOptions(
    'NewFeatureName',
    DB().generalSettings.enableNewFeature,
  );
}
```

#### 7. **Add Documentation**

Add docstring to the model field:
```dart
/// Enable the new feature.
///
/// When `true`, [describe behavior].
/// When `false`, [describe default behavior].
///
/// Default: `false`
@HiveField(XX)
final bool enableNewFeature;
```

#### 8. **Test**

```dart
test('New setting persists', () async {
  final settings = GeneralSettings(enableNewFeature: true);
  DB().generalSettings = settings;
  
  final loaded = DB().generalSettings;
  expect(loaded.enableNewFeature, true);
});

testWidgets('Setting UI works', (tester) async {
  await tester.pumpWidget(/* settings page */);
  
  // Find switch
  final switchFinder = find.byType(Switch);
  expect(switchFinder, findsOneWidget);
  
  // Toggle
  await tester.tap(switchFinder);
  await tester.pump();
  
  // Verify changed
  expect(DB().generalSettings.enableNewFeature, true);
});
```

#### 9. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Add setting: [setting name]

Add [enableNewFeature] setting to [Settings category].

- Add model field
- Add UI control
- Add localization
[- Integrate with engine]

Default: [default value]

Refs #[issue_number]"
```

---

## Workflow 8: Adding a Custom Painter/Animation

### Goal
Create custom graphics or animations for the game board.

### Steps

#### 1. **Define Visual Behavior**

Document:
- What should be drawn/animated?
- When should it appear?
- How long should it last?
- What triggers it?

#### 2. **Create Custom Painter**

Create file in `lib/game_page/services/painters/`:

```dart
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// my_custom_painter.dart

import 'package:flutter/material.dart';

/// Paints [what this paints].
///
/// Used for [purpose].
class MyCustomPainter extends CustomPainter {
  MyCustomPainter({
    required this.color,
    this.animationValue = 1.0,
  });

  final Color color;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Drawing logic
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 * animationValue,
      paint,
    );
  }

  @override
  bool shouldRepaint(MyCustomPainter oldDelegate) {
    return oldDelegate.color != color ||
           oldDelegate.animationValue != animationValue;
  }
}
```

#### 3. **Add Animation** (if needed)

Create animation manager:

```dart
class MyAnimation {
  MyAnimation({required TickerProvider vsync}) {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: vsync,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  late final AnimationController _controller;
  late final Animation<double> _animation;

  Animation<double> get animation => _animation;

  void start() {
    _controller.forward(from: 0.0);
  }

  void dispose() {
    _controller.dispose();
  }
}
```

#### 4. **Integrate into Widget**

```dart
class MyAnimatedWidget extends StatefulWidget {
  const MyAnimatedWidget({super.key});

  @override
  State<MyAnimatedWidget> createState() => _MyAnimatedWidgetState();
}

class _MyAnimatedWidgetState extends State<MyAnimatedWidget>
    with SingleTickerProviderStateMixin {
  late MyAnimation _animation;

  @override
  void initState() {
    super.initState();
    _animation = MyAnimation(vsync: this);
    _animation.start();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation.animation,
      builder: (context, child) {
        return CustomPaint(
          painter: MyCustomPainter(
            color: Colors.blue,
            animationValue: _animation.animation.value,
          ),
        );
      },
    );
  }
}
```

#### 5. **Add to AnimationManager** (for game animations)

Edit `lib/game_page/services/animation/animation_manager.dart`:

```dart
class AnimationManager {
  // Add field
  MyAnimation? _myAnimation;

  // Add trigger method
  void playMyAnimation() {
    _myAnimation?.start();
  }
}
```

#### 6. **Test Animation**

```dart
testWidgets('Animation plays correctly', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: MyAnimatedWidget(),
      ),
    ),
  );

  // Verify initial state
  expect(find.byType(MyAnimatedWidget), findsOneWidget);

  // Let animation run
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));

  // Verify end state
  // (Visual inspection or snapshot test)
});
```

#### 7. **Optimize Performance**

- Use `RepaintBoundary` to isolate repaints
- Implement `shouldRepaint` efficiently
- Avoid expensive calculations in `paint()`
- Cache objects when possible

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: MyCustomPainter(),
      ),
    );
  }
}
```

#### 8. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Add custom painter: [painter name]

Add [MyCustomPainter] for [purpose].
- Create custom painter
[- Add animation support]
- Integrate with [component]

Refs #[issue_number]"
```

---

## Workflow 9: Implementing Accessibility Features

### Goal
Ensure the app is fully accessible to users with disabilities.

### Steps

#### 1. **Audit Current State**

Test with:
- Screen reader (TalkBack on Android, VoiceOver on iOS)
- Large text sizes
- High contrast mode
- Keyboard navigation (desktop)

#### 2. **Add Semantic Labels**

For interactive elements:
```dart
// Bad: No semantics
GestureDetector(
  onTap: () => doSomething(),
  child: Container(
    child: Icon(Icons.add),
  ),
)

// Good: With semantics
Semantics(
  label: S.of(context).addPieceTooltip,
  button: true,
  enabled: true,
  onTap: () => doSomething(),
  child: GestureDetector(
    onTap: () => doSomething(),
    child: Container(
      child: Icon(Icons.add),
    ),
  ),
)
```

#### 3. **Use Semantic Widgets**

Prefer semantic widgets:
```dart
// Good: Built-in semantics
IconButton(
  icon: const Icon(Icons.add),
  tooltip: S.of(context).addPieceTooltip,
  onPressed: () => doSomething(),
)
```

#### 4. **Announce Dynamic Changes**

For game state changes:
```dart
// Use BoardSemanticsNotifier
controller.boardSemanticsNotifier.announce(
  S.of(context).pieceMovedAnnouncement(from, to),
);
```

#### 5. **Support Large Text**

Use relative sizes:
```dart
// Bad: Fixed size
Text('Hello', style: TextStyle(fontSize: 14))

// Good: Theme-based
Text('Hello', style: Theme.of(context).textTheme.bodyMedium)

// Even better: Respects user's font scale
Text(
  'Hello',
  style: Theme.of(context).textTheme.bodyMedium,
  // TextScaler applied automatically via MaterialApp
)
```

#### 6. **Ensure Sufficient Contrast**

Check color contrast ratios:
- Normal text: 4.5:1 minimum
- Large text: 3:1 minimum
- Interactive elements: 3:1 minimum

```dart
// Use theme colors (already checked):
color: Theme.of(context).colorScheme.primary

// Or verify custom colors:
// https://webaim.org/resources/contrastchecker/
```

#### 7. **Add Keyboard Support** (Desktop)

```dart
class KeyboardNavigableWidget extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Focus(
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            doSomething();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(/* ... */),
    );
  }
}
```

#### 8. **Test Accessibility**

```dart
testWidgets('Widget is accessible', (tester) async {
  await tester.pumpWidget(MyWidget());

  // Check semantics
  expect(
    tester.getSemantics(find.byType(MyWidget)),
    matchesSemantics(
      label: 'Expected label',
      isButton: true,
    ),
  );
});
```

Manual testing:
```bash
# Enable screen reader and test manually
# Android: Settings → Accessibility → TalkBack
# iOS: Settings → Accessibility → VoiceOver
```

#### 9. **Document Accessibility**

Add to widget docstring:
```dart
/// My accessible widget.
///
/// Accessibility:
/// - Announces [what it announces]
/// - Supports keyboard navigation
/// - Screen reader compatible
/// - High contrast support
class MyWidget extends StatelessWidget {
  // ...
}
```

#### 10. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Improve accessibility: [component name]

Add accessibility support for [component].
- Add semantic labels
- Add screen reader announcements
- Support large text
[- Add keyboard navigation]

Refs #[issue_number]"
```

---

## Workflow 10: Performance Optimization

### Goal
Improve app performance (frame rate, memory, startup time).

### Steps

#### 1. **Profile Current Performance**

```bash
# Run in profile mode
flutter run --profile

# Open DevTools
flutter pub global run devtools
```

Use Performance tab:
- Identify slow frames (>16ms)
- Find expensive operations
- Check memory usage

#### 2. **Identify Bottleneck**

Common issues:
- Expensive `build()` methods
- Missing `const` constructors
- Unnecessary rebuilds
- Large images/assets
- Synchronous I/O

#### 3. **Apply Optimization**

**Use `const` constructors:**
```dart
// Before:
Text('Hello')

// After:
const Text('Hello')
```

**Minimize rebuilds:**
```dart
// Before: Entire widget rebuilds
class MyWidget extends StatefulWidget {
  @override
  Widget build() {
    return Column(
      children: [
        ExpensiveWidget(),  // Rebuilds unnecessarily
        Text(_counter.toString()),
      ],
    );
  }
}

// After: Only Text rebuilds
class MyWidget extends StatefulWidget {
  @override
  Widget build() {
    return Column(
      children: const [
        ExpensiveWidget(),  // Const: never rebuilds
      ],
      children: [
        Text(_counter.toString()),  // Only this rebuilds
      ],
    );
  }
}
```

**Use RepaintBoundary:**
```dart
RepaintBoundary(
  child: ExpensiveCustomPaint(),
)
```

**Cache expensive computations:**
```dart
class MyWidget extends StatefulWidget {
  late final _cachedValue = _expensiveComputation();

  String _expensiveComputation() {
    // Computed once
  }

  @override
  Widget build() {
    return Text(_cachedValue);  // Reuse cached value
  }
}
```

**Optimize images:**
```bash
# Compress images
# Use appropriate formats (WebP for photos)
# Provide multiple resolutions
assets/images/
  image.png
  2.0x/image.png
  3.0x/image.png
```

#### 4. **Profile Again**

Verify improvement:
```bash
flutter run --profile
# Check Performance tab in DevTools
```

Compare before/after metrics:
- Frame rendering time
- Memory usage
- Startup time

#### 5. **Add Performance Tests**

```dart
testWidgets('Widget renders efficiently', (tester) async {
  await tester.pumpWidget(MyWidget());
  
  // Measure rebuild time
  final stopwatch = Stopwatch()..start();
  
  await tester.pumpWidget(MyWidget());
  
  stopwatch.stop();
  
  // Assert reasonable time
  expect(stopwatch.elapsedMilliseconds, lessThan(16));
});
```

#### 6. **Document Optimization**

Add comments explaining non-obvious optimizations:
```dart
// RepaintBoundary isolates expensive board repaints
// from header updates (reduces frame time by ~8ms)
RepaintBoundary(
  child: GameBoard(),
)
```

#### 7. **Format and Commit**

```bash
./format.sh s
git add .
git commit -m "Optimize performance: [component name]

Improve [metric] by [amount].

Optimizations:
- [Specific change 1]
- [Specific change 2]

Before: [metric value]
After: [improved metric value]

Refs #[issue_number]"
```

---

## Best Practices Across All Workflows

### 1. **Always Format Before Committing**

```bash
./format.sh s
```

### 2. **Write Descriptive Commit Messages**

Follow the format:
```
<type>: <brief summary>

<detailed description>

<list of changes>

<issue references>
```

Types: `Add`, `Fix`, `Refactor`, `Optimize`, `Update`, `Remove`

### 3. **Test on Multiple Platforms** (when relevant)

```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Desktop
flutter run -d windows  # or macos, linux
```

### 4. **Keep Changes Focused**

- One workflow = one logical change
- Don't mix multiple unrelated changes
- Easier to review and revert if needed

### 5. **Document as You Go**

- Update docs in the same commit
- Don't leave documentation for later
- Future you will thank present you

### 6. **Ask for Clarification**

If workflow is unclear or requirements are ambiguous:
- Ask in the issue tracker
- Discuss in development chat
- Don't guess and hope for the best

---

## Quick Reference

| Task | Workflow |
|------|----------|
| New UI element | [Workflow 1](#workflow-1-adding-a-new-ui-feature) |
| New game rule | [Workflow 2](#workflow-2-adding-a-new-game-rule-variant) |
| Add library | [Workflow 3](#workflow-3-integrating-a-third-party-library) |
| Fix bug | [Workflow 4](#workflow-4-fixing-a-bug) |
| Refactor code | [Workflow 5](#workflow-5-refactoring-existing-code) |
| Add text | [Workflow 6](#workflow-6-adding-internationalization-i18n-strings) |
| New setting | [Workflow 7](#workflow-7-creating-a-new-settings-option) |
| Custom graphics | [Workflow 8](#workflow-8-adding-a-custom-painteranimation) |
| Accessibility | [Workflow 9](#workflow-9-implementing-accessibility-features) |
| Performance | [Workflow 10](#workflow-10-performance-optimization) |

---

## References

- [ARCHITECTURE.md](ARCHITECTURE.md): System architecture
- [COMPONENTS.md](COMPONENTS.md): Available components
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md): State management patterns
- [BEST_PRACTICES.md](BEST_PRACTICES.md): Code quality guidelines
- [AGENTS.md](../../../AGENTS.md): AI agent guidelines

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

