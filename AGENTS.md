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

### Naming Conventions

**C++ Engine** (`src/`):
- **Classes/Structs**: PascalCase (Position, SearchEngine, Rule)
- **Functions/Methods**: snake_case (do_move, side_to_move, is_ok)
- **Constants**: UPPER_SNAKE_CASE (MAX_MOVES, VALUE_INFINITE, SQ_NB)
- **Variables**: camelCase (rootPos, bestMove, pieceCount)
- **Namespaces**: PascalCase (Search, Evaluate)
- **Enums**: PascalCase (Color, Phase, Action)
- **Enum Values**: UPPER_SNAKE_CASE or camelCase (MOVE_NONE, WHITE)

**Dart/Flutter** (`src/ui/flutter_app/lib/`):
- **Classes**: PascalCase (GameController, Position)
- **Methods**: camelCase (doMove, sideToMove)
- **Constants**: lowerCamelCase (maxMoves) or UPPER_SNAKE_CASE (MAX_DEPTH)
- **Variables**: camelCase (rootPosition, bestMove)
- **Files**: snake_case (game_controller.dart, rule_settings.dart)

**Cross-Language Mapping**:

| C++ | Dart | Note |
|-----|------|------|
| `do_move()` | `doMove()` | snake_case → camelCase |
| `side_to_move()` | `sideToMove` | getter in Dart (no parens) |
| `Position` | `Position` | Same name, different implementations |
| `SearchEngine` | `Engine` | Different abstraction levels |
| `MAX_MOVES` | `maxMoves` | Different conventions |

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

**Comments:**
* Use Doxygen-style comments for public APIs (`///` or `//!`)
* Use regular comments for implementation details (`//`)

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
- [ ] No performance regression (if applicable)
- [ ] Commit message follows guidelines

---

## 9) C++ Engine Documentation

### Essential Reading for C++ Development

The C++ engine has comprehensive documentation in `src/docs/`.
**AI Agents must read these documents before making changes to C++ code.**

### Core Architecture Documents

**1. CPP_ARCHITECTURE.md** (`src/docs/CPP_ARCHITECTURE.md`)
* Complete engine architecture overview
* Design philosophy and core principles
* Layer-by-layer component breakdown
* Data flow and performance characteristics
* Thread model and integration points
* **Read this first** to understand the engine

**2. CPP_COMPONENTS.md** (`src/docs/CPP_COMPONENTS.md`)
* Comprehensive catalog of 40+ components
* Component purposes and responsibilities
* Public API summaries for each component
* Dependency graphs and usage patterns
* **Check here before modifying components**

**3. UCI_PROTOCOL.md** (`src/docs/UCI_PROTOCOL.md`)
* Complete UCI protocol specification
* All commands with syntax and examples
* Mill-specific FEN format
* Move notation and score formats
* Engine options reference
* **Essential for engine-GUI communication**

### Development Guidelines

**4. CPP_WORKFLOWS.md** (`src/docs/CPP_WORKFLOWS.md`)
* Step-by-step workflows for common tasks
* 8 detailed workflows including:
  - Adding new search algorithm
  - Modifying evaluation function
  - Adding UCI command
  - Optimizing performance bottleneck
  - Adding engine option
  - Fixing search bugs
  - Adding opening book moves
  - Implementing new rule variant
* **Follow these workflows for consistency**

**5. RULE_SYSTEM_GUIDE.md** (`src/docs/RULE_SYSTEM_GUIDE.md`)
* Complete Rule structure reference (30+ fields)
* Field-by-field documentation
* Predefined rule variants
* Step-by-step guide to adding new variants
* C++ ↔ Flutter parameter mapping
* **Essential for rule-related changes**

### API Documentation

**6. API Reference** (`src/docs/api/`)
* **Position.md**: Position class API (100+ methods)
* **SearchEngine.md**: Search coordinator API
* **Search.md**: Search algorithms API
* Additional component APIs (planned)
* **Consult before modifying public APIs**

### Troubleshooting and Examples

**7. TROUBLESHOOTING.md** (`src/docs/TROUBLESHOOTING.md`)
* Common compilation errors
* Runtime error diagnosis
* Search problems and solutions
* Performance issue debugging
* **Check here when encountering issues**

