# Research: Custodian and Intervention Rule Verification

**Date**: 2025-10-06
**Feature**: Verify Custodian and Intervention Rule Implementation
**Phase**: 0 - Research & Analysis

## Overview

This document captures research findings for verifying the custodian and intervention capture rule implementation in Sanmill. The implementation already exists in position.cpp, position.dart, movegen.cpp, and related files. This verification task ensures correctness across 39 functional requirements.

## Technical Decisions

### Decision 1: Test Framework Selection

**Chosen**: Dart `test` package for unit tests, `integration_test` for E2E
**Rationale**:
- Existing Sanmill test infrastructure uses these frameworks
- Dart tests can validate both Dart UI logic and C++ engine behavior via FFI
- Integration tests provide end-to-end validation across UI and engine layers
- No need for separate C++ test framework unless Dart tests reveal engine-specific issues

**Alternatives Considered**:
- Google Test for C++ engine testing: Deferred until Dart tests identify C++-specific bugs
- Manual testing only: Rejected - 39 FRs require automated regression prevention

### Decision 2: Test Organization Strategy

**Chosen**: Organize tests by functional requirement groups (8 test files for 39 FRs)
**Rationale**:
- Maps directly to spec structure (custodian standalone, intervention standalone, combinations, etc.)
- Each file has clear scope (4-9 related FRs)
- Easier to maintain and locate tests for specific requirements
- Aligns with TDD principle of traceable test-to-requirement mapping

**Alternatives Considered**:
- One monolithic test file: Rejected - too large, hard to navigate
- One file per FR: Rejected - 39 files excessive for related functionality
- Group by implementation file (position_test.dart, movegen_test.dart): Rejected - cuts across functional requirements

### Decision 3: FEN Test Data Strategy

**Chosen**: Inline FEN strings in test cases with descriptive constants
**Rationale**:
- FEN notation is compact and human-readable for Nine Men's Morris
- Keeps test data close to assertions for clarity
- Example: `const fenCustodianTriggered = "position c:a1 p:1 ..."`
- Allows easy modification and debugging of specific scenarios

**Alternatives Considered**:
- External FEN files: Rejected - adds indirection, harder to debug
- Programmatic board setup: Rejected - less portable, harder to share test cases

### Decision 4: Coverage Measurement Approach

**Chosen**: Use `flutter test --coverage` with 95% target for rule logic paths
**Rationale**:
- Built into Flutter tooling
- Constitution requires 95% coverage for critical game logic
- Focus coverage on position.dart, mill.dart, import_service.dart (rule implementation)
- UI layer (tap_handler.dart) can have lower coverage if needed

**Alternatives Considered**:
- 100% coverage target: Rejected - unrealistic for defensive error handling branches
- Line coverage only: Rejected - branch coverage important for rule combinations

### Decision 5: Test Execution Order and Dependencies

**Chosen**: Independent test cases with no inter-test dependencies
**Rationale**:
- Each test creates its own game position from FEN
- Tests can run in parallel for speed
- Failures isolated to specific scenarios
- Aligns with TDD best practices

**Alternatives Considered**:
- Sequential tests building on previous state: Rejected - brittle, hard to debug failures
- Shared test fixtures: Only for common FEN parsing utilities, not game state

## Best Practices

### Dart/Flutter Testing
- Use `setUp()` for common test initialization (game engine instance)
- Use `group()` to organize related test cases
- Use descriptive test names matching FR numbers: `test('FR-001: Identify custodian capture', () {})`
- Use `expect()` with explicit matchers for clear failure messages
- Mock time-dependent operations if needed for performance tests

### FEN Notation Testing
- Validate FEN round-trip: export(import(fen)) == fen (FR-027)
- Test both valid and invalid FEN inputs (FR-035)
- Include edge cases: empty boards, full boards, mid-sequence states (FR-025)
- Test all marker combinations: `c:`, `i:`, `p:`, `c:i:` simultaneous (FR-034)

### Rule Combination Testing
- Test all pairwise combinations: custodian+mill, intervention+mill, custodian+intervention
- Test triple combination: custodian+intervention+mill (FR-032, FR-033)
- Test with mayRemoveMultiple=true and =false modes (FR-018 to FR-020, FR-036 to FR-038)
- Verify capture sequence state transitions (first capture determines mode)

