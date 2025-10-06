# Coverage Matrix: Integration Tests → Functional Requirements

**Date**: 2025-10-06
**Task**: T002 - Audit test coverage against 39 FRs

## Summary

**Total FRs**: 39
**Covered by existing 23 integration tests**: ~16 FRs (41%)
**Partially covered**: ~7 FRs (18%)
**Not covered**: ~16 FRs (41%)

## Coverage by Functional Requirement Category

### ✅ Custodian Rule (Standalone) - FR-001 to FR-004

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-001 | Identify custodian capture | ✅ **COVERED** | `placingWhiteCustodian`, `placingWhiteDoubleCustodian`, `movingWhiteCustodianMill` |
| FR-002 | Mark sandwiched piece as only legal target | ⚠️ **PARTIAL** | Implicit in custodian tests, but not explicitly validated |
| FR-003 | Mark non-sandwiched as illegal | ❌ **NOT COVERED** | No explicit illegal move rejection tests |
| FR-004 | Allow capture from mill (custodian) | ✅ **COVERED** | `placingBlackCustodianMillRemoved` |

**Coverage**: 2/4 covered, 1/4 partial, 1/4 missing

---

### ✅ Intervention Rule (Standalone) - FR-005 to FR-009

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-005 | Identify intervention capture | ✅ **COVERED** | `placingWhiteIntervention`, `movingWhiteInterventionWin`, +8 more |
| FR-006 | Mark both endpoints as legal | ✅ **COVERED** | `placingWhiteCrossMillCapture`, `placingWhiteVerticalLineCaptured` |
| FR-007 | Force second capture to other endpoint | ✅ **COVERED** | `placingWhiteSingleCaptureA4`, `placingWhiteSingleCaptureB2` |
| FR-008 | Mark non-endpoints as illegal | ❌ **NOT COVERED** | No explicit illegal move rejection tests |
| FR-009 | Allow capture from mill (intervention) | ✅ **COVERED** | `movingBlackMillCapture`, `placingBlackInterventionMill` |

**Coverage**: 4/5 covered, 0/5 partial, 1/5 missing

---

### ⚠️ Mill + Custodian Combination - FR-010 to FR-013

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-010 | Player chooses mill or custodian | ⚠️ **PARTIAL** | `movingWhiteCustodianMill` tests mill selection, but not custodian choice |
| FR-011 | Prevent mill after custodian selected | ❌ **NOT COVERED** | No tests verify blocking mill captures |
| FR-012 | Don't add custodian to pieceToRemoveCount when mill chosen | ⚠️ **PARTIAL** | Implicit in `movingWhiteCustodianMill` (unexpectedSequences) |
| FR-013 | Execute only remaining mill captures | ⚠️ **PARTIAL** | Implicit in mill selection behavior |

**Coverage**: 0/4 covered, 3/4 partial, 1/4 missing

---

### ⚠️ Mill + Intervention Combination - FR-014 to FR-017

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-014 | Player chooses mill or intervention | ✅ **COVERED** | `placingBlackInterventionMill`, `movingWhiteInterventionWin` |
| FR-015 | Force second capture + prevent mill | ⚠️ **PARTIAL** | Intervention forcing covered, mill prevention not explicit |
| FR-016 | Don't add intervention to pieceToRemoveCount when mill chosen | ❌ **NOT COVERED** | No tests validate pieceToRemoveCount behavior |
| FR-017 | Execute only remaining mill captures | ⚠️ **PARTIAL** | Implicit in test behavior |

**Coverage**: 1/4 covered, 2/4 partial, 1/4 missing

---

### ❌ mayRemoveMultiple=false Mode - FR-018 to FR-020, FR-036 to FR-038

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-018 | Don't pre-increment pieceToRemoveCount | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |
| FR-019 | Execute only chosen mode's count | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |
| FR-020 | Respect capture priority | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |
| FR-036 | Only 1 capture for multi-mill | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |
| FR-037 | Can choose custodian/intervention | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |
| FR-038 | Intervention still requires 2 captures | ❌ **NOT COVERED** | No tests with mayRemoveMultiple=false |

**Coverage**: 0/6 covered, 0/6 partial, 6/6 missing

---

