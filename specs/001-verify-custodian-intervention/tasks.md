# Tasks: Verify Custodian and Intervention Rule Implementation

**Input**: Design documents from `/home/user/Sanmill/specs/001-verify-custodian-intervention/`
**Prerequisites**: plan.md, research.md, data-model.md, quickstart.md

## Execution Strategy

This verification task audits existing 23 integration tests against 39 functional requirements, identifies gaps, and creates missing test coverage. The existing tests in `integration_test/automated_move_test_data.dart` cover ~60% of FRs. New unit tests will fill gaps for FEN notation, move legality, and edge cases.

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions
- Tests: `src/ui/flutter_app/test/game/`
- Integration tests: `src/ui/flutter_app/integration_test/`
- Implementation: `src/ui/flutter_app/lib/game_page/services/`

---

## Phase 3.1: Setup & Baseline

- [ ] T001 Run existing integration test suite to establish baseline
  - Execute: `cd src/ui/flutter_app && flutter test integration_test/automated_move_integration_test.dart`
  - Verify all 23 test cases in `custodianCaptureAndInterventionCaptureTestConfig` execute
  - Document pass/fail status for each test case
  - Create baseline report: `specs/001-verify-custodian-intervention/test-results-baseline.md`

- [ ] T002 Audit existing test coverage against 39 functional requirements
  - Map each of 23 integration test cases to specific FRs they validate
  - Identify covered FRs (estimated ~25/39)
  - Identify uncovered FRs (estimated ~14/39)
  - Document coverage matrix: `specs/001-verify-custodian-intervention/coverage-matrix.md`
  - List: custodian (FR-001-004), intervention (FR-005-009), combos (FR-010-017, FR-032-033), mayRemoveMultiple (FR-018-020, FR-036-038), FEN (FR-021-027, FR-034-035, FR-039), legality (FR-028-031)

---

## Phase 3.2: Gap Filling Tests (Create Missing Coverage)

**CRITICAL: These tests MUST validate existing implementation, not implement new features**

- [ ] T003 [P] Create FEN notation import/export test file
  - File: `src/ui/flutter_app/test/game/fen_notation_test.dart`
  - Coverage: FR-021 to FR-027, FR-034, FR-035, FR-039 (9 FRs)
  - Test cases:
    * FR-021: Export custodian state with `c:w-count-sq|b-count-sq` marker
    * FR-022: Export intervention state with `i:w-count-sq.sq|b-count-sq.sq` marker
    * FR-023: Export pieceToRemoveCount with `p:count` marker
    * FR-024: Import FEN with c:/i:/p: markers and restore state
    * FR-025: Update markers after each remove action in sequence
    * FR-026: Clear markers when sequence complete
    * FR-027: Round-trip consistency (export → import → export == original)
    * FR-034: Accept FEN with both c: and i: simultaneously
    * FR-035: Reject invalid FEN (missing target pieces)
    * FR-039: Export exact pieceToRemoveCount even if exceeds opponent pieces
  - Use correct FEN format from position.cpp: `[board] [side] [phase] [action] [counts] [mills] [halfmove] [fullmove] [c:] [i:] [p:]`

- [ ] T004 [P] Create move legality validation test file
  - File: `src/ui/flutter_app/test/game/move_legality_test.dart`
  - Coverage: FR-028 to FR-031 (4 FRs)
  - Test cases:
    * FR-028: Reject capture of non-custodian piece when custodian active
    * FR-029: Reject capture of non-intervention piece when intervention active
    * FR-030: Reject second intervention capture if not same-line endpoint
    * FR-031: Reject captures violating chosen mode (e.g., mill after custodian selected)
  - Verify `isLegalCapture()` returns false and appropriate error messages

- [ ] T005 [P] Create mayRemoveMultiple=false mode test file (if not covered by existing tests)
  - File: `src/ui/flutter_app/test/game/may_remove_multiple_test.dart`
  - Coverage: FR-018 to FR-020, FR-036 to FR-038 (6 FRs)
  - Test cases:
    * FR-018: pieceToRemoveCount NOT pre-incremented when mayRemoveMultiple=false
    * FR-019: Execute only chosen mode's count
    * FR-020: Respect capture priority throughout sequence
    * FR-036: Only 1 capture when multiple mills + mayRemoveMultiple=false
    * FR-037: Can choose custodian/intervention instead of mill
    * FR-038: Intervention still requires 2 captures under mayRemoveMultiple=false
  - Skip this task if T002 audit shows existing tests cover these FRs

- [ ] T006 [P] Create triple combo test file (custodian + intervention + mill)
  - File: `src/ui/flutter_app/test/game/triple_combo_test.dart`
  - Coverage: FR-032, FR-033 (2 FRs)
  - Test cases:
    * FR-032: Player can choose among all 3 modes when all trigger
    * FR-033: First selection determines active rule (custodian target → custodian rule, intervention target → intervention rule, mill-only target → mill rule)
  - Create board positions where all three rules trigger simultaneously
  - Skip this task if T002 audit shows existing tests cover these FRs

