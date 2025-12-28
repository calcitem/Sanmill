# AGENT INSTRUCTIONS

This document defines a practical playbook for AI Agents working within
the Sanmill repository. It balances safety with productivity, ensuring
consistent, high-quality contributions.

---

## 1) Purpose & Scope

* Provide consistent guidance for AI Agents (code assistants, automation
  bots).
* Cover planning, execution, safety, testing, and collaboration practices.
* Maintain code quality across C++, Flutter/Dart, and build tooling.

---

## 2) Project Context

* **Project Name:** Sanmill
* **Description:** A free, powerful Mill (N Men's Morris) game with CUI (C++), Flutter GUI, and Qt GUI.
* **License:** GNU General Public License version 3 (GPL v3)
* **Primary Goals:**
  - Deliver a high-quality, cross-platform Mill game
  - Provide excellent user experience through Flutter frontend
  - Support multiple platforms: Android, iOS, Windows, macOS, Linux
* **Key Constraints:**
  - GPL v3 compliance for all code contributions
  - Cross-platform compatibility required
  - Performance-critical AI engine (C++)
  - Mobile-first UI/UX design (Flutter)

### Technology Stack

**Core Engine (C++):**
- UCI-like protocol implementation
- Search algorithms (MTD(f), Alpha-Beta, MCTS ect.)
- Bitboard representation

**Frontend (Flutter/Dart):**
- Cross-platform UI (Android, iOS, Windows, macOS, Linux)
- Internationalization (Many languages via ARB files)
- Build system: Flutter CLI, platform-specific tools

**Legacy (Qt/C++):**
- Desktop GUI primarily for debugging
- Not actively maintained; use Flutter for new features

**Testing:**
- C++ unit tests: Google Test (gtest)
- Flutter widget tests and integration tests
- UI automation: Appium
- Monkey testing for stability

**Build & Automation:**
- Shell scripts for initialization and deployment
- CI/CD: GitHub Actions
- Code formatting: clang-format (C++), dart format (Dart)

### Project Structure

```
/
├── src/                       # C++ engine source
│   ├── *.cpp, *.h            # Core game logic, AI, UCI
│   ├── Makefile              # Build configuration for CLI
│   ├── perfect/              # Perfect play databases
│   └── ui/
│       ├── flutter_app/      # Flutter frontend (PRIMARY)
│       │   ├── lib/          # Dart source code
│       │   ├── l10n.yaml     # Localization config
│       │   ├── pubspec.yaml  # Flutter dependencies
│       │   └── android/ios/linux/macos/windows/
│       └── qt/               # Qt frontend (DEBUG ONLY)
├── tests/                    # C++ and integration tests
│   ├── test_*.cpp            # gtest unit tests
│   ├── gtest/                # gtest project files
│   ├── appium/               # UI automation tests
│   └── monkey/               # Stability testing
├── scripts/                  # Utility scripts
├── fastlane/metadata/        # App store metadata
├── include/                  # Public headers
├── format.sh                 # Code formatting script
├── flutter-init.sh           # Flutter setup
└── *.sh                      # Various build/deploy scripts
```

---

## 3) Core Principles

1. **Safety by Default:** Analyze first, modify second. Understand the
   impact of changes on performance-critical code.
2. **Transparency:** State what you'll do, why, and expected impact before
   doing it.
3. **Incrementalism:** Ship small, testable changes; avoid big-bang
   rewrites.
4. **Reversibility:** Ensure every change has a rollback path via git.
5. **Observability:** Validate changes through tests and manual
   verification.
6. **Cross-Platform Compatibility:** Test changes across target platforms
   when possible.
7. **Auditability:** Leave a clear trail in commits.

---

## 4) Commit Workflow

**CRITICAL:** Always follow this sequence:

1. Make your code changes
2. Run `./format.sh s` from repository root and **wait for completion**
3. Run `git add .` to stage changes
4. Run `git commit` with proper message (see §5)

**Never skip the formatting step.** The script runs:
- `clang-format` on all C++ source files
- `dart format` on all Dart/Flutter code

---

## 5) Commit Message Rules

### Format

```
<subject line - imperative mood, max 72 chars>

<body paragraph explaining WHY and WHAT, wrapped at 72 chars>
<additional paragraphs if needed>
```

### Requirements

* **Subject line:** Imperative mood (e.g., "Add", "Fix", "Refactor"),
  capitalize first word, no period at end, max 72 characters
* **Body:** Must be present (even for small changes), wrapped at 72
  characters per line
* **Language:** Use English subject + body
* **References:** Include issue numbers if applicable (`Fix #123`,
  `Refs #456`)

### Examples

```
Add support for 12 Men's Morris variant

This commit introduces support for the 12 Men's Morris game variant,
extending the existing 9 Men's Morris implementation. The AI engine
now handles the additional piece placement phase.

Related changes:
- Add new rule validation in rule.cpp
- Update UI to show 12-piece board option
- Add unit tests for 12-piece game logic

Refs #789
```

---

## 6) Code Quality and Style Guidelines

### C++ Specific Rules

**Error Handling:**
* **Never use try/catch blocks** in C++ code
* **Use assertions** (`assert()`) for preconditions and
  invariants
* **Avoid fallback mechanisms** that hide errors; prefer fail-fast
  behavior
* Errors should be surfaced immediately, not masked with default values

**Code Extension:**
* **Modify existing functions directly** rather than creating wrapper
  functions
* **Avoid "Enhanced" or "Extended" class names** (e.g., no
  `EnhancedSearch`)
* Prefer direct modification of original implementations to maintain
  clarity

**Style:**
* Follow existing code style (enforced by clang-format)

### Dart/Flutter Specific Rules

**Style:**
* Follow `dart format` conventions (automatically applied)

**State Management:**
* Use existing state management approach consistently
* Avoid introducing new state management libraries without discussion
* Keep business logic separate from UI widgets

**Localization:**
* All user-facing strings must go through ARB localization files
* Use existing localization patterns in `lib/generated/l10n/`

---

## 7) Tool Usage Guidelines

### Version Control (git)

* Keep commits atomic (one logical change per commit)

### Build Tools

**C++ Engine:**
```bash
cd src
make all
make test              # Run unit tests
./sanmill # Run sanmill
```

**Flutter App:**
```bash
./flutter-init.sh      # Set up Flutter
cd src/ui/flutter_app
flutter build linux --debug -v      # Linux
flutter run
flutter test
```

**Code Generation:**

The project uses code generation for several purposes. Understanding this
is critical to avoid common mistakes.

* **Generated Files (*.g.dart):**
  - Files with `.g.dart` extension are auto-generated by build_runner
  - These files are gitignored (matched by `*generated*` pattern)
  - They exist only in local development environments
  - Never manually create or edit `.g.dart` files
  - Always run `./flutter-init.sh` after cloning or when dependencies change

* **Hive Type Adapters:**
  - Use `@HiveType(typeId: N)` and `@HiveField(N)` annotations on models
  - Adapters are automatically generated, never write them manually
  - Include `part 'filename.g.dart';` directive in the model file
  - Example pattern (see `lib/appearance_settings/models/color_settings.dart`):
    ```dart
    import 'package:hive_ce_flutter/hive_flutter.dart';
    part 'my_model.g.dart';  // Reference generated file
    
    @HiveType(typeId: 42)
    class MyModel {
      @HiveField(0)
      final String field1;
      // ...
    }
    ```

* **When to Regenerate:**
  - After adding/modifying `@HiveType` or `@HiveField` annotations
  - After changing `@JsonSerializable()` models
  - After updating `@CopyWith()` classes
  - Run: `cd src/ui/flutter_app && dart run build_runner build --delete-conflicting-outputs`

* **Common Pitfalls:**
  - ❌ Don't commit `.g.dart` files to git
  - ❌ Don't write manual Hive adapters when annotations exist
  - ❌ Don't forget the `part 'xxx.g.dart';` directive
  - ✅ Do run `./flutter-init.sh` when setting up the project
  - ✅ Do add `@HiveField` annotations when adding new fields
  - ✅ Do increment field indices sequentially for backward compatibility

**Formatting:**
```bash
./format.sh s          # Format without committing
./format.sh            # Format and commit (don't use manually)
```

### Testing

**C++ Unit Tests:**
```bash
cd tests
# Use existing test infrastructure (gtest)
# Add new test files as test_<component>.cpp
```

**Flutter Tests:**
```bash
cd src/ui/flutter_app
flutter test                    # Unit/widget tests
flutter test integration_test/  # Integration tests
```

---

## 8) Testing & Validation

### Test Requirements

For every code change:

* **C++ engine changes:**
  - Add or update unit tests in `tests/test_<component>.cpp`
  - Ensure all existing tests pass: `make test`
* **Flutter UI changes:**
  - Add widget tests for new UI components
  - Verify accessibility (screen readers, keyboard navigation)

### Validation Checklist

Before submitting changes:

- [ ] Code compiles without warnings
- [ ] All unit tests pass
- [ ] Code is properly formatted (`./format.sh s`)
- [ ] Generated files (.g.dart) are NOT committed
- [ ] Part directives for generated files are present if needed
- [ ] No performance regression (if applicable)
- [ ] Commit message follows guidelines

---

## 9) Documentation

### What NOT to Create

* **Do not create new Markdown documents solely to summarize code
  changes**
* Do not create redundant documentation
* Do not document obvious code

---

## 10) Internationalization (i18n)

### Adding/Modifying Strings

1. Add string to `src/ui/flutter_app/lib/l10n/intl_en.arb` (master file)
2. Run localization generation: `flutter gen-l10n`
3. Use string in code via `S.of(context).yourStringKey`
4. Translation to other languages handled separately (Weblate)

### Guidelines

* Use descriptive, context-rich keys
* Avoid concatenating localized strings
* Support plural forms where needed
* Test with longest translations (German, Russian) for layout
* Maintain space between Chinese and English in mixed text

---

## 11) Quick Reference

### Essential Commands

```bash
# Format code (ALWAYS before commit)
./format.sh s

# Build C++ engine
cd src
make build all

# Run C++ tests
cd src
make test

# Initialize Flutter (includes code generation)
./flutter-init.sh

# Regenerate code (after model changes)
cd src/ui/flutter_app
dart run build_runner build --delete-conflicting-outputs

# Run Flutter app
cd src/ui/flutter_app
flutter run

# Run Flutter tests
cd src/ui/flutter_app
flutter test
```

### Key Files

* `src/Makefile` - C++ build configuration
* `src/ui/flutter_app/pubspec.yaml` - Flutter dependencies
* `src/ui/flutter_app/lib/` - Flutter source code
* `src/ui/flutter_app/l10n.yaml` - Localization configuration
* `format.sh` - Code formatting script
* `AGENTS.md` - This file
* `README.md` - User-facing documentation
