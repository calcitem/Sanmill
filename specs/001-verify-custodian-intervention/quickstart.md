# Quickstart: Custodian and Intervention Rule Verification

**Date**: 2025-10-06
**Feature**: Verify Custodian and Intervention Rule Implementation
**Phase**: 1 - Design & Contracts

## Quick Test Execution

### Run All Tests

```bash
cd /home/user/Sanmill/src/ui/flutter_app

# Run all unit tests with coverage
flutter test --coverage test/game/custodian_rule_test.dart
flutter test --coverage test/game/intervention_rule_test.dart
flutter test --coverage test/game/mill_custodian_combo_test.dart
flutter test --coverage test/game/mill_intervention_combo_test.dart
flutter test --coverage test/game/triple_combo_test.dart
flutter test --coverage test/game/may_remove_multiple_test.dart
flutter test --coverage test/game/fen_notation_test.dart
flutter test --coverage test/game/move_legality_test.dart

# Run integration tests
flutter test integration_test/custodian_intervention_e2e_test.dart

# Generate coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html  # View coverage in browser
```

### Run Specific Test Group

```bash
# Test only custodian standalone rules (FR-001 to FR-004)
flutter test test/game/custodian_rule_test.dart

# Test only FEN notation (FR-021 to FR-027, FR-034, FR-035, FR-039)
flutter test test/game/fen_notation_test.dart

# Run with verbose output
flutter test --reporter expanded test/game/custodian_rule_test.dart
```

### Run Single Test Case

```bash
# Run specific test by name pattern
flutter test --name "FR-001" test/game/custodian_rule_test.dart

# Run test with debugging enabled
flutter test --start-paused test/game/custodian_rule_test.dart
```

## Manual Verification Steps

### Step 1: Verify Custodian Rule (FR-001 to FR-004)

**Setup**:
1. Launch Sanmill app
2. Start new game with custodian rule enabled
3. Set up position: Place White at a4 and c4 (endpoints), Black at b4 (middle)

**Expected**:
- Custodian capture triggers
- Only b4 (sandwiched piece) is selectable
- Attempting to select other Black pieces shows error
- Can capture from Black's mill if b4 is in one

**Pass Criteria**: All 4 expected behaviors confirmed

---

### Step 2: Verify Intervention Rule (FR-005 to FR-009)

**Setup**:
1. New game with intervention rule enabled
2. Set up position: Place Black at a4 and c4 (endpoints), White at b4 (center)

**Expected**:
- Intervention capture triggers
- Both a4 and c4 are selectable (endpoints)
- After selecting a4, must select c4 (forced second capture on same line)
- Attempting other selections shows error
- Can capture from Black's mill if endpoints are in one

**Pass Criteria**: All 5 expected behaviors confirmed

---

### Step 3: Verify Mill + Custodian Combo (FR-010 to FR-013)

**Setup**:
1. New game with both mill and custodian enabled
2. Form a mill AND trigger custodian on same move
3. Test both selection orders

**Test 3a - Custodian First**:
- Select custodian target (sandwiched piece)
- Verify mill captures are blocked
- Verify only 1 capture occurs (the custodian target)

**Test 3b - Mill First**:
- Select mill target (not custodian target)
- Verify custodian opportunity is lost
- Verify remaining mill captures allowed (if any)
- Verify pieceToRemoveCount reflects only mill captures

**Pass Criteria**: Both selection orders behave correctly per FR-010 to FR-013

---

### Step 4: Verify mayRemoveMultiple=false Mode (FR-036 to FR-038)

**Setup**:
1. Configure mayRemoveMultiple=false
2. Form multiple mills on one move

**Expected**:
- Only 1 capture allowed (first mill only)
- Additional mills ignored

**With Custodian/Intervention Available**:
- Player can choose custodian/intervention instead of mill
- If intervention chosen: Still requires 2 captures (endpoints)
- If custodian chosen: Only 1 capture

**Pass Criteria**: mayRemoveMultiple=false honored, intervention still takes 2

---

### Step 5: Verify FEN Notation (FR-021 to FR-027, FR-034, FR-035, FR-039)