---

## Phase 3.3: Edge Case & Clarification Tests

**Based on 5 clarifications from spec.md**

- [ ] T007 [P] Create clarification-based edge case tests
  - File: `src/ui/flutter_app/test/game/edge_cases_test.dart`
  - Test scenarios from clarifications:
    * Clarification 1: Custodian + intervention simultaneous (player chooses via first selection)
    * Clarification 2: FEN with both c: and i: markers (accept both, player chooses)
    * Clarification 3: FEN with missing target piece (reject as invalid)
    * Clarification 4: mayRemoveMultiple=false + multi-mill (1 capture, unless custodian/intervention chosen)
    * Clarification 5: pieceToRemoveCount exceeds pieces (export exact value)

---

## Phase 3.4: Integration & Validation

- [ ] T008 Run full test suite with coverage
  - Execute: `cd src/ui/flutter_app && flutter test --coverage test/game/`
  - Generate coverage report: `genhtml coverage/lcov.info -o coverage/html`
  - Verify 95% coverage on:
    * `lib/game_page/services/engine/position.dart`
    * `lib/game_page/services/mill.dart`
    * `lib/game_page/services/import_export/import_service.dart`
  - Document coverage results in `specs/001-verify-custodian-intervention/coverage-report.md`

- [ ] T009 Validate all 39 functional requirements have passing tests
  - Cross-reference coverage-matrix.md with test results
  - Ensure each of 39 FRs maps to at least one passing test
  - Document any remaining gaps
  - Update `specs/001-verify-custodian-intervention/fr-validation-matrix.md`

- [ ] T010 Run performance benchmarks
  - Measure rule checking performance (<10ms per move target)
  - Measure FEN parsing performance
  - Measure test suite execution time (<5 minutes target)
  - Document results in `specs/001-verify-custodian-intervention/performance-results.md`

---

## Phase 3.5: Bug Fixes (Conditional - Only if Tests Fail)

**These tasks are created ONLY if T001-T009 reveal bugs**

- [ ] T011 [IF NEEDED] Fix bug: [Description]
  - File: `[affected file path]`
  - Issue: [specific bug from test failure]
  - FR affected: [FR number]
  - Fix: [description of fix]

- [ ] T012 [IF NEEDED] Fix bug: [Description]
  - File: `[affected file path]`
  - Issue: [specific bug from test failure]
  - FR affected: [FR number]
  - Fix: [description of fix]

*Additional bug fix tasks added as needed based on test failures*

---

## Dependencies

**Sequential Dependencies**:
- T001 (baseline) must complete before T002 (audit)
- T002 (audit) must complete before T003-T007 (know what gaps to fill)
- T003-T007 (new tests) must complete before T008 (coverage)
- T008 (coverage) must complete before T009 (validation)
- T009 (validation) must complete before T010 (benchmarks)
- T001-T010 must complete before T011+ (bug fixes based on failures)

**Parallel Opportunities**:
- T003, T004, T005, T006, T007 can run in parallel (different files, no shared state)

---

## Parallel Execution Example

```bash
# After T002 audit is complete, run these in parallel:
cd src/ui/flutter_app

# Terminal 1: FEN notation tests
flutter test test/game/fen_notation_test.dart &

# Terminal 2: Move legality tests
flutter test test/game/move_legality_test.dart &

# Terminal 3: mayRemoveMultiple tests (if needed)
flutter test test/game/may_remove_multiple_test.dart &

# Terminal 4: Triple combo tests (if needed)
flutter test test/game/triple_combo_test.dart &

# Terminal 5: Edge case tests
flutter test test/game/edge_cases_test.dart &

# Wait for all to complete
wait
```

---

## Notes

- **Existing Tests**: 23 integration tests in `automated_move_test_data.dart` already validate ~60% of FRs. DO NOT duplicate these tests.
- **FEN Format**: Use correct format from position.cpp: `c:w-count-sq1.sq2|b-count-sq3`, `i:w-count-sq|b-count-sq1.sq2`, `p:square`
- **Test Independence**: Each test must create its own game state from FEN - no shared state between tests
- **TDD Compliance**: Tests validate existing implementation - this is verification, not new feature development
- **Coverage Target**: 95% line + branch coverage for position.dart, mill.dart, import_service.dart
- **Performance Target**: Test suite <5 minutes, rule checking <10ms per move

---

## Validation Checklist

Before marking verification complete:

- [ ] All 23 existing integration tests passing
- [ ] All 39 FRs have at least one passing test
- [ ] 95% coverage achieved on critical paths
- [ ] No test failures or regressions
- [ ] Performance targets met
- [ ] FEN round-trip consistency validated
- [ ] All 5 clarifications from spec.md tested
- [ ] Bug fixes (if any) reviewed and merged

---

*Based on Plan v1.0 - See `plan.md` and Constitution v1.0.0*