**8. examples/** (`src/docs/examples/`)
* `basic_search.cpp` - Basic search usage
* `position_manipulation.cpp` - Position operations
* **Reference for correct API usage**

### AI Agent Workflow for C++ Changes

When making C++ changes:

1. **Read** relevant architecture docs first
2. **Check** CPP_COMPONENTS.md for component overview
3. **Follow** appropriate workflow from CPP_WORKFLOWS.md
4. **Consult** API documentation for method usage
5. **Run** tests after changes
6. **Update** documentation if API changes

---

## 10) Flutter Application Documentation

### Essential Reading for Flutter Development

The Flutter application has comprehensive documentation in
`src/ui/flutter_app/docs/`. **AI Agents must read these documents
before making changes to Flutter code.**

### Core Architecture Documents

**1. ARCHITECTURE.md** (`src/ui/flutter_app/docs/ARCHITECTURE.md`)
* System architecture overview
* Technology stack details
* Directory structure explained
* Architectural layers and patterns
* **Read this first** to understand the system

**2. COMPONENTS.md** (`src/ui/flutter_app/docs/COMPONENTS.md`)
* Comprehensive catalog of all reusable components
* Component location, purpose, and dependencies
* Public API reference for each component
* **Check here before creating new components** to avoid duplication

**3. STATE_MANAGEMENT.md** (`src/ui/flutter_app/docs/STATE_MANAGEMENT.md`)
* Complete guide to state management patterns
* Database usage (Hive)
* ValueNotifier patterns
* GameController state
* **Essential for understanding data flow**

### Development Guidelines

**4. WORKFLOWS.md** (`src/ui/flutter_app/docs/WORKFLOWS.md`)
* "Golden Paths" for common development tasks
* 10 detailed workflows including:
  - Adding new UI features
  - Fixing bugs
  - Adding settings
  - Creating custom painters
  - Performance optimization
* **Follow these workflows for consistency**

**5. BEST_PRACTICES.md** (`src/ui/flutter_app/docs/BEST_PRACTICES.md`)
* Code quality standards
* Widget design patterns
* Performance optimization
* Accessibility requirements
* Testing guidelines
* **Code must adhere to these standards**

### API Documentation

**6. API Reference** (`src/ui/flutter_app/docs/api/`)
* **GameController.md**: Core game controller API
* **Engine.md**: AI engine interface
* **Position.md**: Board state management
* Additional component APIs
* **Consult before modifying public APIs**

### Getting Started

**7. GETTING_STARTED.md** (`src/ui/flutter_app/docs/GETTING_STARTED.md`)
* Developer onboarding guide
* Environment setup instructions
* First contribution walkthrough
* **Recommended for new contributors**

**8. DOCUMENTATION_GUIDE.md**
(`src/ui/flutter_app/docs/DOCUMENTATION_GUIDE.md`)
* How to maintain documentation
* When to update docs
* Documentation standards
* **Update docs alongside code changes**

### AI Agent Workflow for Flutter Changes

When making Flutter changes:

1. **Read** relevant architecture docs first
2. **Check** COMPONENTS.md for existing components
3. **Follow** appropriate workflow from WORKFLOWS.md
4. **Apply** standards from BEST_PRACTICES.md
5. **Update** documentation if API changes
6. **Test** as specified in documentation

### Documentation as SDK

**Critical Concept:** For AI agents, documentation is the SDK. Poor
documentation leads to incorrect code generation. Always:

* Verify documentation matches current code
* Update documentation when changing public APIs
* Add examples for complex functionality
* Cross-reference related components

---

## 11) General Documentation Guidelines

### What NOT to Create

* **Do not create new Markdown documents solely to summarize code
  changes**
* Do not create redundant documentation
* Do not document obvious code

### What TO Update

* API documentation when changing public interfaces
* COMPONENTS.md when adding new components
* WORKFLOWS.md when establishing new processes
* Inline code documentation (docstrings) for all public APIs

---

## 12) Internationalization (i18n)

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

## 13) Quick Reference

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

# Initialize Flutter
./flutter-init.sh

# Run Flutter app
cd src/ui/flutter_app
flutter run

# Run Flutter tests
cd src/ui/flutter_app
flutter test
```

### Key Files

**C++ Engine:**
* `src/Makefile` - C++ build configuration
* `src/*.cpp, src/*.h` - Core engine source files
* `tests/test_*.cpp` - C++ unit tests
* `src/docs/` - **C++ engine documentation (NEW!)**
  - `CPP_ARCHITECTURE.md` - Engine architecture overview
  - `CPP_COMPONENTS.md` - Component catalog (40+ components)
  - `UCI_PROTOCOL.md` - UCI protocol specification
  - `RULE_SYSTEM_GUIDE.md` - Complete rule system guide
  - `CPP_WORKFLOWS.md` - Development workflows (8 workflows)
  - `TROUBLESHOOTING.md` - Common issues and solutions
  - `api/Position.md` - Position class API reference
  - `api/SearchEngine.md` - SearchEngine class API reference
  - `api/Search.md` - Search algorithms API reference
  - `examples/` - Code examples

**Flutter Application:**
* `src/ui/flutter_app/pubspec.yaml` - Flutter dependencies
* `src/ui/flutter_app/lib/` - Flutter source code
* `src/ui/flutter_app/l10n.yaml` - Localization configuration
* `src/ui/flutter_app/docs/` - **Flutter app documentation**
  - `ARCHITECTURE.md` - System architecture
  - `COMPONENTS.md` - Component catalog
  - `WORKFLOWS.md` - Development workflows
  - `BEST_PRACTICES.md` - Code standards
  - `STATE_MANAGEMENT.md` - State management guide
  - `api/` - Widget API documentation

**Build & Deployment:**
* `format.sh` - Code formatting script
* `flutter-init.sh` - Flutter setup script
* `.github/workflows/` - CI/CD pipelines

**Project Documentation:**
* `AGENTS.md` - This file (AI agent guidelines)
* `README.md` - User-facing documentation
* `CONTRIBUTING.md` - Contribution guidelines
* `docs/` - **Project documentation**
  - `MAINTENANCE_GUIDE.md` - Maintenance phase development guide
  - `AI_CONTEXT_GUIDE.md` - AI assistant context guide
  - `guides/ADDING_NEW_GAME_RULES.md` - Rule addition guide
