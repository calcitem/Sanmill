# AGENT INSTRUCTIONS

This document defines a practical playbook for AI Agents working within
the Sanmill repository. It balances safety with productivity, ensuring
consistent, high-quality contributions.

---

## 1) Purpose & Scope

* Provide consistent guidance for AI Agents (code assistants, automation
  bots).
* Cover planning, execution, safety, testing, and collaboration practices.
* Maintain code quality across Rust/TGF, Flutter/Dart, and build tooling.

---

## 2) Project Context

* **Project Name:** Sanmill
* **Description:** A free, powerful Mill (N Men's Morris) game with Flutter GUI and a native Rust/TGF AI engine.
* **License:** GNU Affero General Public License version 3 (AGPL v3)
* **Primary Goals:**
  - Deliver a high-quality, cross-platform Mill game
  - Provide excellent user experience through Flutter frontend
  - Support multiple platforms: Android, iOS, Windows, macOS, Linux
* **Key Constraints:**
  - AGPL v3 compliance for all code contributions
  - Cross-platform compatibility required
  - Performance-critical AI/search paths (Rust/TGF framework)
  - Mobile-first UI/UX design (Flutter)

### Technology Stack

**Rust / TGF Framework:**
- `crates/tgf-core`: game-neutral traits and POD types
- `crates/tgf-search`: generic monomorphised searchers (PVS, MTD(f), MCTS)
- `crates/tgf-mill`: Mill rules, topology, evaluator, and presets
- `crates/tgf-othello`: second-game pressure test
- `crates/tgf-frb`: Flutter Rust Bridge API surface (`rust_lib_sanmill`)
- See `docs/FRAMEWORK_API.md` for the current API contract

**Frontend (Flutter/Dart):**
- Cross-platform UI (Android, iOS, Windows, macOS, Linux)
- Internationalization (Many languages via ARB files)
- Build system: Flutter CLI, platform-specific tools

**Testing:**
- Rust unit / integration tests: `cargo test --workspace`
- Flutter widget tests and integration tests
- UI automation: Appium
- Monkey testing for stability

All gameplay logic and AI search live in the Rust/TGF stack.

**Build & Automation:**
- Shell scripts for initialization and deployment
- CI/CD: GitHub Actions
- Code formatting: dart format (Dart), cargo fmt/clippy (Rust)

### Project Structure

```
/
├── crates/                    # Rust/TGF workspace
│   ├── tgf-core/              # Game-neutral traits and POD types
│   ├── tgf-search/            # Generic searchers (PVS, MTD(f), MCTS)
│   ├── tgf-mill/              # Mill rules, evaluator, presets
│   ├── tgf-othello/           # Second-game pressure test
│   ├── tgf-frb/               # FRB API surface (rust_lib_sanmill)
│   └── tgf-cli/               # Rust CLI / bench tool
├── src/                       # Source root
│   └── ui/
│       └── flutter_app/      # Flutter frontend (PRIMARY)
│           ├── lib/          # Dart source code
│           ├── l10n.yaml     # Localization config
│           ├── pubspec.yaml  # Flutter dependencies
│           └── android/ios/linux/macos/windows/
├── tests/                    # Integration / UI / perf tests
│   ├── appium/               # UI automation tests
│   ├── golden/               # Golden-image baselines
│   ├── monkey/               # Stability testing
│   └── perf_baseline.toml    # Search perf baseline
├── scripts/                  # Utility scripts
├── fastlane/metadata/        # App store metadata
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
- `dart format` on all Dart/Flutter code
- `cargo fmt --all` on Rust code (when `Cargo.toml` is present)
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`

The `format.sh` script no longer invokes `clang-format`.

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

### General Rules (apply to all languages)

**Error Handling:**
* **Use assertions** (`assert!` / `debug_assert!` in Rust,
  `assert(...)` in Dart) for preconditions and invariants.
* **Avoid fallback mechanisms** that hide errors; prefer fail-fast
  behavior so root causes surface immediately during development.
* Errors should be surfaced rather than masked with default values.

**Code Extension:**
* **Modify existing functions directly** rather than creating wrapper
  functions whose only purpose is to intercept calls.
* **Avoid "Enhanced" / "Extended" class names** (e.g., no
  `EnhancedSearch`); prefer editing the original implementation.

The remaining native code (small iOS / macOS / Android Runner shims)
follows the conventions of the corresponding platform tooling and
is rarely touched.

### Rust/TGF Specific Rules

**Architecture:**
* Keep `tgf-core` and `tgf-search` game-neutral.
* Concrete games belong in `crates/tgf-<game_id>/`.
* Search hot paths must use `Searcher<G: Game>`, not `dyn GameRules`.
**Performance:**
* Preserve monomorphised `Game / Workbench / Evaluator` call paths.
* Avoid heap allocation in move generation hot paths unless justified by tests
  or benchmarks.
* The oracle snapshots in `crates/tgf-mill/testdata/legacy_oracle/` provide
  the reference for regression testing; regeneration is no longer possible
  after the C++ engine was removed.

**Style:**
* Follow `cargo fmt` and pass `cargo clippy --workspace --all-targets
  --all-features -- -D warnings`.

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

**Rust / TGF engine:**
```bash
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo run -p tgf-cli -- bench
```

**Flutter App:**
```bash
./flutter-init.sh      # Set up Flutter + Rust/FRB when tools exist
cd src/ui/flutter_app
flutter_rust_bridge_codegen generate
flutter build linux --debug -v      # Linux
flutter run
flutter test
```

**Agentic Flutter debug loop (Flutter 3.44+):**

* When a debug `flutter run` session is already active, prefer using any
  available Flutter/Dart MCP or Dart Tooling Daemon (DTD) integration to
  inspect the running app, read widget/tree state, and trigger hot reload after
  Dart-only edits.
* If no MCP/DTD bridge is available in the current environment, keep the
  `flutter run` process alive and send `r` for hot reload or `R` for hot
  restart instead of stopping and rebuilding for every UI tweak.
* Do not rely on hot reload after native, generated-code, dependency, asset,
  platform, or Rust/FRB boundary changes. Re-run `./flutter-init.sh` and the
  relevant `flutter build ...` command for those changes.
* Treat hot reload as a fast feedback loop, not final validation. Before
  finishing Flutter work, still run `flutter analyze`, focused tests, and the
  relevant platform build.

**Code Generation:**

The project uses code generation for several purposes. Understanding this
is critical to avoid common mistakes.

* **Generated Files (*.g.dart):**
  - Files with `.g.dart` extension are auto-generated by build_runner
  - These files are gitignored (matched by `*generated*` pattern)
  - They exist only in local development environments
  - Never manually create or edit `.g.dart` files
  - Always run `./flutter-init.sh` after cloning or when dependencies change

* **FRB Generated Files (`lib/src/rust/frb_generated*.dart`):**
  - These files are auto-generated by `flutter_rust_bridge_codegen generate`
  - They are intentionally committed, because Flutter builds need the loader
    with the correct native library stem (`rust_lib_sanmill`)
  - Do not edit them manually; regenerate after Rust FRB API changes

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
  - Run: `cd src/ui/flutter_app && dart run build_runner build`

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

**Rust unit tests:**
```bash
cargo test --workspace
cargo test -p rust_lib_sanmill --lib -- --ignored random_walk_extended
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

* **Rust engine changes:**
  - Add or update unit tests in `crates/tgf-*/src/`
  - Ensure all existing tests pass: `cargo test --workspace`
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

### Puzzle Format Documentation

* Refer to `docs/PUZZLE_FORMAT.md` for the current puzzle JSON format
 specification
* Version 1.0 format uses structured `PuzzleSolution` and `PuzzleMove`
 objects with explicit side-to-move information

### Rust module organisation conventions

To keep individual files reviewable and to make the repo easy to
navigate, follow these rules when a module crosses ~1k lines or
needs new sibling helpers:

* **Single-file module → directory:** when adding a sibling that
 belongs to the same module, convert `foo.rs` to `foo/mod.rs` and
 add the sibling as `foo/<sibling>.rs`.  Existing examples:
 `crates/tgf-mill/src/rules/`, `crates/tgf-cli/src/mill_uci/`,
 `crates/tgf-search/src/searcher/`, `crates/tgf-othello/src/`.
* **Tests next to a single-file module:** if the module is still a
 flat `foo.rs` (e.g. `crates/tgf-frb/src/api/simple.rs`) and the
 inline `#[cfg(test)] mod tests { … }` block is large, hoist the
 tests into a sibling `foo_tests.rs` and reference it via:

 ```rust
 #[cfg(test)]
 #[path = "foo_tests.rs"]
 mod tests;
 ```

 The trailing `_tests.rs` suffix and the `#[path]` attribute are
 the convention; do not invent variants.
* **Tests inside a directory module:** when the module is already a
 `foo/` directory, host the test file as `foo/tests.rs` and pull
 it in with `#[cfg(test)] mod tests;` from `foo/mod.rs`.  Do not
 use `#[path]` in this shape — the regular module declaration is
 the convention.
* **Cross-module helpers:** prefer `pub(super)` over `pub(crate)`
 unless the helper is truly used outside the immediate parent
 module.  This keeps the crate-wide grep noise low and makes it
 obvious where sibling files draw their dependencies from.

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
# Format/check code (ALWAYS before commit)
./format.sh s

# Build Rust engine
cargo build --workspace --release

# Run Rust/TGF tests + benchmarks
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings

# Initialize Flutter + Rust/FRB (includes code generation)
./flutter-init.sh

# Regenerate code (after model changes)
cd src/ui/flutter_app
dart run build_runner build

# Run Flutter app
cd src/ui/flutter_app
flutter run

# Run Flutter tests
cd src/ui/flutter_app
flutter test
```

### Key Files

* `src/ui/flutter_app/pubspec.yaml` - Flutter dependencies
* `src/ui/flutter_app/lib/` - Flutter source code
* `src/ui/flutter_app/l10n.yaml` - Localization configuration
* `format.sh` - Code formatting/check script (Dart, Rust fmt/clippy)
* `AGENTS.md` - This file
* `docs/FRAMEWORK_API.md` - Rust/TGF framework API contract
* `README.md` - User-facing documentation