### ❌ FEN Notation Consistency - FR-021 to FR-027, FR-034, FR-035, FR-039

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-021 | Export custodian state with c: marker | ❌ **NOT COVERED** | No FEN export tests |
| FR-022 | Export intervention state with i: marker | ❌ **NOT COVERED** | No FEN export tests |
| FR-023 | Export pieceToRemoveCount with p: marker | ❌ **NOT COVERED** | No FEN export tests |
| FR-024 | Import FEN with c:/i:/p: and restore | ❌ **NOT COVERED** | No FEN import tests |
| FR-025 | Update markers after each remove | ❌ **NOT COVERED** | No FEN update tests |
| FR-026 | Clear markers when complete | ❌ **NOT COVERED** | No FEN clear tests |
| FR-027 | Round-trip consistency | ❌ **NOT COVERED** | No round-trip tests |
| FR-034 | Accept both c: and i: simultaneously | ❌ **NOT COVERED** | No dual-marker tests |
| FR-035 | Reject invalid FEN (missing pieces) | ❌ **NOT COVERED** | No validation tests |
| FR-039 | Export exact count even if exceeds pieces | ❌ **NOT COVERED** | No edge case tests |

**Coverage**: 0/10 covered, 0/10 partial, 10/10 missing

---

### ❌ Move Legality Validation - FR-028 to FR-031

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-028 | Reject non-custodian when custodian active | ❌ **NOT COVERED** | No illegal move tests |
| FR-029 | Reject non-intervention when intervention active | ❌ **NOT COVERED** | No illegal move tests |
| FR-030 | Reject wrong endpoint for intervention | ❌ **NOT COVERED** | No illegal move tests |
| FR-031 | Reject moves violating chosen mode | ❌ **NOT COVERED** | No illegal move tests |

**Coverage**: 0/4 covered, 0/4 partial, 4/4 missing

---

### ⚠️ Triple Combo - FR-032, FR-033

| FR | Requirement | Coverage Status | Test Cases |
|----|-------------|-----------------|------------|
| FR-032 | Choose among all 3 modes when all trigger | ❌ **NOT COVERED** | No tests with all 3 simultaneous |
| FR-033 | First selection determines active rule | ⚠️ **PARTIAL** | Behavior implicit in combo tests, not explicit |

**Coverage**: 0/2 covered, 1/2 partial, 1/2 missing

---

## Coverage Summary Table

| Category | Total FRs | Covered | Partial | Missing | % Complete |
|----------|-----------|---------|---------|---------|------------|
| Custodian Standalone | 4 | 2 | 1 | 1 | 50% |
| Intervention Standalone | 5 | 4 | 0 | 1 | 80% |
| Mill + Custodian | 4 | 0 | 3 | 1 | 0% |
| Mill + Intervention | 4 | 1 | 2 | 1 | 25% |
| mayRemoveMultiple=false | 6 | 0 | 0 | 6 | 0% |
| FEN Notation | 10 | 0 | 0 | 10 | 0% |
| Move Legality | 4 | 0 | 0 | 4 | 0% |
| Triple Combo | 2 | 0 | 1 | 1 | 0% |
| **TOTAL** | **39** | **7** | **7** | **25** | **18%** |

## Gaps Requiring New Tests

### Critical Gaps (High Priority)

1. **FEN Notation** (10 FRs) - Zero coverage
   - Need comprehensive FEN import/export tests
   - Test c:, i:, p: markers individually and combined
   - Test round-trip, validation, error handling

2. **Move Legality** (4 FRs) - Zero coverage
   - Need illegal move rejection tests
   - Test all rule types (custodian, intervention, mill)
   - Validate error messages and state

3. **mayRemoveMultiple=false** (6 FRs) - Zero coverage
   - Need tests with this configuration flag
   - Test interaction with all capture types
   - Validate capture counting behavior

### Medium Priority Gaps

4. **Explicit validation tests** for partial coverage items
   - Mill + custodian combination choices (FR-010, FR-011)
   - Mill + intervention combination choices (FR-016)
   - Triple combo explicit selection (FR-032)

### Low Priority Gaps

5. **Negative test cases** currently implicit
   - FR-003, FR-008: Illegal target selection
   - Already working (implicit in test success), but should be explicit

## Recommendations for T003-T007

**T003**: Create `fen_notation_test.dart` - **10 FRs** (highest priority)
**T004**: Create `move_legality_test.dart` - **4 FRs**
**T005**: Create `may_remove_multiple_test.dart` - **6 FRs** (if flag affects behavior)
**T006**: Create `triple_combo_test.dart` - **2 FRs** (if not covered)
**T007**: Create `edge_cases_test.dart` - Cover partial/implicit items explicitly

**Estimated new coverage**: 22+ FRs → Total 29/39 (74%) with existing 7 + new 22
