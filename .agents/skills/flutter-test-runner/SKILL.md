---
name: flutter-test-runner
description: Select, run, or diagnose Sanmill Flutter tests and coverage. Use for Flutter validation tasks, not Rust-only tests or prose changes.
---

# Flutter Test Runner

Choose the runner for the affected behavior. The directory name alone does
not establish whether a test needs native code or a device.

## Runner selection

| Test type | Requirements | Typical location |
| --- | --- | --- |
| Pure Dart / widget | Initialized Flutter dependencies and appropriate plugin fakes | `src/ui/flutter_app/test/` |
| Host FFI | Host `rust_lib_sanmill` debug library and matching generated FRB bindings | FFI and capture-scenario tests under `test/` |
| Device integration | A supported connected device or desktop target, native app build, and isolated test data | `integration_test/` |

Inspect the selected test's setup and skip conditions. The helper at
`src/ui/flutter_app/test/helpers/test_native_library.dart` can skip native
tests when the host library is missing. A green run with those skips does not
validate the Rust/FRB path.

Examples below start at the repository root and use Bash / Git Bash.
Subshells keep each example's working directory independent.

```bash
# Focused pure Dart/widget test; substitute the affected file.
(cd src/ui/flutter_app && flutter test test/game/game_controller_test.dart)

# Host FFI test: build the native library first.
cargo build -p rust_lib_sanmill
(cd src/ui/flutter_app && flutter test test/games/mill/native_mill_rules_port_ffi_test.dart)

# Capture-scenario batch on the host VM.
./run-integration-test.sh --single
./run-integration-test.sh --full

# Unit/widget/host test suite when the change requires broad coverage.
(cd src/ui/flutter_app && flutter test)
```

For device validation, choose an available target rather than assuming Linux:

```bash
(cd src/ui/flutter_app && flutter devices)
(cd src/ui/flutter_app && flutter test integration_test/ai_hang_smoke_test.dart -d <device-id>)
./tests/monkey/smart-monkey.sh <device-id>
```

Run monkey or whole-device suites when stability or the affected platform path
requires them. Verify their storage and account isolation before running;
do not clear a user's installed app or real saves to obtain clean fixtures.

## Failure diagnosis and completion

- For missing generated output or dependencies, use the relevant initialization
  or generation instructions in [AGENTS.md](../../../AGENTS.md).
- For `MissingPluginException`, inspect plugin registration, mocking, and the
  intended runner. It does not by itself mean the test belongs in
  `integration_test/`.
- For import failures, check paths and dependency resolution first. Use
  `flutter clean` only when evidence points to stale build artifacts.
- For AI differences, align rules, seeds, options, and native binaries and
  explain the discrepancy before changing expectations. Do not bless a new
  sequence simply because the old test failed.
- For timeouts, inspect asynchronous completion and cancellation. Increase a
  timeout only with evidence that the expected workload needs it.
- For a requested fix, repair failures caused by the change and rerun affected
  tests without a new confirmation gate. For an audit-only request, report
  findings and continue independent checks.
- If a device or prerequisite cannot be obtained within scope, record the
  precise gap and complete other checks. Do not treat skips as passes.

The project-wide validation and commit requirements are in AGENTS.md. Running
this Skill does not add a requirement to run every integration test before
every commit.

## Coverage

When coverage is requested or needed to evaluate new behavior:

```bash
(cd src/ui/flutter_app && flutter test --coverage)
(cd src/ui/flutter_app && lcov --summary coverage/lcov.info)
(cd src/ui/flutter_app && genhtml coverage/lcov.info -o coverage/html)
```

Project coverage targets remain overall >=80%, critical logic >=90%, and UI
>=70%. State the metric, included files, and exclusions when reporting them;
identify any enforced CI gate separately. These targets do not require turning
an ordinary focused test run into an unrelated whole-project coverage repair.

Report commands, pass/fail/skip counts, relevant failures, elapsed time, and
coverage if collected. State which native and platform paths were exercised.