### Performance Testing
- Use `Stopwatch` to measure rule checking duration
- Target <10ms per move for rule validation
- Profile if tests reveal performance regressions
- Focus on movegen.cpp logic (move generation with capture rules)

## Implementation Patterns

### Pattern 1: FEN-Based Test Case

```dart
test('FR-001: Identify custodian capture at line endpoint', () {
  const fen = 'position ... c:a1 p:1'; // FEN with custodian marker
  final game = Game.fromFEN(fen);

  expect(game.hasCustodianCapture, isTrue);
  expect(game.custodianTarget, equals(Square.a1));
});
```

### Pattern 2: Rule Combination Test

```dart
test('FR-010: Player chooses between mill and custodian', () {
  const fen = 'position ... millat:a1-b1-c1 c:d1 p:2'; // Both triggered
  final game = Game.fromFEN(fen);

  // Player can select either mill target or custodian target
  expect(game.isLegalCapture(Square.a1), isTrue); // Mill piece
  expect(game.isLegalCapture(Square.d1), isTrue); // Custodian piece
});
```

### Pattern 3: Move Legality Validation

```dart
test('FR-028: Reject non-custodian target when custodian active', () {
  const fen = 'position ... c:a1 p:1';
  final game = Game.fromFEN(fen);

  game.selectCaptureTarget(Square.b1); // Not the custodian target
  expect(game.lastMoveWasIllegal, isTrue);
});
```

### Pattern 4: FEN Round-Trip

```dart
test('FR-027: FEN round-trip consistency', () {
  const originalFEN = 'position ... c:a1 i:b1,c1 p:3';
  final game = Game.fromFEN(originalFEN);
  final exportedFEN = game.toFEN();

  expect(exportedFEN, equals(originalFEN));
});
```

## Known Constraints

1. **Backward Compatibility**: FEN format must remain compatible with existing saved games
2. **No Regression**: Existing mill-only logic must not break
3. **Cross-Platform**: Tests must pass on Android, iOS, Windows, macOS
4. **Performance**: Test suite must complete in <5 minutes (50-80 test cases)

## Existing Test Infrastructure

**Integration Tests** (already implemented in `integration_test/automated_move_test_data.dart`):
- **23 existing test cases** in `custodianCaptureAndInterventionCaptureTestConfig`
- Covers: intervention capture, custodian capture, mill combinations, multi-capture sequences
- Test cases include:
  - `movingWhiteInterventionWin` - Moving phase, intervention + mill
  - `movingBlackMillCapture` - Intervention captures piece in mill
  - `placingWhiteCustodian` - Custodian capture during placing phase
  - `movingWhiteCustodianMill` - Custodian + mill combination
  - `placingWhiteDoubleCustodian` - Multiple custodian captures
  - And 18 more covering various scenarios

**Test Infrastructure** (`automated_move_test_runner.dart`):
- Automated move execution and validation framework
- Real AI engine integration for end-to-end testing
- Sequence validation (expected/unexpected capture sequences)
- 30-second timeout for comprehensive tests

## Testing Dependencies

- `package:test` (Dart unit testing framework)
- `package:integration_test` (Flutter E2E testing) - ✅ **Already in use**
- `package:flutter_test` (Flutter widget testing utilities)
- Existing Sanmill game engine (via FFI to C++)
- **Existing automated test infrastructure** - ✅ **23 test cases already implemented**

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| C++ engine bugs not caught by Dart tests | High | Add C++ unit tests if Dart tests fail at engine boundary |
| FEN format ambiguity | Medium | Document FEN spec in test-scenarios/ directory |
| Test flakiness on different platforms | Medium | Use deterministic test data, avoid timing dependencies |
| Long test execution time | Low | Run tests in parallel, optimize FEN parsing |

## Next Steps (Phase 1)

1. Create data-model.md documenting game state entities
2. Create test-scenarios/ directory with FEN test cases organized by FR
3. Create quickstart.md with manual test execution instructions
4. Update CLAUDE.md (agent context) with test file locations and patterns

---
*Research complete. Ready for Phase 1: Design & Contracts*