**Test 5a - Export with Custodian**:
1. Trigger custodian capture
2. Export position to FEN
3. Verify FEN contains "c:a1" (example square)
4. Verify "p:1" marker present

**Test 5b - Import with Intervention**:
1. Prepare FEN: "position... i:a4,c4 p:2 w 10"
2. Import FEN
3. Verify intervention state restored
4. Verify both endpoints selectable

**Test 5c - Round-Trip**:
1. Export position to FEN
2. Import that FEN
3. Export again
4. Verify FEN strings match (FR-027)

**Test 5d - Invalid FEN**:
1. Prepare FEN with missing target: "position... c:z9 p:1 w 10"
2. Attempt import
3. Verify rejection with error (FR-035)

**Test 5e - Conflicting Markers**:
1. Prepare FEN: "position... c:a1 i:b1,c1 p:3 w 10"
2. Import FEN
3. Verify both captured states active (FR-034)
4. Verify player can choose which to apply

**Pass Criteria**: All FEN import/export scenarios work correctly

---

### Step 6: Verify Move Legality (FR-028 to FR-031)

**Test 6a - Custodian Legality**:
1. Trigger custodian
2. Attempt to capture non-target piece
3. Verify move rejected with clear error

**Test 6b - Intervention Legality**:
1. Trigger intervention
2. Select first endpoint
3. Attempt to capture non-endpoint piece for second capture
4. Verify move rejected

**Test 6c - Capture Mode Violations**:
1. Trigger mill + custodian
2. Select custodian target first
3. Attempt mill capture after
4. Verify move rejected (mode locked to custodian)

**Pass Criteria**: All illegal moves properly rejected

---

## Acceptance Criteria

### Coverage Goals
- Unit test coverage: ≥95% for position.dart, mill.dart, import_service.dart
- Integration test coverage: ≥80% for tap_handler.dart
- All 39 functional requirements have passing tests

### Performance Goals
- Each test case completes in <100ms
- Full test suite completes in <5 minutes
- Rule checking logic <10ms per move

### Quality Gates
- Zero test failures
- Zero linter warnings (`flutter analyze`)
- All edge cases from spec covered
- FEN round-trip consistency validated

## Test Data Sources

### Test Scenarios
- YAML files in `test-scenarios/` directory
- Each YAML maps to specific FR requirements
- Load scenarios dynamically in Dart tests

### FEN Strings
- Inline in test code for readability
- Named constants for reusability
- Comments explain board setup

### Expected Outcomes
- Defined in YAML `expected` sections
- Validated via `expect()` assertions in Dart

## Debugging Failed Tests

### View Test Output
```bash
flutter test --reporter expanded > test_output.log
grep "FAILED" test_output.log
```

### Run Single Failing Test with Debugger
```bash
flutter test --start-paused test/game/custodian_rule_test.dart
# Attach debugger in VS Code
# Set breakpoints in test file
```

### Check Coverage Gaps
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
# Open coverage/html/index.html
# Check red (uncovered) lines in position.dart, mill.dart
```

### Verify FEN Parsing
```bash
# Add print statements in import_service.dart
flutter test test/game/fen_notation_test.dart
# Check console output for FEN parsing details
```

## Common Issues

### Issue: Test flakiness on different platforms
**Solution**: Ensure deterministic test data, avoid timing dependencies

### Issue: FEN parsing errors
**Solution**: Validate FEN format matches spec, check marker syntax (c:, i:, p:)

### Issue: Coverage below 95%
**Solution**: Add edge case tests, test error paths, test boundary conditions

### Issue: Long test execution time
**Solution**: Run tests in parallel, profile slow tests, optimize FEN parsing

---

## Next Steps After Verification

1. **If tests pass**: Document results, close verification task
2. **If tests fail**: Create bug tickets for each failure, link to specific FR
3. **If coverage gaps**: Add missing test cases, re-run coverage
4. **If performance issues**: Profile slow code, optimize hot paths

---

*Quickstart guide complete. Ready for task generation (Phase 2).*
